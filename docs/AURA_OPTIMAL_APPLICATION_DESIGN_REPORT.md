# AURA Optimal Application Design Report

> For: Dev team  
> Date: 2026-04-26  
> Status: Final product/architecture report to pair with `AURA_MVP_FINAL_EXECUTION_REPORT.md`  
> Goal: Design the most capable AURA app around Hermes, CUA, MCP, skills, browser/web, messaging, memory, scheduling, and future isolated lanes without turning AURA into a custom agent runtime.

This report reads the current MVP execution report as the engineering boundary:

- AURA is the native macOS ambient shell.
- Hermes is the agent runtime, planner, delegator, memory/tool/MCP owner, and final synthesizer.
- CUA Driver is the approval-gated host-control lane exposed through `script/aura-cua-mcp`.
- AURA must not become a custom agent loop, browser framework, task database, or hardcoded demo app.

The optimal design is not "add every connector as a button." The optimal design
is a thin native command layer that sends context to project-local Hermes,
surfaces trust and progress, and lets Hermes config own tool exposure,
permissions, and provider setup.

## Sources Reviewed

Repo-local:

- `docs/AURA_MVP_FINAL_EXECUTION_REPORT.md`
- `docs/INTEGRATION_NOTES.md`
- `docs/BETA_READINESS.md`
- `docs/MVP_LAUNCH_CHECKLIST_FROM_CLICKY_DEMO.md`
- `README.md`
- `Sources/AURA/Stores/AURAStore.swift`
- `Sources/AURA/Services/HermesService.swift`
- `Sources/AURA/Services/CuaDriverService.swift`
- `Sources/AURA/Views/CursorSurfaceView.swift`
- `Sources/AURA/Views/MissionRunnerView.swift`
- `script/aura-hermes`
- `script/aura-cua-mcp`
- `config/hermes-default.yaml`
- `script/e2e_test.sh`

Official Hermes docs:

- https://hermes-agent.nousresearch.com/docs/user-guide/features/overview
- https://hermes-agent.nousresearch.com/docs/user-guide/features/tools
- https://hermes-agent.nousresearch.com/docs/user-guide/features/delegation
- https://hermes-agent.nousresearch.com/docs/user-guide/features/mcp
- https://hermes-agent.nousresearch.com/docs/user-guide/features/skills
- https://hermes-agent.nousresearch.com/docs/user-guide/features/voice-mode
- https://hermes-agent.nousresearch.com/docs/skills

Runtime checks on this machine:

- `./script/aura-hermes status`
- `./script/aura-hermes doctor`
- `./script/aura-hermes mcp list`
- `./script/aura-hermes mcp test cua-driver`
- `/Applications/CuaDriver.app/Contents/MacOS/cua-driver status`

Generated design artifact:

- `docs/aura-optimal-system-design.elements.json`
- `docs/aura-optimal-system-design.excalidraw`
- Regeneration command:
  `npx --yes excalidraw-cli create docs/aura-optimal-system-design.elements.json -o docs/aura-optimal-system-design.excalidraw --no-checkpoint`

## Executive Decision

Build AURA as a connection-aware ambient mission operating system for one user.

The product loop should be:

```text
invoke -> capture context -> launch Hermes parent through project wrapper
  -> show workers/progress/approvals -> hand off artifacts -> continue or close
```

AURA should own:

- native invocation and UI
- setup/status affordances
- approval presentation and resume UX
- Hermes process lifecycle
- derived mission/worker/artifact UI state
- audit and recovery

Hermes should own:

- reasoning
- provider routing
- tool selection
- subagent delegation
- memory
- skills
- MCP tool usage
- final synthesis

CUA should own:

- host screen/app inspection
- host control actions
- cursor/keyboard/window interaction

The product should look like a Mac utility, not a chatbot and not a developer
dashboard. The dashboard remains a secondary drill-down.

## First Principles

### 1. The user wants outcomes, not connectors

Connections are implementation details. The user asks "organize my screenshots,"
"find leads," "summarize this PDF," or "build this app." AURA decides which
capabilities are available, what is safe, and what must be approved.

### 2. Every connection has three dimensions

Each connection must be understandable to the user by:

- Capability: what it can do.
- Readiness: installed, authenticated, permissioned, reachable, configured.
- Risk: read-only, local-write, host-control, account-action, external-send,
  spend, credential, financial/legal/medical.

