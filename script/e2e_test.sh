#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HERMES="$ROOT_DIR/script/aura-hermes"
BUILD_AND_RUN="$ROOT_DIR/script/build_and_run.sh"
VERIFY_LOGGING="$ROOT_DIR/script/verify_logging.sh"
SAFE_READ_TOOLSETS="web,skills,todo,memory,session_search,clarify,delegation,cua-driver"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aura-e2e.XXXXXX")"
RUN_APP=1

export AURA_AUDIT_LEDGER_PATH="$TMP_DIR/aura-audit.jsonl"
export AURA_MISSION_ID="aura-e2e-mission"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

usage() {
  cat <<USAGE
usage: $0 [--skip-app]

Runs real end-to-end AURA checks against the project-local Hermes runtime:
  - verifies script/aura-hermes resolves to this repo's .aura Hermes checkout
  - runs real Hermes status
  - starts a real quiet Hermes mission and parses session_id
  - asks real Hermes for a NEEDS_APPROVAL gate
  - resumes that same real Hermes session with --resume
  - optionally builds and launches the macOS app through script/build_and_run.sh
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-app)
      RUN_APP=0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
  shift
done

section() {
  printf "\n==> %s\n" "$1"
}

run_capture() {
  local output_file="$1"
  shift

  if "$@" >"$output_file" 2>&1; then
    return 0
  fi

  local exit_code
  exit_code=$?
  sed -n '1,180p' "$output_file" >&2
  return "$exit_code"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"

  if [[ "$haystack" != *"$needle"* ]]; then
    printf "Expected %s to contain %q\n" "$label" "$needle" >&2
    printf "%s\n" "$haystack" >&2
    exit 1
  fi
}

assert_matches() {
  local haystack="$1"
  local pattern="$2"
  local label="$3"

  if ! printf "%s\n" "$haystack" | grep -Eiq "$pattern"; then
    printf "Expected %s to match %q\n" "$label" "$pattern" >&2
    printf "%s\n" "$haystack" >&2
    exit 1
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"

  if [[ "$haystack" == *"$needle"* ]]; then
    printf "Expected %s to not contain %q\n" "$label" "$needle" >&2
    printf "%s\n" "$haystack" >&2
    exit 1
  fi
}

session_id_from() {
  awk -F': *' 'tolower($1) == "session_id" { print $2; exit }' "$1"
}

section "Project-local Hermes wrapper"
if [[ ! -x "$HERMES" ]]; then
  printf "Missing executable Hermes wrapper: %s\n" "$HERMES" >&2
  exit 1
fi

run_capture "$TMP_DIR/version.txt" "$HERMES" version
version_output="$(<"$TMP_DIR/version.txt")"
assert_contains "$version_output" "Project: $ROOT_DIR/.aura/hermes-agent" "Hermes version output"

section "Repo-backed launch templates"
if [[ ! -f "$ROOT_DIR/config/hermes-default.yaml" ]]; then
  printf "Missing config template: %s\n" "$ROOT_DIR/config/hermes-default.yaml" >&2
  exit 1
fi

if [[ ! -f "$ROOT_DIR/.env.example" ]]; then
  printf "Missing environment template: %s\n" "$ROOT_DIR/.env.example" >&2
  exit 1
fi

assert_contains "$(<"$ROOT_DIR/config/hermes-default.yaml")" 'command: "${AURA_PROJECT_ROOT}/script/aura-cua-mcp"' "Hermes config template"
assert_contains "$(<"$ROOT_DIR/.env.example")" "OPENAI_API_KEY" "environment template"

section "Hermes status"
run_capture "$TMP_DIR/status.txt" "$HERMES" status
status_output="$(<"$TMP_DIR/status.txt")"
assert_contains "$status_output" "Provider:" "Hermes status output"
assert_contains "$status_output" "$ROOT_DIR/.aura/hermes-agent" "Hermes status output"
assert_contains "$status_output" "$ROOT_DIR/.aura/hermes-home" "Hermes status output"

section "Hermes structured sessions"
run_capture "$TMP_DIR/sessions.jsonl" "$HERMES" sessions export -
/usr/bin/python3 - "$TMP_DIR/sessions.jsonl" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    for raw in fh:
        line = raw.strip()
        if not line:
            continue
        session = json.loads(line)
        assert session.get("id"), "missing session id"
        assert "message_count" in session, "missing message_count"
        assert isinstance(session.get("messages"), list), "missing messages list"
        print(f"structured_session={session['id']}")
        break
    else:
        raise SystemExit("no structured sessions exported")
PY

section "Logging schema"
run_capture "$TMP_DIR/logging.txt" "$VERIFY_LOGGING"

section "CUA Driver readiness"
CUA_DRIVER="/Applications/CuaDriver.app/Contents/MacOS/cua-driver"
if [[ ! -x "$CUA_DRIVER" ]]; then
  printf "Missing canonical Cua Driver binary: %s\n" "$CUA_DRIVER" >&2
  exit 1
fi

run_capture "$TMP_DIR/cua-version.txt" "$CUA_DRIVER" --version
run_capture "$TMP_DIR/cua-status.txt" "$CUA_DRIVER" status
cua_status="$(<"$TMP_DIR/cua-status.txt")"
assert_contains "$cua_status" "daemon is running" "CUA Driver status"
run_capture "$TMP_DIR/cua-permissions.txt" "$CUA_DRIVER" call check_permissions '{"prompt":false}'
cua_permissions="$(<"$TMP_DIR/cua-permissions.txt")"
assert_contains "$cua_permissions" "Accessibility: granted" "CUA Driver permissions"
assert_contains "$cua_permissions" "Screen Recording: granted" "CUA Driver permissions"
run_capture "$TMP_DIR/cua-mcp.txt" "$HERMES" mcp test cua-driver
cua_mcp="$(<"$TMP_DIR/cua-mcp.txt")"
assert_contains "$cua_mcp" "Connected" "CUA MCP test output"
assert_contains "$cua_mcp" "Tools discovered" "CUA MCP test output"
assert_contains "$cua_mcp" "script/aura-cua-mcp" "CUA MCP test output"

