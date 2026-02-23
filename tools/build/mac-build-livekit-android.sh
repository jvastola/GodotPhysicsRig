#!/usr/bin/env bash
# Build the Godot LiveKit Android Kotlin plugin and optionally the Rust Android GDExtension.
# Default behavior builds Kotlin only:
# - android/plugins/GodotLiveKit.aar + GodotLiveKit.gdap
#
# Optional flags:
# - --with-rust: also build/install addons/godot-livekit/bin/android/libgodot_livekit.so
# - --rust-only: build/install only the Rust Android GDExtension
# - --help: show usage

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RUST_DIR="${ROOT_DIR}/multiplayer/plugins/godot-livekit/rust"
ANDROID_PLUGIN_DIR="${ROOT_DIR}/multiplayer/plugins/livekit-android"
SOURCE_ADDON_DIR="${ROOT_DIR}/multiplayer/plugins/godot-livekit/addons/godot-livekit"
DEST_ADDON_DIR="${ROOT_DIR}/addons/godot-livekit"
DEST_SO_DIR="${DEST_ADDON_DIR}/bin/android"
DEST_ANDROID_PLUGIN_DIR="${ROOT_DIR}/android/plugins"
API_LEVEL="${ANDROID_API_LEVEL:-29}"
TARGET_TRIPLE="aarch64-linux-android"
BUILD_KOTLIN=true
BUILD_RUST=false

ensure_java() {
  if command -v java >/dev/null 2>&1 && java -version >/dev/null 2>&1; then
    return 0
  fi

  if [[ -d "/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home" ]]; then
    export JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
    export PATH="/opt/homebrew/opt/openjdk@17/bin:${PATH}"
  elif [[ -d "/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home" ]]; then
    export JAVA_HOME="/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home"
    export PATH="/opt/homebrew/opt/openjdk/bin:${PATH}"
  fi

  if ! command -v java >/dev/null 2>&1 || ! java -version >/dev/null 2>&1; then
    echo "ERROR: Java runtime not found."
    echo "Install with Homebrew: brew install openjdk@17"
    echo "Then set in your shell:"
    echo "  export JAVA_HOME=\"/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home\""
    echo "  export PATH=\"/opt/homebrew/opt/openjdk@17/bin:\$PATH\""
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-rust)
      BUILD_RUST=true
      shift
      ;;
    --rust-only)
      BUILD_RUST=true
      BUILD_KOTLIN=false
      shift
      ;;
    --kotlin-only)
      BUILD_KOTLIN=true
      BUILD_RUST=false
      shift
      ;;
    --help|-h)
      echo "Usage: ./tools/build/mac-build-livekit-android.sh [--with-rust|--rust-only|--kotlin-only]"
      echo "Default: Kotlin Android plugin only."
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

if [[ ! -d "${ANDROID_PLUGIN_DIR}" ]]; then
  echo "ERROR: LiveKit Android plugin source not found: ${ANDROID_PLUGIN_DIR}"
  exit 1
fi
if [[ "${BUILD_RUST}" == "true" && ! -d "${RUST_DIR}" ]]; then
  echo "ERROR: LiveKit rust source not found: ${RUST_DIR}"
  exit 1
fi

mkdir -p "${DEST_SO_DIR}" "${DEST_ANDROID_PLUGIN_DIR}"

