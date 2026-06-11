# Remove PI_SESSION_DIR Override From pi-webui

## Summary

Remove pi-webui support for `PI_SESSION_DIR` and any equivalent `sessionDir` override so sessions are loaded only from the canonical Pi agent dir.

## Context

ADR-0003 establishes that pi-webui is a multi-workspace, multi-session server with one canonical session store under `PI_AGENT_DIR`:

- `docs/project/adrs/0003-pi-webui-canonical-session-store.md`

`PLAN-007` relies on that decision for the workspace sidebar catalog:

- `docs/project/plans/PLAN-007-pi-webui-workspace-sidebar.md`

Current pi-webui code still reads `process.env.PI_SESSION_DIR` and passes `sessionDir` through runtime creation, session listing, session switching, and recovery paths. That preserves Pi CLI-style behavior that is ambiguous for a server-wide workspace/session catalog.

## Desired Outcome

pi-webui loads, creates, switches, recovers, imports, forks, and lists sessions from the Pi agent dir only. `PI_AGENT_DIR` remains the server-owned storage root override; `PI_SESSION_DIR` is not supported by pi-webui.

## Scope

- Remove `PI_SESSION_DIR` from pi-webui documented environment variables and help output.
- Remove `process.env.PI_SESSION_DIR` handling from the server.
- Remove `sessionDir` threading from pi-webui runtime target creation, target transitions, recovery, and session listing helpers.
- Update tests that currently set or assert custom `sessionDir` behavior to use temporary `PI_AGENT_DIR` or injected listers instead.
- Ensure sidebar-related services do not accept `sessionDir`.
- Keep Pi's vendored CLI and SDK behavior unchanged.

## Non-Goals

- Do not remove `PI_AGENT_DIR`.
- Do not modify vendored Pi session manager APIs.
- Do not add a replacement custom session storage env var in this ticket.
- Do not migrate existing user session files automatically.

## Acceptance Criteria

- `rg "PI_SESSION_DIR|sessionDir" pi-webui` shows no product support for custom pi-webui session directories except historical notes or clearly unrelated type names, if any remain.
- `pi-webui --help` no longer mentions `PI_SESSION_DIR`.
- `pi-webui/README.md` no longer documents `PI_SESSION_DIR`.
- Runtime startup, `open_cwd`, `switch_session`, recovery flows, and session listing use the canonical Pi agent session store.
- `npm test --prefix pi-webui` passes.
