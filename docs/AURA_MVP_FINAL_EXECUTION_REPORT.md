# AURA MVP Final Execution Report

> **For:** Dev team  
> **Date:** April 2026  
> **Status:** Corrected execution plan for repo-backed MVP, then external beta  
> **Principles:** Simple. Reliable. Fast on low-end Apple Silicon. Trust before autonomy.

This report replaces the earlier launch-audit draft as the execution source of truth.

It is intentionally grounded in the current repo contract:

- AURA is the native macOS ambient shell.
- Hermes is the agent runtime, planner, delegator, memory/tool/MCP owner, and final synthesizer.
- CUA Driver is the approval-gated host-control lane exposed to Hermes through `script/aura-cua-mcp`.
- AURA must not become a custom agent runtime, a browser automation framework, a task database, or a hardcoded demo app.

---

## 0. Corrections To The Previous Report

The previous report had useful direction, but several claims were wrong or too strong for the current repo.

### 0.1 Model config is a runtime validation task, not a proven repo bug

The current repo search does not show a checked-in `gpt-5.4` model reference. Do not write the launch plan as if this is a confirmed code blocker.

Correct blocker:

- The project needs a provider/model configuration template.
- Setup must make it obvious where API keys and model names live.
- `script/aura-hermes doctor` or an equivalent smoke test must prove the configured provider can complete one minimal inference call.
- Do not ship stale model IDs in docs. Treat model IDs as config values validated at setup time.

### 0.2 Voice is not built

The current app has no `SFSpeechRecognizer`, `AVAudioEngine`, microphone permission keys, speech-recognition permission keys, or push-to-talk state machine.

Voice should be implemented, but it is not part of the current baseline.

### 0.3 Current hotkey is tap/open, not hold-to-talk

The current hotkey controller uses Carbon `RegisterEventHotKey` plus a local `NSEvent` key-down monitor. That supports opening the ambient panel. It does not provide a complete key-down/key-up lifecycle for hold-to-talk.

Correct MVP path:

1. Keep `⌃⌥⌘A` tap-to-open working.
2. Add a visible microphone button or keyboard shortcut inside the ambient panel first.
3. Add hold-to-talk only after key-up tracking is implemented and tested globally.

### 0.4 CUA host control is not invisible background automation

Do not claim host-level CUA has no focus stealing, no cursor movement, or no host takeover risk.

Correct framing:

- Localhost CUA is unsandboxed host control.
- It must be explicit, observable, cancellable, and approval-gated.
- For isolated work, use CUA Sandbox or CuaBot later.
- The default MVP behavior must be snapshot -> act -> re-snapshot -> verify.

### 0.5 Do not hardcode CUA tool schemas in AURA

`script/aura-cua-mcp` dynamically lists tools from the running CUA Driver daemon and filters them by AURA policy. The report must not freeze an Anthropic-style hand-written tool schema unless the daemon actually advertises that schema.

Correct implementation:

- Discover MCP tools from the daemon.
- Treat tool names and input schemas as runtime contracts.
- Keep the proxy policy gate as the source of truth for read-only vs action tools.
- Test against the actual advertised tool names from `./script/e2e_test.sh`.

### 0.6 Web research belongs to Hermes, not Swift

AURA should not build its own DuckDuckGo, Brave, scraping, browser, or web extraction subsystem in Swift.

Correct implementation:

- Register/use web tools through Hermes.
- Prefer programmatic web tools when Hermes has them.
- Use CUA browser interaction only when the task requires login, JS-heavy pages, form filling, or host context.

### 0.7 Homebrew is not a complete substitute for signing/notarization

Homebrew can be a useful technical distribution path, but it is not the product-grade answer for nontechnical users.

Correct launch path:

1. Repo-backed technical MVP first.
2. Ad-hoc signed local app for internal testers.
3. Standalone runtime path and first-run bootstrap.
4. Developer ID signing + hardened runtime + notarization before broad external beta.
5. Homebrew Cask as an optional technical install path.

### 0.8 macOS 13 support is desired, not proven

The current Swift package and build script require macOS 14. Do not lower the target just because the APIs may exist on macOS 13.

Correct implementation:

- Keep the current macOS 14 baseline until a Ventura machine passes build, launch, CUA readiness, and e2e.
- After validation, lower both `Package.swift` and `script/build_and_run.sh` together.
- If any dependency fails on Ventura, document macOS 14 as the MVP floor.

