#!/usr/bin/env bash
# Build the Godot LiveKit desktop GDExtension (macOS) and install it into this project.
# Usage:
#   ./tools/build/mac-build-livekit-desktop.sh
#   ./tools/build/mac-build-livekit-desktop.sh --native-only

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RUST_DIR="${ROOT_DIR}/multiplayer/plugins/godot-livekit/rust"
SOURCE_ADDON_DIR="${ROOT_DIR}/multiplayer/plugins/godot-livekit/addons/godot-livekit"
DEST_ADDON_DIR="${ROOT_DIR}/addons/godot-livekit"
DEST_BIN_DIR="${DEST_ADDON_DIR}/bin/macos"
DEST_LIB="${DEST_BIN_DIR}/libgodot_livekit.dylib"

MODE="universal"
if [[ "${1:-}" == "--native-only" ]]; then
  MODE="native"
fi

if [[ ! -d "${RUST_DIR}" ]]; then
  echo "ERROR: LiveKit rust source not found: ${RUST_DIR}"
  exit 1
fi

mkdir -p "${DEST_BIN_DIR}"

pushd "${RUST_DIR}" >/dev/null

if [[ "${MODE}" == "universal" ]]; then
  echo "Building universal macOS binary (arm64 + x86_64)..."
  rustup target add aarch64-apple-darwin x86_64-apple-darwin
  cargo build --release --target aarch64-apple-darwin
  cargo build --release --target x86_64-apple-darwin

  ARM_LIB="${RUST_DIR}/target/aarch64-apple-darwin/release/libgodot_livekit.dylib"
  X64_LIB="${RUST_DIR}/target/x86_64-apple-darwin/release/libgodot_livekit.dylib"

  if [[ ! -f "${ARM_LIB}" || ! -f "${X64_LIB}" ]]; then
    echo "ERROR: Expected macOS artifacts were not produced."
    exit 1
  fi

  lipo -create "${ARM_LIB}" "${X64_LIB}" -output "${DEST_LIB}"
else
  HOST_ARCH="$(uname -m)"
  case "${HOST_ARCH}" in
    arm64) TARGET_TRIPLE="aarch64-apple-darwin" ;;
    x86_64) TARGET_TRIPLE="x86_64-apple-darwin" ;;
    *)
      echo "ERROR: Unsupported host architecture: ${HOST_ARCH}"
      exit 1
      ;;
  esac

  echo "Building native macOS binary (${TARGET_TRIPLE})..."
  rustup target add "${TARGET_TRIPLE}"
  cargo build --release --target "${TARGET_TRIPLE}"
  cp -f "${RUST_DIR}/target/${TARGET_TRIPLE}/release/libgodot_livekit.dylib" "${DEST_LIB}"
fi

popd >/dev/null

# Keep addon metadata in sync with plugin source.
if [[ -f "${SOURCE_ADDON_DIR}/godot-livekit.gdextension" ]]; then
  cp -f "${SOURCE_ADDON_DIR}/godot-livekit.gdextension" "${DEST_ADDON_DIR}/godot-livekit.gdextension"
fi
if [[ -f "${SOURCE_ADDON_DIR}/plugin.cfg" ]]; then
  cp -f "${SOURCE_ADDON_DIR}/plugin.cfg" "${DEST_ADDON_DIR}/plugin.cfg"
fi

echo "Installed: ${DEST_LIB}"

