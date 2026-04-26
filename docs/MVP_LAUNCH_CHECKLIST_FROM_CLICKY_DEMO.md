# Clicky-Parity Roadmap And MVP Launch Checklist

Source: https://x.com/i/status/2048203459976188261

Downloaded and reviewed locally on 2026-04-26. The video is a 3:43 demo of
"Clicky" by Farza. Local generated files were kept outside the repo:

- Video: `/tmp/aura-demo-video/demo.mp4`
- Transcript: `/tmp/aura-demo-video/transcript.txt`

Do not commit the downloaded video or transcript.

## Demo Summary

The demo positions Clicky as a consumer Mac-native agent surface with no setup.
The core flow is:

1. User speaks "Hey Clicky agent..." from anywhere on the Mac.
2. Clicky spawns visible background agents.
3. Agents can organize Desktop files, interact with Apple Reminders, research
   web/Instagram leads into a CSV, build and launch a native Mac app, and accept
   follow-up changes on prior work.
4. The product shows lightweight ambient status while work happens.

## Current AURA Snapshot

Local validation on 2026-04-26:

- `./script/setup.sh --check`: passed.
- `./script/aura-hermes mcp list`: `cua-driver` enabled.
- `cua-driver status`: daemon running.
- `./script/e2e_test.sh`: passed.
- `./script/build_and_run.sh --verify`: passed.
- `./script/aura-hermes doctor`: usable, but reports a broken global
  `~/.local/bin/hermes` symlink and missing optional API keys for full tool
  access.

Current AURA strengths:

- Native SwiftUI/AppKit shell with menu/dashboard and cursor-adjacent mission
  panel.
- Project-local Hermes boundary through `script/aura-hermes`.
- CUA Driver readiness gate and daemon-backed MCP proxy.
- Read Only, Ask Per Task, and Always Allow policy modes.
- Streaming mission output, cancel, timeout, approval parsing, resume, sessions,
  telemetry, and audit ledger.

Current AURA non-goals or gaps versus the demo:

- No voice input yet.
- No hold-to-talk lifecycle.
- No consumer standalone install, signing, notarization, or first-run runtime
  bootstrap.
- No per-agent card stack showing spawned workers and artifacts.
- No first-class artifact browser for CSVs, generated apps, screenshots, or
  final files.
- No in-app provider/key setup wizard.

## Hermes Official Capability Alignment

Sources reviewed:

- https://hermes-agent.nousresearch.com/docs/
- https://hermes-agent.nousresearch.com/docs/skills
- https://hermes-agent.nousresearch.com/docs/user-guide/features/overview
- https://hermes-agent.nousresearch.com/docs/user-guide/features/tools
- https://hermes-agent.nousresearch.com/docs/user-guide/features/delegation
- https://hermes-agent.nousresearch.com/docs/user-guide/features/browser
- https://hermes-agent.nousresearch.com/docs/user-guide/features/mcp
- https://hermes-agent.nousresearch.com/docs/user-guide/features/voice-mode
- https://hermes-agent.nousresearch.com/docs/user-guide/features/skills

Official Hermes docs materially reduce backend risk for AURA:

