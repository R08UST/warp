#!/usr/bin/env powershell
#
# Windows-native equivalent of ./script/run.
#
# Builds and launches OpenWarp via `cargo run`. Mirrors the cross-platform
# logic in script/run for users invoking from PowerShell instead of Git Bash.
#
# Usage:
#   .\script\windows\run.ps1
#   .\script\windows\run.ps1 --release
#   .\script\windows\run.ps1 --features extra,things
#   .\script\windows\run.ps1 -- --some-arg-passed-to-warp

$ErrorActionPreference = 'Stop'

# Locate repo root (this script lives at script\windows\run.ps1).
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $repoRoot

# --- Channel selection ---------------------------------------------------
# OpenWarp is the OSS fork — we always build the `warp-oss` binary.
# Upstream's local-channel path requires `warp-channel-config` from a
# closed-source SSH repo (ssh://git@github.com/warpdotdev/warp-channel-config),
# probing which would prompt for SSH passphrase on every invocation.
# Warp employees who need the local channel can install it manually
# via `./script/install_channel_config` from Git Bash.
$warpBinName = 'warp-oss'
$env:WARP_CHANNEL = 'oss'

# --- Argument parsing ----------------------------------------------------
# Mirrors the bash version's shared parser. Unknown flags and positional
# arguments are forwarded to `cargo run`. Anything after `--` is forwarded
# to the warp binary itself.
$features    = 'gui'
$cargoParams = @()
$warpArgs    = @()

$i = 0
while ($i -lt $args.Count) {
    $arg = $args[$i]

    if ($arg -eq '--') {
        $i++
        while ($i -lt $args.Count) {
            $warpArgs += $args[$i]
            $i++
        }
        break
    }
    elseif ($arg -eq '--features') {
        if ($i + 1 -ge $args.Count -or "$($args[$i + 1])".StartsWith('-')) {
            throw 'Argument for --features is missing'
        }
        $features = "$features,$($args[$i + 1])"
        $i += 2
    }
    elseif ($arg -eq '--host-id') {
        if ($i + 1 -ge $args.Count -or "$($args[$i + 1])".StartsWith('-')) {
            throw 'Argument for --host-id is missing'
        }
        $env:WARP_CLOUD_MODE_DEFAULT_HOST = $args[$i + 1]
        $i += 2
    }
    elseif ($arg -eq '--release') {
        $cargoParams += '--release'
        $i++
    }
    elseif ($arg -eq '--profile') {
        if ($i + 1 -ge $args.Count -or "$($args[$i + 1])".StartsWith('-')) {
            throw 'Argument for --profile is missing'
        }
        $cargoParams += '--profile'
        $cargoParams += $args[$i + 1]
        $i += 2
    }
    else {
        # Unknown flags + positional args get forwarded to cargo.
        $cargoParams += $arg
        $i++
    }
}

# --- Legacy feature -> env var mapping -----------------------------------
# These cargo features were removed and replaced by environment variables
# read by warp-channel-config. Intercept them here so existing --features
# invocations keep working.
$legacyMap = [ordered]@{
    'with_local_server'                 = 'WITH_LOCAL_SERVER'
    'with_local_session_sharing_server' = 'WITH_LOCAL_SESSION_SHARING_SERVER'
    'with_sandbox_telemetry'            = 'WITH_SANDBOX_TELEMETRY'
}
foreach ($feature in $legacyMap.Keys) {
    $featureList = @($features -split ',' | Where-Object { $_ -ne '' })
    if ($featureList -contains $feature) {
        $envVar = $legacyMap[$feature]
        Set-Item -Path "env:$envVar" -Value '1'
        $featureList = $featureList | Where-Object { $_ -ne $feature }
        $features = ($featureList -join ',')
        Write-Output "Note: '$feature' is no longer a cargo feature; setting $envVar=1 instead."
    }
}

# Match the bash entrypoint's exported env vars so any child process / build
# script that looks for them sees the same values.
$env:FEATURES      = $features
$env:WARP_BIN_NAME = $warpBinName

# --- Run -----------------------------------------------------------------
$cargoArgs = @('run', '--bin', $warpBinName, '--features', $features) + $cargoParams
if ($warpArgs.Count -gt 0) {
    $cargoArgs += '--'
    $cargoArgs += $warpArgs
}

Write-Output ('Running cargo ' + ($cargoArgs -join ' '))
& cargo @cargoArgs
exit $LASTEXITCODE
