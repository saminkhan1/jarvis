# AURA Current State Report

Status: code-grounded report after inspecting current `main`.
Date: 2026-04-28

## Executive summary

AURA is already much closer to the intended architecture than the legacy planning docs suggest.

The current app is primarily a Mac-native gateway for project-local Hermes:

- AURA captures native user input.
- AURA launches repo-local Hermes through `script/aura-hermes`.
- AURA streams and renders Hermes output.
- AURA shows lightweight diagnostics/readiness.
- Hermes owns reasoning, sessions, memory, skills, tool exposure, and `computer_use`.

The highest-value work is not broad architecture redesign. It is removing stale docs, preserving current thin-boundary behavior with tests, and making deliberate product decisions around context passing and future structured events.

## Verified current behavior

### Launch boundary

`Sources/AURA/Services/HermesService.swift` is the launch boundary. It:

- executes only `script/aura-hermes` from the project root,
- passes arguments from the store,
- streams stdout/stderr,
- injects AURA telemetry environment values,
- supports termination/cancellation,
- does not edit Hermes persistence or own agent lifecycle semantics.

Current user request launch path in `Sources/AURA/Stores/AURAStore.swift`:

```swift
["chat", "-Q", "--yolo", "--source", "aura", "-q", query]
```

Boundary test coverage exists in `Tests/AURATests/HermesBoundaryTests.swift` and confirms raw prompt passthrough without the old AURA mission envelope.

### Runtime ownership

`script/aura-hermes` pins execution to the repo-local Hermes runtime:

- `HOME=$ROOT_DIR/.aura/home`
- `HERMES_HOME=$ROOT_DIR/.aura/hermes-home`
- `VIRTUAL_ENV=$ROOT_DIR/.aura/hermes-agent/venv`
- `PYTHONPATH=$ROOT_DIR/.aura/hermes-agent`

This is packaging/reproducibility glue, not a second agent runtime.

### Sessions

AURA reads Hermes-owned structured session history with:

```bash
./script/aura-hermes sessions export --source aura -
```

`Sources/AURA/Support/AURASessionParsing.swift` parses this structured export into UI summaries. It includes compatibility handling for old envelope-era sessions, but current prompts are raw.

### Tools and CUA

Hermes owns tool exposure through config. Current template enables `computer_use` under `platform_toolsets.cli` and does not define stale CUA MCP servers.

`Sources/AURA/Services/CuaDriverService.swift` only checks local CUA Driver installation, daemon status, permissions, and whether Hermes has `computer_use` enabled. It does not proxy CUA tools or define a Swift tool schema.

Normal chat is not blocked by host-control readiness. `Tests/AURATests/ReadinessGatingTests.swift` covers this.

### Voice

AURA currently owns native voice capture and transcription UX:

1. `VoiceCaptureService` records audio in the Mac app.
2. `AURAStore` calls:
   ```swift
   ["aura-transcribe-audio", audioURL.path]
   ```
3. `script/aura-hermes` loads Hermes voice tooling and calls `transcribe_recording(audio_path)`.
4. AURA sends the resulting transcript through the normal text request path.

This is an intentional product boundary: voice capture is a Mac-native surface concern. Hermes still owns reasoning and execution after receiving the transcript.

AURA should own this path unless/until Hermes exposes a product-friendly interactive voice/event API that can be embedded cleanly inside AURA without launching external terminals or degrading UX.

## Context snapshot investigation

AURA captures macOS context but does not currently send that context to Hermes.

Relevant code:

- `ContextSnapshot` in `Sources/AURA/Models/AURAMission.swift`
- `contextSnapshot` state in `Sources/AURA/Stores/AURAStore.swift`
- `captureContext`, `captureContextIfStale`, and `missionContextSnapshot` in `AURAStore`
- `ContextSnapshotView` in `Sources/AURA/Views/MissionRunnerView.swift`

Current flow:

```swift
contextSnapshot = missionContextSnapshot(traceID: traceID)
try launchHermes(arguments: Self.hermesChatArguments(query: trimmedGoal), ...)
```

The snapshot is captured, stored, displayed, and logged. It is not included in `hermesChatArguments(query:)` and is not passed as a structured side-channel.

### Why this likely happened

The current implementation appears to be the result of removing the old AURA mission envelope while preserving the native context UI and telemetry scaffolding.

