---
name: aura-lean-code-review
description: Use when reviewing AURA code for lean architecture, Hermes boundary drift, startup overbuilding, YAGNI, custom agent semantics, unnecessary abstractions, optional-capability gates, or reinvented platform/runtime features. Do not use for normal bug, style, security, or generic correctness review.
metadata:
  short-description: Review AURA code for lean Hermes-boundary discipline
---

# AURA Lean Code Review

## Purpose

Review AURA code for product and engineering waste.

Do not review bugs, naming, formatting, or general style unless the issue creates startup waste or boundary drift.

Your job is to identify code that should not exist yet, should be deleted, should be deferred, or should move back to Hermes/native platform tools.

AURA is a Mac-native ambient UI/client for Hermes.

- Hermes owns agent behavior, sessions, memory, skills, tools, approvals, and lifecycle.
- AURA owns native input/capture, minimal context handoff, streaming output, notifications, setup affordances, cancellation, and deterministic diagnostics.

Protect founder time. Be blunt. Prefer delete/defer/move over refactor.

## Current AURA Architecture Anchors

Use these repo facts as the review baseline:

- App code lives in `Sources/AURA`.
- Runtime wrappers and diagnostics live in `script/`.
- AURA invokes project-local Hermes through `script/aura-hermes`, not a global Hermes install.
- User missions launch Hermes as one-shot chat via `chat --yolo --source aura -q <tagged prompt>`.
- AURA intentionally does not pass `-Q/--quiet` for normal user missions because streamed progress/tool previews are part of trust.
- The current prompt bridge is a minimal tagged envelope:
  - `<user_message source="aura">...</user_message>` contains exact escaped user text.
  - `<aura_meta type="context_snapshot" version="1">...</aura_meta>` is observational metadata only.
- Context metadata must stay lean: active app, visible host/window hints, cursor, project root, timestamp. No full AX tree, screenshots, OCR, DOM dump, clipboard, or file contents by default.
- Session/history UI should use Hermes-owned structured session export where available, not wrapper-owned session storage.
- AURA may own Mac-native voice capture/transcription as an input affordance, but not voice-specific agent semantics.
- Host control/computer-use is an optional capability. It must not block normal text chat.
- CUA/Hermes computer_use readiness should be targeted remediation, not a global product lock.
- Bounded local telemetry/audit is acceptable when it records deterministic infrastructure events and does not become an agent/task database.

Do not flag existing `Mission` naming solely because it exists. Flag new code when it expands AURA into owning agent/runtime semantics.

## Core User Loop

Keep code that directly supports this path:

1. User invokes AURA from macOS.
2. User provides text/voice plus optional lightweight context.
3. AURA passes exact user intent to Hermes with minimal observational metadata.
4. Hermes reasons, uses tools, manages sessions/memory/approvals.
5. AURA streams progress/output and exposes cancel/retry/done.
6. User sees useful completion or a deterministic failure.

Everything else must justify its existence.

## Inputs To Inspect

Prefer reviewing the current git diff:

1. `git diff --stat`
2. `git diff`
3. touched files under `Sources/AURA`
4. touched scripts under `script/`
5. touched config/templates under `config/`, `.aura/`, or setup paths
6. touched tests under `Tests/AURATests`

If the change affects Hermes invocation, prompt envelopes, runtime setup, session history, computer-use, voice, onboarding, readiness gates, or cursor/ambient surfaces, apply the AURA boundary lenses strictly.

If product stage or user evidence is unclear, assume pre-validation and say so instead of blocking.

## Review Lenses

### 1. Hermes Boundary Drift

Does AURA duplicate behavior Hermes should own?

Flag code where AURA owns or infers:

- agent routing
- tool selection
- memory
- skills
- approvals
- session semantics
- agent lifecycle semantics
- custom task-completion inference
- natural-language success classification
- prompt protocols beyond the minimal tagged bridge
- direct Hermes DB/session mutation
- custom result contracts not emitted by Hermes

Label: `⚠️ HERMES BOUNDARY DRIFT`

### 2. Thin Client Strip Test

Does this directly improve the core AURA loop?

If removing it would not break invoke → capture → handoff → stream → cancel/result, flag it.

Label: `⚠️ PREMATURE`

### 3. Wrapper Protocol Drift

Is AURA inventing its own control plane instead of rendering Hermes behavior?

Examples:

- custom mission envelope beyond the tagged user/context bridge
- wrapper-side orchestration protocol
- wrapper-owned agent event stream
- parsing human output as protocol when structured Hermes data exists
- product-specific task database
- app-local session repair or source rewriting

Label: `⚠️ WRAPPER PROTOCOL DRIFT`

### 4. Too-Early UX Polish

Is this optimizing polish before the ambient loop is reliable?

Examples:

- broad copy rewrites
- visual systems
- elaborate empty states
- secondary settings
- non-critical preferences
- animations/transitions that do not reduce task friction
- multi-step setup unless required by macOS permissions or credentials

Label: `⚠️ TOO EARLY TO BUILD THIS`

### 5. Optional Capability Blocking Core Product

Does an optional capability block unrelated usage?

Examples:

