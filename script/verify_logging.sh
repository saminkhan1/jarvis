#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

/usr/bin/python3 - "$ROOT_DIR" <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
errors: list[str] = []

telemetry_path = root / "Sources/AURA/Support/AURATelemetry.swift"
telemetry = telemetry_path.read_text(encoding="utf-8")
known_events = set(re.findall(r'case\s+\w+\s*=\s*"([a-z0-9_]+)"', telemetry))

snake_case = re.compile(r"^[a-z][a-z0-9_]*$")

def fail(path: pathlib.Path, line: int, message: str) -> None:
    rel = path.relative_to(root)
    errors.append(f"{rel}:{line}: {message}")

for path in (root / "Sources/AURA").rglob("*.swift"):
    text = path.read_text(encoding="utf-8")
    for line_no, line in enumerate(text.splitlines(), start=1):
        if '"event=' in line or "'event=" in line:
            fail(path, line_no, "direct event= logging is not allowed; use AURATelemetry typed helpers")
        if "privacy: .public" in line and path.name != "AURATelemetry.swift":
            fail(path, line_no, "privacy: .public outside AURATelemetry.swift is not allowed")
        if re.search(r"\bNSLog\s*\(", line) or re.search(r"\bprint\s*\(", line):
            fail(path, line_no, "raw NSLog/print logging is not allowed")
        for key in re.findall(r'\.(?:string|int|int32|bool|privateValue)\("([^"]+)"', line):
            if not snake_case.match(key):
                fail(path, line_no, f"telemetry field is not snake_case: {key}")

for script_name in ("script/aura-hermes", "script/aura-cua-mcp"):
    path = root / script_name
    text = path.read_text(encoding="utf-8")

    if script_name.endswith("aura-hermes"):
        for line_no, line in enumerate(text.splitlines(), start=1):
            match = re.search(r"\btelemetry_log\s+\S+\s+([a-z0-9_]+)\b", line)
            if match and match.group(1) not in known_events:
                fail(path, line_no, f"unknown telemetry event: {match.group(1)}")
            if "telemetry_log" in line:
                for key in re.findall(r"\s([A-Za-z_][A-Za-z0-9_]*)=", line):
                    if not snake_case.match(key):
                        fail(path, line_no, f"telemetry field is not snake_case: {key}")

    if script_name.endswith("aura-cua-mcp"):
        for line_no, line in enumerate(text.splitlines(), start=1):
            match = re.search(r'telemetry_log\(\s*"[^"]+"\s*,\s*"([a-z0-9_]+)"', line)
            if match and match.group(1) not in known_events:
                fail(path, line_no, f"unknown telemetry event: {match.group(1)}")

if not known_events:
    errors.append("Sources/AURA/Support/AURATelemetry.swift: no event registry found")

if errors:
    print("Logging verification failed:", file=sys.stderr)
    for error in errors:
        print(f"  {error}", file=sys.stderr)
    raise SystemExit(1)

print(f"Logging verification passed ({len(known_events)} registered events).")
PY
