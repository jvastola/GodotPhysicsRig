# Meta VRC Security Fix

This document explains how to fix the security issues flagged by Meta's VRC (Virtual Reality Check) scanner.

## Issues Addressed

### 1. Insecure HostnameVerifier (OkHttp ConscryptPlatform)
- **Location**: `okhttp3.internal.platform.ConscryptPlatform`
- **Cause**: OkHttp bundles a class that uses Conscrypt for TLS, which Meta flags as insecure
- **Fix**: Remove the ConscryptPlatform class from OkHttp JAR

### 2. Unsafe SSL TrustManager (JAIN-SIP)
- **Location**: `android.gov.nist.core.net.SslNetworkLayer`, `android.gov.nist.javax.sip.stack.NioTlsMessageProcessor`
- **Cause**: LiveKit depends on JAIN-SIP library which has unsafe SSL implementations
- **Fix**: Exclude the JAIN-SIP dependency entirely

## Quick Setup

Run these commands from the `android/build` directory:

```bash
# 1. Create patched OkHttp (removes ConscryptPlatform)
./gradlew setupMetaVRCSecurity

# 2. Clean the build
rm -rf build

# 3. Export from Godot (with "Use Gradle Build" enabled)
# ... export your APK ...

# 4. Verify the APK
../verify_apk_security.sh ../scenetree.apk
```

## What the Fix Does

### Automatic (via build.gradle)
- Excludes `org.conscrypt:conscrypt-android` dependency
- Excludes `javax.sip:android-jain-sip-ri` dependency (JAIN-SIP)
- Enables R8 minification with ProGuard rules to strip unused code
- Uses patched OkHttp JAR if available

### Manual (via setupMetaVRCSecurity task)
- Downloads OkHttp 4.12.0 from Maven Central
- Removes `ConscryptPlatform` class and related classes
- Creates patched JAR at `libs/patched/okhttp-4.12.0-patched.jar`
- Verifies the patched JAR doesn't contain problematic classes

## Verification

After building your APK, run the verification script:

```bash
./verify_apk_security.sh path/to/your.apk
```

This will check for:
- ConscryptPlatform class
- JAIN-SIP classes (android.gov.nist.*)
- Other SSL-related problematic classes

## Troubleshooting

### Issue still appears after fix
1. Make sure you ran `./gradlew setupMetaVRCSecurity`
2. Clean the build: `rm -rf android/build/build`
3. Re-export from Godot
4. Verify with `./verify_apk_security.sh`

### Build fails after excluding OkHttp
The patched OkHttp JAR must exist before building. Run:
```bash
cd android/build
./gradlew patchOkHttpForMetaVRC
```

### JAIN-SIP classes still present
Check if another dependency is pulling in JAIN-SIP. The exclusion should be global, but some dependencies might bundle it directly.

## Files Modified

- `android/build/build.gradle` - Added exclusions and patched OkHttp support
- `android/build/proguard-rules.pro` - R8 rules to strip problematic classes
- `android/build/gradle.properties` - Enabled R8 full mode
- `android/build/strip_okhttp.gradle` - OkHttp patching tasks
- `android/verify_apk_security.sh` - APK verification script

## Notes

- The JAIN-SIP exclusion may affect SIP functionality if your app uses it (unlikely for most VR apps)
- The patched OkHttp removes Conscrypt support, falling back to Android's default TLS
- This should not affect normal HTTPS functionality