run_capture "$TMP_DIR/hermes-tools.txt" "$HERMES" tools list --platform cli
hermes_tools="$(<"$TMP_DIR/hermes-tools.txt")"
assert_contains "$hermes_tools" "cua-driver  [include only:" "Hermes registered tool surface"
assert_contains "$hermes_tools" "check_permissions" "Hermes registered tool surface"
assert_contains "$hermes_tools" "screenshot" "Hermes registered tool surface"
assert_not_contains "$hermes_tools" "type_text" "Hermes registered tool surface"
assert_not_contains "$hermes_tools" "click" "Hermes registered tool surface"
assert_contains "$(<"$ROOT_DIR/config/hermes-default.yaml")" "tools:" "Hermes CUA config template"
assert_contains "$(<"$ROOT_DIR/config/hermes-default.yaml")" "include:" "Hermes CUA config template"
assert_contains "$(<"$ROOT_DIR/config/hermes-default.yaml")" "check_permissions" "Hermes CUA config template"
assert_contains "$(<"$ROOT_DIR/config/hermes-default.yaml")" "screenshot" "Hermes CUA config template"

section "Connection matrix"
run_capture "$TMP_DIR/connection-matrix.txt" "$ROOT_DIR/script/connection_matrix.sh"
connection_matrix="$(<"$TMP_DIR/connection-matrix.txt")"
assert_contains "$connection_matrix" "AURA connection matrix checks passed." "connection matrix"

section "Real quiet mission"
run_capture "$TMP_DIR/mission.txt" \
  "$HERMES" chat -Q --source aura-e2e --max-turns 1 \
    -t "$SAFE_READ_TOOLSETS" \
    -q "Reply exactly: AURA Hermes OK"
mission_output="$(<"$TMP_DIR/mission.txt")"
assert_contains "$mission_output" "AURA Hermes OK" "quiet mission output"
mission_session="$(session_id_from "$TMP_DIR/mission.txt")"
if [[ -z "$mission_session" ]]; then
  printf "Quiet mission did not return session_id.\n" >&2
  printf "%s\n" "$mission_output" >&2
  exit 1
fi
printf "session_id=%s\n" "$mission_session"

section "Real approval gate"
run_capture "$TMP_DIR/approval.txt" \
  "$HERMES" chat -Q --source aura-e2e --max-turns 1 \
    -t "$SAFE_READ_TOOLSETS" \
    -q $'AURA e2e approval-gate check. Do not use tools. Return exactly these two lines:\nStatus: real Hermes approval gate reached.\nNEEDS_APPROVAL: continue the harmless AURA e2e approval-resume check.'
approval_output="$(<"$TMP_DIR/approval.txt")"
assert_contains "$approval_output" "NEEDS_APPROVAL:" "approval mission output"
approval_session="$(session_id_from "$TMP_DIR/approval.txt")"
if [[ -z "$approval_session" ]]; then
  printf "Approval mission did not return session_id.\n" >&2
  printf "%s\n" "$approval_output" >&2
  exit 1
fi
printf "approval_session_id=%s\n" "$approval_session"

section "Real approval resume"
run_capture "$TMP_DIR/resume.txt" \
  "$HERMES" chat -Q --source aura-e2e --max-turns 1 --resume "$approval_session" \
    -t "$SAFE_READ_TOOLSETS" \
    -q "Continue the AURA e2e approval-resume check. Do not use tools. Reply exactly: Status: real Hermes approval resume completed."
resume_output="$(<"$TMP_DIR/resume.txt")"
assert_contains "$resume_output" "real Hermes approval resume completed" "resume output"
assert_contains "$resume_output" "session_id: $approval_session" "resume output"

section "Audit ledger"
/usr/bin/python3 - "$AURA_AUDIT_LEDGER_PATH" <<'PY'
import json
import sys

path = sys.argv[1]
events = set()
raw = ""
missing_mission_id = []
cua_timing_errors = []
with open(path, "r", encoding="utf-8") as fh:
    for line in fh:
        raw += line
        payload = json.loads(line)
        event = payload.get("event")
        if event:
            events.add(event)
        if payload.get("mission_id") != "aura-e2e-mission":
            missing_mission_id.append(event or "<unknown>")
        if event in {"cua_proxy_start", "cua_proxy_stop"} and "duration_ms" not in payload:
            cua_timing_errors.append(event)

required = {"hermes_wrapper_quiet_start", "hermes_wrapper_quiet_finish"}
missing = required - events
if missing:
    raise SystemExit(f"missing audit events: {sorted(missing)}")

if missing_mission_id:
    raise SystemExit(f"audit entries missing correlated mission_id: {missing_mission_id[:5]}")

if cua_timing_errors:
    raise SystemExit(f"CUA proxy audit entries missing duration_ms: {cua_timing_errors}")

for forbidden in (
    "Reply exactly: AURA Hermes OK",
    "AURA e2e approval-gate check",
    "Continue the AURA e2e approval-resume check",
):
    if forbidden in raw:
        raise SystemExit(f"audit ledger leaked prompt content: {forbidden!r}")

print(f"audit_events={len(events)}")
PY

if [[ "$RUN_APP" == "1" ]]; then
  section "App build and launch"
  run_capture "$TMP_DIR/app-verify.txt" "$BUILD_AND_RUN" --verify
else
  section "App build and launch skipped"
fi

printf "\nAURA e2e checks passed.\n"