### 0.9 Remove unverified benchmark and paper claims from execution gates

Do not gate the launch on unverified external benchmark numbers, model rankings, or paper claims. They can live in a research appendix after separate verification.

Execution gates must be repo-local and measurable.

---

## 1. Current Baseline

### Built and should be preserved

| Area | Current state | Keep / Change |
|---|---|---|
| Native shell | SwiftUI/AppKit app with dashboard, ambient entry, status cards, and mission output | Keep |
| Shortcut | `⌃⌥⌘A` opens AURA | Keep tap-to-open; later add hold-to-talk |
| Runtime bridge | `script/aura-hermes` invokes project-local Hermes under `.aura/` | Keep as hard boundary |
| Hermes home | `HOME` and `HERMES_HOME` are scoped into `.aura/` | Keep |
| CUA integration | `script/aura-cua-mcp` proxies Hermes MCP calls to CuaDriver.app daemon | Keep |
| CUA gate | AURA locks mission workflow until CUA install, daemon, permissions, and MCP registration are ready | Keep for host-control MVP |
| Policies | Read Only, Ask Per Task, Always Allow | Keep; refine external-action rules |
| Approval loop | `NEEDS_APPROVAL:` line -> approval card -> `--resume <session_id>` | Keep |
| Sessions | AURA reads Hermes structured sessions export | Keep |
| Telemetry/audit | Apple Unified Logging plus local JSONL audit ledger | Keep; do not log screenshots/prompts |
| Validation | `script/e2e_test.sh` runs real Hermes/CUA/session/approval checks | Keep and extend |

### Not built and must not be claimed as built

| Area | Status |
|---|---|
| Voice input | Not implemented |
| Push-to-talk | Not implemented |
| User notifications | Not implemented in repo search |
| Artifact browser | Not implemented as a first-class surface |
| Standalone runtime install | Not implemented |
| Model/provider setup wizard | Not implemented |
| Keychain storage | Not implemented |
| Token-level streaming guarantee | Not guaranteed; app streams subprocess output if Hermes emits it |
| Worker progress UI | Not implemented beyond sessions/status output |
| Dynamic benchmark dashboard | Not implemented |

---

## 2. Product Definition

AURA is a **native macOS ambient mission shell**.

The user experience:

1. User presses `⌃⌥⌘A`.
2. A cursor-adjacent panel opens.
3. User types or speaks a mission.
4. AURA captures lightweight context.
5. AURA launches one Hermes parent mission through `script/aura-hermes`.
6. Hermes plans, calls tools, delegates, and synthesizes.
7. AURA displays state, progress, approvals, logs, cancel, and final output.
8. Risky actions pause with an approval card.

The MVP should feel like this:

> “I tell AURA what I want. It sees enough of my Mac to understand the context. It works through Hermes. It asks before doing risky things. It gives me a useful final artifact.”

---

## 3. Canonical Architecture

```text
User
  │
  │  ⌃⌥⌘A / panel / future voice
  ▼
AURA SwiftUI/AppKit shell
  ├─ context snapshot: active app, bundle id, pid, cursor, project root
  ├─ policy: Read Only / Ask Per Task / Always Allow
  ├─ parent mission launch/cancel
  ├─ approval card and resume
  ├─ status, logs, sessions, final output
  └─ no custom agent loop
       │
       │ ./script/aura-hermes chat -Q --source aura ...
       ▼
Project-local Hermes runtime
  ├─ planning and tool routing
  ├─ durable sessions and memory
  ├─ web/tools/skills/MCP
  ├─ delegate_task background workers
  └─ final synthesis
       │
       │ MCP tool calls
       ▼
script/aura-cua-mcp
  ├─ daemon-backed MCP proxy
  ├─ dynamic CUA tool discovery
  ├─ read-only tool filtering before approval
  ├─ action tool filtering after approval/policy
  └─ audit logging without screenshots/prompts
       │
       ▼
CuaDriver.app daemon
  ├─ screen/window/read tools
  └─ host-control action tools
```

### AURA owns

- macOS UI and UX.
- Context capture.
- Global automation policy.
- Parent Hermes process lifecycle.
- Approval card lifecycle.
- Mission status and final output display.
- Local audit trail.
- Onboarding/recovery for Hermes and CUA readiness.
- Installed-runtime resolution for standalone builds.

### Hermes owns

