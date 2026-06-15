# PLAN-004 Phase 3 Follow-Up: Remove `/resume` Path Arguments

Status: Implemented.

## Goal

Make `/resume` a picker-only command in `pi-webui`.

After this change, typed `/resume <path>` is not supported. Users resume a known session by invoking `/resume` with no argument and choosing from the session picker. Users bring an external JSONL file into the current session store with `/import <path>`.

This plan supersedes the `/resume <path>` items in `PLAN-004-phase-3-target-based-transitions.md`.

## Conversation Context

During review of the Phase 3 runtime target changes, we noticed that the new `resolveSessionTransition(...)` path rejects `/resume` arguments unless they are already valid absolute session pointers with an existing session header. That looked like a possible regression from the old pi-webui code, which passed the raw path to Pi's `runtime.switchSession(...)`.

Follow-up investigation showed that the Pi TUI does not expose `/resume <path>` as an interactive command. In Pi TUI:

- `/resume` only opens the session selector.
- The selector lists known sessions from the current project and all projects.
- The selected known session path is passed to `runtimeHost.switchSession(...)`.
- `/import <path>` is the command that accepts an arbitrary path argument.
- `/import` confirms the action, requires the input file to exist, copies it into the current session directory when needed, and then switches to the imported destination.

This means supporting typed `/resume <path>` in pi-webui is not parity with the Pi TUI. It also blurs the semantic boundary between resume and import.

## Decision

Remove support for `/resume <path>` in pi-webui.

Keep these meanings distinct:

- `/resume`: choose and continue a known session through the session picker.
- session picker selection: switch to that known session through the selected-target transition path.
- `switch_session` protocol command: switch to a session chosen by the UI, after session target prevalidation.
- `/import <path>`: import an external JSONL file into the current session store, then switch to it according to the import policy.

Do not let `/resume` create missing session files, repair corrupt/headerless files, or act as an import shortcut.

## Rationale

PLAN-004 makes pi-webui own the selected runtime target, with runtime cwd required to match the selected target cwd. Session transitions need the target session header cwd before committing the selected target or persisting `lastCwd`.

Allowing `/resume <path>` to pass arbitrary path strings into Pi's session opening behavior would reintroduce ambiguity:

- A missing path can become a new session file through `SessionManager.open(...)`.
- A corrupt or headerless file can be rewritten into a fresh session.
- Relative, `~`, and `file://` path handling becomes command-specific path convenience rather than selected-target intent.
- The command overlaps with `/import`, which is already the path-taking external-session workflow.

The selected-target model is clearer if typed resume is picker-only and import is the explicit external file operation.

## Scope

Update `pi-webui` only.

Files likely to change:

- `pi-webui/src/server/index.ts`
- `pi-webui/src/server/target-transitions.ts`
- `pi-webui/test/server-target-transitions.test.mjs`
- client slash command behavior/tests if any command catalog or result handling assumes `/resume <path>`
- `docs/project/plans/PLAN-004-phase-3-target-based-transitions.md`, if desired, to point at this follow-up plan

## Implementation Steps

1. Change the `/resume` slash handler so it ignores or rejects any argument.
   - Recommended behavior: return the session picker payload for `/resume` and fail loudly for `/resume <arg>` with a clear message such as `Usage: /resume`.
   - Do not resolve a target from typed `/resume <arg>`.

2. Keep picker-driven session switching.
   - Runtime session picker selection should continue to send `switch_session`.
   - No-runtime session picker selection should continue to send `select_session`.
   - Both protocol paths should keep session target prevalidation and selected-target commitment semantics.

3. Keep `/import <path>` as the only path-taking session-file command.
   - Do not make import a persisting explicit target transition unless the product decision changes.
   - Preserve the import policy from the runtime-target-host handoff: successful import keeps selected target coherent without writing `lastCwd`.

4. Update Phase 3 documentation or tests that still describe `/resume <path>`.
   - Remove `/resume <path>` from the "Commands To Migrate" list.
   - Replace validation scenarios that mention typed `/resume <session>` with picker or protocol-level session switching scenarios.

5. Add focused tests.
   - `/resume` with no argument returns the session picker payload.
   - `/resume <path>` does not call `resolveSessionTransition` or mutate runtime target state.
   - Session picker / `switch_session` still prevalidates a missing, corrupt, or headerless session before runtime mutation.
   - `/import <path>` remains the accepted path-taking session-file workflow.

## Verification

Run:

```bash
npm test --prefix pi-webui
```

Manual smoke checks:

- From an active runtime, type `/resume`; confirm the session picker opens.
- Pick a session; confirm the runtime switches, URL moves to session mode, and `lastCwd` persists the selected session header cwd.
- Type `/resume /tmp/session.jsonl`; confirm the command does not switch or import.
- Type `/import /tmp/session.jsonl`; confirm import remains the path-taking workflow.

## Done Criteria

- `/resume <path>` is no longer a supported pi-webui command path.
- `/resume` remains available as a picker command.
- Session picker and protocol session switching still use selected-target prevalidation.
- `/import <path>` remains the only external JSONL path workflow.
- PLAN-004's selected-target invariants remain intact.
