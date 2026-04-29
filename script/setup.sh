#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AURA_DIR="$ROOT_DIR/.aura"
AURA_HOME="$AURA_DIR/home"
HERMES_HOME="$AURA_DIR/hermes-home"
HERMES_AGENT_DIR="$AURA_DIR/hermes-agent"
HERMES_REPO="${AURA_HERMES_REPO:-https://github.com/NousResearch/hermes-agent.git}"
HERMES_REF="${AURA_HERMES_REF:-b07791db0508f92625dfc9e75f20c331cc7bb528}"
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

apply_hermes_local_patches() {
  section "Project-local Hermes compatibility patches"

  local patch_file="$ROOT_DIR/patches/hermes-agent/cua-driver-compat.patch"
  if [[ ! -f "$patch_file" ]]; then
    fail "Missing Hermes compatibility patch: $patch_file"
    return
  fi

  if [[ ! -d "$HERMES_AGENT_DIR/.git" ]]; then
    warn "Hermes checkout is missing; cannot apply compatibility patches yet"
    return
  fi

  if git -C "$HERMES_AGENT_DIR" apply --reverse --check "$patch_file" >/dev/null 2>&1; then
    ok "Hermes CuaDriver compatibility patch is applied"
    return
  fi

  if [[ "$CHECK_ONLY" == "1" ]]; then
    if git -C "$HERMES_AGENT_DIR" apply --check "$patch_file" >/dev/null 2>&1; then
      warn "Hermes CuaDriver compatibility patch is not applied; setup will apply it"
    else
      warn "Hermes CuaDriver compatibility patch cannot be applied cleanly"
    fi
    return
  fi

  if git -C "$HERMES_AGENT_DIR" apply --check "$patch_file" >/dev/null 2>&1; then
    git -C "$HERMES_AGENT_DIR" apply "$patch_file"
    ok "Applied Hermes CuaDriver compatibility patch"
  else
    fail "Hermes CuaDriver compatibility patch cannot be applied cleanly"
  fi
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

configure_hermes_computer_use_config() {
  section "Hermes computer-use config"

  local config_target="$HERMES_HOME/config.yaml"
  local hermes_python="$HERMES_AGENT_DIR/venv/bin/python3"
  [[ -x "$hermes_python" ]] || hermes_python="$HERMES_AGENT_DIR/venv/bin/python"

  if [[ ! -f "$config_target" ]]; then
    warn "$config_target is missing; setup will create it before configuring computer_use"
    return
  fi

  if [[ "$CHECK_ONLY" == "1" ]]; then
    if "$hermes_python" - "$config_target" <<'PY' >/dev/null 2>&1
import sys, yaml
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    config = yaml.safe_load(fh) or {}
platform_toolsets = config.get("platform_toolsets") or {}
cli = platform_toolsets.get("cli") or []
raise SystemExit(0 if "computer_use" in cli else 1)
PY
    then
      ok "Hermes computer_use toolset is enabled for AURA CLI missions"
    else
      warn "Hermes config should enable platform_toolsets.cli: computer_use"
    fi
    return
  fi

  if [[ ! -x "$hermes_python" ]]; then
    warn "Hermes Python is missing; skipping Hermes computer_use config update"
    return
  fi

  local config_output
  if config_output="$("$hermes_python" - "$config_target" <<'PY'
import sys

import yaml

path = sys.argv[1]

with open(path, "r", encoding="utf-8") as fh:
    config = yaml.safe_load(fh) or {}

if not isinstance(config, dict):
    raise SystemExit("config root is not a mapping")

changed = False

platform_toolsets = config.setdefault("platform_toolsets", {})
if not isinstance(platform_toolsets, dict):
    platform_toolsets = {}
    config["platform_toolsets"] = platform_toolsets
    changed = True

cli = platform_toolsets.get("cli")
if not isinstance(cli, list):
    cli = []
    platform_toolsets["cli"] = cli
    changed = True

if "computer_use" not in cli:
    cli.append("computer_use")
    changed = True

if changed:
    with open(path, "w", encoding="utf-8") as fh:
        yaml.safe_dump(config, fh, sort_keys=False, allow_unicode=True)
    print("updated")
else:
    print("unchanged")
PY
  )"; then
    if [[ "$config_output" == "updated" ]]; then
      ok "Enabled Hermes computer_use config"
    else
      ok "Hermes computer_use config already present"
    fi
  else
    warn "Could not configure Hermes computer_use."
    printf "%s\n" "$config_output" >&2
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

check_hermes_computer_use() {
  section "Hermes computer-use support"

  if [[ ! -d "$HERMES_AGENT_DIR" ]]; then
    warn "Hermes checkout is missing; setup will install a build with Hermes-owned computer-use support"
    return
  fi

  local missing=0
  for path in \
    "$HERMES_AGENT_DIR/tools/computer_use/tool.py" \
    "$HERMES_AGENT_DIR/tools/computer_use/cua_backend.py" \
    "$HERMES_AGENT_DIR/tools/computer_use_tool.py"; do
    if [[ ! -f "$path" ]]; then
      warn "Missing Hermes computer-use file: ${path#$HERMES_AGENT_DIR/}"
      missing=1
    fi
  done

  if [[ -f "$HERMES_AGENT_DIR/toolsets.py" ]]; then
    if ! grep -q '"computer_use"' "$HERMES_AGENT_DIR/toolsets.py"; then
      warn "Hermes toolsets.py does not expose the computer_use toolset"
      missing=1
    fi
  else
    warn "Missing Hermes toolsets.py; cannot verify computer_use toolset exposure"
    missing=1
  fi

  if (( missing == 0 )); then
    ok "Hermes checkout includes computer_use tool and cua-driver backend"
  elif [[ "$CHECK_ONLY" != "1" ]]; then
    fail "Project-local Hermes checkout does not include required computer-use support."
  fi
}

check_cua() {
  section "CUA Driver source binary"

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

  ok "CUA source binary: $cua_bin"
  cat <<'MSG'
  AURA embeds this binary into dist/AURA.app/Contents/MacOS/cua-driver
  during ./script/build_and_run.sh and signs it as com.wexprolabs.aura.
  Grant Accessibility and Screen Recording to AURA, not CuaDriver.app.
MSG
}

print_next_steps() {
  section "Next commands"

  cat <<EOF
Run these from the repo root:
  ./script/aura-hermes doctor
  ./script/verify_runtime_paths.sh
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
  apply_hermes_local_patches
  ensure_hermes_venv
  seed_templates
  configure_hermes_computer_use_config
  migrate_hermes_voice_config
  check_wrapper
  check_hermes_computer_use
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