- Planning.
- Tool routing.
- Memory.
- MCP tool selection.
- Web/research workflows.
- `delegate_task` workers.
- Final synthesis.

### CUA proxy owns

- Connecting Hermes MCP stdio to the already permissioned CuaDriver.app daemon.
- Filtering CUA tools by AURA policy.
- Blocking action tools until approval/policy permits them.
- Preventing mission workflows from triggering macOS permission prompts.

---

## 4. Safety Contract

AURA’s default mode is **Read Only**.

### Always safe without approval

- Read visible app context.
- Inspect screen/window state through read-only CUA tools.
- Explain what is visible.
- Draft text.
- Research public information through Hermes tools.
- Produce local recommendations in the panel.

### Requires approval in Ask Per Task

- Any local file write.
- Any destructive file operation.
- Any host-control action that changes app state.
- Any browser click that submits, posts, buys, sends, deletes, uploads, downloads paid assets, or changes account state.
- Any terminal command that changes system/project state.

### Requires explicit approval even in Always Allow

Always Allow does **not** mean unrestricted autonomy. These actions must still pause:

- Sending email, text, DM, comments, or posts.
- Contacting a creator, vendor, lead, candidate, or customer.
- Hiring a UGC/influencer creator.
- Purchases, ad spend, subscriptions, paid API calls, or marketplace actions.
- Credential entry, login recovery, account/security settings.
- Public publishing or external file sharing.
- Git pushes, production deploys, package publishing.
- Financial, legal, medical, identity, or tax actions.

Approval copy must say exactly what will happen, what app/site will be touched, and what irreversible/external side effect may occur.

---

## 5. Launch Acceptance Scenarios

These scenarios validate the generic mission architecture. Do not hardcode them into primary UI buttons.

### UC1 — Observe and advise: DaVinci Resolve color grading

**Mode:** Read Only  
**Goal:** User asks: “How do I color grade this?” while DaVinci Resolve is active.

Expected flow:

1. AURA captures active app/cursor context.
2. Hermes uses CUA read/screenshot tools if needed.
3. Hermes explains visible panels and suggests next steps.
4. No clicks, no edits, no file writes.

Pass criteria:

- Correctly identifies the app or admits uncertainty.
- References visible UI elements.
- Produces actionable steps.
- No approval requested.

### UC2 — Observe and act: Figma to webpage

**Mode:** Ask Per Task  
**Goal:** User asks: “Turn this Figma design into a working webpage.”

Expected flow:

1. Hermes inspects visible design through CUA read tools.
2. Hermes plans code generation.
3. Hermes asks approval before writing files.
4. After approval, worker writes files to a clear output directory.
5. Hermes asks approval before opening or controlling a browser if needed.
6. AURA surfaces final path/artifact.

Pass criteria:

- File write approval is shown before write.
- Output path is explicit.
- Generated page opens only after approval or safe policy.
- User can cancel.

### UC3 — Observe and advise: After Effects panel explanation

**Mode:** Read Only  
**Goal:** User asks: “What does this panel do?” while After Effects is active.

Pass criteria:

- Correctly identifies or describes the visible panel.
- Gives explanation without acting.
- Completes as a plain read-only mission.

### UC4 — Research: camera/product alternatives

**Mode:** Read Only  
**Goal:** User asks: “Find cameras like this under $1k.”

Expected flow:

1. Hermes uses screen context to identify the product when visible.
2. Hermes prefers programmatic web/research tools if configured.
3. CUA browser interaction is fallback only.
4. Hermes delegates parallel research if useful.
5. AURA displays final comparison.

Pass criteria:

- Returns at least five candidates or explains why it cannot.
- Includes price/source/date seen if available.
- Does not log in, buy, message sellers, or submit forms.

### UC5 — Guided action: Figma logo design

**Mode:** Ask Per Task  
**Goal:** User asks: “Help me design this logo in Figma.”

Expected flow:

1. Hermes explains recommended next step.
2. User chooses to do it themselves or approves AURA to act.
3. For every state-changing Figma action, AURA gates through approval unless policy permits.
4. Hermes follows snapshot -> act -> re-snapshot -> verify.

Pass criteria:

- CUA actions target the visible Figma canvas/tools accurately.
- No runaway click loop.
- User can cancel between steps.

### UC6 — PDF summary and email draft/send

**Mode:** Ask Per Task  
**Goal:** User asks: “Summarize this PDF and email it to my team.”