Do not reimplement those dimensions as an AURA planning layer. Hermes config is
the source of truth for what is exposed. AURA may show status and setup hints so
the user understands why Hermes can or cannot use a capability.

### 3. AURA's moat is trust and context, not tool ownership

Hermes already supports broad tools: web, browser, terminal/file,
code_execution, delegation, memory, skills, MCP, cron, media, messaging, and
provider routing. AURA wins by making those capabilities safe and native on the
Mac.

### 4. The UI must represent background work as objects

Hermes can delegate. AURA must turn delegated work into visible worker state.
The user should not need to parse logs to know what is running, blocked, done,
or failed.

### 5. Runtime truth must be discovered, not assumed

Official Hermes support and local availability are different. The app must
discover runtime state from Hermes status/doctor/MCP tests and CUA readiness,
then show what is available now.

## Current Runtime Reality

Ready now:

- Project-local Hermes wrapper through `script/aura-hermes`.
- OpenAI Codex auth is logged in.
- CUA Driver daemon is running.
- `cua-driver` MCP server is enabled through `script/aura-cua-mcp`.
- CUA raw MCP surface is discoverable through the daemon proxy. Hermes config
  currently exposes the safe read-only include list to AURA-launched missions.
- Core Hermes toolsets reported available: `browser`, `clarify`,
  `code_execution`, `cronjob`, `terminal`, `delegation`, `feishu_doc`,
  `feishu_drive`, `file`, `image_gen`, `memory`, `session_search`, `skills`,
  `todo`, `tts`, `vision`, `mcp-cua-driver`.

Configured but needs caution:

- `config/hermes-default.yaml` seeds `model.default: gpt-5.4` and
  `provider: openai-codex`. Treat this as setup-time config, not a product
  claim. Doctor/status must validate the active provider/model.
- Terminal backend is local. This is powerful and should remain controlled by
  Hermes config and approval prompts for writes/state changes.

Supported but not operational locally until setup is completed:

- `web`: blocked by missing Exa/Parallel/Tavily/Firecrawl configuration.
- `browser-cdp`: system dependency not met.
- `spotify`: system dependency not met.
- `discord` and `discord_admin`: missing Discord token.
- `messaging`: system dependency not met.
- `homeassistant`: system dependency not met.
- `moa`, `rl`: missing API keys/submodule dependencies.
- Messaging platforms in Hermes status are not configured: Telegram, Discord,
  WhatsApp, Signal, Slack, Email, SMS, DingTalk, Feishu, WeCom, Weixin,
  BlueBubbles, QQBot.

Current AURA mission launch:

- AURA invokes `./script/aura-hermes chat -Q --source aura -q <mission envelope>`.
- AURA does not pass `-t` toolset overrides.
- AURA does not pass `AURA_AUTOMATION_POLICY` or `AURA_CUA_ALLOW_ACTIONS`.
- Hermes config decides MCP/tool exposure and approval behavior.

This keeps AURA lean and avoids a duplicate planner. Missing providers should
be explained by Hermes status/doctor output and surfaced by AURA setup/status
UI, not by custom mission routing code.

## Target Architecture

Detailed Excalidraw system design:

- Source elements: `docs/aura-optimal-system-design.elements.json`
- Openable drawing: `docs/aura-optimal-system-design.excalidraw`

The drawing shows the concrete target topology:

- Native Mac product surfaces: menu bar, ambient prompt, worker palette, badge
  stack, hover cards, activity view, readiness center.
- AURA core: context snapshot, setup/status checks, mission envelope, Hermes
  process lifecycle, worker and artifact UI projection, telemetry/audit.
- Project-local Hermes runtime: wrapper, parent mission, provider routing,
  configured tool exposure, delegation, memory/sessions, skills, cron, MCP
  manager, approval rules.
- Connection lanes: CUA proxy/daemon/host Mac, web/search, browser automation,
  terminal/file/code, messaging/delivery, external MCP, isolated lanes, native
  artifacts.

The drawing is intentionally connection-aware instead of button-oriented. The
implementation boundary is Hermes-owned: connections flow through Hermes config,
while AURA displays setup/status and projects Hermes progress into native UI.

