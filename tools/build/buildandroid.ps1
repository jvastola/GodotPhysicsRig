# Build Android GDExtension plugins and export Godot project for Quest 3
# Usage: .\buildandroid.ps1 [-Deploy] [-Clean] [-SkipPlugins]

param(
    [switch]$Deploy,
    [switch]$Clean,
    [switch]$SkipPlugins,
    [switch]$Help
)

# Configuration
$GODOT_PATH = if ($env:GODOT_PATH) { $env:GODOT_PATH } else { "C:\Program Files\Godot\Godot.exe" }
$EXPORT_PRESET = "Quest 3"
$OUTPUT_APK = "android\scenetree.apk"
$ADB_PACKAGE = "com.anyreality.scenetree"

# Show help
if ($Help) {
    Write-Host "Usage: .\buildandroid.ps1 [OPTIONS]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Deploy         Deploy APK to connected Quest device after build"
    Write-Host "  -Clean          Clean build artifacts before building"
    Write-Host "  -SkipPlugins    Skip building Android plugins (use existing AARs)"
    Write-Host "  -Help           Show this help message"
    exit 0
}

Write-Host "========================================" -ForegroundColor Blue
Write-Host "  Android Build Script for Quest 3" -ForegroundColor Blue
Write-Host "========================================" -ForegroundColor Blue
Write-Host ""

# Check for Godot
if (-not (Test-Path $GODOT_PATH)) {
    Write-Host "ERROR: Godot not found at $GODOT_PATH" -ForegroundColor Red
    Write-Host "Set GODOT_PATH environment variable to your Godot executable"
    exit 1
}

Write-Host "✓ Godot found at: $GODOT_PATH" -ForegroundColor Green

# Clean if requested
if ($Clean) {
    Write-Host ""
    Write-Host "Cleaning build artifacts..." -ForegroundColor Yellow
    
    Remove-Item -Path "addons\godot_android_webview\android_plugin\build" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "android_plugin_source\livekit\build" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "android\build\build" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $OUTPUT_APK -Force -ErrorAction SilentlyContinue
    
    Write-Host "✓ Clean complete" -ForegroundColor Green
}

# Build Android plugins
if (-not $SkipPlugins) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Blue
    Write-Host "  Building Android Plugins" -ForegroundColor Blue
    Write-Host "========================================" -ForegroundColor Blue
    
    # Build GodotAndroidWebView plugin
    Write-Host ""
    Write-Host "Building GodotAndroidWebView plugin..." -ForegroundColor Yellow
    $WEBVIEW_DIR = "addons\godot_android_webview\android_plugin"
    
    if (Test-Path $WEBVIEW_DIR) {
        Push-Location $WEBVIEW_DIR
        
        # Check for godot-lib.aar
        if (-not (Test-Path "libs\godot-lib.release.aar")) {
            Write-Host "WARNING: godot-lib.release.aar not found in $WEBVIEW_DIR\libs" -ForegroundColor Yellow
            Write-Host "Attempting to continue with Maven dependency..."
        }
        
        # Ue gradlew.bat on Windows& 
        .\gradlew.bat clean assembleRelease

        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "ERROR: GodotAndroidWebView build failed" -ForegroundColor Red
            Pop-Location
            exit 1
        }
        
        # Copy AAR to android/plugins
        if (Test-Path "build\outputs\aar\GodotAndroidWebView-release.aar") {
            Copy-Item "build\outputs\aar\GodotAndroidWebView-release.aar" "..\..\..\android\plugins\GodotAndroidWebView.aar" -Force
            Write-Host "✓ GodotAndroidWebView plugin built and copied" -ForegroundColor Green
        } else {
            Write-Host "ERROR: GodotAndroidWebView AAR not found after build" -ForegroundColor Red
            Pop-Location
            exit 1
        }
        
        # Check for gdap file
        if (Test-Path "..\..\..\android\plugins\GodotAndroidWebView.gdap") {
            Write-Host "✓ GodotAndroidWebView.gdap already in place" -ForegroundColor Green
        }
        
        Pop-Location
    } else {
        Write-Host "WARNING: WebView plugin directory not found, skipping" -ForegroundColor Yellow
    }
    
    # Build GodotLiveKit plugin
    Write-Host ""
    Write-Host "Building GodotLiveKit plugin..." -ForegroundColor Yellow
    $LIVEKIT_DIR = $null
    $LIVEKIT_DEST_DIR = $null
    if (Test-Path "multiplayer\plugins\livekit-android") {
        $LIVEKIT_DIR = "multiplayer\plugins\livekit-android"
        $LIVEKIT_DEST_DIR = "..\..\..\android\plugins"
    } elseif (Test-Path "android_plugin_source\livekit") {
        $LIVEKIT_DIR = "android_plugin_source\livekit"
        $LIVEKIT_DEST_DIR = "..\..\android\plugins"
    }
    
    if ($LIVEKIT_DIR -and (Test-Path $LIVEKIT_DIR)) {
        Push-Location $LIVEKIT_DIR
        
        & .\gradlew.bat assembleRelease --quiet
        
        # Copy AAR and gdap to android/plugins
        if (Test-Path "build\outputs\aar\livekit-release.aar") {
            Copy-Item "build\outputs\aar\livekit-release.aar" "$LIVEKIT_DEST_DIR\GodotLiveKit.aar" -Force
            Write-Host "✓ GodotLiveKit plugin built" -ForegroundColor Green
        } elseif (Test-Path "build\outputs\aar\GodotLiveKit-release.aar") {
            Copy-Item "build\outputs\aar\GodotLiveKit-release.aar" "$LIVEKIT_DEST_DIR\GodotLiveKit.aar" -Force
            Write-Host "✓ GodotLiveKit plugin built" -ForegroundColor Green
        } else {
            Write-Host "WARNING: GodotLiveKit AAR not found, checking for existing..." -ForegroundColor Yellow
            if (Test-Path "$LIVEKIT_DEST_DIR\GodotLiveKit.aar") {
                Write-Host "✓ Using existing GodotLiveKit.aar" -ForegroundColor Green
            } else {
                Write-Host "ERROR: No GodotLiveKit AAR available" -ForegroundColor Red
                Pop-Location
                exit 1
            }
        }
        
        # Copy gdap file if it exists
        if (Test-Path "GodotLiveKit.gdap") {
            Copy-Item "GodotLiveKit.gdap" "$LIVEKIT_DEST_DIR\" -Force
        }
        
        Pop-Location
    } else {
        Write-Host "WARNING: LiveKit plugin directory not found, skipping" -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "✓ All plugins built successfully" -ForegroundColor Green
}