Correct MVP behavior:

1. Hermes reads/extracts the PDF with the best available tool path.
2. Hermes drafts the summary email.
3. AURA shows the email body for review.
4. Sending is always approval-gated.
5. If no recipient is known, Hermes asks for recipient or drafts without sending.

Pass criteria:

- Email is never sent without explicit approval.
- Draft text is visible before send.
- Long PDF reading has timeout and failure handling.

### UC7 — Social-to-campaign mission: TikTok inspiration to merch/video

**Mode:** Ask Per Task with external-action hard gates  
**Goal:** User is watching a TikTok and says: “Look at this TikTok, understand it, and replicate the idea to sell t-shirt merch for my AI lab WexproLabs.”

This is a validation scenario for spec-driven, multi-path autonomy. It must not be a hardcoded TikTok feature.

Expected high-level flow:

1. AURA captures current app/context and launches a Hermes mission.
2. Hermes inspects the visible TikTok context through CUA read tools.
3. If allowed and technically possible, Hermes may use browser/terminal tools to save or analyze the video; if not, it proceeds from visible context and asks for user-provided URL/file.
4. Hermes extracts: hook, format, visual theme, audience, offer angle, brand fit, and merch/video options.
5. Hermes proposes a decision card with options such as:
   - AI-generated adaptation.
   - Human UGC/influencer recreation.
   - Hybrid: AI draft plus human creator polish.
6. AURA requires approval before:
   - Downloading copyrighted media if policy requires it.
   - Contacting creators.
   - Sending email/text/DM.
   - Paying for generation tools.
   - Posting or publishing.
7. Final output is one or more artifacts:
   - Creative brief.
   - Shot list/script.
   - T-shirt copy/design prompt.
   - AI-video generation prompt/storyboard.
   - Outreach draft if UGC path is chosen.

Pass criteria:

- User receives a useful artifact even if no video download happens.
- AURA asks before external contact, spend, publishing, or sending.
- Hermes does not assume a single path; it presents the best next decision.

---

## 6. Phase 0 — Unblock And Stabilize Repo-Backed MVP

**Goal:** Any developer can clone the repo, set up local Hermes/CUA, and pass the existing e2e checks.

### Tasks

| ID | Task | Files | Verification |
|---|---|---|---|
| P0.1 | Add `script/setup.sh` for repo-backed setup | `script/setup.sh` | Fresh clone setup reaches actionable success/failure in under 10 minutes |
| P0.2 | Add config template and env example | `config/hermes-default.yaml`, `.env.example` | New dev knows provider/model/key locations |
| P0.3 | Add provider/model smoke test | `script/aura-hermes`, setup docs, or `script/doctor.sh` | One minimal inference call succeeds or returns actionable error |
| P0.4 | Keep project-local Hermes boundary | existing `script/aura-hermes` | No app code calls global `hermes` |
| P0.5 | Verify CUA readiness path | `script/e2e_test.sh`, docs | CUA daemon, permissions, MCP proxy pass |
| P0.6 | Decide macOS floor by test | `Package.swift`, `script/build_and_run.sh` | macOS 13 only if Ventura passes build + e2e; otherwise keep 14 |
| P0.7 | Update README quickstart | `README.md` | One clean setup path exists |

### `script/setup.sh` requirements

The script should:

1. Check macOS version.
2. Check Xcode CLT / Swift availability.
3. Prepare `.aura/` directories.
4. Install or update project-local Hermes using a pinned source/version.
5. Create `.aura/hermes-home/config.yaml` from template if missing.
6. Explain API key setup without echoing secrets.
7. Check CuaDriver.app presence.
8. Start CUA daemon if installed.
9. Print exact manual permission steps if required.
10. End by recommending `./script/e2e_test.sh`.

Do **not** force `curl | bash` without a visible prompt/explanation.

### Exit criteria

```bash
./script/setup.sh
./script/aura-hermes doctor
./script/e2e_test.sh
./script/build_and_run.sh --verify
```

All pass on the dev machine or fail with actionable messages.

---

## 7. Phase 1 — Observe And Advise

**Goal:** AURA can answer questions about the user’s visible Mac context without taking action.

### Tasks