```text
User
  |
  | hotkey / menu bar / mic / future context trigger
  v
AURA Native Shell
  |
  | ContextSnapshot + MissionEnvelope
  v
Hermes Parent Mission
  |
  | configured tools + skills + MCP + provider routing + delegation
  v
Connections
  |-- CUA Driver MCP proxy for host screen/app read and action
  |-- web/search/extract providers
  |-- browser automation providers
  |-- terminal/file/code execution backends
  |-- Apple/native app skills
  |-- messaging/delivery platforms
  |-- cron/scheduled tasks
  |-- memory/session search
  |-- external MCP servers
  |-- future CUA Sandbox / CuaBot isolated desktops
```

## Core Product Surfaces

### 1. Menu Bar Status

Purpose: always-on presence and quick state.

Must show:

- idle/running/attention/error
- active worker count
- approval-needed count
- setup-needed state if any required connection is broken

Primary actions:

- New Mission
- Open Activity
- Open Readiness
- Cancel Mission

### 2. Ambient Prompt

MVP:

- `⌃⌥⌘A` tap-to-open.
- text input remains first-class.
- voice is launched through Hermes Voice Mode, not an AURA transcription path.

AURA should provide a native entry point into project-local Hermes voice mode
and clear setup/status affordances. Hermes owns microphone recording, silence
detection, speech-to-text, text-to-speech, continuous voice loop behavior, and
voice configuration.

### 3. Worker Stack

Purpose: represent background work as visible objects.

Required objects:

- compact 2x2 worker palette for top active/recent workers
- right-edge worker badge stack for all active/recent workers
- hover card per worker
- artifact actions on completed workers

This is required for Clicky-style parity and also for trust.

### 4. Activity View

Purpose: drill-down for technical users and debugging.

Keep:

- current mission output
- Hermes sessions
- logs/status
- approval history

Do not make this the primary everyday product surface.

### 5. Readiness Center

Purpose: make supported connections explicit and self-healing.

This replaces scattered setup messages with one capability map.

Groups:

- Runtime: Hermes, provider/model, local config, global symlink warning.
- Host control: CUA install, daemon, Accessibility, Screen Recording, MCP.
- Web/browser: web providers, browser automation, CDP/local browser.
- Local work: terminal backend, file/code execution, sandbox backend.
- Native apps/skills: Apple Reminders, Notes, iMessage, FindMy, Spotify.
- Messaging/delivery: email/SMS/Slack/Discord/etc.
- Memory/sessions: built-in memory, session search.
- Scheduling: Hermes cron.
- External MCP: each stdio/HTTP server.

Each row should have:

- status: ready, needs auth, needs permission, missing dependency, disabled,
  degraded
- last checked
- setup hint
- safe diagnostic/test action

## Hermes-Owned Connection Status

AURA should not add a second capability planner or permission registry. It may
show a status view derived from bounded commands and local passive checks:

- `./script/aura-hermes status`
- `./script/aura-hermes doctor`
- `./script/aura-hermes mcp list`
- `./script/aura-hermes mcp test cua-driver`
- CUA passive permission checks
- local config template presence

Rules:

- Use `script/aura-hermes` and `script/aura-cua-mcp`; never global Hermes.
- Do not parse secrets or display secret values.
- Do not infer tool permissions from AURA state.
- Treat Hermes config as authoritative for which tools exist and what approvals
  are required.
- When setup is missing, show the Hermes/CUA command that diagnoses it instead
  of blocking missions with a custom classifier.

## Mission Launch Design

AURA should send the user goal and Mac context directly to Hermes. Hermes remains
the planner and tool router.

```text
User goal
  -> capture Mac context
  -> build concise mission envelope
  -> launch Hermes parent
```

Examples:

| Mission | Required capabilities | Preferred route | Approval |
|---|---|---|---|
| "What is this panel?" | context read, CUA screenshot/window | Hermes chooses configured CUA tools | Hermes config |
| "Clean my screenshots" | file ops, desktop context | Hermes chooses configured file/CUA tools | Hermes config |
| "Find leads under 50k followers" | web/search/browser, artifact | Hermes web; browser fallback | write CSV approval |
| "Set reminder" | Apple skill/native app | Hermes apple-reminders skill or CUA app action | required |
| "Build a Spotify app" | terminal/file/code, Spotify optional | Hermes code/file/terminal; Spotify only if ready | write/build/open approval |
| "Send this email" | doc read, messaging delivery | Hermes skills/messaging | always send approval |
| "Schedule this every Friday" | cron | Hermes cronjob | approval if it acts externally later |

