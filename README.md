# AURA

AURA is a native macOS ambient assistant shell, not a chatbot. It is the menu bar cockpit that opens a cursor-adjacent panel, captures lightweight host context, and routes work to a project-local Hermes runtime plus Cua Driver for host control.

- Global hot key: `⌃⌥⌘A`
- Native shell: SwiftUI + AppKit on macOS 14+
- Local runtime: Hermes lives under `.aura/` and is invoked only through `script/aura-hermes`
- Control lane: Cua Driver is required for host interaction and stays approval-gated

## Quick Start

```bash
./script/build_and_run.sh
```

## Verify

```bash
./script/build_and_run.sh --verify
./script/e2e_test.sh
```

## Useful Commands

```bash
./script/aura-hermes doctor
./script/aura-hermes status
./script/aura-logs stream
./script/aura-logs audit
```

## What AURA Does

- shows Hermes health, Cua readiness, approvals, and mission output
- launches one Hermes parent mission per task
- keeps approvals explicit
- stores a bounded local audit trail

## What AURA Does Not Do

- use the global Hermes install
- own browser automation, a task database, or long-term memory
- hide host-control risk behind background automation

## Repo Map

- `Sources/AURA` app shell
- `script/` runtime wrappers and diagnostics
- `docs/` beta and integration notes

For deeper integration details, see `docs/INTEGRATION_NOTES.md` and `docs/BETA_READINESS.md`.
