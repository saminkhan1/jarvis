# AURA

AURA is a Mac-native ambient assistant shell backed by a project-local Hermes install.

Current phase: Hermes-orchestrated ambient mission runner.

- AURA captures cheap Mac context, gathers mission approval, and shows status/output.
- Hermes is the parent orchestrator for planning, memory, sessions, tools, and `delegate_task` background workers.
- CUA Driver is the required host-Mac readiness lane. AURA opens only into onboarding until Cua Driver is installed, running, permissioned, and registered with Hermes. AURA does not install it automatically.
- Ambient interaction is shortcut-first: press global `⌃⌥⌘A` to open the cursor-adjacent mission panel, then let Hermes run the parent mission.
- The cursor-adjacent aura stays close to the real pointer and changes color for idle/listening/running/approval/error state. AURA does not replace the system cursor.
- Automation is governed by one global policy: Read Only, Ask Per Task, or Always Allow. Mission launch stays lean: goal, start, cancel.
- The dashboard shows Hermes health, CUA readiness, current mission state, approvals, output, and Hermes' own structured session export. AURA does not maintain a custom task database.

## Tech Stack

- App shell: Swift 5.9, SwiftUI, AppKit, SwiftPM, macOS 14+.
- Desktop integration: AppKit windows/panels, Carbon global hot key, `NSWorkspace`, macOS Accessibility and Screen Recording via Cua Driver.
- Agent backend: project-local Hermes checkout under `.aura/hermes-agent`, isolated Hermes home under `.aura/hermes-home`, invoked only through `script/aura-hermes`.
- AI runtime: OpenAI Codex provider through Hermes, currently using `gpt-5.4` by default.
- Tooling lane: Hermes MCP with AURA's daemon-backed `script/aura-cua-mcp` proxy for Cua Driver. AURA does not launch raw `cua-driver mcp` during missions.
- Automation policy: Read Only, Ask Per Task, and Always Allow are enforced by AURA UI state plus the CUA MCP proxy.
- Observability: typed JSON Apple Unified Logging through `AURATelemetry`, stable event registry, trace IDs, app session IDs, privacy-safe fields, and feature categories for app, launch, UI, mission, approval, Hermes, CUA, and process events.
- Audit trail: bounded local JSONL ledger through `AURAAuditLedger` for mission, approval, Hermes, CUA governance, and tool/action boundary events. It avoids raw prompts, mission output, screenshots, tool args/results, secrets, raw paths, and document contents.
- Verification: `script/verify_logging.sh` enforces logging schema rules, `script/e2e_test.sh` runs the real Hermes/CUA/approval/app-launch path, and `script/smoke_test.sh` delegates to e2e.
- Distribution state: SwiftPM-built local app bundle in `dist/`; standalone beta packaging/signing/notarization is still a blocker.

## Local Commands

```bash
./script/build_and_run.sh
./script/build_and_run.sh --verify
./script/aura-hermes status
./script/aura-hermes doctor
./script/aura-hermes chat -Q --source aura -t web,skills,todo,memory,session_search,clarify,delegation -q "Reply exactly: AURA Hermes OK"
./script/aura-hermes tools --summary list
./script/aura-hermes mcp list
./script/e2e_test.sh
./script/smoke_test.sh
```

## Current Status

- Native app builds and launches through SwiftPM.
- Main window is a lean dashboard for Hermes health, CUA readiness, current mission state, approvals, structured Hermes sessions, and output.
- First launch runs a passive readiness check. The functional mission surface stays locked until CUA setup is complete. Permission prompts only happen from explicit onboarding actions; normal mission workflow never triggers macOS permission prompts.
- Normal Hermes missions expose CUA through AURA's daemon-backed MCP proxy. The proxy forwards to the already-onboarded CuaDriver.app daemon instead of launching raw `cua-driver mcp` under AURA.
- Ambient panel opens with `⌃⌥⌘A` for mission entry and approval continuation.
- Hermes is invoked only through `script/aura-hermes`.
- AURA launches one Hermes parent mission and resumes it with `--resume` after approval.
- AURA emits typed JSON unified logs plus a bounded local JSONL audit ledger for mission, approval, Hermes, and CUA governance events.
- `script/verify_logging.sh` enforces the telemetry schema and blocks ad hoc app logging.
- `script/e2e_test.sh` covers real project-local Hermes status, CUA readiness, quiet mission start, `NEEDS_APPROVAL`, `--resume`, and app launch verification.
- `script/smoke_test.sh` delegates to the same real e2e flow.
- AURA does not own memory, browser automation, screen capture, subagent orchestration, or a task database.
- CUA Driver is installed, running through a user LaunchAgent, and registered with project-local Hermes MCP.