Mission launch rules:

- Do not pass `-t` from AURA.
- Do not pass `AURA_AUTOMATION_POLICY` or `AURA_CUA_ALLOW_ACTIONS`.
- Include only goal, context snapshot, CUA readiness, and AURA safety copy in
  the mission envelope.
- If Hermes returns `NEEDS_APPROVAL`, AURA presents the approval and resumes the
  same Hermes session without changing toolsets.

## Worker And Artifact State

The MVP report says not to create a custom task database. That is correct for
execution truth. AURA still needs a derived UI state model.

Use Hermes sessions/delegation/process output as source of truth, but maintain a
small UI projection:

```swift
struct WorkerRun: Identifiable {
    let id: String
    let parentMissionID: String
    var hermesSessionID: String?
    var title: String
    var domain: WorkerDomain
    var status: WorkerStatus
    var latestAction: String
    var commandSnippet: String?
    var startedAt: Date
    var endedAt: Date?
    var artifacts: [AURAArtifact]
    var needsApproval: ApprovalRequest?
}

struct AURAArtifact: Identifiable {
    let id: String
    let workerID: String
    let path: String
    let type: ArtifactType
    let title: String
    let createdAt: Date
}
```

This model should be:

- derived from Hermes output and known paths
- small
- safe to reconstruct
- not a competing planner
- not a source of truth for subagent execution

## Connection Usage Policy

### CUA Driver

Use for:

- visible app/window context
- screen inspection
- host app actions when explicitly approved
- login/local state workflows only when needed

Do not use for:

- generic web scraping when Hermes web tools can do it
- file generation that terminal/file tools can do
- silent foreground takeover

### Web

Use Hermes programmatic web tools first for public research. If not configured,
the readiness center must say which provider is missing. Browser/CUA fallback
is only for logged-in, JS-heavy, or user-visible state.

### Browser

Use Hermes browser automation before CUA browser clicking when possible. Use
local Chrome/CDP only when configured and when the task needs local session
state. Account changes, submits, messages, purchases, uploads, deletes, or posts
remain approval-gated.

### Terminal/File/Code Execution

Use for local builds, generated apps, reports, CSVs, docs, and repo tasks after
Hermes config and approval rules permit. Prefer isolated terminal backends later
for risky/untrusted code. Local terminal is powerful and should be transparent
in worker cards.

### Skills

Use skills for repeatable domains instead of hardcoding app workflows:

- Apple Reminders/Notes/iMessage/FindMy
- Spotify
- OCR/documents/PDF
- Google Workspace
- social URL analysis
- software-dev helpers

AURA's setup should test skill dependencies before marketing a workflow.

### Messaging And Delivery

Treat every delivery connection as high-risk. Drafting is allowed; sending is
always approved by the user with recipient, channel, body, and side effects
visible.

### Cron/Scheduled Work

Use Hermes cron rather than building an AURA scheduler. AURA should display
scheduled jobs, pause/resume/edit/remove them, and surface delivery targets.
Any scheduled job that can send/post/spend must require explicit setup-time and
run-time approval rules.

### Memory

Use Hermes built-in memory for MVP. AURA can show memory status and session
recovery but should not create a separate long-term memory system.

### External MCP

Use MCP for GitHub, databases, internal APIs, file systems, and third-party
tools. AURA should not hand-code integrations when an MCP server exists. Each
MCP server gets a readiness row that points back to Hermes config for tool
exposure and approval behavior.

### Isolated Lanes

For risky computer-use or untrusted execution, prefer:

- Hermes container/remote terminal backends: Docker, SSH, Singularity, Modal,
  Daytona.
- CUA Sandbox or CuaBot for isolated GUI work.

Do not run risky exploratory tasks on the user's real desktop by default.

## UI Flow

### Default Mission

1. User presses `⌃⌥⌘A`.
2. Ambient prompt opens near cursor.
3. AURA captures frontmost app, bundle id, pid, cursor position, project root.
4. AURA launches one Hermes parent mission through `script/aura-hermes`.
5. Worker placeholder appears immediately.
6. Hermes output/delegation/tool signals update worker cards.
7. Approval blocks attach to the relevant worker.
8. Completion creates artifacts and follow-up actions.

