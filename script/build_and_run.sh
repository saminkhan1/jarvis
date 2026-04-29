#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="AURA"
BUNDLE_ID="com.wexprolabs.aura"
CUA_PROCESS_NAME="cua-driver"
CUA_BUNDLE_ID="com.trycua.driver"
CUA_SOURCE_BINARY="/Applications/CuaDriver.app/Contents/MacOS/cua-driver"
CUA_HELPER_NAME="cua-driver"
CUA_LAUNCH_AGENT_LABEL="com.trycua.cua_driver_daemon"
MIN_SYSTEM_VERSION="14.0"
DEFAULT_CODESIGN_IDENTITY="AURA Local Development"
CODESIGN_IDENTITY="${AURA_CODESIGN_IDENTITY:-$DEFAULT_CODESIGN_IDENTITY}"
AURA_RESET_TCC_ON_BUILD="${AURA_RESET_TCC_ON_BUILD:-0}"
AURA_RESET_CUA_TCC_ON_BUILD="${AURA_RESET_CUA_TCC_ON_BUILD:-1}"
AURA_DISABLE_EXTERNAL_CUA_LAUNCH_AGENT_ON_BUILD="${AURA_DISABLE_EXTERNAL_CUA_LAUNCH_AGENT_ON_BUILD:-1}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_HOME="${HOME:-}"
if [[ -n "${SUDO_USER:-}" ]]; then
  DSCL_HOME="$(/usr/bin/dscl . -read "/Users/$SUDO_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2; exit}' || true)"
  if [[ -n "$DSCL_HOME" && -d "$DSCL_HOME" ]]; then
    REAL_HOME="$DSCL_HOME"
  fi
fi
if [[ -z "$REAL_HOME" || ! -d "$REAL_HOME" ]]; then
  REAL_HOME="$HOME"
fi
LOGIN_KEYCHAIN="$REAL_HOME/Library/Keychains/login.keychain-db"
OPENSSL_BIN="/usr/bin/openssl"
if [[ -x /opt/homebrew/bin/openssl ]]; then
  OPENSSL_BIN="/opt/homebrew/bin/openssl"
fi
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
CUA_HELPER_BINARY="$APP_MACOS/$CUA_HELPER_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

usage() {
  echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
  echo "env: AURA_RESET_TCC_ON_BUILD=1 resets AURA privacy grants, including Microphone" >&2
  echo "env: AURA_RESET_CUA_TCC_ON_BUILD=0 preserves CUA privacy grants" >&2
  echo "env: AURA_DISABLE_EXTERNAL_CUA_LAUNCH_AGENT_ON_BUILD=0 preserves the upstream CUA LaunchAgent" >&2
}

validate_mode() {
  case "$MODE" in
    run|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify)
      ;;
    *)
      usage
      exit 2
      ;;
  esac
}

stop_existing_apps() {
  stop_external_cua_launch_agent
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  pkill -x "$CUA_PROCESS_NAME" >/dev/null 2>&1 || true
  pkill -f "$CUA_SOURCE_BINARY" >/dev/null 2>&1 || true
  pkill -f "$CUA_HELPER_BINARY" >/dev/null 2>&1 || true
}

stop_external_cua_launch_agent() {
  if [[ "$AURA_DISABLE_EXTERNAL_CUA_LAUNCH_AGENT_ON_BUILD" == "0" ]]; then
    return 0
  fi

  local launch_domain
  launch_domain="gui/$(id -u)"

  if /bin/launchctl print "$launch_domain/$CUA_LAUNCH_AGENT_LABEL" >/dev/null 2>&1; then
    echo "Stopping external CUA LaunchAgent: $CUA_LAUNCH_AGENT_LABEL" >&2
    /bin/launchctl bootout "$launch_domain/$CUA_LAUNCH_AGENT_LABEL" >/dev/null 2>&1 || true
  fi

  /bin/launchctl disable "$launch_domain/$CUA_LAUNCH_AGENT_LABEL" >/dev/null 2>&1 || true
}

reset_privacy_decisions() {
  if [[ "$AURA_RESET_TCC_ON_BUILD" != "0" ]]; then
    echo "Resetting macOS privacy decisions for $BUNDLE_ID" >&2
    /usr/bin/tccutil reset All "$BUNDLE_ID" >/dev/null 2>&1 || true
  fi

  if [[ "$AURA_RESET_CUA_TCC_ON_BUILD" != "0" ]]; then
    echo "Resetting macOS privacy decisions for $CUA_BUNDLE_ID" >&2
    /usr/bin/tccutil reset All "$CUA_BUNDLE_ID" >/dev/null 2>&1 || true
  fi

  /usr/bin/killall "System Settings" >/dev/null 2>&1 || true
}

prepare_dev_permissions() {
  stop_existing_apps
  reset_privacy_decisions
}

validate_mode
prepare_dev_permissions

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

