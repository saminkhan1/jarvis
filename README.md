# AURA

AURA is a native macOS ambient assistant shell, not a chatbot. It is the menu bar cockpit that expands a cursor-adjacent composer in place, captures lightweight host context, and routes work to a project-local Hermes runtime plus Cua Driver for host control.

- Global hot key: `⌃⌥⌘A`
- Native shell: SwiftUI + AppKit on macOS 14+
- Local runtime: Hermes lives under `.aura/` and is invoked only through `script/aura-hermes`
- Control lane: Cua Driver is required for host interaction; MVP missions run Hermes with `--yolo`

## MVP Launch Status

AURA is currently a repo-backed technical MVP. Testers should clone this repo,
run the setup script, and launch through the project scripts.

`dist/AURA.app` is a local ad-hoc signed development artifact. It is not a
Developer ID signed, notarized, stapled, standalone beta build yet.

## Fresh Clone Quick Start

1. Set up the repo-local runtime:

   ```bash
   ./script/setup.sh
   ```

2. Configure the model provider and credentials if `doctor` reports setup work:

   ```bash
   ./script/aura-hermes setup
   ```

   Secrets belong in `.aura/hermes-home/.env`. Provider/model config belongs in
   `.aura/hermes-home/config.yaml`. The setup script seeds both files from
   checked-in templates only when they are missing.

3. Confirm Cua Driver is installed, daemonized, permissioned, and visible to
   Hermes:

   ```bash
   /Applications/CuaDriver.app/Contents/MacOS/cua-driver status
   /Applications/CuaDriver.app/Contents/MacOS/cua-driver call check_permissions '{"prompt":false}'
   ./script/aura-hermes mcp list
   ```

4. Run the launch gates:

   ```bash
   ./script/aura-hermes doctor
   ./script/connection_matrix.sh
   ./script/e2e_test.sh
   ./script/build_and_run.sh --verify
   ```

5. Launch AURA:

   ```bash
   ./script/build_and_run.sh
   ```

## Verify

```bash
./script/setup.sh --check
./script/aura-hermes doctor
./script/connection_matrix.sh
./script/e2e_test.sh
./script/build_and_run.sh --verify
```

## Useful Commands

```bash
./script/setup.sh --check
./script/aura-hermes doctor
./script/aura-hermes status
./script/aura-hermes mcp list
./script/connection_matrix.sh
./script/aura-logs stream
./script/aura-logs audit
./script/aura-monitor --open
```

## Local App Bundle Runtime

`./script/build_and_run.sh` builds `dist/AURA.app`, checks that the repo-local
Hermes runtime exists, and launches the app with `AURA_PROJECT_ROOT` pointing at
this checkout. Moving `dist/AURA.app` outside the repo is not supported in this
pass; Developer ID signing and notarization remain release work.

## What AURA Does

- shows Hermes health, Cua readiness, and mission output
- launches one Hermes parent mission per task
- runs Hermes missions approval-free with `--yolo` for MVP validation
- stores a bounded local audit trail

## What AURA Does Not Do

- use the global Hermes install
- own browser automation, a task database, or long-term memory
- implement a production permission policy yet

## Repo Map

- `Sources/AURA` app shell
- `script/` runtime wrappers and diagnostics
- `docs/` beta and integration notes

For the launch source of truth and deeper integration details, see
`docs/AURA_MVP_FINAL_EXECUTION_REPORT.md`, `docs/INTEGRATION_NOTES.md`,
`docs/BETA_READINESS.md`, and `docs/AURA_MAIN_APPLICABILITY.md`.
