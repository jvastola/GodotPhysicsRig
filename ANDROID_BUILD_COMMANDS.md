# LiveKit Android Build Commands

Use these commands to rebuild the LiveKit GDExtension for Android (Quest 3).

## Prerequisites
- Rust installed
- Android NDK installed
- `cargo-ndk` installed (`cargo install cargo-ndk`)
- Android targets installed (`rustup target add aarch64-linux-android`)

## Build Command
Run this from the `godot-livekit/rust` directory:

```powershell
cargo ndk -t aarch64-linux-android build --release
```

## Install Command
After building, copy the library to the Godot addons folder:

```powershell
copy "target\aarch64-linux-android\release\libgodot_livekit.so" "..\..\addons\godot-livekit\bin\android\arm64-v8a\libgodot_livekit.so"
```

## One-Liner (PowerShell)
```powershell
cd godot-livekit/rust; cargo ndk -t aarch64-linux-android build --release; copy "target\aarch64-linux-android\release\libgodot_livekit.so" "..\..\addons\godot-livekit\bin\android\arm64-v8a\libgodot_livekit.so"; cd ../..
```
