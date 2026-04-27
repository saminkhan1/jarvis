#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aura-monitor-test.XXXXXX")"
FIXTURE="$TMP_DIR/log.jsonl"
MONITOR_PID=""

cleanup() {
  if [[ -n "$MONITOR_PID" ]]; then
    kill "$MONITOR_PID" >/dev/null 2>&1 || true
    wait "$MONITOR_PID" >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

/usr/bin/python3 - "$ROOT_DIR" "$FIXTURE" <<'PY'
import json
import pathlib
import sys
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader

root = pathlib.Path(sys.argv[1])
fixture = pathlib.Path(sys.argv[2])
loader = SourceFileLoader("aura_monitor", str(root / "script" / "aura-monitor"))
spec = spec_from_loader(loader.name, loader)
module = module_from_spec(spec)
loader.exec_module(module)

payload = {
    "event": "mission_start_requested",
    "severity": "info",
    "trace_id": "mission-test",
    "mission_id": "mission-span",
    "operation": "invoke_agent",
    "duration_ms": 1234,
}
raw = json.dumps(
    {
        "timestamp": "2026-04-27 12:00:00.000000-0400",
        "eventMessage": json.dumps(payload, separators=(",", ":"), sort_keys=True),
    },
    separators=(",", ":"),
    sort_keys=True,
)

encoded = module.sse_event(raw, event_id=42)
assert "event: log\n" in encoded
assert "id: 42\n" in encoded
assert f"data: {raw}\n\n" in encoded

fixture.write_text(raw + "\n", encoding="utf-8")
PY

PORT="$(
  /usr/bin/python3 - <<'PY'
import socket

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
)"

"$ROOT_DIR/script/aura-monitor" --port "$PORT" --fixture "$FIXTURE" >"$TMP_DIR/server.log" 2>&1 &
MONITOR_PID="$!"

/usr/bin/python3 - "$PORT" "$FIXTURE" <<'PY'
import pathlib
import sys
import time
import urllib.request

port = sys.argv[1]
fixture = pathlib.Path(sys.argv[2])
base = f"http://127.0.0.1:{port}"

deadline = time.time() + 5
while True:
    try:
        with urllib.request.urlopen(base + "/health", timeout=0.5) as response:
            assert response.read() == b"ok\n"
        break
    except Exception:
        if time.time() >= deadline:
            raise
        time.sleep(0.1)

with urllib.request.urlopen(base + "/", timeout=2) as response:
    html = response.read().decode("utf-8")
    assert "AURA Log Monitor" in html

with urllib.request.urlopen(base + "/events", timeout=5) as response:
    events = response.read().decode("utf-8")

raw = fixture.read_text(encoding="utf-8").strip()
assert "event: log" in events
assert f"data: {raw}" in events

print("AURA monitor tests passed.")
PY
