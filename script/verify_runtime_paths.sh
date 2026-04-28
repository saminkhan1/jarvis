#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HERMES="$ROOT_DIR/script/aura-hermes"
CONFIG_PATH="$ROOT_DIR/.aura/hermes-home/config.yaml"
EXPECTED_ENV="$ROOT_DIR/.aura/hermes-home/.env"

if [[ ! -x "$HERMES" ]]; then
  echo "missing Hermes wrapper: $HERMES" >&2
  exit 1
fi

if [[ ! -f "$CONFIG_PATH" ]]; then
  echo "runtime config not found: $CONFIG_PATH" >&2
  exit 1
fi

config_path="$($HERMES config path)"
env_path="$($HERMES config env-path)"

if [[ "$config_path" != "$CONFIG_PATH" ]]; then
  echo "wrapper did not use repo-local HERMES_HOME config path" >&2
  echo "expected: $CONFIG_PATH" >&2
  echo "actual:   $config_path" >&2
  exit 1
fi

if [[ "$env_path" != "$EXPECTED_ENV" ]]; then
  echo "wrapper did not use repo-local HERMES_HOME env path" >&2
  echo "expected: $EXPECTED_ENV" >&2
  echo "actual:   $env_path" >&2
  exit 1
fi

export ROOT_DIR CONFIG_PATH
python3 - <<'PY'
from pathlib import Path
import os
import sys

root = Path(os.environ["ROOT_DIR"])
config_path = Path(os.environ["CONFIG_PATH"])
text = config_path.read_text()

current_label = None
current_kind = None
missing = []


def resolved_path(value: str) -> Path:
    resolved = value.replace("${AURA_PROJECT_ROOT}", str(root))
    if resolved.startswith("./"):
        resolved = str(root / resolved[2:])
    return Path(resolved)


for raw in text.splitlines():
    line = raw.rstrip("\n")
    trimmed = line.strip()

    if line.startswith("hooks:"):
        current_kind = "hooks"
        current_label = None
        continue

    if line.startswith("mcp_servers:"):
        current_kind = "mcp_servers"
        current_label = None
        continue

    if line and not line.startswith(" "):
        current_kind = None
        current_label = None
        continue

    if current_kind is None:
        continue

    if line.startswith("  ") and not line.startswith("    ") and trimmed.endswith(":"):
        current_label = trimmed[:-1]
        continue

    if not trimmed.startswith("command:") or current_label is None:
        continue

    value = trimmed[len("command:"):].strip().strip('"\'')
    if not value:
        continue

    path = resolved_path(value)
    if path.exists():
        continue

    qualified_label = f"{current_kind}.{current_label}"
    missing.append((qualified_label, str(path)))

if missing:
    print("Missing configured runtime command paths:", file=sys.stderr)
    for label, path in missing:
        print(f"- {label}: {path}", file=sys.stderr)
    sys.exit(1)

print("Wrapper resolves repo-local config and env paths correctly.")
print("All configured runtime command paths exist.")
PY
