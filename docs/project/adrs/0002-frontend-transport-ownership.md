# ADR-0002: Frontend Transport Ownership

Status: Accepted

Date: 2026-06-07

## Context

pi-webui currently uses a websocket connection for active Pi runtime interaction, streamed session events, command results, and frontend state updates. The workspace/session sidebar needs a different read pattern: bounded catalog reads, pagination, manual refresh for the first version, and active-row highlighting.

Using the websocket for all sidebar data would couple a read-heavy navigation surface to the active runtime stream. Adding a second mutation path for active runtime changes would also risk split-brain behavior between the websocket controller, URL state, and any new tRPC over HTTP APIs.

The project needs a clear ownership model for tRPC over HTTP, future SSE stale notifications, and websocket transports.

## Decision

pi-webui will use each frontend transport for a distinct responsibility.

tRPC over HTTP owns request/response read models. These APIs are internal to this repository, with client and server code owned together, so tRPC provides the canonical end-to-end typed contract instead of duplicating request and response types across an ad hoc HTTP JSON boundary. tRPC over HTTP may later own durable management APIs when those APIs do not directly mutate the active runtime in the current browser tab.

SSE owns one-way server-to-client notifications for scoped purposes that do not require a bidirectional runtime channel. Sidebar stale notifications are a known future use, but the first workspace sidebar version intentionally ships without automatic sidebar invalidation or a sidebar SSE endpoint.

The websocket owns active runtime interaction. This includes prompts, active runtime commands, streamed session events, command results, command effects, `open_cwd`, and `switch_session`.

## Consequences

- The sidebar can fetch workspace and session catalog data through typed tRPC queries over HTTP without depending on the active runtime stream.
- When SSE is used, events should be small notifications, not full replacement payloads, unless a later ADR changes that boundary.
- Manual sidebar refresh is acceptable for the first sidebar version; transport ownership does not require every read model to have automatic invalidation.
- Runtime mutations that affect the current tab's active Pi runtime continue through the websocket.
- tRPC reads must not update URL state, start a Pi runtime, switch sessions, or otherwise mutate the active runtime.
- Durable management operations may move to tRPC over HTTP later only when their runtime and URL-state implications are explicit.

## Guardrails

- Do not add a tRPC procedure or HTTP endpoint for `open_cwd` or `switch_session` while the websocket owns active runtime mutation.
- Do not use SSE as a general replacement for websocket session streaming.
- Do not let tRPC read responses become the source of truth for the active runtime target.
- Use typed command effects from websocket command results for URL synchronization after runtime mutations.
- When stale notifications are added, treat them as invalidation hints only. The client should refetch or reconcile through the owning read API.
