# Remove pi-webui Session Directory Overrides

Status: Implemented 2026-06-11

## Summary

Remove pi-webui support for `PI_SESSION_DIR`, `PI_AGENT_DIR`, and any equivalent `sessionDir` override so sessions and server-owned Pi state are loaded only from Pi's canonical agent dir.

## Context

ADR-0003 establishes that pi-webui is a multi-workspace, multi-session server with one canonical session store. It currently names that store as `PI_AGENT_DIR`:

- `docs/project/adrs/0003-pi-webui-canonical-session-store.md`

`PLAN-007` relies on that decision for the workspace sidebar catalog:

- `docs/project/plans/archived/PLAN-007-pi-webui-workspace-sidebar.md`

Implementation research found that `PI_AGENT_DIR` is a pi-webui-specific alias, not Pi's canonical environment variable. Pi's SDK derives its canonical agent-dir variable as `PI_CODING_AGENT_DIR` and its default session APIs read sessions from `getAgentDir()/sessions`.

Current pi-webui code still reads `process.env.PI_AGENT_DIR`, `process.env.PI_SESSION_DIR`, and passes `sessionDir` through runtime creation, session listing, session switching, and recovery paths. That preserves Pi CLI-style behavior that is ambiguous for a server-wide workspace/session catalog and leaves two agent-dir environment variables with overlapping meanings.

## Desired Outcome

pi-webui loads, creates, switches, recovers, imports, forks, and lists sessions from the Pi agent dir only. Pi's canonical `PI_CODING_AGENT_DIR` remains the only supported agent storage root override. `PI_AGENT_DIR`, `PI_SESSION_DIR`, and `sessionDir` are not supported by pi-webui.

## Scope

- Remove `PI_SESSION_DIR` from pi-webui documented environment variables and help output.
- Remove `PI_AGENT_DIR` from pi-webui documented environment variables and help output.
- Remove `process.env.PI_AGENT_DIR` handling from the server.
- Remove `process.env.PI_SESSION_DIR` handling from the server.
- Remove `sessionDir` threading from pi-webui runtime target creation, target transitions, recovery, and session listing helpers.
- Update tests that currently set or assert custom `sessionDir` or `PI_AGENT_DIR` behavior to use temporary `PI_CODING_AGENT_DIR` or injected listers instead.
- Ensure sidebar-related services do not accept `sessionDir`.
- Keep Pi's vendored CLI and SDK behavior unchanged.

## Non-Goals

- Do not modify vendored Pi session manager APIs.
- Do not add a replacement custom session storage env var in this ticket.
- Do not migrate existing user session files automatically.

## Research Notes

- Pi's canonical agent-dir env var is `PI_CODING_AGENT_DIR`.
- `PI_AGENT_DIR` was added by pi-webui as a server-facing alias.
- Pi's `SessionManager.create(cwd)` and `SessionManager.list(cwd)` use the default session dir when no `sessionDir` is passed.
- Pi's default session dir is rooted at `getAgentDir()/sessions`, where `getAgentDir()` reads `PI_CODING_AGENT_DIR`.
- Pi's `SessionManager.listAll()` reads from `getAgentDir()/sessions` and does not accept `sessionDir`.
- Keeping `PI_SESSION_DIR` lets current-project session reads use one storage root while all-project/sidebar reads use another.
- Keeping both `PI_AGENT_DIR` and `PI_CODING_AGENT_DIR` leaves pi-webui state such as `workspaces.json` and Pi session state able to diverge if both env vars are set differently.

## Implementation Plan

1. Make `PI_CODING_AGENT_DIR` the only pi-webui agent-dir override.
   - Replace `const agentDir = process.env.PI_AGENT_DIR || getAgentDir()` with `const agentDir = getAgentDir()`.
   - Remove all `PI_AGENT_DIR` mentions from pi-webui help output and README documentation.
   - Keep passing `agentDir` into Pi SDK service creation and pi-webui workspace-store helpers.

2. Remove custom session-dir support from server runtime paths.
   - Delete `const sessionDir = process.env.PI_SESSION_DIR`.
   - Call `runtimeSessionManagerForTarget({ target })` without a session-dir override.
   - Call `resolveRuntimeTarget`, `resolveSessionTransition`, and recovery helpers without `sessionDir`.
   - Remove `sessionDir` from server log metadata.

3. Remove `sessionDir` from helper APIs.
   - Change `listSerializedSessions({ cwd, sessionDir })` to `listSerializedSessions({ cwd })`.
   - Change `SessionManager.list(args.cwd, args.sessionDir)` to `SessionManager.list(args.cwd)`.
   - Change `SessionManager.open(path, sessionDir)` and `SessionManager.create(cwd, sessionDir)` calls in pi-webui helpers to their default forms.
   - Remove `sessionDir?: string` from pi-webui helper argument types.

4. Update tests to use Pi's canonical agent dir.
   - Set `process.env.PI_CODING_AGENT_DIR` to a temporary agent dir in tests that need SDK default session storage.
   - Write session fixtures under `<agentDir>/sessions/<bucket>/*.jsonl` or create them through `SessionManager.create(cwd)` when testing default session placement.
   - Remove custom `sessionDir` fixture fields from runtime-target, target-transition, and command-protocol tests.
   - Keep fake/injected listers for future sidebar tests instead of reintroducing a storage-root override.

5. Clean up historical references carefully.
   - Product docs and help output should no longer document `PI_AGENT_DIR` or `PI_SESSION_DIR`.
   - Existing ADR/plan text that says the canonical store is under `PI_AGENT_DIR` should be updated in the same implementation branch or in a small documentation follow-up so it names `PI_CODING_AGENT_DIR`.
   - Historical session notes may keep old names when they are clearly describing past behavior.

## Acceptance Criteria

- `rg "PI_AGENT_DIR|PI_SESSION_DIR|sessionDir" pi-webui` shows no product support for custom pi-webui session directories or pi-webui-specific agent-dir aliases except historical notes or clearly unrelated type names, if any remain.
- `pi-webui --help` no longer mentions `PI_AGENT_DIR` or `PI_SESSION_DIR`.
- `pi-webui/README.md` no longer documents `PI_AGENT_DIR` or `PI_SESSION_DIR`.
- Runtime startup, `open_cwd`, `switch_session`, recovery flows, and session listing use the canonical Pi agent session store.
- Tests that need an isolated Pi agent dir use `PI_CODING_AGENT_DIR`.
- `npm test --prefix pi-webui` passes.
