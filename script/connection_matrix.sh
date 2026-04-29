#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HERMES="$ROOT_DIR/script/aura-hermes"
DEFAULT_AURA_CUA_DRIVER="$ROOT_DIR/dist/AURA.app/Contents/MacOS/cua-driver"
if [[ -n "${AURA_CUA_DRIVER:-}" ]]; then
  CUA_DRIVER="$AURA_CUA_DRIVER"
elif [[ -x "$DEFAULT_AURA_CUA_DRIVER" ]]; then
  CUA_DRIVER="$DEFAULT_AURA_CUA_DRIVER"
else
  CUA_DRIVER="/Applications/CuaDriver.app/Contents/MacOS/cua-driver"
fi
TMP_DIR="${TMPDIR:-/tmp}/aura-connection-matrix.$$"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT
mkdir -p "$TMP_DIR"

section() {
  printf "\n==> %s\n" "$1"
}

fail() {
  printf "FAIL: %s\n" "$1" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    fail "$label missing '$needle'"
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    fail "$label unexpectedly contained '$needle'"
  fi
}

assert_any_contains() {
  local haystack="$1"
  local label="$2"
  shift 2

  local needle
  for needle in "$@"; do
    if [[ "$haystack" == *"$needle"* ]]; then
      return 0
    fi
  done

  fail "$label missing all expected markers: $*"
}

run_capture() {
  local output_file="$1"
  shift
  "$@" >"$output_file" 2>&1
}

section "Hermes runtime"
run_capture "$TMP_DIR/status.txt" "$HERMES" status
status_output="$(<"$TMP_DIR/status.txt")"
assert_contains "$status_output" "Project:" "Hermes status"
assert_contains "$status_output" "Provider:" "Hermes status"
assert_contains "$status_output" "Model:" "Hermes status"

section "Hermes config and tools"
run_capture "$TMP_DIR/config-check.txt" "$HERMES" config check
config_output="$(<"$TMP_DIR/config-check.txt")"
assert_contains "$config_output" "Configuration Status" "Hermes config check"
run_capture "$TMP_DIR/tools.txt" "$HERMES" tools list --platform cli
tools_output="$(<"$TMP_DIR/tools.txt")"
assert_contains "$tools_output" "Built-in toolsets (cli)" "Hermes tools list"
assert_contains "$tools_output" "✓ enabled  computer_use" "Hermes tools list"

section "Host context pack"
[[ -x "$CUA_DRIVER" ]] || fail "Missing CUA Driver binary: $CUA_DRIVER"
run_capture "$TMP_DIR/cua-status.txt" "$CUA_DRIVER" status
cua_status="$(<"$TMP_DIR/cua-status.txt")"
assert_contains "$cua_status" "daemon is running" "CUA status"
run_capture "$TMP_DIR/cua-permissions.txt" "$CUA_DRIVER" call check_permissions '{"prompt":false}'
cua_permissions="$(<"$TMP_DIR/cua-permissions.txt")"
assert_contains "$cua_permissions" "Accessibility: granted" "CUA permissions"
assert_contains "$cua_permissions" "Screen Recording: granted" "CUA permissions"

section "Local artifact pack"
assert_any_contains "$tools_output" "Local artifact toolsets" "✓ enabled  terminal" "✗ disabled  terminal"
assert_any_contains "$tools_output" "Local artifact toolsets" "✓ enabled  file" "✗ disabled  file"
assert_any_contains "$tools_output" "Local artifact toolsets" "✓ enabled  code_execution" "✗ disabled  code_execution"

section "Web and browser packs"
assert_any_contains "$tools_output" "Web toolset" "✓ enabled  web" "✗ disabled  web"
assert_any_contains "$tools_output" "Browser toolset" "✓ enabled  browser" "✗ disabled  browser"
assert_any_contains "$config_output" "Web provider setup" "EXA_API_KEY" "TAVILY_API_KEY" "FIRECRAWL_API_KEY" "Configuration Status"
assert_any_contains "$config_output" "Browser provider setup" "BROWSERBASE_API_KEY" "BROWSER_USE_API_KEY" "CAMOFOX_URL" "Configuration Status"

section "Apple app skills"
run_capture "$TMP_DIR/skills.txt" "$HERMES" skills list
skills_output="$(<"$TMP_DIR/skills.txt")"
assert_contains "$skills_output" "apple-notes" "Hermes skills list"
assert_contains "$skills_output" "apple-reminders" "Hermes skills list"
assert_contains "$skills_output" "imessage" "Hermes skills list"
assert_contains "$skills_output" "findmy" "Hermes skills list"

section "Messaging pack"
assert_contains "$status_output" "Messaging Platforms" "Hermes status"
assert_any_contains "$tools_output" "Messaging toolset" "✓ enabled  messaging" "✗ disabled  messaging"
assert_any_contains "$status_output" "Messaging configured/degraded state" "not configured" "Telegram"

section "Cron pack"
run_capture "$TMP_DIR/cron.txt" "$HERMES" cron list
cron_output="$(<"$TMP_DIR/cron.txt")"
assert_any_contains "$cron_output" "Hermes cron list" "No scheduled jobs" "ID" "Name"

section "External MCP pack"
run_capture "$TMP_DIR/mcp-list.txt" "$HERMES" mcp list
mcp_list="$(<"$TMP_DIR/mcp-list.txt")"
assert_any_contains "$mcp_list" "Hermes MCP list" "MCP Servers" "No MCP servers configured"
assert_not_contains "$mcp_list" "cua-driver" "Hermes MCP list"

printf "\nAURA connection matrix checks passed.\n"
