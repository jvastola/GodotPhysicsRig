#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
HOST="$(hostname -s 2>/dev/null || hostname)"
OUT_DIR="${1:-/tmp/quest-manifest-diag-${HOST}-${STAMP}}"
mkdir -p "$OUT_DIR"

REPORT="$OUT_DIR/report.txt"
APK_PATH="${2:-$ROOT_DIR/android/scenetree.apk}"

section() {
  printf "\n===== %s =====\n" "$1" | tee -a "$REPORT"
}

run() {
  {
    printf "$ %s\n" "$*"
    eval "$@"
  } >>"$REPORT" 2>&1 || {
    printf "[command failed]\n" >>"$REPORT"
  }
}

section "Environment"
run "date -u"
run "uname -a"
if command -v sw_vers >/dev/null 2>&1; then
  run "sw_vers"
fi
run "pwd"
if command -v git >/dev/null 2>&1; then
  run "git rev-parse --short HEAD"
  run "git status --short"
fi

section "Godot Toolchain"
if [[ -n "${GODOT_PATH:-}" && -x "${GODOT_PATH}" ]]; then
  GODOT_BIN="${GODOT_PATH}"
elif [[ -x "/Applications/Godot.app/Contents/MacOS/godot" ]]; then
  GODOT_BIN="/Applications/Godot.app/Contents/MacOS/godot"
else
  GODOT_BIN=""
fi
if [[ -n "$GODOT_BIN" ]]; then
  run "\"$GODOT_BIN\" --version"
  printf "Godot binary: %s\n" "$GODOT_BIN" >>"$REPORT"
else
  printf "Godot binary: not found\n" >>"$REPORT"
fi
run "java -version"

section "Project XR Settings"
if command -v rg >/dev/null 2>&1; then
  run "rg -n \"^\\[editor_plugins\\]|^enabled=|openxr|xr_features|meta_xr_features|plugins/|gradle_build/min_sdk|gradle_build/target_sdk|version/code|version/name\" project.godot export_presets.cfg -S"
else
  run "grep -nE \"^\\[editor_plugins\\]|^enabled=|openxr|xr_features|meta_xr_features|plugins/|gradle_build/min_sdk|gradle_build/target_sdk|version/code|version/name\" project.godot export_presets.cfg"
fi

section "Addon/Plugin Inventory"
run "ls -la addons"
run "find addons/godotopenxrvendors -maxdepth 5 -type f | sort"
run "find addons/godotopenxrvendors -type f | wc -l"
run "find addons/godotopenxrvendors -type f -name '*.aar' | sort"
run "find android/plugins -maxdepth 2 -type f | sort"
run "find android/plugins -maxdepth 2 -type f -name '*.aar' -o -name '*.gdap' | sort"
if command -v shasum >/dev/null 2>&1; then
  run "find android/plugins -maxdepth 2 -type f \\( -name '*.aar' -o -name '*.gdap' \\) -print0 | xargs -0 shasum -a 256"
fi

section "Godot Cache State"
run "cat .godot/extension_list.cfg"
if command -v rg >/dev/null 2>&1; then
  run "rg -n \"godotopenxrvendors|openxr|meta\" .godot/editor/filesystem_cache10 -S"
else
  run "grep -nE \"godotopenxrvendors|openxr|meta\" .godot/editor/filesystem_cache10"
fi

section "Android Build Manifests"
run "find android/build -name AndroidManifest.xml -print | sort"
if command -v rg >/dev/null 2>&1; then
  run "rg -n \"com\\.oculus\\.intent\\.category\\.VR|com\\.oculus\\.vr\\.focusaware|com\\.oculus\\.supportedDevices|IMMERSIVE_HMD|android\\.hardware\\.vr\\.headtracking\" android/build -S"
else
  run "grep -R -nE \"com\\.oculus\\.intent\\.category\\.VR|com\\.oculus\\.vr\\.focusaware|com\\.oculus\\.supportedDevices|IMMERSIVE_HMD|android\\.hardware\\.vr\\.headtracking\" android/build"
fi

section "APK Manifest"
SDK_ROOT="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
AAPT_BIN=""
if [[ -d "$SDK_ROOT/build-tools" ]]; then
  AAPT_BIN="$(find "$SDK_ROOT/build-tools" -name aapt -type f | sort -V | tail -n 1 || true)"
fi
if [[ -n "$AAPT_BIN" && -f "$APK_PATH" ]]; then
  printf "Using aapt: %s\n" "$AAPT_BIN" >>"$REPORT"
  "$AAPT_BIN" dump xmltree "$APK_PATH" AndroidManifest.xml >"$OUT_DIR/apk_manifest_xmltree.txt" 2>&1 || true
  if command -v rg >/dev/null 2>&1; then
    run "rg -n \"com\\.oculus\\.intent\\.category\\.VR|com\\.oculus\\.vr\\.focusaware|com\\.oculus\\.supportedDevices|IMMERSIVE_HMD|android\\.hardware\\.vr\\.headtracking\" \"$OUT_DIR/apk_manifest_xmltree.txt\" -S"
  else
    run "grep -nE \"com\\.oculus\\.intent\\.category\\.VR|com\\.oculus\\.vr\\.focusaware|com\\.oculus\\.supportedDevices|IMMERSIVE_HMD|android\\.hardware\\.vr\\.headtracking\" \"$OUT_DIR/apk_manifest_xmltree.txt\""
  fi
else
  printf "aapt/apk missing. aapt=%s apk=%s\n" "${AAPT_BIN:-missing}" "$APK_PATH" >>"$REPORT"
fi

printf "\nWrote diagnostics to: %s\n" "$OUT_DIR" | tee -a "$REPORT"