# Export Godot project
Write-Host ""
Write-Host "========================================" -ForegroundColor Blue
Write-Host "  Exporting Godot Project" -ForegroundColor Blue
Write-Host "========================================" -ForegroundColor Blue
Write-Host ""
Write-Host "Exporting to: $OUTPUT_APK" -ForegroundColor Yellow
Write-Host "Using preset: $EXPORT_PRESET" -ForegroundColor Yellow
Write-Host ""

# Run Godot export (let it prepare assets, ignore gradle failure)
Write-Host "Preparing assets with Godot..." -ForegroundColor Yellow
& $GODOT_PATH --headless --export-debug $EXPORT_PRESET $OUTPUT_APK 2>$null

# Run gradle manually with correct Windows path separators
Write-Host "Running Gradle build..." -ForegroundColor Yellow
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
Push-Location "android\build"
cmd /c "gradlew.bat assembleStandardDebug -Pexport_package_name=$ADB_PACKAGE -Pexport_version_code=32 -Pexport_version_name=1.32 -Pexport_version_min_sdk=29 -Pexport_version_target_sdk=33 -Pexport_enabled_abis=arm64-v8a -Pperform_zipalign=true -Pperform_signing=true"
$gradleResult = $LASTEXITCODE
Pop-Location

if ($gradleResult -ne 0) {
    Write-Host "ERROR: Gradle build failed" -ForegroundColor Red
    exit 1
}

# Copy the APK to the output location
Copy-Item "android\build\build\outputs\apk\standard\debug\android_debug.apk" $OUTPUT_APK -Force

if (-not (Test-Path $OUTPUT_APK)) {
    Write-Host "ERROR: APK not found after export" -ForegroundColor Red
    exit 1
}

$APK_SIZE = (Get-Item $OUTPUT_APK).Length / 1MB
$APK_SIZE_STR = "{0:N2} MB" -f $APK_SIZE

Write-Host ""
Write-Host "✓ Export successful!" -ForegroundColor Green
Write-Host "  APK: $OUTPUT_APK ($APK_SIZE_STR)" -ForegroundColor Green

# Deploy if requested
if ($Deploy) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Blue
    Write-Host "  Deploying to Quest" -ForegroundColor Blue
    Write-Host "========================================" -ForegroundColor Blue
    Write-Host ""
    
    # Check for adb
    try {
        $null = Get-Command adb -ErrorAction Stop
    } catch {
        Write-Host "ERROR: adb not found in PATH" -ForegroundColor Red
        Write-Host "Install Android SDK platform-tools and add to PATH"
        exit 1
    }
    
    # Check for connected device
    $devices = adb devices | Select-String "device$"
    if ($devices.Count -eq 0) {
        Write-Host "ERROR: No Quest device connected" -ForegroundColor Red
        Write-Host "Connect your Quest via USB and enable developer mode"
        exit 1
    }
    
    Write-Host "Installing APK..." -ForegroundColor Yellow
    adb install -r $OUTPUT_APK
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ APK installed successfully" -ForegroundColor Green
        Write-Host ""
        Write-Host "Note: Launch the app manually from your Quest's app library" -ForegroundColor Yellow
        Write-Host "(Auto-launch is blocked by Quest security restrictions)" -ForegroundColor Yellow
    } else {
        Write-Host "ERROR: APK installation failed" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Blue
Write-Host "  BUILD COMPLETE!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Blue
Write-Host ""