| ID | Task | Files | Verification |
|---|---|---|---|
| P1.1 | Strengthen mission envelope for read-only screen questions | `Sources/AURA/Stores/AURAStore.swift` | Hermes understands active app/context and can call read-only CUA tools |
| P1.2 | Keep CUA setup hard-gate clear | `ContentView.swift`, `CuaDriverService.swift` | User sees exact missing requirement |
| P1.3 | Stream subprocess output to mission panel as emitted | `AURAStore.swift`, mission view | User sees progress/output without waiting for process exit |
| P1.4 | Add final artifact summary block | Mission output view | Final answer is easy to copy |
| P1.5 | Add read-only regression prompts | `script/e2e_test.sh` or new smoke script | DaVinci/AE/PDF-style observe prompts do not request action approval |

### Exit criteria

- User can ask a screen-context question.
- Hermes can inspect using read-only CUA tools.
- AURA displays a useful answer.
- No host-control action tools are exposed in Read Only mode.

---

## 8. Phase 2 — Voice Input

**Goal:** Voice is additive, not required. Text input remains the fallback.

### Recommended MVP order

1. Add a microphone button in the ambient panel.
2. Add speech-to-text using `SFSpeechRecognizer` and `AVAudioEngine`.
3. Add permission copy and privacy keys.
4. Show partial transcript while listening.
5. Submit transcript into the existing mission text field.
6. Add hold-to-talk later after global key-up tracking is reliable.

### Tasks

| ID | Task | Files | Verification |
|---|---|---|---|
| P2.1 | Add `VoiceInputManager` | `Sources/AURA/Services/VoiceInputManager.swift` | Transcript updates with partial results |
| P2.2 | Add microphone UI | ambient panel / mission view | User can start/stop voice without hotkey hold |
| P2.3 | Add privacy keys to generated Info.plist | `script/build_and_run.sh` and future packaging | macOS permission prompts are meaningful |
| P2.4 | Add text fallback | existing mission input | Voice failure never blocks typed missions |
| P2.5 | Add voice-state indicator | cursor/panel UI | Listening/thinking/running states are visually distinct |

### Exit criteria

- User can speak a mission and see text appear.
- Release/stop sends the transcript into the normal Hermes mission path.
- Revoked microphone permission shows a clear recovery message.

---

## 9. Phase 3 — Observe And Act Through CUA

**Goal:** AURA can safely let Hermes use CUA action tools under policy control.

### Rules

- Do not call raw CUA action APIs from Swift mission code.
- Mission-time CUA goes through Hermes -> `script/aura-cua-mcp` -> CuaDriver.app daemon.
- Tool discovery is dynamic.
- Read Only exposes read-only tools only.
- Ask Per Task requires `NEEDS_APPROVAL:` before action tools.
- Always Allow may expose local action tools, but external side effects still require approval.

### Tasks

| ID | Task | Files | Verification |
|---|---|---|---|
| P3.1 | Audit CUA proxy read/action filtering | `script/aura-cua-mcp` | Read Only cannot see action tools |
| P3.2 | Add action-loop prompt contract | Hermes/AURA mission envelope docs | Hermes follows snapshot -> act -> re-snapshot -> verify |
| P3.3 | Add coordinate/retina tests if action tools require coordinates | e2e or test harness | Click target accuracy is measured on Retina and non-Retina |
| P3.4 | Add mission timeouts and cancellation hardening | `AURAStore.swift`, `HermesService.swift` | Stuck mission is cancellable and does not orphan process |
| P3.5 | Add retry/backoff where AURA directly owns subprocess/tool calls | `HermesService.swift`, `CuaDriverService.swift` | Transient failure gives retry then actionable error |
| P3.6 | Add action approval regression tests | e2e | File write/send/delete/submit all pause correctly |

### Exit criteria

- CUA action tools are policy-gated.
- User approval resumes the same Hermes session.
- A 10-step host-control mission can be cancelled.
- No mission can trigger macOS permission prompts inline.

---

## 10. Phase 4 — Delegation And Background Work

**Goal:** Use Hermes `delegate_task`; do not build a custom worker manager in AURA.

### Correct design

AURA launches one parent mission. The parent may call Hermes delegation. AURA observes the parent mission output and Hermes sessions. AURA does not own a separate task database.

### Tasks