That is directionally correct: the previous envelope made AURA look like it owned prompt protocol and context semantics. Removing the envelope restored raw prompt passthrough, but left context capture as a UI-only feature.

### Product implication

Hermes does not automatically receive AURA's captured active-app/cursor context today. It can still inspect the machine through Hermes-owned tools such as `computer_use` when needed, but the specific AURA-captured snapshot is not part of the agent input.

### Options

#### Option A — Keep current behavior

AURA captures context for UI/diagnostics only. Hermes uses its own tools when it needs machine context.

Benefits:
- strongest boundary purity,
- no prompt injection/envelope drift,
- least code.

Costs:
- user may expect AURA to understand “this” or “here” from the active Mac context, but Hermes will not receive AURA's snapshot unless it actively inspects via tools.

#### Option B — Add a minimal context side-channel later

AURA sends context as explicit metadata if Hermes supports a structured input/event protocol.

Example future shape:

```json
{
  "type": "input.context",
  "source": "aura",
  "active_app": "Finder",
  "bundle_id": "com.apple.finder",
  "cursor": {"x": 1200, "y": 700}
}
```

Benefits:
- preserves raw user text,
- avoids prompt-envelope drift,
- lets Hermes decide how/when to use the metadata.

Costs:
- requires Hermes protocol support,
- not worth inventing inside AURA alone.

#### Option C — Reintroduce prompt-enveloped context

Not recommended. This regresses into AURA-owned agent prompt semantics and makes AURA a semantic middleware layer.

## Legacy docs removal

The old docs were planning artifacts and no longer match current code. In particular, they describe or imply:

- mission envelopes,
- approval cards/resume flows,
- future planning phases as current state,
- older CUA/MCP architecture,
- broad MVP plans that are now misleading.

They should be deleted rather than maintained as current documentation.

Current source of truth should be:

- `AGENTS.md` for project constraints and commands,
- this report for the current architecture read,
- tests and scripts for executable verification.

## Future structured Hermes event protocol

This is future work, not needed for the immediate cleanup.

Current AURA integration consumes raw stdout/stderr. This is simple and works, but it forces AURA to infer UI state from text and special markers such as `session_id:`.

A Hermes-owned structured event stream would improve AURA without making AURA smarter.

Potential event examples:

```json
{"type":"run.started","session_id":"..."}
{"type":"message.delta","text":"..."}
{"type":"tool.started","name":"terminal"}
{"type":"tool.finished","name":"terminal","status":"success"}
{"type":"approval.requested","id":"...","summary":"..."}
{"type":"run.completed","status":"success"}
```

### Net benefit vs current raw stdout

1. Less fragile parsing
   - AURA would not need to scrape `session_id:` or choose between stdout and combined output.

2. Better UI state
   - running, tool progress, completion, failure, cancellation, and attention-needed states become explicit.

3. Cleaner approval UX later
   - AURA can render Hermes approval requests without owning policy.

4. Better artifacts/attachments later
   - Hermes can emit artifact metadata; AURA can render/open/share it.

5. Better cancellation/retry semantics
   - AURA can map UI actions to Hermes run/session IDs rather than process-only state.

6. Preserves the thin boundary
   - Hermes still owns meaning; AURA only renders events.

### Current tradeoff

Raw stdout is good for MVP because it is simple and already works. Structured events become worthwhile when AURA needs richer UI fidelity: tool progress, approvals, artifacts, resumable sessions, or robust background runs.

## Recommendations

1. Delete stale planning docs.
2. Keep AURA-owned native voice capture/STT UX as an intentional Mac-native surface.
3. Do not reintroduce prompt envelopes for context.
4. Keep context snapshot as UI/diagnostics until Hermes has a structured metadata/event path.
5. Preserve current tests that lock raw prompt passthrough and normal chat availability.
6. Add future guardrails only when they protect current behavior; avoid broad refactors.
7. Treat structured Hermes events as future protocol work with clear UX payoff, not as near-term architecture churn.

## Verification run before this report

Commands run during inspection:

```bash
swift test --parallel
./script/verify_runtime_paths.sh
./script/e2e_test.sh --skip-app
./script/aura-hermes tools list --platform cli
/Applications/CuaDriver.app/Contents/MacOS/cua-driver status
```

Observed results:

- Swift tests passed.
- Runtime path verification passed.
- E2E skip-app verification passed.
- Hermes `computer_use` was enabled for CLI.
- CUA Driver daemon was running.
