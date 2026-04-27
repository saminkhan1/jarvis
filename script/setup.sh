#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AURA_DIR="$ROOT_DIR/.aura"
AURA_HOME="$AURA_DIR/home"
HERMES_HOME="$AURA_DIR/hermes-home"
HERMES_AGENT_DIR="$AURA_DIR/hermes-agent"
HERMES_REPO="${AURA_HERMES_REPO:-https://github.com/NousResearch/hermes-agent.git}"
HERMES_REF="${AURA_HERMES_REF:-edc78e258c394be5804ea3c7a844fd965aaf121a}"
MIN_MACOS_MAJOR=14
CHECK_ONLY=0
WARNINGS=0
ERRORS=0

usage() {
  cat <<USAGE
usage: $0 [--check]

Sets up the repo-backed AURA MVP runtime:
  - checks macOS, Swift/Xcode CLT, git, Python, and CUA Driver
  - installs or validates project-local Hermes under .aura/hermes-agent
  - seeds .aura/hermes-home/config.yaml and .aura/hermes-home/.env if missing
  - performs passive CUA daemon and permission checks

Options:
  --check   validate only; do not create, clone, install, update, or copy files
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)
      CHECK_ONLY=1
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

ok() {
  printf "  OK: %s\n" "$1"
}

warn() {
  WARNINGS=$((WARNINGS + 1))
  printf "  WARN: %s\n" "$1" >&2
}

fail() {
  ERRORS=$((ERRORS + 1))
  printf "  FAIL: %s\n" "$1" >&2
}

version_major() {
  printf "%s" "$1" | awk -F. '{print $1}'
}

lowercase() {
  printf "%s" "$1" | tr '[:upper:]' '[:lower:]'
}

find_python_for_hermes() {
  local candidate
  for candidate in python3.11 python3; do
    if command -v "$candidate" >/dev/null 2>&1; then
      if "$candidate" - <<'PY' >/dev/null 2>&1
import sys
raise SystemExit(0 if sys.version_info >= (3, 11) else 1)
PY
      then
        command -v "$candidate"
        return 0
      fi
    fi
  done
  return 1
}

check_host() {
  section "Host requirements"

  if [[ "$(uname -s)" != "Darwin" ]]; then
    fail "AURA is a macOS app; this setup script requires Darwin/macOS."
  else
    local macos_version major
    macos_version="$(sw_vers -productVersion 2>/dev/null || echo "unknown")"
    major="$(version_major "$macos_version")"
    if [[ "$major" =~ ^[0-9]+$ ]] && (( major >= MIN_MACOS_MAJOR )); then
      ok "macOS $macos_version"
    else
      fail "macOS 14 or newer is required for the current MVP; found $macos_version."
    fi
  fi

  if xcode-select -p >/dev/null 2>&1 && xcrun --find swift >/dev/null 2>&1; then
    ok "Xcode Command Line Tools and Swift are available"
  else
    fail "Install Xcode Command Line Tools: xcode-select --install"
  fi

  if command -v git >/dev/null 2>&1; then
    ok "git is available"
  else
    fail "Install git before running setup."
  fi

  if find_python_for_hermes >/dev/null; then
    ok "Python 3.11+ is available for Hermes"
  elif command -v uv >/dev/null 2>&1; then
    ok "uv is available and can provision Python 3.11 for Hermes"
  else
    fail "Install Python 3.11+ or uv before running setup."
  fi
}

ensure_directories() {
  section "AURA directories"

  if [[ "$CHECK_ONLY" == "1" ]]; then
    for path in "$AURA_DIR" "$AURA_HOME" "$HERMES_HOME"; do
      if [[ -d "$path" ]]; then
        ok "$path exists"
      else
        warn "$path is missing; setup will create it"
      fi
    done
    return
  fi

  mkdir -p "$AURA_HOME" "$HERMES_HOME"
  ok "Prepared .aura/home and .aura/hermes-home"
}