| ID | Task | Files | Verification |
|---|---|---|---|
| P4.1 | Confirm Hermes delegation config | Hermes config template | Flat delegation, max 3 children by default |
| P4.2 | Add progress protocol | Hermes prompt/config, AURA parser | Parent emits simple progress lines AURA can display |
| P4.3 | Display worker progress without owning worker state | `AURAStore.swift`, mission UI | Panel shows “worker: reading PDF page 4/10” if emitted |
| P4.4 | Worker timeout handling | Hermes config / prompt contract | Timeout returns error summary to parent |
| P4.5 | Worker failure recovery | e2e/manual | Parent can retry, degrade, or ask user |

### Exit criteria

- Three parallel research workers can complete and synthesize into one answer.
- A failed worker does not crash the parent mission.
- AURA stays responsive while Hermes works.

---

## 11. Phase 5 — Standalone Runtime And Beta Distribution

**Goal:** Move from repo-backed technical MVP to external beta safely.

### Current blocker

Standalone app beta is not ready because runtime resolution depends on the repo layout. `AURAPaths` must support both:

1. Repo-backed development runtime.
2. Installed runtime under Application Support.

### Tasks

| ID | Task | Files | Verification |
|---|---|---|---|
| P5.1 | Add installed runtime path | `AURAPaths.swift` | App outside repo finds runtime under Application Support |
| P5.2 | Add runtime bootstrap command | `script/aura-bootstrap` or app first-run flow | Populates Hermes, Hermes home, wrappers, CUA registration |
| P5.3 | Preserve repo-backed dev path | `AURAPaths.swift`, tests | Existing `./script/build_and_run.sh` still works |
| P5.4 | Add first-run wizard | SwiftUI views/services | Hermes, CUA, API key, permissions, MCP shown step by step |
| P5.5 | Add packaging script | `script/package.sh` | Produces signed local app/DMG artifact |
| P5.6 | Add clean-machine validation | docs/checklist | Install, launch, setup, first mission pass on clean Mac |

### Distribution decision

- **Internal/dev:** repo clone + setup script.
- **Technical beta:** ad-hoc signed build or Homebrew Cask can be acceptable if testers understand macOS security prompts.
- **General external beta:** Developer ID, hardened runtime, notarization, stapling, and clean-machine Gatekeeper validation are required.

Do not present Homebrew as “zero friction for all users.” It is a useful install path, not a security/signing replacement.

---

## 12. Verification Matrix

Run this matrix before calling the MVP beta-ready.

### Core commands

```bash
./script/setup.sh
./script/aura-hermes doctor
./script/aura-hermes status
./script/aura-hermes mcp list
./script/e2e_test.sh
./script/build_and_run.sh --verify
```

CUA checks:

```bash
/Applications/CuaDriver.app/Contents/MacOS/cua-driver status
/Applications/CuaDriver.app/Contents/MacOS/cua-driver call check_permissions '{"prompt":false}'
./script/aura-hermes mcp test cua-driver
```

Signing/package checks:

```bash
codesign -dvvv --entitlements :- dist/AURA.app
spctl -a -vv dist/AURA.app
```

### Functional gates

- [ ] Fresh clone setup reaches a runnable state.
- [ ] `script/aura-hermes` uses project-local Hermes only.
- [ ] CUA Driver setup gate blocks missions until ready.
- [ ] Read Only mode exposes read-only CUA tools only.
- [ ] Ask Per Task pauses before action tools.
- [ ] Approval resumes the same Hermes session with `--resume`.
- [ ] Deny stops the mission.
- [ ] Cancel terminates the active child process.
- [ ] User can complete one observe/advice mission.
- [ ] User can complete one approved host-control mission.
- [ ] User can complete one delegated research mission.

### Safety gates

- [ ] Sending email is blocked until approval.
- [ ] Posting/commenting/messaging is blocked until approval.
- [ ] Purchases/ad spend/subscriptions are blocked until approval.
- [ ] File overwrite/delete is blocked until approval.
- [ ] Browser submit buttons are treated as approval-worthy when side effects are possible.
- [ ] Credentials are never requested or entered without explicit user approval and clear context.
- [ ] Screenshots are not written to logs by default.
- [ ] Prompts and screen contents are not copied into the audit ledger.

### Reliability gates

- [ ] Bad API key produces actionable error.
- [ ] Missing Hermes runtime produces actionable setup command.
- [ ] Missing CUA Driver produces onboarding state.
- [ ] CUA daemon stopped produces start/recovery action.
- [ ] Screen Recording revoked produces recovery instructions.
- [ ] Accessibility revoked produces recovery instructions.
- [ ] Network/model failure does not hang the UI.
- [ ] 50 sequential smoke missions do not crash AURA.
- [ ] RSS is recorded during soak; regression threshold decided from measurement, not guesses.