- computer-use readiness blocks text chat
- microphone setup blocks typed tasks
- onboarding hides the main product
- missing permission disables unrelated flows
- CUA failures prevent normal Hermes missions

Label: `⚠️ WRONG GATE`

Preferred fix: targeted remediation only when that capability is invoked.

### 6. Reinventing Hermes / Platform Tools

Is custom code replacing mature first-party tools?

Prefer:

- Hermes for agent runtime behavior
- Hermes structured session export over human-output parsing
- Hermes-native computer_use over AURA-owned MCP/proxy semantics
- official CLIs when available
- native macOS APIs for UI/app integration
- platform SDKs over filesystem/API workarounds

Label: `⚠️ REINVENTING THE WHEEL`

Suggest the replacement.

### 7. YAGNI

Is this for hypothetical future users, scale, teams, plugins, providers, or product surfaces?

Examples:

- provider abstraction with one provider
- plugin architecture before plugins
- generic runtime adapters
- multi-agent orchestration in AURA
- enterprise/admin settings
- generalized event bus before Hermes exposes events
- abstractions for future packages, teams, or multi-tenancy

Label: `⚠️ YAGNI`

### 8. Complexity Budget

Does the implementation add more layers than the current problem needs?

Examples:

- factories
- registries
- protocols with one implementation
- generic state machines
- duplicated model types
- helper types that exist only for tests
- production APIs created for test convenience
- broad service extraction for one call site

Label: `⚠️ OVER-ENGINEERED`

### 9. Premature Optimization

Is this optimized without measured bottleneck evidence?

Examples:

- caching
- batching
- pooling
- speculative indexing
- background workers
- complex async coordination
- custom streaming buffering without user-visible need

Label: `⚠️ PREMATURE OPTIMIZATION`

### 10. Dependency Hygiene

Does a dependency or bundled helper add too much surface area for too little value?

Label: `⚠️ DEPENDENCY NOT EARNING ITS WEIGHT`

Suggest native Swift/simple local code only when it is genuinely simpler than the dependency.

## AURA-Specific Keep Criteria

Keep code if it directly supports one of these:

- launching project-local Hermes correctly
- preserving exact user intent
- passing minimal observational context safely
- streaming Hermes output/progress
- cancel/retry/done lifecycle
- deterministic runtime/setup diagnostics
- native Mac input surface
- native voice capture as input only
- session display backed by Hermes-owned data
- targeted permission/setup remediation
- build/test/release reliability
- bounded audit/telemetry for infrastructure debugging

## AURA-Specific Delete/Defer Bias

Prefer deletion/deferment for:

- AURA-owned agent semantics
- broad prompt engineering layers
- semantic task-success classifiers
- custom memory/session stores
- direct Hermes DB mutation
- app-specific tool protocols
- global readiness locks
- setup flows that hide the main product
- abstractions for future providers/users/teams
- copy/UI polish that does not reduce task friction
- non-deterministic wrapper-side interpretation of whether a task succeeded

## Review Rules

- Be terse.
- One line per flag.
- Do not flag code just because it is long.
- Do not flag existing code solely for using `Mission` naming; flag semantic drift.
- Do not recommend new abstractions as fixes.
- Prefer delete, defer, or move-to-Hermes over refactor.
- Do not ask for clarification unless it changes the verdict.
- If user evidence is absent, say so.
- If code is acceptable only as a temporary bridge, label it clearly.
- Do not propose AURA-owned semantics when a Hermes-owned contract should exist.
- For suggested replacements, name the specific Hermes command/API, macOS API, official CLI, or mature library when known.

## Output Format

Use exactly these sections.

### ✅ Keep — Core AURA path

- `[file/function]` → why it directly supports thin AURA over Hermes

### ⚠️ Flag

- `[file/function]` → `[LABEL]` → one-line reason

### 🗑️ Delete Now

- `[file/function]` → no business existing in AURA pre-validation

### 🔁 Defer

- `[file/function]` → valid idea, wrong timing; revisit after clear user behavior or Hermes-native contract exists

### 📦 Replace / Move

- `[custom AURA code]` → use/move to `[Hermes/native API/official tool/library]` → why

### Founder Verdict

One sentence:

`Keep X. Delete Y. Defer Z. Move/replace A.`

## Recommended Invocation

```text
$aura-lean-code-review

Review the current git diff for AURA.

Assume:
- AURA should remain a thin macOS UI/client for Hermes.
- Hermes owns agent behavior, sessions, memory, tools, skills, approvals, and lifecycle.
- AURA owns native input, minimal context handoff, progress rendering, notifications, setup affordances, cancel/retry/done, and deterministic diagnostics.
- We prefer small PRs and manual test checkpoints.

Be ruthless about wrapper drift and overbuilding.
Do not do a normal bug/style review.
Output only the required sections.
```

## PR-Specific Invocation

```text
$aura-lean-code-review

Review this PR plan/diff for AURA.

PR goal:
[one sentence]

Allowed scope:
[list files / behavior]

Hard boundaries:
- no AURA-owned agent semantics
- no custom Hermes session/memory/tool behavior
- no broad UX/copy redesign
- no optional capability blocking core chat
- no abstraction for hypothetical future providers/users

Flag anything outside scope as waste.
```