ensure_hermes_checkout() {
  section "Project-local Hermes checkout"

  if ! command -v git >/dev/null 2>&1; then
    fail "git is required before Hermes can be installed or updated."
    return
  fi

  if [[ -d "$HERMES_AGENT_DIR/.git" ]]; then
    local head
    head="$(git -C "$HERMES_AGENT_DIR" rev-parse HEAD 2>/dev/null || true)"
    if [[ "$head" == "$HERMES_REF" ]]; then
      ok "Hermes checkout is pinned at $HERMES_REF"
      return
    fi

    if [[ "$CHECK_ONLY" == "1" ]]; then
      warn "Hermes checkout is at ${head:-unknown}; setup will move it to $HERMES_REF if clean"
      return
    fi

    if [[ -n "$(git -C "$HERMES_AGENT_DIR" status --porcelain 2>/dev/null || true)" ]]; then
      warn "Hermes checkout has local changes; leaving it at ${head:-unknown}"
      return
    fi

    git -C "$HERMES_AGENT_DIR" fetch --quiet origin
    git -C "$HERMES_AGENT_DIR" checkout --quiet "$HERMES_REF"
    ok "Updated Hermes checkout to $HERMES_REF"
    return
  fi

  if [[ -e "$HERMES_AGENT_DIR" ]]; then
    fail "$HERMES_AGENT_DIR exists but is not a git checkout. Move it aside and rerun setup."
    return
  fi

  if [[ "$CHECK_ONLY" == "1" ]]; then
    warn "Hermes checkout is missing; setup will clone $HERMES_REPO"
    return
  fi

  mkdir -p "$AURA_DIR"
  git clone "$HERMES_REPO" "$HERMES_AGENT_DIR"
  git -C "$HERMES_AGENT_DIR" checkout --quiet "$HERMES_REF"
  ok "Cloned Hermes checkout at $HERMES_REF"
}

ensure_hermes_venv() {
  section "Project-local Hermes Python environment"

  local hermes_python="$HERMES_AGENT_DIR/venv/bin/python3"
  [[ -x "$hermes_python" ]] || hermes_python="$HERMES_AGENT_DIR/venv/bin/python"

  if [[ -x "$hermes_python" && -x "$HERMES_AGENT_DIR/venv/bin/hermes" ]]; then
    ok "Hermes virtual environment exists"
    return
  fi

  if [[ "$CHECK_ONLY" == "1" ]]; then
    warn "Hermes virtual environment is missing; setup will create it under .aura/hermes-agent/venv"
    return
  fi

  if [[ ! -d "$HERMES_AGENT_DIR" ]]; then
    fail "Hermes checkout is missing; cannot create virtual environment."
    return
  fi

  if command -v uv >/dev/null 2>&1; then
    (cd "$HERMES_AGENT_DIR" && uv venv venv --python 3.11)
    if [[ -f "$HERMES_AGENT_DIR/uv.lock" ]]; then
      (cd "$HERMES_AGENT_DIR" && UV_PROJECT_ENVIRONMENT="$HERMES_AGENT_DIR/venv" uv sync --all-extras --locked) \
        || (cd "$HERMES_AGENT_DIR" && uv pip install -e ".[all]")
    else
      (cd "$HERMES_AGENT_DIR" && uv pip install -e ".[all]")
    fi
  else
    local python_cmd
    if ! python_cmd="$(find_python_for_hermes)"; then
      fail "Python 3.11+ or uv is required to create the Hermes virtual environment."
      return
    fi
    "$python_cmd" -m venv "$HERMES_AGENT_DIR/venv"
    "$HERMES_AGENT_DIR/venv/bin/python" -m pip install --upgrade pip setuptools wheel
    (cd "$HERMES_AGENT_DIR" && "$HERMES_AGENT_DIR/venv/bin/python" -m pip install -e ".[all]")
  fi

  if [[ -x "$HERMES_AGENT_DIR/venv/bin/hermes" ]]; then
    ok "Hermes dependencies installed"
  else
    fail "Hermes install finished but venv/bin/hermes is missing."
  fi
}

