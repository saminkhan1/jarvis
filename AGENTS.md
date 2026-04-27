# AURA Project Context

AURA is a Mac-native ambient assistant shell, not a chatbot.

## Architecture

- Native shell: SwiftUI/AppKit macOS app in `Sources/AURA`.
- Backend agent: isolated Hermes install under `.aura/`, invoked only through `script/aura-hermes`.
- Future desktop lane: CUA Driver through MCP, not custom Swift automation.
- Future isolated lane: CUA Sandbox or CuaBot for risky computer-use tasks.

## Constraints

- Stay lean. Prefer existing Hermes, MCP, CUA, Browser Use, and platform SDKs over custom infrastructure.
- Do not use the global Hermes install.
- Do not commit `.aura/`, API keys, logs, generated artifacts, or local caches.
- AURA MVP missions run Hermes with `--yolo`; product permission policy is deferred.
- Do not build custom approval infrastructure in AURA until the product loop is validated.
- Avoid copying protected creator content; transform/adapt creative patterns into original work.

## Local Commands

- Run app: `./script/build_and_run.sh`
- Verify app process: `./script/build_and_run.sh --verify`
- Full e2e verification: `./script/e2e_test.sh`
- Hermes version: `./script/aura-hermes version`
- Hermes diagnostics: `./script/aura-hermes doctor`
- Hermes setup: `./script/aura-hermes setup`
- Hermes MCP list: `./script/aura-hermes mcp list`
- CUA status: `cua-driver status`

## Current Local Runtime

- Project Hermes home: `.aura/hermes-home`
- Project Hermes checkout: `.aura/hermes-agent`
- CUA app: `/Applications/CuaDriver.app`
- CUA CLI: `/opt/homebrew/bin/cua-driver`
- CUA LaunchAgent: `~/Library/LaunchAgents/com.trycua.cua_driver_daemon.plist`
