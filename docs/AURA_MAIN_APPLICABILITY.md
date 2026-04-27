# AURA Mainline Applicability Notes

This note maps `AURA_MVP_FINAL_EXECUTION_REPORT.md` to the current `main` branch.

## Current Alignment

- `script/aura-hermes` already enforces the project-local Hermes boundary under `.aura/` and scopes `HOME` plus `HERMES_HOME` into the repo runtime.
- `script/aura-cua-mcp` already keeps CUA behind the daemon-backed MCP proxy and filters read-only versus action tools by AURA policy.
- `AURAStore` already launches one Hermes parent mission with `--yolo`, passes a mission envelope, captures the `session_id`, and supports cancellation.
- `script/e2e_test.sh` already verifies Hermes wrapper isolation, CUA readiness, MCP registration, real YOLO mission flow, audit correlation, and app launch.
- The repo correctly treats voice, standalone runtime install, signing/notarization, and polished beta onboarding as future work rather than current baseline.

## Apply First

1. Add `script/setup.sh` for repo-backed setup.
   - Check macOS version, Swift/Xcode CLT, `.aura/` directories, project-local Hermes, CUA install, daemon state, and permissions.
   - End with the exact next command: `./script/e2e_test.sh`.
   - Do not hide install side effects behind an unexplained `curl | bash`.

2. Add config templates.
   - Add `config/hermes-default.yaml` and `.env.example`.
   - Document where provider, model, and API keys belong.
   - Keep model IDs as setup-time config, not hardcoded launch claims.

3. Add a provider/model smoke test.
   - Extend `script/aura-hermes doctor` or add `script/doctor.sh`.
   - Run one minimal inference call.
   - Fail with actionable setup guidance for missing keys, bad model IDs, or network/provider errors.

4. Update README quickstart.
   - Document the fresh-clone sequence: setup, provider config, CUA readiness, e2e, build/run.
   - Keep the current short run command, but do not present it as enough for a new developer.

5. Add product-loop regression coverage.
   - Extend `script/e2e_test.sh` or add a smoke script with screen-context prompts.
   - Assert normal missions run through Hermes with `--yolo`.
   - Defer permission policy coverage until the product loop is validated.

6. Keep standalone runtime work scoped as the next beta blocker.
   - `AURAPaths` is still repo/dist-oriented.
   - Add Application Support runtime resolution only after repo-backed setup is reliable.

## Defer

- Voice input and hold-to-talk should come after the typed mission loop is stable.
- CUA coordinate accuracy tests matter when host-control action missions are a launch target.
- Delegated worker progress should remain a Hermes output protocol, not a custom AURA task database.
- Packaging, Developer ID signing, hardened runtime, notarization, and clean-machine validation are beta-distribution work, not repo-backed MVP work.

## Mainline Critical Path

```text
setup.sh + config templates + provider smoke test
  -> README fresh-clone quickstart
  -> YOLO mission regression tests
  -> permission policy regression tests
  -> Application Support runtime resolution
  -> standalone bootstrap and packaging
```