seed_templates() {
  section "AURA Hermes templates"

  local config_template="$ROOT_DIR/config/hermes-default.yaml"
  local env_template="$ROOT_DIR/.env.example"
  local config_target="$HERMES_HOME/config.yaml"
  local env_target="$HERMES_HOME/.env"

  [[ -f "$config_template" ]] || fail "Missing template: config/hermes-default.yaml"
  [[ -f "$env_template" ]] || fail "Missing template: .env.example"

  if [[ "$CHECK_ONLY" == "1" ]]; then
    [[ -f "$config_target" ]] && ok "$config_target exists" || warn "$config_target is missing; setup will copy config/hermes-default.yaml"
    [[ -f "$env_target" ]] && ok "$env_target exists" || warn "$env_target is missing; setup will copy .env.example"
    return
  fi

  if [[ ! -f "$config_target" ]]; then
    cp "$config_template" "$config_target"
    ok "Created .aura/hermes-home/config.yaml from template"
  else
    ok "Preserved existing .aura/hermes-home/config.yaml"
  fi

  if [[ ! -f "$env_target" ]]; then
    cp "$env_template" "$env_target"
    chmod 600 "$env_target" 2>/dev/null || true
    ok "Created .aura/hermes-home/.env from template"
  else
    ok "Preserved existing .aura/hermes-home/.env"
  fi
}

migrate_cua_mcp_config() {
  section "CUA MCP Hermes config"

  local config_target="$HERMES_HOME/config.yaml"
  local hermes_python="$HERMES_AGENT_DIR/venv/bin/python3"
  [[ -x "$hermes_python" ]] || hermes_python="$HERMES_AGENT_DIR/venv/bin/python"

  if [[ ! -f "$config_target" ]]; then
    warn "$config_target is missing; setup will create it before migration"
    return
  fi

  if [[ "$CHECK_ONLY" == "1" ]]; then
    if grep -q "AURA_AUTOMATION_POLICY\\|AURA_CUA_ALLOW_ACTIONS" "$config_target"; then
      warn "CUA MCP config still uses old AURA env policy gates; run ./script/setup.sh to migrate to Hermes tools.include"
      return
    fi

    if grep -q "script/aura-cua-mcp" "$config_target"; then
      ok "CUA MCP is configured in Hermes"
    else
      warn "CUA MCP should be configured with mcp_servers.cua-driver.command"
    fi
    return
  fi

  if [[ ! -x "$hermes_python" ]]; then
    warn "Hermes Python is missing; skipping CUA MCP config migration"
    return
  fi

  local migration_output
  if migration_output="$("$hermes_python" - "$config_target" <<'PY'
import sys

import yaml

path = sys.argv[1]
read_tools = [
    "check_permissions",
    "get_accessibility_tree",
    "get_agent_cursor_state",
    "get_config",
    "get_cursor_position",
    "get_recording_state",
    "get_screen_size",
    "get_window_state",
    "list_apps",
    "list_windows",
    "screenshot",
    "zoom",
]

with open(path, "r", encoding="utf-8") as fh:
    config = yaml.safe_load(fh) or {}

if not isinstance(config, dict):
    raise SystemExit("config root is not a mapping")

servers = config.setdefault("mcp_servers", {})
if not isinstance(servers, dict):
    servers = {}
    config["mcp_servers"] = servers

server = servers.setdefault("cua-driver", {})
if not isinstance(server, dict):
    server = {}
    servers["cua-driver"] = server

changed = False

command = "${AURA_PROJECT_ROOT}/script/aura-cua-mcp"
if server.get("command") != command:
    server["command"] = command
    changed = True

env = server.get("env")
if isinstance(env, dict):
    for key in ("AURA_AUTOMATION_POLICY", "AURA_CUA_ALLOW_ACTIONS"):
        if key in env:
            env.pop(key, None)
            changed = True
    if not env:
        server.pop("env", None)
        changed = True
elif env is not None:
    server.pop("env", None)
    changed = True

tools = server.get("tools")
if not isinstance(tools, dict):
    tools = {}
    server["tools"] = tools
    changed = True

include = tools.get("include")
if isinstance(include, list) and set(include) == set(read_tools):
    tools.pop("include", None)
    changed = True

if tools.get("exclude") == []:
    tools.pop("exclude", None)
    changed = True

for key in ("prompts", "resources"):
    if tools.get(key) is not False:
        tools[key] = False
        changed = True

if server.get("enabled") is not True:
    server["enabled"] = True
    changed = True

if changed:
    with open(path, "w", encoding="utf-8") as fh:
        yaml.safe_dump(config, fh, sort_keys=False, allow_unicode=True)
    print("migrated")
else:
    print("unchanged")
PY
  )"; then
    if [[ "$migration_output" == "migrated" ]]; then
      ok "Migrated CUA MCP exposure into Hermes tools.include"
    else
      ok "CUA MCP exposure already lives in Hermes config"
    fi
  else
    warn "Could not migrate CUA MCP config."
    printf "%s\n" "$migration_output" >&2
  fi
}