### Approval

Approval copy must include:

- action
- target app/site/file/account/path
- risk category
- whether it is one-time or continuing
- what remains blocked after approval

Approval is not a dashboard-only concept. If a worker is blocked, the badge and
hover card must show it.

### Artifact Handoff

Every artifact should have:

- path
- type
- owning worker
- open/reveal/continue action
- safety policy for opening/running

CSV opens in Numbers or default CSV app. Generated apps can launch only when
Hermes approval permits or after explicit approval. Reports/logs open read-only.

## Dev Implementation Plan

### Phase 1: Hermes Config And Readiness Center

Files likely involved:

- `Sources/AURA/Models/`
- `Sources/AURA/Services/HermesService.swift`
- `Sources/AURA/Services/CuaDriverService.swift`
- `Sources/AURA/Stores/AURAStore.swift`
- new `Sources/AURA/Views/ReadinessCenterView.swift`

Tasks:

1. Keep CUA MCP transport lean and policy-free.
2. Move CUA tool exposure to Hermes config.
3. Parse bounded status from Hermes status/doctor and MCP list/test.
4. Add readiness rows for Hermes, provider/model, CUA, web, browser, terminal,
   skills, messaging, cron, memory, external MCP.
5. Add test/fix actions where safe.
6. Ensure no secrets are read into UI.

Acceptance:

- A developer can see that CUA is ready, web is missing keys, Spotify is blocked,
  and messaging is unconfigured before launching a mission.

### Phase 2: Capability Plan In Mission Envelope

Files likely involved:

- `Sources/AURA/Stores/AURAStore.swift`
- `Sources/AURA/Models/AURAMission.swift`

Tasks:

1. Remove AURA-side policy/toolset selection from mission launch.
2. Remove CUA action env gates from AURA-launched Hermes processes.
3. Keep the mission envelope focused on goal, context, readiness, and safety.
4. Resume approvals in the same Hermes session without changing toolsets.

Acceptance:

- AURA launches Hermes without `-t`.
- AURA does not pass `AURA_AUTOMATION_POLICY` or `AURA_CUA_ALLOW_ACTIONS`.
- Hermes config remains the only source of tool exposure.

### Phase 3: WorkerRun Projection And Ambient Worker UI

Files likely involved:

- `Sources/AURA/Stores/AURAStore.swift`
- `Sources/AURA/Views/CursorSurfaceView.swift`
- new worker views/controllers

Tasks:

1. Add `WorkerRun` and `AURAArtifact` UI projection.
2. Parse Hermes output for delegation/tool/process/progress/approval/artifact.
3. Add worker palette, badge stack, and hover card.
4. Attach approvals and artifacts to workers.

Acceptance:

- A delegated mission visibly shows multiple workers.
- A blocked worker is obvious without opening the dashboard.
- Completed workers expose artifacts.

### Phase 4: Artifact Registry

Tasks:

1. Parse final packets and known output paths.
2. Detect generated files in approved output directories.
3. Add open/reveal/continue actions.
4. Keep audit entries for local writes and launches.

Acceptance:

- CSV, generated app, folder, and report outputs are first-class UI objects.

### Phase 5: Hermes Voice Mode Integration

Tasks:

1. Add an AURA action labeled "Open Hermes Voice Mode".
2. Launch or foreground an interactive project-local Hermes surface through
   `script/aura-hermes`, never a global Hermes install.
3. Show setup hints and diagnostics for Hermes voice prerequisites:
   `hermes-agent[voice]` dependencies, PortAudio, ffmpeg, `voice`, `stt`, and
   `tts` config in `.aura/hermes-home/config.yaml`. Use Hermes'
   `tools.voice_mode.check_voice_requirements()` as the authoritative runtime
   probe.
4. Prefer Hermes local STT with `faster-whisper` when available, since it needs
   no API key. Cloud STT/TTS providers remain Hermes configuration.
5. Link the user to Hermes voice commands: `/voice on`, `/voice off`,
   `/voice tts`, `/voice status`, and configurable `voice.record_key`.

Acceptance:

- Hermes voice mode opens from AURA using the project-local runtime.
- `/voice status` works in the launched Hermes surface.
- AURA does not capture, transcribe, store, or score audio/transcripts itself.
- AURA does not request macOS microphone permission directly unless a future
  Hermes-supported embedded UI requires it.

