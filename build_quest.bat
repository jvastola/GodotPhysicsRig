@echo off
setlocal

REM ============================================
REM  Configuration - Set these environment variables or override here
REM ============================================
REM Required env vars:
REM   GODOT_PATH     - Path to Godot console executable
REM   KEYSTORE_PATH  - Path to release keystore
REM   KEYSTORE_PASS  - Keystore password
REM   KEYSTORE_ALIAS - Keystore alias
REM Optional:
REM   ANDROID_HOME   - Android SDK path (defaults to %LOCALAPPDATA%\Android\Sdk)
REM   OUTPUT_APK     - Output APK path (defaults to android\scenetree.apk)

if not defined GODOT_PATH (
    echo ERROR: GODOT_PATH environment variable not set
    echo Set it to your Godot console executable path
    exit /b 1
)
if not defined KEYSTORE_PATH (
    echo ERROR: KEYSTORE_PATH environment variable not set
    exit /b 1
)
if not defined KEYSTORE_PASS (
    echo ERROR: KEYSTORE_PASS environment variable not set
    exit /b 1
)
if not defined KEYSTORE_ALIAS (
    echo ERROR: KEYSTORE_ALIAS environment variable not set
    exit /b 1
)

if not defined ANDROID_HOME set ANDROID_HOME=%LOCALAPPDATA%\Android\Sdk
if not defined OUTPUT_APK set OUTPUT_APK=android\scenetree.apk

echo ========================================
echo   Building Quest 3 APK (Release)
echo ========================================
echo.

REM Step 0: Clean previous build artifacts to ensure fresh build
echo Step 0: Cleaning previous build...
if exist "android\build\build\intermediates\merged_native_libs" rmdir /s /q "android\build\build\intermediates\merged_native_libs"

REM Step 1: Let Godot prepare the assets (export-release for release build)
echo.
echo Step 1: Preparing assets with Godot...
"%GODOT_PATH%" --headless --export-release "Quest 3" %OUTPUT_APK% 2>nul

REM Step 2: Copy plugin files (CRITICAL for OpenXR and LiveKit to work!)
echo.
echo Step 2: Copying plugin files to build...

REM Copy the Meta AAR to libs folder
if not exist "android\build\libs\release" mkdir "android\build\libs\release"
copy /Y "addons\godotopenxrvendors\.bin\android\release\godotopenxr-meta-release.aar" "android\build\libs\release\"

REM Copy the GDExtension .so file to the jniLibs folder
if not exist "android\build\libs\release\arm64-v8a" mkdir "android\build\libs\release\arm64-v8a"
copy /Y "addons\godotopenxrvendors\.bin\android\template_release\arm64\libgodotopenxrvendors.so" "android\build\libs\release\arm64-v8a\"

REM Copy the GodotLiveKit AAR to libs folder
copy /Y "android\plugins\GodotLiveKit.aar" "android\build\libs\release\"

echo   - Copied godotopenxr-meta-release.aar
echo   - Copied libgodotopenxrvendors.so
echo   - Copied GodotLiveKit.aar

REM Step 3: Run gradle build manually with correct path separators
echo.
echo Step 3: Building with Gradle (Release)...
pushd android\build
call gradlew.bat assembleStandardRelease ^
    -Pexport_package_name=com.anyreality.scenetree ^
    -Pexport_version_code=32 ^
    -Pexport_version_name=1.32 ^
    -Pexport_version_min_sdk=29 ^
    -Pexport_version_target_sdk=33 ^
    -Pexport_enabled_abis=arm64-v8a ^
    -Pperform_zipalign=true ^
    -Pperform_signing=true ^
    "-Prelease_keystore_file=%KEYSTORE_PATH%" ^
    "-Prelease_keystore_password=%KEYSTORE_PASS%" ^
    "-Prelease_keystore_alias=%KEYSTORE_ALIAS%" ^
    "-Pplugins_remote_binaries=io.livekit:livekit-android:2.5.0|org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3"
popd

if errorlevel 1 (
    echo ERROR: Gradle build failed
    exit /b 1
)

REM Step 4: Copy the APK to the output location
echo.
echo Step 4: Copying APK...
copy /Y "android\build\build\outputs\apk\standard\release\android_release.apk" "%OUTPUT_APK%"

echo.
echo ========================================
echo   BUILD COMPLETE!
echo ========================================
echo APK: %OUTPUT_APK%
echo.
echo To install on Quest:
echo   adb install -r %OUTPUT_APK%
