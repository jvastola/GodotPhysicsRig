# Build the Godot LiveKit desktop GDExtension (Windows) and install it into this project.
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\tools\build\windows-build-livekit-desktop.ps1

param(
    [string]$TargetTriple = "x86_64-pc-windows-msvc"
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Resolve-Path (Join-Path $ScriptDir "..\..")
$RustDir = Join-Path $RootDir "multiplayer\plugins\godot-livekit\rust"
$SourceAddonDir = Join-Path $RootDir "multiplayer\plugins\godot-livekit\addons\godot-livekit"
$DestAddonDir = Join-Path $RootDir "addons\godot-livekit"
$DestBinDir = Join-Path $DestAddonDir "bin\windows"
$DestDll = Join-Path $DestBinDir "godot_livekit.dll"

if (-not (Test-Path $RustDir)) {
    throw "LiveKit rust source not found: $RustDir"
}

New-Item -ItemType Directory -Path $DestBinDir -Force | Out-Null

Push-Location $RustDir
try {
    rustup target add $TargetTriple | Out-Host
    cargo build --release --target $TargetTriple | Out-Host
}
finally {
    Pop-Location
}

$SourceDll = Join-Path $RustDir "target\$TargetTriple\release\godot_livekit.dll"
if (-not (Test-Path $SourceDll)) {
    throw "Expected Windows artifact was not produced: $SourceDll"
}

Copy-Item -Force $SourceDll $DestDll

# Keep addon metadata in sync with plugin source.
$SourceGdextension = Join-Path $SourceAddonDir "godot-livekit.gdextension"
$SourcePluginCfg = Join-Path $SourceAddonDir "plugin.cfg"
if (Test-Path $SourceGdextension) {
    Copy-Item -Force $SourceGdextension (Join-Path $DestAddonDir "godot-livekit.gdextension")
}
if (Test-Path $SourcePluginCfg) {
    Copy-Item -Force $SourcePluginCfg (Join-Path $DestAddonDir "plugin.cfg")
}

Write-Host "Installed: $DestDll"