### Phase 6: Connection Packs

Implement and test in this order:

1. Host context pack: CUA read and action gates.
2. Local artifact pack: terminal/file/code execution for outputs.
3. Web research pack: web provider or browser fallback with clear setup.
4. Apple app pack: Reminders/Notes/iMessage/FindMy dependencies and approvals.
5. Messaging pack: draft/send approval for email/SMS/Slack/etc.
6. Schedule pack: Hermes cron create/list/pause/resume/edit.
7. External MCP pack: GitHub or filesystem MCP as first non-CUA example.

## Issue Breakdown

Create issues in this order:

1. `runtime: move CUA tool exposure to Hermes config`
2. `connections: parse Hermes status/doctor into readiness rows`
3. `connections: parse MCP list/test and CUA availability`
4. `ui: add Readiness Center`
5. `mission: defer tool routing to Hermes config`
6. `mission: simplify approval resume through Hermes session`
7. `workers: add WorkerRun and AURAArtifact projection models`
8. `workers: parse Hermes delegation/tool/process/progress signals`
9. `ui: add ambient worker palette and badge stack`
10. `ui: add worker hover card and attached approval card`
11. `artifacts: add artifact registry and open/reveal/continue actions`
12. `web: add web provider readiness and research smoke test`
13. `browser: add browser/CDP readiness and fallback setup copy`
14. `skills: verify Apple Reminders/Notes skill dependencies`
15. `voice: add Hermes Voice Mode launcher`
16. `messaging: add draft/send approval contract`
17. `cron: expose Hermes scheduled jobs read/manage UI`
18. `mcp: add first external MCP readiness row beyond CUA`
19. `qa: add connection matrix smoke tests`
20. `packaging: carry registry/readiness into standalone bootstrap`

## Verification Matrix

### Connection readiness

- Hermes provider/model ready.
- CUA ready and MCP registered.
- Hermes configured CUA include list exposes only intended tools.
- Raw CUA MCP daemon can still be tested through the transport proxy.
- Web reports ready or exact missing provider keys.
- Browser reports ready or exact missing dependency.
- Skills reports installed and dependency status for Apple Reminders at minimum.
- Messaging reports unconfigured until credentials are present.
- Cron jobs list works even when there are zero jobs.

### Mission behavior

- Observe current app without approval.
- Web research either succeeds or shows missing web provider.
- Desktop cleanup requests approval before moving files.
- Apple Reminders requests approval before state change.
- Generated app writes only after approval and returns artifact path.
- Messaging drafts without sending, then asks before send.
- Scheduled job creation asks for confirmation if it will act later.
- Delegated research shows multiple workers.

### Safety

- AURA does not pass mission `-t` toolset overrides.
- AURA does not pass CUA policy/action env gates.
- Hermes config controls CUA action tool exposure.
- Hermes still stops for external sends/posts/purchases/credentials.
- Audit ledger does not store screenshots or prompt text.
- Cancel stops the active parent mission.
- Timeout does not orphan a visible worker.

## Design Non-Goals

Do not build:

- custom Swift agent planner
- custom browser automation
- custom long-term memory
- custom scheduler
- custom speech-to-text or text-to-speech pipeline
- Apple Speech or AVFoundation transcription layer
- duplicate voice session state outside Hermes
- separate per-connector chat screens
- hardcoded Figma/TikTok/Clicky demo buttons
- direct Swift calls to CUA action APIs during missions
- global Hermes dependency
- broad external-send automation without approval

## Final Recommendation

The most optimal AURA design is a native Mac trust shell around Hermes, not a
feature-by-feature clone of any one demo.

Use all supported connections through Hermes config and one mission pipeline.
The user sees a simple ambient command surface, visible workers, clear
approvals, and concrete artifacts. Hermes sees a precise mission envelope with
context, readiness, and safety constraints. CUA and every other connection
remain behind Hermes-owned configuration and explicit approval boundaries.

Build in this order:

```text
Hermes Config/Readiness
  -> Mission Envelope
  -> Worker UI
  -> Artifact Handoff
  -> Voice
  -> Connection Packs
  -> Standalone Bootstrap
```

This keeps the app lean, unlocks the full Hermes/CUA ecosystem, and gives the
dev team a stable architecture for both repo-backed MVP and external beta.
