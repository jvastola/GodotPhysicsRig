# Build the Godot LiveKit Android Kotlin plugin and optionally the Rust Android GDExtension.
# Default behavior builds Kotlin only:
# - android\plugins\GodotLiveKit.aar + GodotLiveKit.gdap
#
# Optional switches:
# - -WithRust: also build/install addons\godot-livekit\bin\android\libgodot_livekit.so
# - -RustOnly: build/install only the Rust Android GDExtension
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\tools\build\windows-build-livekit-android.ps1

param(
    [int]$AndroidApiLevel = 29,
    [switch]$WithRust,
    [switch]$RustOnly
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Resolve-Path (Join-Path $ScriptDir "..\..")
$RustDir = Join-Path $RootDir "multiplayer\plugins\godot-livekit\rust"
$AndroidPluginDir = Join-Path $RootDir "multiplayer\plugins\livekit-android"
$SourceAddonDir = Join-Path $RootDir "multiplayer\plugins\godot-livekit\addons\godot-livekit"
$DestAddonDir = Join-Path $RootDir "addons\godot-livekit"
$DestSoDir = Join-Path $DestAddonDir "bin\android"
$DestAndroidPluginDir = Join-Path $RootDir "android\plugins"
$TargetTriple = "aarch64-linux-android"

if (-not (Test-Path $AndroidPluginDir)) {
    throw "LiveKit Android plugin source not found: $AndroidPluginDir"
}
if (($WithRust -or $RustOnly) -and (-not (Test-Path $RustDir))) {
    throw "LiveKit rust source not found: $RustDir"
}

New-Item -ItemType Directory -Path $DestSoDir -Force | Out-Null
New-Item -ItemType Directory -Path $DestAndroidPluginDir -Force | Out-Null

if ($RustOnly) {
    $BuildRust = $true
    $BuildKotlin = $false
}
else {
    $BuildRust = [bool]$WithRust
    $BuildKotlin = $true
}

if ($BuildRust) {
    Write-Host "Building Android Rust GDExtension ($TargetTriple)..."
    Push-Location $RustDir
    try {
        rustup target add $TargetTriple | Out-Host

        $HasCargoNdk = $null -ne (Get-Command cargo-ndk -ErrorAction SilentlyContinue)
        if ($HasCargoNdk) {
            cargo ndk -t arm64-v8a -p $AndroidApiLevel build --release | Out-Host
        }
        else {
            if (-not $env:ANDROID_NDK_HOME) {
                throw "cargo-ndk not found and ANDROID_NDK_HOME is not set. Install cargo-ndk or set ANDROID_NDK_HOME."
            }

            $ToolchainBin = Join-Path $env:ANDROID_NDK_HOME "toolchains\llvm\prebuilt\windows-x86_64\bin"
            if (-not (Test-Path $ToolchainBin)) {
                throw "Android NDK toolchain not found: $ToolchainBin"
            }

            $env:CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER = Join-Path $ToolchainBin "aarch64-linux-android$AndroidApiLevel-clang.cmd"
            $env:CARGO_TARGET_AARCH64_LINUX_ANDROID_AR = Join-Path $ToolchainBin "llvm-ar.exe"
            cargo build --release --target $TargetTriple | Out-Host
        }
    }
    finally {
        Pop-Location
    }

    $SourceSo = Join-Path $RustDir "target\$TargetTriple\release\libgodot_livekit.so"
    if (-not (Test-Path $SourceSo)) {
        throw "Expected Android .so artifact was not produced: $SourceSo"
    }
    Copy-Item -Force $SourceSo (Join-Path $DestSoDir "libgodot_livekit.so")
    Write-Host "Installed: $(Join-Path $DestSoDir 'libgodot_livekit.so')"
}

if ($BuildKotlin) {
    Write-Host "Building Android LiveKit Kotlin plugin (AAR)..."
    Push-Location $AndroidPluginDir
    try {
        .\gradlew.bat clean assembleRelease | Out-Host
    }
    finally {
        Pop-Location
    }

    $CandidateAars = @(
        (Join-Path $AndroidPluginDir "build\outputs\aar\GodotLiveKit-release.aar"),
        (Join-Path $AndroidPluginDir "build\outputs\aar\livekit-release.aar")
    )

    $AarSource = $null
    foreach ($Candidate in $CandidateAars) {
        if (Test-Path $Candidate) {
            $AarSource = $Candidate
            break
        }
    }
    if (-not $AarSource) {
        $AnyAar = Get-ChildItem -Path (Join-Path $AndroidPluginDir "build\outputs\aar") -Filter *.aar -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($AnyAar) {
            $AarSource = $AnyAar.FullName
        }
    }
    if (-not $AarSource) {
        throw "No AAR artifact found in $(Join-Path $AndroidPluginDir 'build\outputs\aar')"
    }

    Copy-Item -Force $AarSource (Join-Path $DestAndroidPluginDir "GodotLiveKit.aar")

    $GdapSource = Join-Path $AndroidPluginDir "GodotLiveKit.gdap"
    if (Test-Path $GdapSource) {
        Copy-Item -Force $GdapSource (Join-Path $DestAndroidPluginDir "GodotLiveKit.gdap")
    }

    Write-Host "Installed: $(Join-Path $DestAndroidPluginDir 'GodotLiveKit.aar')"
    Write-Host "Installed: $(Join-Path $DestAndroidPluginDir 'GodotLiveKit.gdap')"
}

# Keep addon metadata in sync with plugin source.
$SourceGdextension = Join-Path $SourceAddonDir "godot-livekit.gdextension"
$SourcePluginCfg = Join-Path $SourceAddonDir "plugin.cfg"
if (Test-Path $SourceGdextension) {
    Copy-Item -Force $SourceGdextension (Join-Path $DestAddonDir "godot-livekit.gdextension")
}
if (Test-Path $SourcePluginCfg) {
    Copy-Item -Force $SourcePluginCfg (Join-Path $DestAddonDir "plugin.cfg")
}
