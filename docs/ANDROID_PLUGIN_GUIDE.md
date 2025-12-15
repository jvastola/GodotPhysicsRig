# Android LiveKit Plugin Update Guide

This guide explains how to update, build, and verify the Android LiveKit plugin for the Godot project.

## 1. Source Code Location
The source code for the Android plugin is located in:
`android_plugin_source/livekit/`

Key files:
- **Plugin Logic:** `src/main/kotlin/com/jvastola/physicshand/livekit/GodotLiveKitPlugin.kt`
- **Build Config:** `build.gradle`
- **Project Settings:** `settings.gradle`

## 2. Prerequisites
- **JDK 17**: Ensure you have Java Development Kit 17 installed.
- **Android SDK**: Ensure the Android SDK is installed and the `ANDROID_HOME` environment variable is set (usually handled automatically by Android Studio or Gradle).

## 3. Building the Plugin
To build the plugin and install it into the Godot project, run the following command from the terminal:

```bash
cd android_plugin_source/livekit
./gradlew installPlugin
```

### What this command does:
1.  Compiles the Kotlin source code.
2.  Assembles the `.aar` (Android Archive) library.
3.  Copies the generated `GodotLiveKit.aar` to `android/plugins/`.
4.  Copies the `GodotLiveKit.gdap` configuration file to `android/plugins/`.

## 4. Verifying the Update
After running the build command, verify that the plugin files have been updated in the Godot project:

1.  Check the **timestamp** of the files in `android/plugins/`:
    -   `android/plugins/GodotLiveKit.aar`
    -   `android/plugins/GodotLiveKit.gdap`
2.  Ensure they match the time you ran the build.

## 5. Exporting to Quest 3
**CRITICAL:** Updating the plugin files in `android/plugins/` does **NOT** automatically update the installed app on your Quest 3.

You must **re-export** the project:
1.  Open Godot.
2.  Go to **Project > Export**.
3.  Select the **Android** preset.
4.  Click **Export Project** (or **Export PCK/ZIP** if you are just patching).
5.  Install the new APK to your device:
    ```bash
    adb install -r <path_to_your_exported_apk>.apk
    ```
    *(Or use the "Remote Debug" feature in Godot if configured)*

## Troubleshooting
-   **Build Fails?** Check `build.gradle` for dependency versions. Ensure you are using a compatible Android Gradle Plugin version (currently 8.1.1) and Kotlin version (1.9.0).
-   **Changes not showing?** Make sure you actually re-exported the APK. The Godot Editor does not "hot reload" Android plugins.
-   **Clean Build:** If you encounter weird caching issues, run `./gradlew clean` before installing.