### UX gates

- [ ] First mission can be started from `⌃⌥⌘A`.
- [ ] Mission status is visible: idle/running/needs approval/done/failed/cancelled.
- [ ] User can copy final output.
- [ ] Approval copy is specific and understandable.
- [ ] Errors tell the user what to do next.
- [ ] Text input works even if voice is unavailable.

---

## 13. Issue Breakdown For Dev Team

Create issues in this order.

### P0 issues

1. `setup: add repo-backed script/setup.sh`
2. `config: add hermes-default.yaml and .env.example`
3. `doctor: add provider/model smoke test`
4. `docs: update README quickstart for fresh clone`
5. `qa: run and document Ventura/macOS 13 compatibility result`
6. `runtime: keep repo-backed path and design Application Support path`

### P1 issues

7. `mission: strengthen read-only screen-context envelope`
8. `ui: improve final output/artifact display`
9. `e2e: add read-only observe/advice smoke mission`
10. `telemetry: verify audit ledger excludes prompts/screenshots`

### P2 issues

11. `voice: add VoiceInputManager using Speech + AVFoundation`
12. `voice: add mic button and partial transcript UI`
13. `packaging: add microphone/speech privacy keys to Info.plist generation`
14. `hotkey: evaluate global key-up support for hold-to-talk`

### P3 issues

15. `cua: add policy-gating regression tests for read/action tools`
16. `mission: add action-loop prompt contract`
17. `qa: add coordinate accuracy harness if needed`
18. `mission: harden timeout/cancel/orphan-process handling`
19. `mission: add retry/backoff for owned subprocess calls`

### P4 issues

20. `delegation: validate flat max-3 worker config`
21. `delegation: define progress-line protocol`
22. `ui: display parent/worker progress without custom task DB`
23. `e2e: add delegated research smoke mission`

### P5 issues

24. `runtime: implement Application Support runtime resolution`
25. `bootstrap: install/update runtime for standalone app`
26. `onboarding: first-run wizard for Hermes/CUA/provider/key`
27. `package: add local DMG packaging script`
28. `qa: clean-machine beta checklist`

---

## 14. What Not To Build Before MVP

| Do not build yet | Reason |
|---|---|
| Custom agent loop in Swift | Hermes owns planning/delegation/tools |
| Custom browser automation stack | Hermes/tools/CUA own browser work |
| Domain-specific TikTok/Figma/DaVinci buttons | Use natural-language missions |
| Custom CUA driver | CUA Driver is already the host-control lane |
| Local LLM support | Cloud/runtime complexity explodes MVP scope |
| Multi-user/team features | Single-user desktop MVP first |
| Long-term AURA task DB | Use Hermes sessions/delegation state |
| Nested delegation depth > 1 | Flat delegation is safer and easier to debug |
| Screen recording/replay UI | Add only if debugging requires it |
| Unverified benchmark claims in launch docs | Execution gates must be measurable locally |

---

## 15. Critical Path

```text
Phase 0: repo-backed setup and e2e
  -> setup.sh, config templates, provider smoke test, CUA readiness, README

Phase 1: observe/advice mission quality
  -> read-only screen-context missions, better output, no unsafe actions

Phase 2: voice input
  -> mic button, SFSpeechRecognizer, privacy keys, text fallback

Phase 3: observe/action through CUA
  -> dynamic tools, approval gates, cancel/timeouts, action regression tests

Phase 4: delegation
  -> Hermes delegate_task validation, progress display, worker failure handling

Phase 5: standalone beta
  -> Application Support runtime, first-run wizard, packaging/signing, clean-machine test
```

MVP beta is ready only when Phase 0 through Phase 3 pass on the maintainer machine and at least one clean tester machine. Delegation can ship as “beta inside beta” if it is stable enough for research/report tasks but not yet safe for external side effects.

---

## 16. Final Dev Instruction

Implement the smallest reliable loop first:

```text
shortcut -> panel -> typed mission -> context snapshot -> project-local Hermes -> read-only CUA inspection -> streamed answer -> approval if needed -> resume -> final output
```

Then add voice, action accuracy, delegation, and standalone packaging in that order.

Do not chase a flashy demo before the trust loop is solid.