## Next Todo

1. Make the app runtime-location aware for standalone beta builds.
2. Add first-run bootstrap for Hermes, CUA readiness, and MCP registration outside this repo.
3. Add Developer ID signing, hardened runtime, notarization, stapling, and Gatekeeper validation.
4. Run a clean-machine beta install test.

See `docs/BETA_READINESS.md` for the current beta gate checklist.

## Backend Configuration

Hermes is isolated under `.aura/` and must be invoked through `script/aura-hermes`.
The machine may also have a global Hermes install under `~/.hermes`; AURA does not use it.

Current defaults:

- Provider: OpenAI Codex
- Model: `gpt-5.4`
- Hermes home: `.aura/hermes-home`
- Working directory: this repository
- Persona: AURA backend, concise and safety-gated

Optional API keys for web search, image generation, messaging, and other integrations can be added later in `.aura/hermes-home/.env`.

## Mission Runner Contract

AURA launches one Hermes parent mission with a structured mission envelope. Hermes decides when to use `delegate_task`; AURA does not spawn subagents or split work itself.

The primary entry point is the ambient panel opened by `⌃⌥⌘A`. The main window is for diagnostics, global automation policy, CUA readiness, and longer mission output.

The UI should not expose demo-specific buttons as primary controls. Users describe the mission; Hermes infers the workflow and delegates when useful.

Hermes quiet chat returns a `session_id`; AURA keeps that ID only in memory and uses `--resume` when continuing an approval-gated mission. Mission history and background-work visibility stay in Hermes sessions, not an AURA database.

Global automation policy:

- Read Only: analyze, research, plan, draft, and inspect the screen through CUA read/snapshot tools without writes or host-control actions.
- Ask Per Task: Hermes can inspect the screen and returns `NEEDS_APPROVAL` before local writes, state-changing commands, CUA actions, or foreground actions.
- Always Allow: Hermes may perform non-destructive local writes, state-changing terminal work, and CUA host-control actions, while still stopping for destructive, credential-sensitive, financial, purchase, posting, or external-send actions.

CUA MCP is registered through `script/aura-cua-mcp`, a daemon-backed proxy. It never exposes `check_permissions` prompt mode during mission workflow; if permissions are revoked, AURA locks back to onboarding.

When Hermes returns `NEEDS_APPROVAL: <reason>`, AURA shows a small approval card. Approve & Continue resumes the same Hermes session with approval for only that exact pending action. Deny stops the mission.

Using AURA requires:

1. Cua Driver installed.
2. CuaDriver daemon running.
3. Accessibility and Screen Recording permissions granted to Cua Driver.
4. `cua-driver` registered as a Hermes MCP server.
5. Global policy set for the intended workflow.

Consequential actions still require a hard stop. Hermes should return `NEEDS_APPROVAL: <reason>` before sends, posts, purchases, destructive file ops, credential-sensitive work, financial actions, or unrelated foreground takeover.

## Current CUA Setup

- Cua Driver app: `/Applications/CuaDriver.app`
- Canonical CUA binary: `/Applications/CuaDriver.app/Contents/MacOS/cua-driver`
- CLI symlink on this machine: `/opt/homebrew/bin/cua-driver`
- Installed version: `0.0.5`
- Daemon LaunchAgent: `~/Library/LaunchAgents/com.trycua.cua_driver_daemon.plist`
- Project-local Hermes MCP: `cua-driver` registered in `.aura/hermes-home/config.yaml`
