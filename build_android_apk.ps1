# Build Android APK for Quest 3 using Godot headless export
# Adjust paths and export preset name as needed for your project.

# Determine the directory of this script (project root)
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

# Path to the Godot executable (modify if your installation differs)
$godotExe = "C:\Program Files\Godot\Godot_v4.2.2-stable_win64.exe"

# Export preset name defined in export_presets.cfg
# Ensure this preset is configured for Android/Quest 3 (includes keystore, permissions, etc.)
$exportPreset = "Android_Quest3"

# Output APK path (relative to project root)
$outputApk = "builds/quest3.apk"

Write-Host "🚀 Building Android APK using preset '$exportPreset'..."

# Run Godot in headless mode to export the APK
& $godotExe --headless --export-release $exportPreset $outputApk

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Build succeeded! APK saved to $outputApk"
} else {
    Write-Error "❌ Build failed with exit code $LASTEXITCODE"
}
