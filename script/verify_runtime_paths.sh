#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_PATH="$ROOT_DIR/.aura/hermes-home/config.yaml"

if [[ ! -f "$CONFIG_PATH" ]]; then
  echo "runtime config not found: $CONFIG_PATH" >&2
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
missing = []
for raw in text.splitlines():
    line = raw.strip()
    if not line.startswith("command:"):
        continue
    value = line[len("command:"):].strip().strip('"\'')
    if not value:
        continue
    path = Path(value.replace("${AURA_PROJECT_ROOT}", str(root)))
    if not path.exists():
        missing.append(str(path))

if missing:
    print("Missing configured MCP command paths:")
    for path in missing:
        print(f"- {path}")
    sys.exit(1)

print("All configured MCP command paths exist.")
PY