has_codesign_identity() {
  HOME="$REAL_HOME" /usr/bin/security find-identity -v -p codesigning "$LOGIN_KEYCHAIN" 2>/dev/null | grep -F "\"$CODESIGN_IDENTITY\"" >/dev/null
}

create_local_codesign_identity() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap "rm -rf '$tmp_dir'" RETURN

  HOME="$REAL_HOME" /usr/bin/security delete-certificate \
    -c "$DEFAULT_CODESIGN_IDENTITY" \
    "$LOGIN_KEYCHAIN" >/dev/null 2>&1 || true

  "$OPENSSL_BIN" req \
    -newkey rsa:2048 \
    -nodes \
    -keyout "$tmp_dir/aura-local-dev.key" \
    -x509 \
    -days 3650 \
    -out "$tmp_dir/aura-local-dev.crt" \
    -subj "/CN=$DEFAULT_CODESIGN_IDENTITY" \
    -addext "basicConstraints=critical,CA:FALSE" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" >/dev/null 2>&1

  "$OPENSSL_BIN" pkcs8 \
    -topk8 \
    -nocrypt \
    -in "$tmp_dir/aura-local-dev.key" \
    -out "$tmp_dir/aura-local-dev.pkcs8" >/dev/null 2>&1

  HOME="$REAL_HOME" /usr/bin/certtool i "$tmp_dir/aura-local-dev.crt" \
    k="$LOGIN_KEYCHAIN" \
    r="$tmp_dir/aura-local-dev.pkcs8" \
    f=8 \
    a >/dev/null 2>&1

  HOME="$REAL_HOME" /usr/bin/security add-trusted-cert \
    -r trustRoot \
    -p codeSign \
    -k "$LOGIN_KEYCHAIN" \
    "$tmp_dir/aura-local-dev.crt" >/dev/null 2>&1 || true
}

ensure_codesign_identity() {
  if has_codesign_identity; then
    return 0
  fi

  if [[ "$CODESIGN_IDENTITY" != "$DEFAULT_CODESIGN_IDENTITY" ]]; then
    echo "Missing requested code signing identity: $CODESIGN_IDENTITY" >&2
    echo "Set AURA_CODESIGN_IDENTITY to an installed stable local development identity." >&2
    exit 1
  fi

  echo "Creating stable local code signing identity: $DEFAULT_CODESIGN_IDENTITY" >&2
  create_local_codesign_identity || {
    echo "Could not create $DEFAULT_CODESIGN_IDENTITY in the login keychain." >&2
    echo "Create a stable code signing certificate manually or set AURA_CODESIGN_IDENTITY." >&2
    exit 1
  }

  if ! has_codesign_identity; then
    echo "Created identity was not visible to codesign: $DEFAULT_CODESIGN_IDENTITY" >&2
    exit 1
  fi
}

ensure_codesign_identity

swift build --product "$APP_NAME"
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

if [[ -x "$CUA_SOURCE_BINARY" ]]; then
  cp "$CUA_SOURCE_BINARY" "$CUA_HELPER_BINARY"
  chmod +x "$CUA_HELPER_BINARY"
else
  echo "Warning: missing CUA source binary; host-control helper will not be embedded: $CUA_SOURCE_BINARY" >&2
fi

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
  <key>NSMicrophoneUsageDescription</key>
  <string>AURA records your spoken mission request when you use in-app voice input.</string>
  <key>NSRemindersUsageDescription</key>
  <string>AURA may access Reminders when you ask it to manage reminders through Hermes tools.</string>
  <key>NSCalendarsUsageDescription</key>
  <string>AURA may access Calendar when you ask it to manage calendar events through Hermes tools.</string>
  <key>NSContactsUsageDescription</key>
  <string>AURA may access Contacts when you ask it to use contact details through Hermes tools.</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>AURA may send Apple Events to apps when you ask Hermes to broker Mac automation.</string>
</dict>
</plist>
PLIST

if [[ -x "$CUA_HELPER_BINARY" ]]; then
  HOME="$REAL_HOME" /usr/bin/codesign \
    --force \
    --sign "$CODESIGN_IDENTITY" \
    --identifier "$BUNDLE_ID" \
    --keychain "$LOGIN_KEYCHAIN" \
    "$CUA_HELPER_BINARY" >/dev/null
fi

HOME="$REAL_HOME" /usr/bin/codesign --force --sign "$CODESIGN_IDENTITY" --keychain "$LOGIN_KEYCHAIN" "$APP_BUNDLE" >/dev/null

open_app() {
  HOME="$REAL_HOME" /usr/bin/open \
    -n \
    --env "AURA_PROJECT_ROOT=$ROOT_DIR" \
    --env "HERMES_CUA_DRIVER_CMD=$CUA_HELPER_BINARY" \
    "$APP_BUNDLE"
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
    usage
    exit 2
    ;;
esac