if [[ "${BUILD_RUST}" == "true" ]]; then
  echo "Building Android Rust GDExtension (${TARGET_TRIPLE})..."
  pushd "${RUST_DIR}" >/dev/null
  rustup target add "${TARGET_TRIPLE}"

  if command -v cargo-ndk >/dev/null 2>&1; then
    cargo ndk -t arm64-v8a -p "${API_LEVEL}" build --release
  else
    if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
      echo "ERROR: cargo-ndk not found and ANDROID_NDK_HOME is not set."
      echo "Install cargo-ndk: cargo install cargo-ndk"
      exit 1
    fi

    NDK_PREBUILT_BASE="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt"
    HOST_TAG=""
    for candidate in darwin-arm64 darwin-x86_64; do
      if [[ -d "${NDK_PREBUILT_BASE}/${candidate}" ]]; then
        HOST_TAG="${candidate}"
        break
      fi
    done

    if [[ -z "${HOST_TAG}" ]]; then
      echo "ERROR: Could not locate Android NDK prebuilt toolchain in ${NDK_PREBUILT_BASE}"
      exit 1
    fi

    TOOLCHAIN_BIN="${NDK_PREBUILT_BASE}/${HOST_TAG}/bin"
    export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="${TOOLCHAIN_BIN}/aarch64-linux-android${API_LEVEL}-clang"
    export CARGO_TARGET_AARCH64_LINUX_ANDROID_AR="${TOOLCHAIN_BIN}/llvm-ar"
    cargo build --release --target "${TARGET_TRIPLE}"
  fi
  popd >/dev/null

  SOURCE_SO="${RUST_DIR}/target/${TARGET_TRIPLE}/release/libgodot_livekit.so"
  if [[ ! -f "${SOURCE_SO}" ]]; then
    echo "ERROR: Expected Android .so artifact was not produced: ${SOURCE_SO}"
    exit 1
  fi
  cp -f "${SOURCE_SO}" "${DEST_SO_DIR}/libgodot_livekit.so"
  echo "Installed: ${DEST_SO_DIR}/libgodot_livekit.so"
fi
if [[ "${BUILD_KOTLIN}" == "true" ]]; then
  ensure_java
  echo "Building Android LiveKit Kotlin plugin (AAR)..."
  pushd "${ANDROID_PLUGIN_DIR}" >/dev/null
  chmod +x ./gradlew
  ./gradlew clean assembleRelease
  popd >/dev/null

  AAR_SOURCE=""
  for candidate in \
    "${ANDROID_PLUGIN_DIR}/build/outputs/aar/GodotLiveKit-release.aar" \
    "${ANDROID_PLUGIN_DIR}/build/outputs/aar/livekit-release.aar"; do
    if [[ -f "${candidate}" ]]; then
      AAR_SOURCE="${candidate}"
      break
    fi
  done

  if [[ -z "${AAR_SOURCE}" ]]; then
    AAR_SOURCE="$(find "${ANDROID_PLUGIN_DIR}/build/outputs/aar" -maxdepth 1 -name '*.aar' | head -n 1 || true)"
  fi

  if [[ -z "${AAR_SOURCE}" ]]; then
    echo "ERROR: No AAR artifact found in ${ANDROID_PLUGIN_DIR}/build/outputs/aar"
    exit 1
  fi

  cp -f "${AAR_SOURCE}" "${DEST_ANDROID_PLUGIN_DIR}/GodotLiveKit.aar"
  if [[ -f "${ANDROID_PLUGIN_DIR}/GodotLiveKit.gdap" ]]; then
    cp -f "${ANDROID_PLUGIN_DIR}/GodotLiveKit.gdap" "${DEST_ANDROID_PLUGIN_DIR}/GodotLiveKit.gdap"
  fi

  echo "Installed: ${DEST_ANDROID_PLUGIN_DIR}/GodotLiveKit.aar"
  echo "Installed: ${DEST_ANDROID_PLUGIN_DIR}/GodotLiveKit.gdap"
fi

# Keep addon metadata in sync with plugin source.
if [[ -f "${SOURCE_ADDON_DIR}/godot-livekit.gdextension" ]]; then
  cp -f "${SOURCE_ADDON_DIR}/godot-livekit.gdextension" "${DEST_ADDON_DIR}/godot-livekit.gdextension"
fi
if [[ -f "${SOURCE_ADDON_DIR}/plugin.cfg" ]]; then
  cp -f "${SOURCE_ADDON_DIR}/plugin.cfg" "${DEST_ADDON_DIR}/plugin.cfg"
fi