| Capability | Official Hermes support | AURA implication |
|---|---|---|
| Subagents / parallel work | `delegate_task` spawns isolated child agents with restricted toolsets, separate terminal sessions, default concurrency of 3, interrupt propagation, and final summaries returned to the parent. CLI mode has live tree progress; gateway mode batches progress callbacks. | Backend exists. AURA needs to render delegated child state instead of only showing parent mission text. |
| Background processes | Terminal supports `background=true`; `process` can list, poll, wait, log, kill, and write to running sessions. PTY mode supports interactive CLIs. | Backend exists for long builds/tests. AURA should surface process/session state, not just raw stdout. |
| Toolsets | Built-in categories include web , terminal/file, browser(https://cloud.browser-use.com/ in hermes skills), media, orchestration, memory, automation/delivery, MCP, and integrations. Common toolsets include `web`, `terminal`, `file`, `browser`, `vision`, `image_gen`, `skills`, `tts`, `todo`, `memory`, `session_search`, `cronjob`, `code_execution`, `delegation`, `clarify`, and dynamic MCP toolsets. | AURA should not pass per-mission toolset overrides. Configure available tools in project-local Hermes and keep AURA focused on context, launch, status, approvals, and UI projection. |
| Web and browser | Browser automation supports cloud providers, (https://cloud.browser-use.com/ in hermes skills). Browser pages are represented as accessibility-tree snapshots with ref IDs, with screenshot/vision support. | Do not build a Swift browser stack. Route web tasks through Hermes tools; use CUA only when host desktop context or logged-in local state is specifically required. |
| Voice | Hermes supports voice interaction in CLI and messaging platforms, including microphone input, spoken replies, and Discord voice channels. Local STT can work with `faster-whisper` and no API key. | Use Hermes Voice Mode directly. AURA should provide a project-local launcher/status affordance, not a native microphone/transcription stack. |
| MCP | Hermes discovers stdio and HTTP MCP servers, prefixes tools, supports startup registration, resources/prompts where available, and per-server tool filtering. | AURA's CUA daemon proxy is the right transport boundary. Keep tool exposure in Hermes config; avoid native Swift automation first. |
| Memory | Hermes has bounded curated memory across sessions via `MEMORY.md` and `USER.md`; changes are persisted and loaded at session start. | AURA should not add its own long-term memory for MVP. It can display/recover Hermes sessions and let Hermes own memory. |
| Skills | Skills are on-demand knowledge docs with progressive disclosure. Hermes can load skills as slash commands or by natural conversation, scan external skill dirs, create/update/delete agent-managed skills, and install hub skills with security scanning. Skills Hub lists 654 skills, including 74 built-in. | AURA should expose skills as backend capability, not hardcode demo workflows. Launch setup should verify important skills/tool dependencies. |
| Apple/native app skills | Skills Hub lists built-in `apple-notes`, `apple-reminders`, `findmy`, and `imessage`. It also lists `google-workspace`, `spotify`, `ocr-and-documents`, `powerpoint`, `xurl`, and other productivity/social skills. | Many Clicky-style demos are Hermes-skill-shaped. 
| Scheduled automations | Hermes has cron/scheduled tasks with natural-language or cron expressions, delivery targets, and pause/resume/edit operations. | Not needed for MVP demo parity, but AURA should not build its own scheduler if this becomes a product requirement. |


Important local reality from `./script/aura-hermes doctor` on 2026-04-26:

- `mcp-cua-driver`, browser tools, Codex auth, and core toolsets are available.
- Hermes reports missing optional API keys for full web tool access.
- `spotify` is listed but currently blocked by a system dependency.
- A broken global `~/.local/bin/hermes` symlink exists; AURA itself still uses
  `script/aura-hermes`, but testers may be confused if they run global Hermes.

Therefore, the launch framing should be:

> Hermes is capable enough for the Clicky-style backend shape. AURA's MVP work is
> to provide the Mac-native trust, setup, progress, approval, artifact, and
> background-worker surfaces around project-local Hermes.

## UI And Background-Agent Comparison

This section is based on the video frames and transcript, not Clicky source code.

### Clicky UI Pattern

Clicky keeps the primary product surface out of the way:

- A small menu-bar/status item appears near the top-right.
- A compact floating 2x2 agent palette appears on the desktop. Each slot has a
  domain-like icon, such as a screen/desktop icon, AirPods-style icon, or
  briefcase icon, with circular progress rings.
- Each spawned background agent also appears as a small colored desktop badge
  or chip near the right edge. The badges stack vertically and use color/shape
  to distinguish concurrent workers.
- Hovering a running worker expands it into a larger translucent status card.
  In the desktop-cleanup example, the card shows:
  - a truncated task title: `ORGANIZE DESKTOP SCREE...`
  - a green `Running` status pill
  - the current low-level command/tool activity, for example `ls -1 ...` and
    `sed -n ...`
  - a subtle progress line at the bottom
- Completion is communicated by the resulting state or artifact becoming visible
  in native apps: the Desktop folder exists, Reminders contains the new item,
  Numbers opens the influencer CSV, and the generated Spotify app launches.

The user does not live in a large control center. The main feedback loop is:
ambient badge -> optional hover detail -> native artifact/app opens.

### AURA UI Pattern Today

AURA currently exposes mission state more explicitly and centrally:

- Main SwiftUI dashboard with status cards for Hermes, Mission, Policy, and CUA.
- Cursor-adjacent ambient panel for typing a mission and approving/denying.
- Cursor-following assistant bubble that summarizes the latest mission line and
  changes color by state.
- Mission output is a monospaced text stream in the dashboard.
- Hermes sessions are shown as rows with session id, preview, status, model,
  message count, and tool-call count.

That makes AURA more inspectable and safer for a technical MVP, but less
consumer-native than Clicky. AURA shows the parent mission; Clicky visually
separates the spawned workers.

### Background Agent Handling

Clicky appears to treat each spawned task as a first-class UI object:

- The user can spawn multiple workers from voice without opening a dashboard.
- Each worker gets an icon/color/status identity.
- Workers run concurrently and remain visible while the user continues using
  the Mac.
- The system can say two agents are done while two are still running.
- Hovering a worker exposes operational details without forcing a full logs
  window.
- Completed workers hand off to concrete artifacts or native apps.

AURA currently treats Hermes as the first-class unit:

- One parent Hermes mission is launched per AURA request.
- Hermes may delegate internally, but AURA does not yet render child workers as
  separate UI entities.
- AURA streams parent output and logs delegation/tool signals for telemetry.
- Completion is text-first unless Hermes itself opens or creates an artifact.
- Follow-up work depends on Hermes session continuity, but the UI does not yet
  offer a clear "continue this completed mission" action.

### Product Implication For AURA

For Clicky-parity, AURA does need to recreate the observable visual treatment:
ambient worker badges, hover detail cards, concurrent worker state, and native
artifact handoff. A simpler compact worker list can be an internal checkpoint,
but the clone demo is not done until the ambient worker UI exists.

Minimum credible behavior:

1. Keep the parent mission visible and cancellable.
2. Parse or summarize Hermes delegation events into a compact worker list.
3. Show worker states: queued, running, needs approval, done, failed.
4. Surface the latest meaningful action per worker, not raw unbounded logs only.
5. On completion, show artifacts as clickable/openable paths or launch the
   created native artifact when policy allows.
6. Preserve safety: opening artifacts is okay after approval/policy; sending,
   posting, purchasing, credential handling, and external contact remain gated.

For exact demo parity, add an ambient worker stack:

- persistent top-right or cursor-adjacent worker badges
- one badge per delegated child or artifact-producing task
- hover/expand cards with task title, status, latest action, elapsed time, and
  cancel/reveal controls
- completed cards that become artifact shortcuts
- a full activity view only as secondary drill-down

## UI Flow Spec For Developers

This section is the implementation-facing UI contract. It describes the target
observable flow; component names are suggested and can change during
implementation.

### Surface Inventory

| Surface | Purpose | Default location | Opens when | Closes when |
|---|---|---|---|---|
| Menu bar item | Always-on AURA presence and quick status. | macOS menu bar. | App launch. | App quits. |
| Ambient prompt | Voice/text command capture. | Near cursor or top-right safe area. | Hotkey, menu-bar click, or mic action. | Submit, Escape, outside click, or explicit close. |
| Worker palette | At-a-glance active/recent agents. | Floating desktop overlay, compact 2x2 grid. | First worker starts. | No active/recent workers after retention window. |
| Worker badge stack | Persistent per-worker presence. | Right screen edge, vertically stacked. | Worker created. | User dismisses completed worker or retention expires. |
| Worker hover card | Operational detail without opening dashboard. | Opens inward from the hovered badge/palette slot. | Hover or focus on worker. | Pointer leaves, Escape, or another worker opens. |
| Approval sheet/card | Gated action confirmation. | Attached to the relevant worker card when possible; otherwise ambient prompt. | Hermes/AURA requests approval. | Approve, deny, cancel, timeout. |
| Artifact strip | Outputs from completed work. | Bottom of hover card or details drill-down. | Worker has artifacts. | Worker dismissed or artifact removed. |
| Full activity view | Debug/drill-down logs and sessions. | Existing dashboard. | User clicks details. | User closes dashboard. |

### Global UI States

The app should always be in one of these user-visible states:

| State | Menu bar | Prompt | Worker UI | User expectation |
|---|---|---|---|---|
| Idle | Neutral icon. | Hidden. | Hidden or faded recent completions. | AURA is available but doing nothing. |
| Listening | Mic/listening affordance. | Visible with waveform or recording indicator. | Existing workers remain visible. | Speech is being captured. |
| Reviewing transcript | Attention state. | Shows transcript and submit/edit controls. | Existing workers remain visible. | User can correct risky/low-confidence voice input. |
| Submitting | Busy state. | Disabled composer with spinner. | New pending worker may appear. | Mission is being handed to Hermes. |
| Running | Active/ring state. | Usually hidden after submit. | Palette and badge stack visible. | Work continues in background. |
| Needs approval | Attention state. | Approval visible if focused. | Relevant worker badge/card pulses or highlights. | User action is required before continuing. |
| Completed | Done state briefly. | Hidden unless opened. | Completed worker becomes artifact shortcut. | Output is ready. |
| Failed | Error state. | Optional retry prompt. | Failed worker is visible with reason. | User can inspect and retry. |

### Primary Flow: Voice Mission

1. User invokes AURA by hotkey, menu-bar action, or mic control.
2. Ambient prompt appears without taking over the screen.
3. If voice mode is active, prompt enters `Listening`:
   - show mic icon/state
   - show live waveform or recording timer
   - keep existing workers visible
4. On stop, AURA transcribes audio.
5. If transcript confidence is acceptable and the task is low risk, submit
   directly. If confidence is low or the task touches files/apps/accounts, show
   the transcript in `Reviewing transcript` with edit and submit controls.
6. On submit, create a parent mission and immediately show a pending worker
   placeholder so the user sees continuity from command to background work.
7. When Hermes emits the first concrete delegation/tool/process event, replace
   the placeholder with the real worker title, icon, status, and latest action.
8. Hide the prompt after submit unless approval is needed.

### Primary Flow: Text Mission

1. User invokes AURA.
2. Ambient prompt appears with focused text input.
3. User submits.
4. Prompt enters `Submitting`, then hides.
5. Worker palette and badge stack show the mission/worker lifecycle exactly as
   in the voice flow.

Text and voice must converge into the same mission pipeline after transcription.
Do not create separate agent runtimes or separate policy paths.

### Worker Creation Flow

When AURA starts or detects a unit of background work:

1. Create a `WorkerRun`.
2. Assign stable visual identity:
   - icon by task domain: desktop/files, Apple app, web/research, code/app,
     browser/account, generic
   - color by worker id, stable for the session
   - short title from user prompt or Hermes child-agent summary
3. Add worker to:
   - 2x2 palette if it is active or recently completed
   - right-edge badge stack
   - full activity view
4. Set initial state:
   - `queued` for planned/delegated work not yet running
   - `running` once Hermes/tool/process activity starts
   - `needs approval` when blocked on user confirmation
   - `done`, `failed`, or `cancelled` on terminal state

If more than four workers exist, the palette shows the four most relevant
workers in this order: needs approval, running, failed, recently completed. The
badge stack can contain more workers and should scroll or compress if needed.

### Worker Badge Behavior

Each badge is a small persistent desktop object. It should be glanceable before
it is readable.

Required badge content:

- domain icon
- state color/ring
- progress or activity animation
- attention pulse only for `needs approval` or fresh failure

Badge interactions:

- hover/focus: open hover card
- click: pin hover card open
- double click or primary action: open artifact if completed, otherwise open
  details
- secondary/context action: cancel, reveal, dismiss, copy artifact path where
  available

Badge states:

- `queued`: dim ring, no animation
- `running`: animated ring or subtle spinner
- `needs approval`: highlighted ring and attention pulse
- `done`: check state, quiet color
- `failed`: error color, no aggressive flashing
- `cancelled`: neutral stopped state

### Hover Card Layout

The hover card should fit the demo use case without becoming a log window.

Required layout from top to bottom:

1. Header row:
   - worker icon
   - truncated uppercase or title-case task label
   - status pill
2. Latest action:
   - one or two lines max
   - examples: `Listing Desktop screenshots`, `Writing CSV`,
     `Building Swift app`, `Waiting for Reminders approval`
3. Optional command/tool detail:
   - monospaced single-line snippet if useful
   - never stream unbounded logs in the card
4. Progress row:
   - elapsed time
   - small progress/activity line
5. Action row:
   - `Cancel` while running
   - `Approve` / `Deny` when blocked
   - `Open`, `Reveal`, `Continue`, `Details` when completed

The card opens inward from the screen edge so it never clips offscreen. Text
must truncate or wrap cleanly inside the card; no overlap is acceptable.

### Approval Flow

Approvals should feel attached to the worker that needs them.

1. Hermes/AURA detects a gated action.
2. Worker state becomes `needs approval`.
3. Badge and palette slot highlight.
4. Hover card or attached approval card shows:
   - what will happen
   - target app/file/account/path
   - risk category: file write, host control, account action, send/post,
     purchase, credential, financial
   - Approve and Deny controls
5. If approved, worker returns to `running`.
6. If denied, worker either continues with an alternate plan or becomes
   `cancelled`/`failed` with a clear reason.

Never hide an approval only in the dashboard. The ambient UI must make blocked
work obvious.

### Artifact Handoff Flow

When a worker produces an output:

1. Register artifact path, type, title, and owning worker.
2. Update worker state to `done`.
3. Convert completed badge/card into an output shortcut.
4. Show primary action by artifact type:
   - CSV: `Open in Numbers` or default CSV app
   - folder/file: `Reveal`
   - generated app: `Launch`
   - screenshot/image: `Open`
   - log/report: `Open`
5. Keep `Continue` visible for artifacts that support follow-up work, especially
   generated apps and research files.

Completed workers should remain visible long enough for the user to discover the
artifact without opening the dashboard.

### Multi-Agent Flow

The demo explicitly shows multiple background agents with mixed completion
state. AURA should support this as a first-class flow.

1. User starts one mission that delegates, or starts multiple missions.
2. Each child/task gets its own worker identity.
3. Palette shows active top four workers.
4. Badge stack shows all current workers.
5. Menu bar can summarize counts: running, done, attention.
6. If the assistant says "two are done and two are still running", the UI must
   visibly agree.
7. Completion of one worker must not collapse or obscure the still-running
   workers.

### Follow-Up Flow

Follow-up is required for the generated-app part of the reference demo.

1. User opens or hovers a completed app-building worker.
2. User chooses `Continue` or submits a new prompt while that worker/session is
   selected.
3. AURA attaches the new prompt to the prior Hermes session/artifact context.
4. Worker re-enters `running` or creates a linked child worker.
5. Artifact path remains stable unless Hermes intentionally creates a new
   version.
6. On completion, AURA relaunches or reveals the updated artifact when policy
   allows.

### Error And Empty States

Errors should be specific enough for a tester to fix setup issues quickly.

Required error patterns:

- Missing web/search provider: show provider setup issue and link to readiness.
- Missing Apple automation permission: show permission name and recovery path.
- Missing CUA daemon/permission: show CUA readiness action.
- Spotify dependency blocked: show dependency status and keep the generated app
  demo scoped accordingly.
- Hermes child failed: show child title and final summary.
- Artifact missing: show expected path and offer reveal parent folder/logs.

Avoid generic "failed" cards without a concrete cause or next action.

### Event-To-UI Mapping

| Event source | Example event | UI update |
|---|---|---|
| User submit | Prompt submitted. | Create pending parent worker; prompt enters submitting. |
| Hermes delegation | Child agent spawned. | Create or link `WorkerRun`; add badge/palette slot. |
| Hermes tool call | Browser/file/terminal action. | Update latest action and optional command/tool detail. |
| Hermes process | Background build/test command. | Keep worker running; show process label and elapsed time. |
| AURA policy | Approval required. | Worker becomes needs approval; show attached approval card. |
| File/artifact detector | CSV/app/folder created. | Attach artifact to worker; show open/reveal actions. |
| Hermes completion | Child/parent done. | Mark worker done; keep artifact shortcut visible. |
| Hermes failure/timeout | Error or timeout. | Mark failed; show reason and retry/details. |
| User cancel | Cancel clicked. | Cancel worker/mission where supported; update badge/card. |

### Visual Guardrails

- Ambient UI must not cover the active app's main content for long periods.
- Default overlays should be small; details appear on hover/focus.
- No nested cards in the dashboard or hover card.
- No in-app explanatory marketing copy in the main workflow.
- Icon buttons should use familiar symbols with tooltips.
- Worker colors must be distinct but restrained; avoid a one-hue palette.
- Motion should communicate state, not decorate the screen.
- Every visual state must have a text/state equivalent for accessibility and
  testing.

## Clicky-Parity Roadmap

Goal: recreate the observable Clicky demo flow as an AURA-native product
experience. This means matching the interaction model, background-agent
visibility, task outcomes, and artifact handoff shown in the video. Do not copy
Clicky branding, proprietary assets, proprietary code, or protected design
files.

Success criterion: a side-by-side AURA demo can follow the same sequence as the
reference video and produce equivalent outcomes:

1. Invoke AURA from anywhere on the Mac.
2. Ask it to clean up screenshots on the Desktop.
3. Watch a visible background worker run, hover it, and see status/details.
4. Ask it to create an Apple Reminders item.
5. Ask it to research Instagram micro-influencers and write a CSV.
6. Ask it to build and launch a small native Mac app.
7. See multiple agents where some are done while others are still running.
8. Open the Reminders result, CSV artifact, and generated Mac app.
9. Ask a follow-up change against the generated app and see it update/relaunch.

### Phase 0: Reference Spec And Demo Harness

Timeline: 2-3 days.

Deliverables:

- Keep the downloaded reference video, transcript, and keyframes outside the
  repo.
- Convert the transcript into a timecoded demo script with exact prompts,
  expected agent states, and expected outputs.
- Define the AURA side-by-side recording script before implementation starts.
- Add manual acceptance cases for the four visible demo tasks: Desktop cleanup,
  Reminders, influencer CSV, and generated Mac app.

Acceptance:

- Anyone on the team can run the same demo script and know whether AURA matches
  the reference flow.
- The roadmap tracks observable parity, not vague "agent UX" goals.

### Phase 1: Ambient Worker UI

Timeline: 1-2 weeks.

Build the visible shell first, even if some workers initially use mocked
progress. The demo depends on feeling like work is happening in the background.

Deliverables:

- Menu-bar entry remains present and stable.
- Global hotkey opens a compact prompt surface near the cursor.
- Add a floating 2x2 worker palette with:
  - one slot per active/recent worker
  - icon, color, circular progress ring, and state
  - compact done/running/failed/needs-approval visual treatment
- Add a right-edge worker badge stack with one badge per background task.
- Add hover cards for each worker showing:
  - truncated task title
  - status pill
  - latest meaningful tool/command/action
  - elapsed time
  - cancel, reveal output, and open details controls
- Keep the full dashboard as a secondary drill-down, not the main demo surface.

Acceptance:

- During a multi-agent mission, the user can tell what is running without
  opening the dashboard.
- Hovering a worker shows enough operational detail to feel transparent without
  dumping raw logs.
- Completed workers become artifact shortcuts when they produced files/apps.

Likely implementation areas:

- New ambient overlay controller, separate from the existing mission panel.
- New SwiftUI worker badge/palette/card components.
- `AURAStore` state for active workers and artifacts.

### Phase 2: Hermes Delegation And Worker Event Model

Timeline: 1-2 weeks.

Clicky visually treats background agents as first-class objects. AURA needs an
internal model that turns Hermes parent/child work into UI workers.

Deliverables:

- Introduce a `WorkerRun` model with:
  - stable id
  - parent mission/session id
  - title
  - status: queued, running, needs approval, done, failed, cancelled
  - latest action
  - tool/process/session identifiers
  - started/ended timestamps
  - artifact paths
  - approval requirement
- Parse Hermes stream output for delegation, tool, process, approval, artifact,
  and completion events.
- Map Hermes delegated child agents to visible worker cards.
- Map long-running terminal/background processes to worker latest-action state.
- Preserve cancellation and timeout behavior per parent mission; add worker-level
  cancel where Hermes can safely support it.
- Persist enough session/artifact metadata to support "continue this" follow-up.

Acceptance:

- A Hermes delegation mission produces separate visible AURA worker states.
- If Hermes reports two workers complete and two still running, AURA shows that
  distinction without relying on free-form transcript text.
- The parent mission remains cancellable and auditable.

### Phase 3: Voice-First Invocation

Timeline: 1-2 weeks.

The reference demo is voice-led. AURA can keep text input, but parity requires a
native microphone path.

Deliverables:

- Add a microphone button to the ambient prompt.
- Add push-to-talk from the prompt; global hold-to-talk can come after the
  first voice path is reliable.
- Transcribe into the same mission composer used by text.
- Show the transcript before submit when confidence is low or the mission is
  risky.
- Route voice missions through the same policy and approval system as typed
  missions.
- Decide whether MVP uses Apple Speech, local faster-whisper, or Hermes voice
  plumbing; keep the runtime project-local and documented.

Acceptance:

- User can complete at least the Desktop cleanup and Reminders demo prompts by
  voice.
- Voice does not bypass approval gates.
- Text fallback remains available.

### Phase 4: Demo Task Parity

Timeline: 2-4 weeks.

These are the exact visible capabilities from the Clicky video. Each gets a
golden prompt, acceptance state, and known dependency list.

Deliverables:

- Desktop cleanup:
  - prompt: clean up screenshots on Desktop
  - creates/reuses a Desktop folder
  - moves matching screenshots after approval/policy check
  - worker shows file actions and completion
- Apple Reminders:
  - prompt: dinner reminder tomorrow at 9 PM
  - uses Hermes Apple Reminders skill or CUA-backed native app control
  - opens/reveals Reminders result when allowed
  - approval-gates state-changing native app work
- Influencer research CSV:
  - prompt: find Instagram micro-influencers under 50k followers for a landing
    page/product context
  - uses Hermes web/browser tools
  - writes a CSV with handles, URLs, follower counts, category, rationale, and
    draft DM
  - opens in Numbers or reveals file
- Generated Mac app:
  - prompt: build a small Mac app that controls local Spotify with a retro
    record-player UI
  - creates the app in an approved output directory
  - builds and launches it
  - records the artifact path
- Follow-up iteration:
  - prompt: make the background red and more retro
  - continues the prior app-building session
  - modifies, rebuilds, and relaunches the same artifact
- Multi-agent concurrency:
  - run at least two demo tasks concurrently
  - show mixed states: running, done, needs approval, failed if applicable

Acceptance:

- Each demo task has a repeatable manual script.
- Failures show actionable missing dependency or approval state, not generic
  "agent failed" output.
- Produced artifacts can be opened from the ambient worker UI.

### Phase 5: Artifact Handoff

Timeline: 1 week.

Clicky's outputs become native Mac artifacts. AURA needs that same handoff.

Deliverables:

- Artifact registry for generated files, folders, apps, screenshots, CSVs, and
  logs.
- Worker cards show primary artifact and secondary artifacts.
- `Reveal in Finder`, `Open`, and `Continue` actions.
- Safe output directory convention for generated apps and files.
- Native launch behavior respects policy and approval mode.

Acceptance:

- CSV opens in Numbers or the user's default CSV app.
- Generated app launches from its output location.
- Completed worker cards remain useful after the mission stream ends.

### Phase 6: Setup, Permissions, And Safety

Timeline: 1 week.

The demo feels zero-setup. AURA can ship a technical MVP first, but parity
requires setup friction to be surfaced and fixed.

Deliverables:

- In-app readiness screen for:
  - project-local Hermes health
  - auth/provider status
  - web/search provider availability
  - CUA Driver status and permissions
  - Apple automation permissions
  - browser/CDP availability
  - Spotify dependency status
- Recovery copy for each missing dependency.
- Keep Read Only as the default posture for broad testers.
- Preserve hard approval gates for sends, posts, purchases, credentials,
  financial actions, and external-contact workflows.
- Keep audit ledger entries for every host-control and file-write action.

Acceptance:

- A tester can see why a demo task cannot run before starting it.
- Approval prompts are explicit enough to preserve trust but do not destroy the
  ambient flow.

### Phase 7: Side-By-Side Polish Pass

Timeline: 1 week.

Deliverables:

- Record AURA running the exact reference script.
- Compare frame-by-frame against the reference for:
  - invocation latency
  - worker visibility
  - hover card clarity
  - concurrent-agent state
  - native artifact handoff
  - follow-up iteration speed
- Trim dashboard dependence from the demo path.
- Fix visual overlap, text truncation, animation timing, and stale state.

Acceptance:

- AURA can be demoed without explaining internal Hermes logs.
- The viewer understands which agents are running, which are done, and where
  their outputs went.

### Parallel Workstreams

These can proceed in parallel once Phase 0 is complete:

| Workstream | Owner surface | Main dependency | Done when |
|---|---|---|---|
| Ambient UI | SwiftUI/AppKit overlay | Worker model shape | Worker palette, badges, and hover cards run against mocked and real state. |
| Hermes events | `HermesService` / store | Delegation output format | Parent/child/process/artifact events become structured worker updates. |
| Voice | Prompt surface / mission composer | STT choice | Voice missions submit through normal policy path. |
| Demo tasks | Hermes skills/tools/CUA | Local dependencies | Four reference tasks pass repeatably. |
| Artifacts | Store + UI actions | Worker completion metadata | Outputs are openable/revealable/continuable. |
| Setup/safety | Readiness and approval UI | Doctor/dependency probes | Missing capabilities are visible before a failed demo. |

## Checklist

Legend:

- Required: should be done before MVP launch.
- Should: important for a credible demo-backed MVP, but can ship after the
  repo-backed technical MVP if clearly documented.
- Later: useful for consumer parity, not needed for the first technical MVP.

| Area | Demo behavior | AURA status | Launch check |
|---|---|---|---|
| Hotkey ambient entry | Agent is available from the Mac desktop. | Partial. AURA has `Ctrl+Option+Cmd+A` and cursor panel. | Required: keep hotkey/panel stable and verified with `build_and_run.sh --verify`. |
| Voice invocation | User speaks every mission. | Missing. Docs explicitly say voice is not built. | Should: add microphone button and speech-to-text before marketing voice-first. Keep text fallback. |
| Hold-to-talk | Demo feels push-to-talk/always ready. | Missing. Current hotkey is tap-to-open. | Later: implement only after global key-up tracking is tested. |
| Agent spawning | User says "agent" and multiple background agents run. | Backend strong. Hermes `delegate_task` supports isolated child agents and parallel batches; AURA launches one parent mission. | Required: prove delegation through AURA and surface delegated progress clearly enough in mission output. |
| Per-agent visibility | Demo shows/mentions hoverable agent state. | Backend partial, UI missing. Hermes has CLI tree/gateway progress; AURA has no per-worker cards. | Should: add compact worker/progress summaries from Hermes output/session data before a polished public demo. |
| Ambient worker stack | Demo has colored stacked worker badges and hover detail cards. | Missing. AURA has one cursor bubble and dashboard output. | Should: for MVP, parse worker states into a compact list; for consumer beta, add ambient worker badges. |
| Desktop cleanup | Agent cleans screenshots into a Desktop folder. | Architecturally possible through CUA/Hermes, approval-gated. | Required: add an acceptance test/manual script for "organize visible Desktop screenshots" in Ask Per Task and Always Allow. |
| Native Apple apps | Agent sets a Reminders item. | Backend strong but dependency-sensitive. Skills Hub lists built-in Apple Notes/Reminders/FindMy/iMessage skills; CUA is also available. | Required: verify Apple Reminders skill/dependency path locally and gate state-changing native actions. |
| Web research | Agent researches Instagram micro-influencers. | Backend strong, local setup partial. Hermes supports web search/extract and browser automation; local doctor reports missing optional web API keys. | Required: configure at least one reliable web/research path or make the limitation explicit in setup. |
| Logged-in/social surfaces | Agent inspects Instagram in Chrome. | Backend strong but risky. Hermes browser supports local Chrome/CDP and browser sessions; CUA can inspect host state. | Should: gate account-state changes and messaging; research/read-only is okay, outreach is approval-only. |
| CSV artifact | Agent creates a CSV of leads and DM examples. | Possible after file-write approval; no artifact browser. | Required: final packet must show explicit output path. Should: add artifact list/open actions. |
| Generated Mac app | Agent builds and launches a native app. | Possible through Hermes terminal/file/code tools after approval; not productized. | Should: add one golden "generate simple SwiftPM app into output dir" scenario with build/launch gates. |
| Follow-up iteration | User asks to modify the generated app. | Partial. Hermes sessions exist, but AURA has no clear continue-completed-session UI. | Should: add "continue last mission" or selected-session continuation before showing iterative app-building demos. |
| Native app control | Demo app controls Spotify. | Backend possible. Skills Hub lists built-in Spotify skill; local doctor says Spotify system dependency not met. | Later: keep this as an example output until local Spotify auth/dependency checks pass. |
| Skills / reusable workflows | Demo implies repeated categories: desktop, Apple apps, research, app building. | Backend strong. Hermes skills are built-in, hub-installable, and agent-managed. | Required: verify that AURA launches Hermes with `skills` enabled and setup docs explain where skill dependencies live. |
| Zero setup | Demo says built for consumers, no setup. | Not ready. AURA is repo-backed technical MVP. | Required: position launch as technical MVP only. External beta needs standalone runtime, signing, notarization, and first-run bootstrap. |
| Safety posture | Demo shows powerful background actions. | Strong. AURA has policy modes, approvals, audit, and CUA gating. | Required: keep Read Only default and verify approval gates for writes, host control, sends, posts, purchases, credentials, and financial actions. |
| Mission cancel/timeout | Not highlighted in demo. | Present. Cancel and 300s timeout exist. | Required: keep e2e coverage passing and document timeout behavior. |
| Onboarding/recovery | Demo implies no setup friction. | Partial. CUA gate is clear; Hermes/provider setup is still technical. | Required: improve recovery copy for missing Hermes auth/API/web tools before inviting non-core testers. |

## MVP Launch Gate

For the repo-backed MVP, launch only when these are true:

1. Existing local gates pass: setup check, Hermes doctor with only documented
   non-blocking issues, CUA MCP list, e2e, and build verification.
2. AURA can complete one read-only screen-context mission.
3. AURA can complete one approval-gated host-control mission.
4. AURA can complete one Hermes delegation mission and show child/worker
   progress well enough that the user knows what is running.
5. AURA can complete one web/research mission or clearly reports missing web
   provider/tool setup.
6. AURA can complete one skills-backed mission, preferably Apple Reminders or
   OCR/docs, or clearly reports missing local dependencies.
7. AURA can produce one local artifact after approval and show the output path.
8. AURA can show at least a compact status summary for delegated/background
   work, even if child agents are not yet full ambient UI objects.
9. Safety hard stops are tested for send/post/purchase/credential/financial
   actions.
10. Docs and UI do not imply AURA-native voice, zero-setup, standalone install, or consumer
   app parity until those are built.

For an external consumer beta, add these gates:

1. Standalone runtime location and first-run bootstrap.
2. Developer ID signing, hardened runtime, notarization, stapling, and clean
   machine Gatekeeper validation.
3. In-app provider/key setup and recovery.
4. First-class artifact surface.
5. Voice input if marketing follows the Clicky-style demo.
