# Quest 3 Android Export Configuration Guide

This guide will help you configure Godot to export the PhysicsHand project as an APK for Meta Quest 3 with LiveKit support.

## Prerequisites Complete

✅ Android SDK installed at: `C:\Users\Admin\AppData\Local\Android\Sdk`  
✅ Android NDK 29.0.14206865 installed  
✅ LiveKit Android arm64 binaries built and installed

## Godot Editor Configuration Steps

### 1. Configure Android SDK Path

1. Open Godot Editor
2. Go to `Editor > Editor Settings`
3. Navigate to `Export > Android`
4. Set **Android SDK Path**: `C:\Users\Admin\AppData\Local\Android\Sdk`
5. Click **Apply** and close

### 2. Install Android Build Template

1. Go to `Project > Install Android Build Template...`
2. Click **Install** (this creates `android/` directory in your project)

### 3. Download Android Export Templates

1. Go to `Editor > Manage Export Templates...`
2. Download templates for Godot 4.4 if not already installed
3. Close the template manager

### 4. Create Android Export Preset

1. Go to `Project > Export...`
2. Click **Add...** and select **Android**
3. Name the preset: `Quest 3`

### 5. Configure Export Preset Settings

Configure the following settings in your Quest 3 export preset:

#### Basic Settings
- **Export Path**: `builds/quest3/PhysicsHand.apk`
- **Runnable**: ✅ (Enable for one-click deploy)

#### Options Tab

**Custom Template**:
- **Use Custom Build**: ✅ Enable
- **Export Format**: APK

**Architectures**:
- **armeabi-v7a**: ❌
- **arm64-v8a**: ✅ Enable (Quest 3 requires arm64)
- **x86**: ❌
- **x86_64**: ❌

**XR Features**:
- **XR Mode**: `OpenXR`
- **Hand Tracking**: `Optional` or `None` (depending on your needs)
- **Hand Tracking Frequency**: `High`
- **Passthrough**: `Optional` or `None`

**Vendor Specific**:
- Under **XR Features**, select the **Meta** plugin/loader if available
- If you haven't installed the Godot OpenXR Vendors plugin, you can skip this

**Package**:
- **Unique Name**: `com.yourcompany.physicshand.quest3`
- **Name**: `PhysicsHand`
- **Signed**: ❌ (for debug builds)
- **Min SDK**: `29` (Quest 3 requirement)
- **Target SDK**: `33`

**Permissions**:
Enable the following permissions for LiveKit voice chat:
- **INTERNET**: ✅
- **RECORD_AUDIO**: ✅
- **MODIFY_AUDIO_SETTINGS**: ✅
- **ACCESS_NETWORK_STATE**: ✅

**Screen**:
- **Immersive Mode**: ✅ Enable

**Graphics**:
- **OpenGL Debug**: ❌ (for production)

#### Resources Tab
- **Export Mode**: Export all resources in the project

## 6. Verify Project Settings

Go to `Project > Project Settings`:

**XR**:
- `XR > OpenXR > Enabled`: ✅
- `XR > Shaders > Enabled`: ✅
- `XR > OpenXR > Foveation Level`: `3` (already set)

**Rendering**:
- `Rendering > Renderer > Rendering Method`: `gl_compatibility` (already set)
- `Rendering > Renderer > Rendering Method > Mobile`: `gl_compatibility` (already set)
- `Rendering > Textures > VRAM Compression > Import ETC2  ASTC`: ✅ (already set)

## 7. Export APK

### First Export:
1. Click **Export Project** in the Export window
2. Choose save location (e.g., `builds/quest3/PhysicsHand.apk`)
3. Wait for export to complete (may take a few minutes first time)

### Run on Quest 3:
1. Enable Developer Mode on your Quest 3:
   - Install Meta Quest mobile app
   - Go to Settings > Developer
   - Enable Developer Mode

2. Connect Quest 3 via USB to your PC

3. In Godot, with Quest 3connected and the **Quest 3** export preset selected as **Runnable**, click the **Play** button or press **F5**

4. Godot will build, deploy, and launch the app on your Quest 3 automatically!

### Manual ADB Installation (Alternative):
```powershell
# Verify Quest 3 is connected
adb devices

# Install APK
adb install -r "builds/quest3/PhysicsHand.apk"

# Monitor logs
adb logcat -s godot:V
```

## Troubleshooting

### "OpenXR failed to initialize"
- Ensure OpenXR is enabled in Project Settings
- Verify Quest 3 has the latest firmware
- Check that XR Mode is set to "OpenXR" in export preset

### "Permission denied" or "Installation failed"
- Enable Developer Mode on Quest 3
- Use `adb install -r` to replace existing installation
- Try uninstalling old version first: `adb uninstall com.yourcompany.physicshand.quest3`

### "LiveKit not loading"
- Verify `libgodot_livekit.so` exists in `addons/godot-livekit/bin/android/arm64-v8a/`
- Check gdextension file includes Android platform
- Rebuild project after adding plugins

### No audio in LiveKit
- Verify RECORD_AUDIO and MODIFY_AUDIO_SETTINGS permissions are enabled
- Check mic permissions in Quest 3 system settings for your app
- Test LiveKit connection from desktop first to verify server setup

## Next Steps

1. Open Godot Editor and follow steps 1-7 above
2. Export and test the APK on Quest 3
3. Verify LiveKit voice chat works on the headset
4. Report any issues!

## Files Created/Modified

- `addons/godot-livekit/bin/android/arm64-v8a/libgodot_livekit.so` (27.6 MB)
- `addons/godot-livekit/godot-livekit.gdextension` (updated with Android support)
- `godot-livekit/rust/Cargo.toml` (switched to rustls for Android)
