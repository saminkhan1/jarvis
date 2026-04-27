# AURA Integration Notes

## Current Backend Contract

AURA uses the project-local Hermes install through `script/aura-hermes`.

- Do not call the global `hermes` binary from app code.
- Keep `HOME` and `HERMES_HOME` scoped to `.aura/`.
- Use Hermes for durable background work, skills, memory, provider routing, MCP, and tool orchestration.
- Do not build a custom agent loop unless Hermes fails a concrete production requirement.

## Hermes Usage

Hermes is the first long-running agent backend.

- Quick diagnostics use `version`, `status`, and `doctor`.
- User-triggered agent work should use `./script/aura-hermes chat -Q --yolo --source aura -q "<prompt>"` for non-interactive MVP missions.
- Background agents should use Hermes `delegate_task`; AURA does not spawn or manage subagents.
- AURA launches one parent mission and passes enough context for Hermes to delegate safely.
- Project instructions belong in `AGENTS.md` or `HERMES.md`; global assistant tone belongs in `.aura/hermes-home/SOUL.md`.
- MVP missions use `--yolo`; do not build a custom AURA approval loop until the product loop is validated.

## Mission Runner

AURA owns:

- Cheap Mac context capture.
- Parent Hermes process start/cancel.
- In-memory Hermes `session_id` capture for mission/session display.
- Status and final output display.
- Read-only display of `hermes sessions list`.
- Global shortcut-first ambient entry with `⌃⌥⌘A`.
- Cursor-adjacent mission composer for goal entry, start, and cancel.
- Cursor-adjacent state indicator instead of replacing the system cursor.

Hermes owns:

- Planning and tool routing.
- `delegate_task` background workers.
- Session history and memory.
- MCP tool selection.
- Final synthesis.

Avoid primary UI buttons for individual demos. Users should ask for a mission; Hermes should infer the workflow and delegate as needed.

Approval loop:

- Deferred. Hermes runs with `--yolo` for MVP validation.
- AURA does not create a custom task database for approvals.
- AURA does not create a custom background-agent/task database. Use Hermes sessions and Hermes delegation state as the source of truth.

Default delegation posture:

- Flat delegation only at first.
- Up to 3 concurrent children.
- Parent passes complete context because subagents start fresh.
- Child toolsets are scoped to the subtask: `web`, `terminal,file`, or `terminal,file,web`.

## CUA Usage

CUA is not the agent brain. It is the host computer-use lane registered with Hermes through AURA's daemon-backed MCP proxy.

- Ordinary AURA missions launch with the `cua-driver` Hermes toolset enabled, but the command is `script/aura-cua-mcp`, not raw `cua-driver mcp`.
- `script/aura-cua-mcp` forwards tool calls to the CuaDriver.app daemon socket so macOS TCC stays attached to the already-approved `com.trycua.driver` bundle.
- MVP sessions expose the configured CUA MCP tool surface through Hermes.
- Treat CUA setup as a hard product gate: AURA's mission workflow stays locked until Cua Driver is installed, running, permissioned, and registered.
- Register CUA Driver with Hermes through MCP rather than writing custom Swift desktop automation first.
- CUA Driver requires macOS Accessibility and Screen Recording permissions.
- The safe action loop is always: snapshot, act, re-snapshot, verify.
- Prefer element-indexed AX actions when available; use pixel actions only for non-AX surfaces.
- AURA checks readiness and can register MCP, but does not install CUA automatically.
- macOS permission prompts are onboarding-only. Mission start, CUA proxy calls, and normal workflow checks must use passive status checks only.

## CUA Sandbox And CuaBot

Use sandboxed CUA surfaces when the task should not touch the host Mac.

- Use CUA Sandbox for isolated Linux/macOS/Windows/Android computer-use tasks.
- Use CuaBot when an agent should operate inside a streamed container/desktop rather than the user's real workspace.
- Host control through CUA `localhost` is unsandboxed and must be treated as high-risk.

## AURA Safety Boundary

AURA owns the user-visible trust layer.

- Product permission policy is deferred while MVP missions run with `--yolo`.
- The eventual beta policy must restore explicit approval boundaries before broad user distribution.
- Every background task should expose status, logs, cancel, and final artifacts.
