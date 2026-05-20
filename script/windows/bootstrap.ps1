#!/usr/bin/env powershell

$ErrorActionPreference = 'Stop'

# Git for Windows can be installed system-wide (Program Files) or per-user (LOCALAPPDATA\Programs\Git).
$gitBinCandidates = @(
    "$env:PROGRAMFILES\Git\bin",
    "$env:LOCALAPPDATA\Programs\Git\bin"
)
$gitBinDir = $gitBinCandidates | Where-Object { Test-Path -PathType Container $_ } | Select-Object -First 1
if (-not $gitBinDir) {
    Write-Error 'Git for Windows is required. Please install it at:'
    Write-Error 'https://gitforwindows.org/'
    exit 1
}

if (-not (Get-Command -Name cargo -Type Application -ErrorAction SilentlyContinue)) {
    Write-Output 'Installing rust...'
    Invoke-WebRequest -Uri 'https://win.rustup.rs/x86_64' -OutFile "$env:Temp\rustup-init.exe"
    & "$env:Temp\rustup-init.exe"
    Write-Output 'Please start a new terminal session so that cargo is in your PATH'
    exit 1
}

# Visual Studio Build Tools (MSVC compiler + linker + Windows SDK) are required to link Rust crates
# targeting x86_64-pc-windows-msvc.
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$haveMsvcBuildTools = $false
if (Test-Path $vswhere) {
    $vsInstall = & $vswhere -latest -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 Microsoft.VisualStudio.Component.Windows11SDK.22621 `
        -property installationPath
    if ($vsInstall) { $haveMsvcBuildTools = $true }
}
if (-not $haveMsvcBuildTools) {
    Write-Output 'Installing Visual Studio Build Tools (MSVC + Windows SDK)...'
    winget install -e --id Microsoft.VisualStudio.2022.BuildTools `
        --accept-package-agreements --accept-source-agreements `
        --override '--passive --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.Windows11SDK.22621 --includeRecommended'
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

# A bash executable should come with Git for Windows
& "$gitBinDir\bash.exe" "$PWD\script\install_cargo_test_deps"

# Needed in wasm compilation for parsing the version of wasm-bindgen
winget install jqlang.jq

# CMake is needed to build native dependencies.
winget install -e --id Kitware.CMake

# We use InnoSetup to build our release bundle installer.
winget install -e --id JRSoftware.InnoSetup

# protoc (protobuf compiler) is required by prost-build for several crates.
# Mirrors the manual GitHub-release install used in script/linux/install_build_deps
# so we get a modern protoc (>= 3.15, needed for proto3 'optional' fields).
if (-not (Get-Command -Name protoc -Type Application -ErrorAction SilentlyContinue)) {
    Write-Output 'Installing protoc...'
    $protocVersion = '25.1'
    $protocDir = "$env:LOCALAPPDATA\protoc"
    $protocZip = "$env:TEMP\protoc-$protocVersion-win64.zip"
    $protocUrl = "https://github.com/protocolbuffers/protobuf/releases/download/v$protocVersion/protoc-$protocVersion-win64.zip"

    New-Item -ItemType Directory -Force -Path $protocDir | Out-Null
    Invoke-WebRequest -Uri $protocUrl -OutFile $protocZip
    Expand-Archive -Path $protocZip -DestinationPath $protocDir -Force
    Remove-Item $protocZip

    # Persist to user PATH so future shells pick it up.
    $protocBin = Join-Path $protocDir 'bin'
    $userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
    if (-not $userPath) { $userPath = '' }
    if ($userPath -notlike "*$protocBin*") {
        $newUserPath = if ($userPath) { "$userPath;$protocBin" } else { $protocBin }
        [Environment]::SetEnvironmentVariable('PATH', $newUserPath, 'User')
    }
    # And make it available to the current session immediately.
    $env:PATH = "$env:PATH;$protocBin"

    Write-Output "Installed protoc $protocVersion to $protocDir"
}

Write-Output ''
Write-Output 'Bootstrap complete. Build OpenWarp with:'
Write-Output '    cargo run --bin warp-oss --features gui'
Write-Output '    cargo run --release --bin warp-oss --features gui'