migrate_hermes_voice_config() {
  section "Hermes Voice Mode config"

  local config_target="$HERMES_HOME/config.yaml"
  local hermes_python="$HERMES_AGENT_DIR/venv/bin/python3"
  [[ -x "$hermes_python" ]] || hermes_python="$HERMES_AGENT_DIR/venv/bin/python"

  if [[ ! -f "$config_target" ]]; then
    warn "$config_target is missing; setup will create it before voice config migration"
    return
  fi

  if [[ "$CHECK_ONLY" == "1" ]]; then
    if grep -q "^voice:" "$config_target" && grep -q "^stt:" "$config_target" && grep -q "^tts:" "$config_target"; then
      ok "Hermes Voice Mode config blocks are present"
    else
      warn "Hermes Voice Mode config should include voice, stt, and tts blocks"
    fi
    return
  fi

  if [[ ! -x "$hermes_python" ]]; then
    warn "Hermes Python is missing; skipping voice config migration"
    return
  fi

  local migration_output
  if migration_output="$("$hermes_python" - "$config_target" <<'PY'
import sys

import yaml

path = sys.argv[1]

with open(path, "r", encoding="utf-8") as fh:
    config = yaml.safe_load(fh) or {}

if not isinstance(config, dict):
    raise SystemExit("config root is not a mapping")

changed = False

defaults = {
    "voice": {
        "record_key": "ctrl+b",
        "max_recording_seconds": 120,
        "auto_tts": False,
        "beep_enabled": True,
        "silence_threshold": 200,
        "silence_duration": 3.0,
    },
    "stt": {
        "provider": "local",
        "local": {
            "model": "base",
        },
    },
    "tts": {
        "provider": "edge",
        "edge": {
            "voice": "en-US-AriaNeural",
        },
    },
}

for section, values in defaults.items():
    current = config.get(section)
    if not isinstance(current, dict):
        config[section] = values
        changed = True
        continue

    for key, value in values.items():
        if key not in current:
            current[key] = value
            changed = True
        elif isinstance(value, dict) and not isinstance(current.get(key), dict):
            current[key] = value
            changed = True
        elif isinstance(value, dict):
            for child_key, child_value in value.items():
                if child_key not in current[key]:
                    current[key][child_key] = child_value
                    changed = True

if changed:
    with open(path, "w", encoding="utf-8") as fh:
        yaml.safe_dump(config, fh, sort_keys=False, allow_unicode=True)
    print("migrated")
else:
    print("unchanged")
PY
  )"; then
    if [[ "$migration_output" == "migrated" ]]; then
      ok "Added Hermes Voice Mode config defaults"
    else
      ok "Hermes Voice Mode config already present"
    fi
  else
    warn "Could not migrate Hermes Voice Mode config."
    printf "%s\n" "$migration_output" >&2
  fi
}

