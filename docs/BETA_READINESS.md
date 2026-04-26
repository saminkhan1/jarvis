# AURA Beta Readiness

This is the current checklist before AURA can go to beta users.

## Current State

- Local SwiftPM app builds and launches.
- Real e2e verification passes with project-local Hermes.
- CUA Driver is installed on this machine, running through a user LaunchAgent, and registered with project-local Hermes MCP.
- First launch now runs passive CUA readiness checks and locks AURA into onboarding until Cua Driver is installed, daemonized, permissioned, and registered. Permission prompts are only user-clicked from onboarding, use Cua Driver's explicit prompt mode, and never run from the mission workflow.
- Normal Hermes missions use explicit toolsets including `cua-driver`, registered as `script/aura-cua-mcp`. The proxy forwards to the CuaDriver.app daemon and blocks prompt mode during workflow.
- Hermes sessions are shown from Hermes structured JSONL export.
- Current `dist/AURA.app` is a local debug artifact, not a beta distributable.

## Beta Blockers

1. Choose the beta distribution model.

   Repo-backed beta is viable for technical testers: they clone this repo, run setup, and launch through `./script/build_and_run.sh`.

   Standalone app beta is not ready: if `AURA.app` is moved outside this repo, `AURAPaths.projectRoot` will not reliably find `script/aura-hermes`, `.aura/hermes-agent`, or `.aura/hermes-home`.

2. Add a first-run runtime bootstrap for standalone beta.

   A standalone build needs a stable runtime location, likely under Application Support, for:

   - Hermes checkout/install
   - Hermes home/config/auth
   - AURA wrapper equivalent
   - CUA Driver install detection
   - CUA daemon LaunchAgent setup
   - MCP registration into the correct Hermes home

3. Add beta packaging/signing.

   Current inspected artifact:

   - App: `dist/AURA.app`
   - Signing: ad hoc bundle signature from `script/build_and_run.sh`
   - TeamIdentifier: not set
   - Gatekeeper: rejected
   - Entitlements: none

   Needed for external beta:

   - Developer ID Application certificate
   - hardened runtime signing
   - non-development entitlements
   - signed archive or DMG
   - notarization
   - stapling
   - Gatekeeper validation on a clean machine

4. Finish beta onboarding and recovery UI.

   CUA hard-gate onboarding is in place. The app still needs cleaner standalone recovery for:

   - Hermes runtime missing
   - Hermes auth/setup needed
   - CUA Driver missing
   - CUA daemon stopped
   - Accessibility or Screen Recording missing
   - MCP server missing or disabled

5. Confirm safety defaults for beta.

   Before beta, default policy should remain `Read Only`, and host-control actions should remain gated unless the user explicitly changes policy and CUA is ready.

## Current Validation Commands

```bash
./script/e2e_test.sh
./script/build_and_run.sh --verify
./script/aura-hermes status
./script/aura-hermes mcp list
/Applications/CuaDriver.app/Contents/MacOS/cua-driver status
/Applications/CuaDriver.app/Contents/MacOS/cua-driver call check_permissions '{"prompt":false}'
```

## Signing Inspection Commands

```bash
codesign -dvvv --entitlements :- dist/AURA.app
spctl -a -vv dist/AURA.app
security find-identity -p codesigning -v
xcrun notarytool --help
```

## Minimum Next Implementation Slice

Make the app runtime-location aware:

1. Keep repo-backed development working exactly as-is.
2. Add a user Application Support runtime path for standalone builds.
3. Teach `AURAPaths` to resolve either repo runtime or installed runtime.
4. Add a bootstrap command/script that can populate the installed runtime.
5. Add e2e coverage for both repo-backed and installed-runtime path resolution.
