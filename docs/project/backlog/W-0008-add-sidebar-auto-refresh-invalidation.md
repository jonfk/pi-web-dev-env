# Add Sidebar Auto-Refresh Invalidation

## Summary

Add automatic workspace sidebar refresh after `PLAN-007` ships with manual refresh only.

## Context

`docs/project/plans/PLAN-007-pi-webui-workspace-sidebar.md` intentionally scopes v1 sidebar freshness to mount, page reload, and explicit user refresh. That keeps the first sidebar implementation smaller and avoids underspecified invalidation hooks.

The known limitation is that workspace/session catalog rows, counts, ordering, modified times, and message counts can drift stale after server-side workspace or session changes.

`docs/project/adrs/0002-frontend-transport-ownership.md` reserves SSE as the future one-way notification transport for this class of invalidation. SSE events should remain invalidation hints only; the client should refetch through the owning tRPC read API.

## Desired Outcome

Add server-owned sidebar stale notifications so the sidebar can refresh automatically without guessing from browser-side command names or runtime packets.

## Scope

- Add a minimal sidebar SSE endpoint, likely `GET /api/sidebar/events`.
- Add a debounced server-side sidebar invalidation broker.
- Emit a global `sidebar_index_stale` event for v1 of automatic invalidation.
- Add workspace-scoped stale events only if implementation proves global refetches are too broad.
- Keep SSE payloads as small invalidation hints, not full workspace/session payloads.
- Keep sidebar data reads on tRPC over HTTP.
- Keep active runtime mutations on the websocket.
- Do not add tRPC or HTTP mutations for `open_cwd` or `switch_session`.

## Event Source Matrix

Every event source below must be either implemented with a test or explicitly documented as intentionally excluded:

- Workspace add: emit after `addWorkspace` succeeds.
- Workspace remove: emit after `removeWorkspace` succeeds.
- `open_cwd`: emit after a successful target transition if it can create, adopt, or expose a durable session in a saved workspace.
- `new_session`: emit after a successful target transition if it can create or expose a durable session in a saved workspace.
- `switch_session` / runtime-free `select_session`: do not emit for active-row highlighting alone; emit only if the transition adopts or rewrites persisted session metadata used by the sidebar catalog.
- First durable session creation: emit when the current session file changes from absent to present.
- Session rename / `set_session_name`: emit after the rename succeeds.
- Prompt or turn completion: emit after events that update persisted modified time or message count.
- External session file change: emit after an accepted refresh from file.
- Import, clone, fork, or similar flows: emit if they create, copy, or adopt durable sessions under a saved workspace.
- Read-only picker/list requests: do not emit.
- Refresh, abort, model changes, tool changes, or settings changes: do not emit unless they write durable session metadata used by the sidebar catalog.

## Acceptance Criteria

- Sidebar clients receive `sidebar_index_stale` after each implemented catalog-changing event source.
- The client refetches `sidebar.workspaceIndex()` after `sidebar_index_stale`.
- Stale notifications do not change URL state.
- Active runtime target changes still update active sidebar highlighting through the runtime bridge, not through catalog invalidation.
- SSE disconnect does not break manual refresh or page-load fetching.
- Tests cover every implemented event source in the matrix.
- Tests cover at least one intentionally excluded source so active-state-only changes do not force catalog refetches.
