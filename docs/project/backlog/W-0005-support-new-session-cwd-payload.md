# Split Runtime New Session And Open Cwd Commands

## Summary

Keep the pi-webui websocket `new_session` command aligned with Pi's runtime new-session lifecycle, and add a separate `open_cwd` command for opening a disposable cwd runtime.

## Context

`docs/project/plans/PLAN-007-pi-webui-workspace-sidebar.md` needs workspace-level new-session actions. A sidebar click on a saved workspace should be able to open a disposable runtime in that workspace without first switching through a separate slash command.

`new_session` resolves from the existing Selected Runtime Target. That is correct for the normal "new session here" command because it calls Pi's `runtime.newSession()` and preserves `session_before_switch("new")`, cancellation, and `session_start.reason = "new"`.

Cross-cwd workspace actions are different: Pi's `AgentSessionRuntime.newSession()` is cwd-bound. Without extending Pi, an explicit cwd action is a pi-webui runtime-target replacement, not a Pi new-session lifecycle operation.

This work depends on `docs/project/backlog/W-0004-add-typed-command-effects-for-url-state.md`, which owns typed command effects for URL synchronization.

## Desired Outcome

Support this client command:

```js
send({ type: "open_cwd", cwd: workspace.path });
```

For `open_cwd`:

- Validate it through the same cwd transition path used by `/cwd`, `/workspace`, and existing target transitions.
- Start a disposable Cwd Mode runtime in the validated cwd.
- Return command data containing the validated `cwd`.
- Return the typed runtime-target command effect from `W-0004`.
- Let browser URL state move the URL to `?cwd=<validated-cwd>` from that typed effect.

For `new_session`:

- Reject a `cwd` payload.
- Preserve Pi runtime behavior: start a new session from the current Selected Runtime Target via `runtime.newSession()`.

## Acceptance Criteria

- `open_cwd` with `cwd: "/some/workspace"` starts the new runtime in `/some/workspace`.
- `new_session` without `cwd` keeps the current Pi lifecycle behavior.
- `new_session` with `cwd` fails loudly and tells callers to use `open_cwd`.
- Invalid cwd input fails before replacing the current runtime.
- The `open_cwd` command result includes the validated cwd so browser URL state becomes a URL Cwd Pointer.
- The command result includes a typed runtime-target effect for the validated cwd.
- Tests cover explicit cwd, omitted cwd, invalid cwd behavior, and the rejected mixed protocol.

## Notes

- This is a prerequisite cleanup for `PLAN-007`; implement it independently before the sidebar work.
- `open_cwd` is not sidebar-specific; it is the general "open disposable cwd runtime" protocol command.
- Do not silently coerce malformed cwd input. Validate at the command boundary and fail loudly.
