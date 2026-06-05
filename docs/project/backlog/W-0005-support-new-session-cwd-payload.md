# Support New Session Cwd Payload

## Summary

Allow the pi-webui websocket `new_session` command to start a new session in an explicit cwd.

## Context

`docs/project/plans/PLAN-007-pi-webui-workspace-sidebar.md` needs workspace-level new-session actions. A sidebar click on a saved workspace should be able to start a new disposable session in that workspace without first switching the current runtime target through a separate workspace command.

Current `new_session` behavior resolves from the existing Selected Runtime Target. That is correct for the normal "new session here" command, but ambiguous for workspace sidebar actions.

This work depends on `docs/project/backlog/W-0004-add-typed-command-effects-for-url-state.md`, which owns typed command effects for URL synchronization.

## Desired Outcome

Support this client command:

```js
send({ type: "new_session", cwd: workspace.path });
```

When `cwd` is provided:

- Validate it through the same cwd transition path used by `/cwd`, `/workspace`, and existing target transitions.
- Start a New Session Cwd Mode runtime in the validated cwd.
- Return command data containing the validated `cwd`.
- Return the typed runtime-target command effect from `W-0004`.
- Let browser URL state move the URL to `?cwd=<validated-cwd>` from that typed effect.

When `cwd` is omitted:

- Preserve the existing behavior: start a new session from the current Selected Runtime Target.

## Acceptance Criteria

- `new_session` with `cwd: "/some/workspace"` starts the new runtime in `/some/workspace`.
- `new_session` without `cwd` keeps the current behavior.
- Invalid cwd input fails before replacing the current runtime.
- The command result includes the validated cwd so browser URL state becomes a URL Cwd Pointer.
- The command result includes a typed runtime-target effect for the validated cwd.
- Tests cover explicit cwd, omitted cwd, and invalid cwd behavior.

## Notes

- This is a prerequisite cleanup for `PLAN-007`; implement it independently before the sidebar work.
- Do not add a separate sidebar-specific packet unless the existing `new_session` command shape proves incompatible.
- Do not silently coerce malformed cwd input. Validate at the command boundary and fail loudly.