check_wrapper() {
  section "AURA Hermes wrapper"

  if [[ ! -x "$ROOT_DIR/script/aura-hermes" ]]; then
    fail "Missing executable wrapper: script/aura-hermes"
    return
  fi

  if [[ "$CHECK_ONLY" == "1" && ! -x "$HERMES_AGENT_DIR/venv/bin/python3" && ! -x "$HERMES_AGENT_DIR/venv/bin/python" ]]; then
    warn "Hermes runtime is not installed yet; skipping wrapper version check"
    return
  fi

  local output
  if output="$("$ROOT_DIR/script/aura-hermes" version 2>&1)"; then
    if [[ "$output" == *"Project: $HERMES_AGENT_DIR"* ]]; then
      ok "Wrapper resolves to project-local Hermes"
    else
      fail "Wrapper did not report project-local Hermes path."
      printf "%s\n" "$output" >&2
    fi
  else
    fail "Wrapper version check failed."
    printf "%s\n" "$output" >&2
  fi
}

check_cua() {
  section "CUA Driver passive readiness"

  local cua_bin="/Applications/CuaDriver.app/Contents/MacOS/cua-driver"
  if [[ ! -x "$cua_bin" ]] && command -v cua-driver >/dev/null 2>&1; then
    cua_bin="$(command -v cua-driver)"
  fi

  if [[ ! -x "$cua_bin" ]]; then
    warn "Cua Driver is not installed."
    cat <<'MSG'
  Install Cua Driver after reviewing its installer:
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/trycua/cua/main/libs/cua-driver/scripts/install.sh)"
MSG
    return
  fi

  ok "Cua Driver binary: $cua_bin"

  local status_output
  if status_output="$("$cua_bin" status 2>&1)"; then
    local normalized_status
    normalized_status="$(lowercase "$status_output")"
    if [[ "$normalized_status" == *"daemon is running"* || "$normalized_status" == *"is running"* ]]; then
      ok "Cua Driver daemon is running"
    else
      warn "Cua Driver daemon is not running."
      printf "  Start it with:\n    open -n -g /Applications/CuaDriver.app --args serve\n"
    fi
  else
    warn "Could not read Cua Driver daemon status."
    printf "%s\n" "$status_output" >&2
  fi

  local permissions_output
  if permissions_output="$("$cua_bin" call check_permissions '{"prompt":false}' 2>&1)"; then
    local normalized_permissions
    normalized_permissions="$(lowercase "$permissions_output")"
    if [[ "$normalized_permissions" == *"accessibility: granted"* && "$normalized_permissions" == *"screen recording: granted"* ]]; then
      ok "Cua Driver Accessibility and Screen Recording permissions are granted"
    else
      warn "Cua Driver permissions are incomplete."
      cat <<'MSG'
  Open System Settings > Privacy & Security, then grant CuaDriver.app:
    - Accessibility
    - Screen Recording
  Restart the CUA daemon after changing permissions.
MSG
    fi
  else
    warn "Could not check Cua Driver permissions passively."
    printf "%s\n" "$permissions_output" >&2
  fi
}

print_next_steps() {
  section "Next commands"

  cat <<EOF
Run these from the repo root:
  ./script/aura-hermes doctor
  ./script/connection_matrix.sh
  ./script/e2e_test.sh
  ./script/build_and_run.sh --verify

Provider/auth setup:
  ./script/aura-hermes setup

Secrets belong in:
  .aura/hermes-home/.env

Config belongs in:
  .aura/hermes-home/config.yaml
EOF
}

main() {
  check_host
  ensure_directories
  ensure_hermes_checkout
  ensure_hermes_venv
  seed_templates
  migrate_cua_mcp_config
  migrate_hermes_voice_config
  check_wrapper
  check_cua
  print_next_steps

  section "Setup result"
  if (( ERRORS > 0 )); then
    printf "AURA setup found %d error(s) and %d warning(s).\n" "$ERRORS" "$WARNINGS" >&2
    exit 1
  fi

  if (( WARNINGS > 0 )); then
    printf "AURA setup completed with %d warning(s).\n" "$WARNINGS"
  else
    printf "AURA setup completed successfully.\n"
  fi
}

main
