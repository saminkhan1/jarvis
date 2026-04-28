#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HERMES="$ROOT_DIR/script/aura-hermes"
CONFIG_PATH="$ROOT_DIR/.aura/hermes-home/config.yaml"
EXPECTED_ENV="$ROOT_DIR/.aura/hermes-home/.env"
HERMES_AGENT_DIR="$ROOT_DIR/.aura/hermes-agent"

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

export ROOT_DIR CONFIG_PATH HERMES_AGENT_DIR
python3 - <<'PY'
from pathlib import Path
import os
import sys

root = Path(os.environ["ROOT_DIR"])
config_path = Path(os.environ["CONFIG_PATH"])
hermes_agent_dir = Path(os.environ["HERMES_AGENT_DIR"])
text = config_path.read_text()

required_computer_use_paths = [
    hermes_agent_dir / "tools/computer_use/tool.py",
    hermes_agent_dir / "tools/computer_use/cua_backend.py",
    hermes_agent_dir / "tools/computer_use_tool.py",
]
missing_computer_use = [path for path in required_computer_use_paths if not path.exists()]

toolsets_path = hermes_agent_dir / "toolsets.py"
toolset_missing = False
if not toolsets_path.exists():
    missing_computer_use.append(toolsets_path)
elif '"computer_use"' not in toolsets_path.read_text(encoding="utf-8"):
    toolset_missing = True

if missing_computer_use or toolset_missing:
    print("Project-local Hermes checkout is missing computer-use support:", file=sys.stderr)
    for path in missing_computer_use:
        print(f"- {path}", file=sys.stderr)
    if toolset_missing:
        print("- toolsets.py does not expose the computer_use toolset", file=sys.stderr)
    print("Run ./script/setup.sh to install the pinned Hermes runtime with computer_use.", file=sys.stderr)
    sys.exit(1)

in_platform_toolsets = False
in_cli_toolset = False
cli_has_computer_use = False

for raw in text.splitlines():
    line = raw.rstrip("\n")
    stripped = line.strip()
    if not stripped or stripped.startswith("#"):
        continue
    if not line.startswith(" "):
        in_platform_toolsets = stripped == "platform_toolsets:"
        in_cli_toolset = False
        continue
    if in_platform_toolsets and in_cli_toolset and stripped.startswith("-"):
        item = stripped[1:].strip().strip('"\'')
        if item == "computer_use":
            cli_has_computer_use = True
            break
        continue
    if in_platform_toolsets and line.startswith("  ") and not line.startswith("    ") and not stripped.startswith("-"):
        in_cli_toolset = stripped == "cli:"
        continue

if not cli_has_computer_use:
    print("Runtime config does not enable platform_toolsets.cli: computer_use; run ./script/setup.sh.", file=sys.stderr)
    sys.exit(1)

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
print("Hermes runtime config uses Hermes computer_use instead of AURA CUA MCP proxy.")
print("All configured runtime command paths exist.")
PY
