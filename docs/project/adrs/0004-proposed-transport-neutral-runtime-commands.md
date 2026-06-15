# ADR-0004: Proposed Transport Neutral Runtime Commands

Status: Proposed

Date: 2026-06-15

Would Supersede: ADR-0002 if accepted after prototyping

## Context

ADR-0002 currently assigns request/response read models to tRPC, one-way stale notifications to SSE, and active runtime interaction to websocket. That decision avoided split-brain behavior while the workspace sidebar was being introduced.

Richer React surfaces such as a resume picker need typed request/response workflows for implementable runtime commands. Routing those workflows through an ad hoc browser bridge can make command acceptance, command effects, cancellation policy, and result verification harder to express and test.

Adding tRPC mutations directly beside websocket command handlers would recreate the split-brain risk ADR-0002 was designed to avoid. The transport boundary therefore needs to distinguish transport mechanics from runtime command authority before tRPC is allowed to expose runtime commands.

This ADR is a proposal. ADR-0002 remains the accepted rule until a prototype proves this design.

## Proposed Decision

pi-webui would use each frontend transport for a distinct responsibility, but active runtime mutation authority would belong to a transport-neutral runtime command layer.

tRPC over HTTP would continue to own request/response read models. tRPC could also expose non-interactive request/response runtime command adapters when they target a server-owned runtime instance and delegate to the shared runtime command layer. These procedures would not become a second runtime authority. They would be typed adapters over the same target transition, command effect, concurrency, and validation rules used by websocket commands.

SSE would continue to own one-way server-to-client notifications for scoped purposes that do not require a bidirectional runtime channel.

The websocket would own live runtime interaction. This includes prompt streaming, streamed session events, runtime output, extension UI prompts, interactive command flows, and any command that requires browser-side interaction while it is running.

The runtime command layer would own active runtime mutations. This includes runtime target transitions such as `open_cwd`, `switch_session`, and `new_session`; concurrency policy for commands that cannot run together; runtime identity checks; and typed command effects. Websocket and tRPC adapters could expose runtime commands only by delegating to this layer.

Runtime identity would have two levels:

- Durable session identity names the saved session, such as a session file or future stable session id.
- Runtime instance identity names one live server-owned runtime attachment, using an opaque runtime id and generation.

The same durable session may be opened by multiple browser tabs. Those tabs must not accidentally share active runtime command authority merely because they point at the same saved session. Runtime commands that mutate a live tab runtime should target the runtime instance id and, when needed, the runtime generation so stale commands fail loudly instead of mutating a replaced runtime.

## Consequences

- Runtime mutations that affect the current tab's active Pi runtime would go through the shared runtime command layer, even when exposed over websocket or tRPC.
- tRPC reads would still not update URL state, start a Pi runtime, switch sessions, or otherwise mutate the active runtime.
- tRPC runtime command procedures could mutate a runtime only when runtime identity, generation handling, concurrency policy, non-interactive behavior, and URL-state command effects are explicit.
- Durable management operations could move to tRPC over HTTP when their runtime and URL-state implications are explicit.
- Prompt submission could return command acceptance over request/response APIs, but streamed assistant output would remain websocket-owned.
- Target-changing request/response commands could return committed runtime state and typed command effects after the runtime command layer commits the transition.
- Closing a browser tab after a non-interactive request is accepted would not automatically abort server-side work that can safely continue.
- Commands that require browser interaction would stay on websocket until the project defines a transport-neutral interaction channel or an attached-client policy.

## Guardrails

- Do not implement tRPC runtime commands as independent logic beside websocket command handlers. Shared behavior must live in the runtime command layer.
- Do not implement interactive tRPC runtime commands in the first version. If a runtime command may require extension UI, permission UI, browser confirmation, text input, custom UI, or another browser-side continuation, keep it on websocket or fail with an explicit non-interactive unsupported result.
- Do not use SSE as a general replacement for websocket session streaming.
- Do not let tRPC read responses become the source of truth for the active runtime target.
- Use typed command effects from runtime command results for URL synchronization after runtime mutations, independent of transport.
- Reject or fail commands that target a stale runtime id or generation.
- Serialize or reject concurrent runtime commands according to command class. Exclusive target transitions must not run concurrently against the same runtime instance.
- Use a durable session scoped lock for commands that can write the same saved session from multiple runtime instances.

## Prototype Requirement

Before this ADR can be accepted, implement `docs/project/backlog/W-0013-prototype-transport-neutral-runtime-commands.md` or an equivalent prototype.

The prototype should prove:

- one non-interactive runtime command can be invoked through tRPC;
- the existing websocket path for the same command delegates to the same runtime command layer;
- stale runtime generation commands fail without mutating the selected target;
- concurrent exclusive target transitions cannot both commit;
- successful target-changing commands return committed runtime state and typed command effects;
- streamed runtime events and assistant output remain websocket-owned.
