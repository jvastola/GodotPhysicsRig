@echo off
REM Build script for GodotAndroidWebView plugin (Windows)
REM Run this from the android_plugin directory

echo ========================================
echo Building GodotAndroidWebView Plugin
echo ========================================

REM Check if libs folder exists
if not exist "libs" (
    echo Creating libs folder...
    mkdir libs
)

REM Check for godot-lib.aar
if not exist "libs\godot-lib.release.aar" (
    echo.
    echo ERROR: godot-lib.release.aar not found in libs folder!
    echo.
    echo Please copy godot-lib.template_release.aar from your Godot export templates:
    echo   Windows: %%APPDATA%%\Godot\export_templates\4.x.x\android\
    echo.
    echo Rename it to: godot-lib.release.aar
    echo Place it in: %CD%\libs\
    echo.
    pause
    exit /b 1
)

REM Check for gradle wrapper
if not exist "gradlew.bat" (
    echo Creating Gradle wrapper...
    call gradle wrapper --gradle-version 8.2
)

echo.
echo Building release AAR...
call gradlew.bat assembleRelease

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo BUILD FAILED!
    pause
    exit /b 1
)

echo.
echo Copying AAR to android/plugins...
if not exist "..\..\..\android\plugins" (
    mkdir "..\..\..\android\plugins"
)
copy /Y "build\outputs\aar\android_plugin-release.aar" "..\..\..\android\plugins\GodotAndroidWebView.aar"

echo.
echo ========================================
echo BUILD SUCCESSFUL!
echo ========================================
echo.
echo Plugin copied to: android\plugins\GodotAndroidWebView.aar
echo.
echo Next steps:
echo 1. Enable the plugin in your Android export settings
echo 2. Export your project to Android/Quest
echo.
pause
