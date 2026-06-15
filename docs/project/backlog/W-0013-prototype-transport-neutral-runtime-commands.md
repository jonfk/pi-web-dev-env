# Prototype Transport Neutral Runtime Commands

## Summary

Prototype a transport-neutral runtime command layer for pi-webui and expose one non-interactive implementable runtime command through tRPC as proof that future React UI surfaces can use typed request/response commands without creating a second runtime authority.

## Context

`docs/project/adrs/0002-frontend-transport-ownership.md` keeps active runtime mutations on websocket to avoid split-brain behavior between the websocket controller, URL state, and tRPC APIs. That remains the accepted rule. `docs/project/adrs/0004-proposed-transport-neutral-runtime-commands.md` proposes a replacement boundary, but it should not be accepted until this prototype proves the design.

Richer React surfaces such as the future resume picker need typed request/response command workflows:

- submit a user action from a React component;
- target the live runtime instance the user is viewing;
- receive an accepted, committed, cancelled, busy, stale, or failed result;
- apply typed command effects to URL state only after the runtime command layer commits;
- keep streamed runtime output on websocket.

The proposed ADR keeps websocket as the live event stream and interactive command transport, but moves active runtime mutation authority into a shared runtime command layer that websocket and tRPC adapters both delegate to.

This ticket is a proof of concept for that boundary. It should not implement a full resume picker or a broad command framework.

## Desired Outcome

Add enough runtime command infrastructure to prove that a non-interactive runtime command can be invoked through tRPC while preserving one server-side authority for target mutation, command effects, concurrency, and runtime identity.

The prototype should make future UI work possible without requiring React components to coordinate complex command verification through an ad hoc browser bridge.

## Recommended Prototype Command

Use `switch_session` as the first command unless implementation discovers a concrete blocker. It is the most relevant command for a richer resume picker and exercises the important behavior:

- target a live runtime instance;
- perform an exclusive runtime target transition;
- return committed target state;
- return typed URL command effects;
- fail if the runtime id or generation is stale.

If `switch_session` proves too coupled to existing websocket controller code for a focused prototype, use `open_cwd` only if it exercises the same runtime identity, exclusive transition, and command-effect behavior.

## Scope

- Introduce or extract a runtime command layer near the existing **Runtime Target Host** and **Target Transition Module** boundaries.
- Add a server-owned runtime instance identity:
  - opaque runtime id;
  - generation that increments when the selected runtime target is replaced.
- Expose the current runtime handle to the browser shell after runtime creation or target replacement.
- Add one tRPC mutation for a non-interactive runtime command.
- Require the tRPC mutation input to include runtime id and, for target-changing commands, the expected generation.
- Delegate both the new tRPC mutation and the existing websocket command path to the same runtime command layer for the prototyped command.
- Return a typed runtime command result with either:
  - success, committed runtime handle, and typed command effects; or
  - failure code and message.
- Keep URL state changes in the browser and drive them from typed command effects.
- Reject or fail exclusive runtime target transitions when another exclusive transition is already running for the same runtime instance.
- Fail stale runtime commands loudly when the runtime id or generation no longer matches.
- Keep streamed session events and assistant output on websocket.

## Non-Goals

- Do not implement interactive tRPC commands.
- Do not move streamed runtime events, assistant output, or extension UI prompts to tRPC.
- Do not implement a general transport-neutral browser interaction channel.
- Do not implement the React resume picker in this ticket.
- Do not add session deletion in this ticket.
- Do not replace sidebar catalog reads or SSE invalidation work.
- Do not make durable session identity the only active runtime identity; the prototype must distinguish durable session identity from live runtime instance identity.

## Command Result Shape

The exact TypeScript names can follow local code style, but the prototype should preserve this structure:

```ts
type RuntimeHandle = {
  runtimeId: string;
  generation: number;
  sessionFile: string | null;
  cwd: string;
};

type RuntimeCommandResult =
  | {
      ok: true;
      target: RuntimeHandle;
      effects: RuntimeCommandEffect[];
    }
  | {
      ok: false;
      code:
        | "busy"
        | "stale_runtime_generation"
        | "runtime_not_found"
        | "not_found"
        | "cancelled"
        | "requires_interactive_client"
        | "runtime_error";
      message: string;
    };
```

The command effect vocabulary should reuse or extend the existing typed command-effect flow rather than introducing a second URL policy language.

## Concurrency Policy

For the prototype:

- Exclusive target transitions must not run concurrently for the same runtime instance.
- If an exclusive transition is already active, a second exclusive transition should fail with `busy`.
- Read-only runtime queries may run concurrently.
- Commands that may write the same durable session from different runtime instances should use a durable session scoped lock before this pattern is expanded beyond the prototype.

Do not add loose defensive recovery for malformed command input. Validate at the command boundary and fail loudly.

## Disconnect And Cancellation Policy

For this prototype, tRPC commands are non-interactive only. Once the server accepts a command that can continue without browser interaction, closing the browser tab should not automatically abort the command.

If the command path discovers that browser interaction is required, it should fail explicitly with `requires_interactive_client` rather than attempting to continue over tRPC.

## Acceptance Criteria

- A runtime instance has an opaque runtime id and generation visible to the browser shell.
- The prototyped command can be invoked through tRPC with runtime id and expected generation.
- The existing websocket path for the same command delegates to the same runtime command layer.
- Successful command execution returns committed runtime handle data and typed command effects.
- Browser URL state is still updated only by applying typed command effects.
- A tRPC command with a stale generation fails and does not mutate the selected runtime target.
- Two concurrent exclusive target transitions against the same runtime instance cannot both commit.
- Streamed runtime events and assistant output still arrive over websocket.
- A command path that would require browser interaction is not exposed as an interactive tRPC flow.
- Tests cover runtime manager success, stale generation failure, busy/concurrent transition failure, and websocket/tRPC adapter parity for the prototyped command.
- `npm test --prefix pi-webui` passes.

## Notes

- This ticket may supersede the transport recommendation in `docs/project/backlog/W-0012-add-react-resume-picker.md` after the prototype proves the runtime command layer.
- This ticket should build on `docs/project/backlog/W-0007-deepen-typed-command-effect-flow.md` if that cleanup is still pending.
- Use existing pi-webui vocabulary from `pi-webui/CONTEXT.md`: **Selected Runtime Target**, **Runtime Target Host**, **Target Transition Module**, **Session Replacement Adapter**, **URL Session Pointer**, and **URL Cwd Pointer**.
