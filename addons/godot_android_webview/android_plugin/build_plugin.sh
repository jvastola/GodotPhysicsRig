#!/bin/bash
# Build script for GodotAndroidWebView plugin (macOS/Linux)
# Run this from the android_plugin directory

echo "========================================"
echo "Building GodotAndroidWebView Plugin"
echo "========================================"

# Check if libs folder exists
if [ ! -d "libs" ]; then
    echo "Creating libs folder..."
    mkdir -p libs
fi

# Check for godot-lib.aar
if [ ! -f "libs/godot-lib.release.aar" ]; then
    echo ""
    echo "ERROR: godot-lib.release.aar not found in libs folder!"
    echo ""
    echo "Please copy godot-lib.template_release.aar from your Godot export templates:"
    echo "  macOS: ~/Library/Application Support/Godot/export_templates/4.x.x/android/"
    echo "  Linux: ~/.local/share/godot/export_templates/4.x.x/android/"
    echo ""
    echo "Rename it to: godot-lib.release.aar"
    echo "Place it in: $(pwd)/libs/"
    echo ""
    exit 1
fi

# Check for gradle wrapper
if [ ! -f "gradlew" ]; then
    echo "Creating Gradle wrapper..."
    gradle wrapper --gradle-version 8.2
fi

# Make gradlew executable
chmod +x gradlew

echo ""
echo "Building release AAR..."
./gradlew assembleRelease

if [ $? -ne 0 ]; then
    echo ""
    echo "BUILD FAILED!"
    exit 1
fi

echo ""
echo "Copying AAR to android/plugins..."
mkdir -p ../../../android/plugins
cp build/outputs/aar/android_plugin-release.aar ../../../android/plugins/GodotAndroidWebView.aar

echo ""
echo "========================================"
echo "BUILD SUCCESSFUL!"
echo "========================================"
echo ""
echo "Plugin copied to: android/plugins/GodotAndroidWebView.aar"
echo ""
echo "Next steps:"
echo "1. Enable the plugin in your Android export settings"
echo "2. Export your project to Android/Quest"
echo ""
