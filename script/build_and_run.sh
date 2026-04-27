#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="AURA"
BUNDLE_ID="com.wexprolabs.aura"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

check_runtime() {
  local missing=0

  if [[ ! -x "$ROOT_DIR/script/aura-hermes" ]]; then
    echo "Missing project-local Hermes wrapper: $ROOT_DIR/script/aura-hermes" >&2
    missing=1
  fi

  if [[ ! -x "$ROOT_DIR/.aura/hermes-agent/venv/bin/python3" && ! -x "$ROOT_DIR/.aura/hermes-agent/venv/bin/python" ]]; then
    echo "Missing project-local Hermes Python runtime under .aura/hermes-agent/venv" >&2
    missing=1
  fi

  if [[ ! -f "$ROOT_DIR/.aura/hermes-home/config.yaml" ]]; then
    echo "Missing project-local Hermes config: .aura/hermes-home/config.yaml" >&2
    missing=1
  fi

  if (( missing > 0 )); then
    echo "Run: cd \"$ROOT_DIR\" && ./script/setup.sh" >&2
    exit 1
  fi
}

check_runtime

swift build --product "$APP_NAME"
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

/usr/bin/codesign --force --sign - "$APP_BUNDLE" >/dev/null

open_app() {
  AURA_PROJECT_ROOT="$ROOT_DIR" /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\" || eventMessage CONTAINS \"AURA.Hermes\" || eventMessage CONTAINS \"AURA.CUAProxy\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
