# PLAN-007: pi-webui Workspace Sidebar

## Source Material

- Brainstorming decision thread for the pi-webui workspace/session sidebar.
- Existing pi-webui browser shell: `pi-webui/public/index.html`
- Existing pi-webui app controller: `pi-webui/public/app.js`
- Existing pi-webui styles: `pi-webui/public/styles.css`
- Existing URL state module: `pi-webui/public/url-state.mjs`
- Existing session listing helper: `pi-webui/src/server/session-info.ts`
- Existing workspace registry: `pi-webui/src/server/workspace-store.ts`
- Existing target transition handling: `pi-webui/src/server/index.ts`
- Accepted frontend migration ADR: `docs/project/adrs/0001-incremental-react-typescript-frontend-migration.md`
- Accepted frontend transport ADR: `docs/project/adrs/0002-frontend-transport-ownership.md`
- Accepted session storage ADR: `docs/project/adrs/0003-pi-webui-canonical-session-store.md`
- Pre-work ticket: `docs/project/backlog/archived/W-0004-add-typed-command-effects-for-url-state.md`
- Pre-work ticket: `docs/project/backlog/archived/W-0005-support-new-session-cwd-payload.md`
- Pre-work ticket: `docs/project/backlog/archived/W-0010-remove-pi-session-dir-override.md`
- Pre-implementation spike ticket: `docs/project/backlog/W-0009-prototype-sidebar-build-and-index-contract.md`
- Follow-up ticket: `docs/project/backlog/W-0008-add-sidebar-auto-refresh-invalidation.md`
- Existing URL/session tests: `pi-webui/test/url-state.test.mjs`
- Existing workspace tests: `pi-webui/test/workspace-store.test.mjs`
- Domain vocabulary: `pi-webui/CONTEXT.md`

Use this plan as the implementation checklist for the first workspace sidebar version after `W-0004`, `W-0005`, `W-0009`, and `W-0010` have landed.

## Goal

Add a collapsible pi-webui sidebar that shows saved workspaces and the sessions that belong to those workspaces. The sidebar gives users a persistent workspace/session navigation surface similar to the Codex app while preserving the existing modal pickers for broader recovery, cwd, and all-session workflows.

The sidebar is a separate navigation read model, not part of the active Pi runtime stream. Implement it as a React + TypeScript island that uses tRPC over HTTP for workspace/session reads, manual refresh for catalog freshness, and the existing WebSocket command channel only for active runtime mutations such as switching sessions or opening a workspace cwd.

This plan assumes typed command effects from `docs/project/backlog/archived/W-0004-add-typed-command-effects-for-url-state.md`, the explicit new-session cwd payload from `docs/project/backlog/archived/W-0005-support-new-session-cwd-payload.md`, the sidebar build/index prototype from `docs/project/backlog/W-0009-prototype-sidebar-build-and-index-contract.md`, and canonical session storage from `docs/project/backlog/archived/W-0010-remove-pi-session-dir-override.md` already exist. Do not add sidebar-specific URL synchronization rules.

## Locked Decisions

- Scope this feature to `pi-webui` only.
- Add a real client build step now.
- Use React and TypeScript for the sidebar.
- Mount the sidebar as a React island inside the existing pi-webui shell instead of rewriting the full app in this plan.
- Keep `public/app.js` as source static browser code; do not move it into the Vite build in this plan.
- Build generated sidebar client assets under `pi-webui/dist/client`, not under `pi-webui/public`.
- Serve generated sidebar client assets from a dedicated `/client/*` static route.
- Emit stable sidebar asset names so `public/index.html` can reference `/client/sidebar.js` and `/client/sidebar.css`.
- Split server and client TypeScript configs before adding React files.
- Use Vite build output only for v1; do not add Vite dev-server integration in this plan.
- Use exactly one Vite client entry for v1: `src/client/sidebar/main.tsx`.
- Mount that client entry into `#workspace-sidebar-root`.
- Serve `/client/*` before the existing `public` static fallback.
- Serve `/client/*` with no-cache headers while sidebar asset names are stable.
- Missing `/client/sidebar.js` or `/client/sidebar.css` should fail as ordinary static 404s; do not add runtime fallback logic.
- Use tRPC over HTTP for sidebar read models.
- Do not add sidebar SSE stale notifications in v1.
- Sidebar index freshness is manual in v1: fetch the bounded index on mount, page reload, and explicit sidebar refresh action.
- Manual refresh always replaces the visible bounded index and resets loaded overflow pages for every workspace.
- Keep active runtime mutations on the existing WebSocket command channel for v1.
- Show only saved workspaces as top-level sidebar groups.
- Do not infer sidebar workspace groups from arbitrary session cwd values.
- Sessions appear under a workspace only when the session `cwd` exactly matches that workspace path.
- Sessions outside saved workspaces remain accessible through existing session picker flows, but do not appear in the sidebar.
- Sidebar session catalog reads use the server's canonical Pi agent session store under `PI_CODING_AGENT_DIR` or Pi's default agent dir; they do not honor CLI-style session directory overrides.
- `WorkspaceIndexService` must not accept, read, or pass through `PI_SESSION_DIR` or any `sessionDir` override.
- Desktop sidebar defaults to visible for first-time users.
- Desktop sidebar supports show/hide only. Do not add a collapsed icon rail in v1.
- Treat viewport widths of `900px` and wider as desktop for sidebar layout.
- Treat viewport widths below `900px` as mobile for sidebar layout.
- Persist the desktop show/hide preference in browser local storage under `pi-webui:sidebar-visible`.
- Mobile sidebar defaults to hidden.
- Mobile sidebar behaves as an off-canvas drawer with a backdrop.
- Do not persist mobile drawer open state.
- Clicking a workspace header expands or collapses that workspace group.
- Persist workspace expansion state in browser local storage under `pi-webui:sidebar-expanded-workspaces`.
- Workspace expansion persistence is keyed by workspace path.
- Missing expansion state defaults to expanded.
- Clicking a workspace new-session action starts a new disposable session in that workspace through `open_cwd`.
- Clicking a session switches to that session through `switch_session`.
- Existing URL Session Pointer and URL Cwd Pointer behavior remains the source of truth for durable navigation.
- Each workspace initially shows at most the 5 most recent sessions.
- Workspaces with more matching sessions expose a `show more` action that requests 10 additional sessions for that workspace using the server-provided `nextCursor`.
- `sidebar.workspaceSessions` requires a cursor; missing cursors fail at the API boundary instead of defaulting to the first overflow page.
- Stale workspace session cursors fail clearly on the server; manual refresh is the recovery path.
- Existing modal pickers remain available and are not replaced by this feature.

## First-Version Behavior

- A sidebar toggle is visible in pi-webui.
- At `900px` and wider, the app shell is a two-column layout when the sidebar is visible.
- At `900px` and wider, hiding the sidebar removes it from the layout and gives the chat surface the full width.
- Below `900px`, the sidebar opens over the chat as a drawer.
- The drawer closes when the user clicks the backdrop, presses Escape, selects a session, or starts a new workspace session.
- The sidebar header renders a manual refresh action.
- Saved workspaces render in a stable deterministic order.
- Each workspace group renders:
  - workspace name
  - compact display path
  - session count
  - expand/collapse affordance
  - new-session action
  - matching session rows when expanded
- Session rows render:
  - session name, first message, or shortened id fallback
  - relative modified time
  - message count
  - active state when the row matches the active session file
- Workspace groups initially render the bounded `sessionsWindow` supplied by the sidebar API.
- Active session highlighting is applied only to loaded session rows. If the active session is outside the loaded recent window or loaded overflow pages, do not create a synthetic active session row in v1.
- Workspace groups with `hasMore` show a compact `show more` action.
- Clicking `show more` sends the workspace's current `nextCursor`, loads the next 10 workspace sessions, and appends them to that workspace.
- If the workspace session list changed since the cursor was issued, the server rejects the stale cursor. Leave the visible rows unchanged and require manual refresh for a fresh bounded window.
- Manual refresh discards all loaded overflow pages even when a workspace `listVersion` is unchanged.
- While the initial sidebar index is loading, show the sidebar shell with a compact loading state rather than blocking the rest of the app.
- If the initial sidebar index load fails, show a compact sidebar error state with the same manual refresh action as the retry path.
- While manual refresh is in flight, keep the previous catalog visible, mark refresh as busy, and ignore additional refresh clicks until the request settles.
- While a workspace `show more` request is in flight, keep the current rows visible, mark only that workspace page action as busy, and ignore additional `show more` clicks for the same workspace until the request settles.
- A transient failed `show more` request should leave the existing workspace rows unchanged and expose a compact retry affordance through the same `show more` action.
- A stale-cursor `show more` failure should leave the existing workspace rows unchanged and expose the manual refresh path instead of retrying the same cursor.
- A workspace group shows an active workspace state when the active cwd exactly matches its path.
- If the active cwd matches a saved workspace but the current session is not durable yet, the workspace group remains highlighted and no fake session row is created.
- Empty workspace groups remain visible and show only the workspace header plus new-session action.
- The sidebar exposes a manual refresh action that refetches the bounded index.
- Sidebar workspace/session catalog rows, counts, ordering, modified times, and message counts may become stale after workspace or session changes until manual refresh or page reload.
- Active workspace and active session highlighting can update through the sidebar runtime bridge without refetching the bounded index.

## Non-Goals

- Do not add inferred cwd groups.
- Do not add pinned sessions.
- Do not add session deletion, rename, export, or context menus.
- Do not add drag and drop reordering.
- Do not add a collapsed desktop rail.
- Do not replace `/resume`, `/workspace`, `/cwd`, or recovery pickers.
- Do not move active runtime target ownership out of the WebSocket controller in this plan.
- Do not add HTTP mutations for `open_cwd` or `switch_session` in v1.
- Do not add a sidebar SSE endpoint in v1.
- Do not add automatic sidebar refresh, sidebar SSE stale notifications, or server-side sidebar invalidation hooks in v1.
- Do not add new all-session pagination in this plan.
- Do not add fuzzy search in v1 unless implementation discovers the list is unusable without it.

## Architecture

The sidebar has three separate responsibilities:

1. tRPC read procedures answer workspace/session catalog questions over HTTP.
2. A manual refresh action lets the user refetch the bounded catalog snapshot.
3. The existing WebSocket command channel performs active runtime mutations and emits typed command effects for URL synchronization.

This boundary keeps the sidebar independent from the main chat runtime while avoiding a second mutation path for the current tab's active Pi runtime.

## Implementation Phases

Implement PLAN-007 in focused phases. Keep `W-0009` separate from the full sidebar UI work; later phases may be separate PRs or combined when the diff stays easy to review.

1. Prerequisite prototype
   - Complete `docs/project/backlog/W-0009-prototype-sidebar-build-and-index-contract.md`.
   - Keep the proven Vite build, `/client/*` serving, and workspace index contract as the foundation for this plan.
   - Do not build the real sidebar UI in this phase.
2. Server read API
   - Finalize `WorkspaceIndexService`, tRPC router/procedures, `/api/trpc` route ordering, and server tests.
   - Preserve the transport boundary: tRPC reads only, WebSocket runtime mutations only.
3. Shell integration
   - Add the sidebar DOM placement, stable asset load order, and `window.piWebuiSidebarBridge`.
   - Mount a minimal sidebar island against the real bridge before adding full UI state.
4. Sidebar UI state
   - Implement workspace groups, expansion persistence, manual refresh, pagination, active highlighting, and loading/error/concurrency states.
   - Keep catalog freshness manual in v1.
5. Verification
   - Run build and test verification.
   - Complete desktop/mobile manual checks and regression checks for URL transitions, modal pickers, composer, slash menu, file completion, modal, and toast layers.

## Data Model

The sidebar read model must not reconstruct workspace grouping from `session_state`, `sessions`, or command-specific picker payloads. The server-side read model owns:

- saved workspace ordering;
- exact `session.cwd === workspace.path` membership;
- deterministic session sorting;
- a default recent-session window of 5 sessions per saved workspace;
- session counts per saved workspace;
- cursor-based pagination for additional workspace sessions, returning 10 additional sessions per page request.

Saved workspace ordering is deterministic and server-owned. Sort workspaces by stored workspace name using simple case-sensitive code-point comparison, then by absolute workspace path as a tie-breaker. Do not use locale-dependent ordering, creation time, updated time, current active workspace, or session recency for v1 ordering.

The sidebar catalog API must remain independent from the tab-local active runtime target. Active workspace and active session state are owned by the client bridge, not by the workspace/session listing response.

The exact session field names should follow `SerializedSessionInfo`. Do not create loose client-side aliases if the server already has a stable serialized shape.

### Session Storage Contract

pi-webui is a multi-workspace, multi-session server, not a single CLI invocation. Sidebar reads must therefore use the server-owned canonical session store rooted in the Pi agent dir. In practice, the workspace index service reads persisted session metadata from the default Pi agent session tree associated with `PI_CODING_AGENT_DIR` or Pi's default agent dir; it must not honor `PI_SESSION_DIR`, `sessionDir`, or other per-invocation session directory overrides.

This deliberately differs from Pi CLI behavior. The CLI can scope a single invocation to a custom session directory, but the sidebar needs one coherent server-wide catalog across saved workspaces. Mixing `SessionManager.list(cwd, sessionDir)` with `SessionManager.listAll()` makes that catalog ambiguous because `listAll()` does not accept a `sessionDir`.

The workspace index service should take an injectable session lister in tests. That injection is only a testability boundary for exact grouping, sorting, pagination, and cursor behavior; it is not a product hook for custom session storage.

### Bounded Index Response

```json
{
  "workspaces": [
    {
      "name": "project",
      "path": "/abs/workspace",
      "createdAt": "2026-06-05T00:00:00.000Z",
      "updatedAt": "2026-06-05T00:00:00.000Z",
      "sessionCount": 27,
      "sessionsWindow": {
        "limit": 5,
        "sessions": [],
        "nextCursor": "opaque-cursor",
        "hasMore": true,
        "listVersion": "session-list-fingerprint"
      }
    }
  ]
}
```

### Workspace Sessions Page Response

```json
{
  "workspacePath": "/abs/workspace",
  "listVersion": "session-list-fingerprint",
  "sessions": [],
  "nextCursor": "opaque-cursor-2",
  "hasMore": true
}
```

## tRPC API Plan

Add a small sidebar tRPC API surface to the existing pi-webui HTTP server. This is an internal API where the client and server live in the same repository, so the request/response API must use tRPC for end-to-end type safety instead of hand-written fetch wrappers and duplicated client/server types.

### tRPC Procedures

- `sidebar.workspaceIndex()`
  - Returns the bounded index response.
  - Does not accept `cwd`, `sessionFile`, or other tab-local active target hints.
  - Does not return `current` or `activeSessionOutsideWindow`.
  - The client derives active workspace and active session state from the sidebar runtime bridge.
- `sidebar.workspaceSessions({ workspacePath, cursor, limit })`
  - Returns one additional page for a saved workspace.
  - `workspacePath` is an exact saved workspace path value passed as typed input.
  - `limit` must be `10` in v1.
  - `cursor` is required and must be an opaque string previously returned by the server-side workspace index service.

### API Rules

- tRPC input and output types are the canonical API contract for sidebar reads.
- Serve the tRPC HTTP adapter from `/api/trpc`.
- HTTP request dispatch order must be `/api/trpc`, then `/client/*`, then the existing public static fallback.
- Use runtime validation at the tRPC input boundary, currently with `zod` schemas.
- Absolute filesystem paths are data values, never route path components.
- Do not encode workspace paths into REST route segments such as `/api/sidebar/workspaces/:workspacePath/sessions`.
- If a non-tRPC REST fallback is ever added, use `GET /api/sidebar/workspace-sessions?workspacePath=...&cursor=...&limit=10`.
- Base64url-encoded workspace paths are only acceptable if a future route-shaped REST API has a strong reason to exist.
- The client must import the tRPC router type instead of duplicating sidebar API response interfaces by hand.
- tRPC procedures must validate input at the API boundary and fail clearly for malformed input.
- The tRPC read API is allowed to read saved workspaces and persisted session metadata.
- The tRPC read API must read sidebar session metadata through the canonical Pi agent session store only; do not thread `sessionDir` through sidebar services or procedures.
- The tRPC read API must not start or mutate a Pi runtime.
- The tRPC read API must not update URL state.
- Use clear errors for missing cursors, invalid cursors, stale cursors, unknown workspaces, or unsupported limits.
- Unknown workspace paths must fail clearly instead of being normalized or loosely matched.
- Do not loosely parse malformed client input; fail at the API boundary.

## Server Plan

### Files To Update

- `pi-webui/src/server/index.ts`
- `pi-webui/src/server/session-info.ts` only if `SerializedSessionInfo` needs a small exported type or helper.

### Files To Add

- `pi-webui/src/server/workspace-index.ts`
- `pi-webui/src/server/trpc.ts`
- `pi-webui/src/server/sidebar-router.ts`
- `pi-webui/test/server-sidebar-router.test.mjs`
- `pi-webui/test/server-workspace-index.test.mjs`

### Server Implementation Sequence

1. Add a `WorkspaceIndexService` or equivalent read-model module.
2. Cover exact workspace/session grouping with focused server tests.
   - Inject a fake session lister in tests instead of relying on `PI_SESSION_DIR`.
   - Cover that service construction and sidebar procedures do not accept a `sessionDir` option.
3. Add cursor encode/decode and list-version behavior for workspace session pages, including clear stale-cursor rejection.
4. Add the tRPC server adapter, app router, and shared router type export.
5. Add the `sidebar.workspaceIndex` query procedure.
6. Add the `sidebar.workspaceSessions` query procedure.
7. Keep existing WebSocket startup, bootstrap, recovery, and command result behavior intact.

## Client Build Plan

Add a real client build step for React + TypeScript.

### Files To Update

- `pi-webui/package.json`
- `pi-webui/package-lock.json`
- `pi-webui/tsconfig.json`
- `pi-webui/src/server/index.ts`
- `pi-webui/public/index.html`
- `pi-webui/public/app.js`
- `pi-webui/public/styles.css`

### Files To Add

- `pi-webui/tsconfig.base.json`
- `pi-webui/tsconfig.server.json`
- `pi-webui/tsconfig.client.json`
- `pi-webui/vite.config.ts`
- `pi-webui/src/client/sidebar/main.tsx`
- `pi-webui/src/client/sidebar/Sidebar.tsx`
- `pi-webui/src/client/sidebar/trpc.ts`
- `pi-webui/src/client/sidebar/state.ts`
- `pi-webui/src/client/sidebar/types.ts`
- `pi-webui/src/client/sidebar/styles.css`
- `pi-webui/test/sidebar-state.test.mjs`

### Build Requirements

- Use Vite with React and TypeScript.
- Add the tRPC client/server dependencies required for the internal typed sidebar read API.
- Keep the existing static browser app working while the sidebar is introduced.
- Build the sidebar bundle into `pi-webui/dist/client`.
- Do not write generated sidebar assets into `pi-webui/public`.
- Serve `pi-webui/dist/client` from `/client/*` with an explicit static route in `src/server/index.ts`.
- Match `/client/*` before the existing `public` static fallback route.
- Serve `/client/*` with no-cache headers because the emitted asset names are stable in v1.
- If `/client/sidebar.js` or `/client/sidebar.css` is missing, return the normal static 404 response; do not silently skip sidebar startup or inject fallback markup.
- Keep the existing `public` static route as the source-static route for `/`, `/app.js`, `/styles.css`, and existing public modules.
- Configure Vite with `base: "/client/"`.
- Configure Vite with exactly one entry point: `src/client/sidebar/main.tsx`.
- Configure Vite/Rollup to emit stable entry and CSS names:
  - `dist/client/sidebar.js`
  - `dist/client/sidebar.css`
  - `dist/client/chunks/*` for secondary chunks, if any
- Keep the sidebar CSS as one emitted CSS file for v1.
- Keep server TypeScript compilation working through `npm run build`.
- Change `npm run build` to run `tsc -p tsconfig.server.json && tsc -p tsconfig.client.json && vite build` before the existing executable chmod step.
- Do not add a Vite dev-server workflow or `npm run dev` requirement in this plan.
- Keep `tsconfig.json` as the default project config that references or extends the server/client configs; do not leave it as the only compiler boundary.
- Move shared compiler options into `tsconfig.base.json`.
- Make `tsconfig.server.json` include the existing server and extension TypeScript sources and emit to `dist`.
- Make `tsconfig.client.json` include only `src/client/**/*.ts` and `src/client/**/*.tsx` and use `noEmit` for Vite type-checking.
- Add exactly one sidebar mount point in `public/index.html`: `#workspace-sidebar-root`.
- Place `#workspace-sidebar-root` inside `.app-shell` before `<main class="main">`.
- Update `public/index.html` to load `/app.js` before the React island and to load the React island through stable built assets:

```html
<link rel="stylesheet" href="/client/sidebar.css" />
<script type="module" src="/app.js"></script>
<script type="module" src="/client/sidebar.js"></script>
```

- Do not require a full React rewrite of `public/app.js` in this plan.
- Keep `package.json.files` relying on the existing `dist` entry; do not add generated client assets to `public`.
- Verify `npm run build --prefix pi-webui` produces `dist/server/index.js`, `dist/client/sidebar.js`, and `dist/client/sidebar.css`.

### Pre-Implementation Prototype

Complete `docs/project/backlog/W-0009-prototype-sidebar-build-and-index-contract.md` before implementing the full sidebar UI. That prototype owns proving the Vite React TypeScript island build, `/client/*` static serving, ordinary static 404 behavior for missing generated assets, and the workspace index contract for exact grouping, stable cursors, and list-version semantics.

Do not separately prototype the runtime bridge or DOM placement unless PLAN-007 implementation uncovers a concrete load-order, state notification, or layout failure. The bridge and DOM placement are small enough to specify as contracts in this plan and verify during normal implementation.

## Client Plan

### Integration Boundary

The existing app should expose a small bridge for the sidebar:

```ts
type SidebarRuntimeBridge = {
  getCurrentTarget(): { cwd: string | null; sessionFile: string | null };
  openCwd(cwd: string): void;
  switchSession(sessionPath: string): void;
  subscribeCurrentTarget(listener: () => void): () => void;
};
```

The bridge delegates active runtime mutations to the existing WebSocket `send` function:

```js
send({ type: "open_cwd", cwd: workspace.path });
send({ type: "switch_session", sessionPath: session.path });
```

`public/app.js` owns bridge target notifications. It should notify subscribers after `currentSessionState` changes through `session_state`, after invalid or cwd-required startup clears the current target, and after other existing app-owned target updates. The React island must not parse WebSocket packets directly.

The bridge's current target shape should be derived from existing app state:

- `cwd`: the current `session_state.cwd` when present, or the connected cwd before the first session-state snapshot when available;
- `sessionFile`: the current `session_state.sessionFile` when present, otherwise `null`.

Expose the bridge as a single browser global owned by `public/app.js`, `window.piWebuiSidebarBridge`. `public/index.html` must load `/app.js` before `/client/sidebar.js` so the bridge exists before the React island mounts. If the global is missing, the sidebar entry should fail loudly during development rather than silently creating a second runtime authority.

Place `#workspace-sidebar-root` inside `.app-shell` as a sibling before `<main class="main">`. On desktop, the React island renders the docked sidebar into that root and toggles `.app-shell.sidebar-visible` for the two-column shell. On mobile, the same root renders the off-canvas drawer and backdrop. Do not place the sidebar root outside `.app-shell`, inside `.main`, or near the modal/toast layers.

### Client Implementation Sequence

1. Add `#workspace-sidebar-root` inside `.app-shell` before `<main class="main">`.
2. Add the sidebar runtime bridge in `public/app.js`.
3. Mount the React sidebar island from the built client entry.
4. Track sidebar UI state:
   - latest bounded workspace index response
   - desktop visible preference
   - mobile drawer open state
   - expanded workspace paths
   - loaded workspace pages
5. Initialize desktop visible preference from `pi-webui:sidebar-visible`, defaulting to visible when unset.
6. Fetch the bounded workspace index.
7. Render saved workspace groups from the bounded index response.
8. Render active workspace and active session states from the bridge current target.
9. Initialize workspace expansion state from `pi-webui:sidebar-expanded-workspaces`, defaulting missing workspace paths to expanded.
10. Wire workspace header click to expand/collapse and persist the path-specific expansion state.
11. Wire workspace new-session action to `bridge.openCwd(workspace.path)`.
12. Wire session row click to `bridge.switchSession(session.path)`.
13. Wire `show more` to request the next tRPC page for that workspace.
14. On successful `show more`, append returned pages and update that workspace's `nextCursor`/`hasMore` state.
15. Close the mobile drawer after session or workspace new-session selection.
16. Handle Escape to close only the mobile drawer when it is open.
17. Add a sidebar refresh action that refetches the bounded workspace index.
18. Re-render active workspace and active session states when the bridge reports a current target change; do not refetch the bounded workspace index solely because the active target changed.
19. Keep existing modal keyboard behavior intact.

Bounded index responses are asynchronous catalog snapshots. The client must discard out-of-order bounded index responses using a monotonically increasing request id or equivalent latest-request guard. This prevents an older catalog request from replacing a newer catalog response after manual refetches.

Manual refresh is the only v1 freshness mechanism. The visible catalog may become stale after workspace add/remove, `open_cwd`, `new_session`, `switch_session`, first durable session creation, session rename, prompt or turn events that update modified time or message count, external session file changes, and import/clone/fork flows that create or adopt sessions. Automatic sidebar refresh, SSE stale notifications, and server-side invalidation hooks are follow-up work tracked in `docs/project/backlog/W-0008-add-sidebar-auto-refresh-invalidation.md`, not PLAN-007 work.

### Workspace Index Cursor Contract

The workspace index service owns cursor and list-version semantics.

- `listVersion` is a deterministic string fingerprint of the sorted session list for one saved workspace.
- The fingerprint should include only the fields that affect pagination and visible session row freshness in v1: session path, modified timestamp, message count, first message, and display name.
- The fingerprint should not include active target state, workspace expansion state, loaded page offset, or client-local visibility state.
- A page cursor encodes `{ workspacePath, listVersion, offset }` as an opaque string.
- The initial `sessionsWindow.nextCursor` offset is the bounded window length, usually 5; page requests never infer that offset from a missing cursor.
- A page request must include a cursor; missing cursors fail clearly at the API boundary.
- Cursor decode must fail clearly for malformed cursors.
- A page request must fail clearly if the cursor workspace does not match `workspacePath`.
- A page request must recompute the current workspace `listVersion` before slicing the page.
- A page request must fail clearly if the cursor `listVersion` does not match the current workspace `listVersion`.
- Successful page responses return the current workspace `listVersion`, which matches the accepted cursor version.
- The client must treat cursor strings as opaque data and must not construct or inspect them.

## Command Wiring

- Session row click uses the existing runtime-aware session switch path:

```js
send({ type: "switch_session", sessionPath: session.path });
```

- Workspace new-session action uses the target-specific new-session protocol from `W-0005`:

```js
send({ type: "open_cwd", cwd: workspace.path });
```

- `show more` uses the typed tRPC client:

```ts
await trpc.sidebar.workspaceSessions.query({
  workspacePath: workspace.path,
  cursor,
  limit: 10,
});
```

Do not overload workspace header clicks with side effects.

## URL State Requirements

- Selecting a session must update the URL to the selected durable session through typed command effects from `switch_session`.
- Starting a new workspace session must update the URL to `?cwd=<workspace.path>` through typed command effects from the target-specific new-session protocol.
- tRPC sidebar reads must not change the URL.
- Hiding or showing the sidebar must not change the URL.
- Expanding or collapsing workspace groups must not change the URL.
- Refreshing the sidebar index must not change the URL.
- Loading more workspace sessions must not change the URL.
- Mobile drawer open state must not change the URL.

## Styling Requirements

- Match the existing pi-webui dark, monospace, low-chrome visual style.
- Keep the sidebar work-focused and dense.
- Do not introduce cards inside the sidebar.
- Do not add decorative gradients or large empty hero-like surfaces.
- Use stable sidebar width on desktop, suggested `280px`.
- Use `@media (min-width: 900px)` for the docked desktop sidebar and `@media (max-width: 899px)` for the mobile drawer.
- Mirror the CSS breakpoint in TypeScript with `const DESKTOP_SIDEBAR_QUERY = "(min-width: 900px)"`.
- Keep row heights stable so active state or hover state does not shift layout.
- Ensure long workspace names, paths, and session titles truncate or wrap intentionally.
- Ensure the sidebar does not cover the composer on desktop.
- Ensure the mobile drawer respects `--app-height` and the visual viewport behavior used by the app shell.
- Ensure text does not overlap buttons or affordances at narrow mobile widths.

Suggested CSS surface:

- `.app-shell.sidebar-visible`
- `.sidebar`
- `.sidebar-backdrop`
- `.sidebar-toggle`
- `.sidebar-header`
- `.sidebar-refresh-button`
- `.sidebar-workspaces`
- `.workspace-group`
- `.workspace-header`
- `.workspace-new-button`
- `.session-row`
- `.session-row.active`
- `.workspace-show-more`

## Accessibility Requirements

- Sidebar toggle has an accessible label and `aria-expanded`.
- Workspace headers are buttons with `aria-expanded`.
- Session rows are buttons.
- New-session workspace actions are buttons with workspace-specific labels.
- Mobile backdrop can be dismissed with Escape.
- Focus should move naturally after opening the mobile drawer. Prefer focusing the sidebar toggle or first workspace header if doing so does not disrupt desktop usage.
- Active session should not rely on color alone; use a left border, marker, or clear text treatment.

## Testing Plan

### Pre-Work Tests

Confirm `W-0004` tests cover typed runtime-target command effects driving URL state.

Confirm `W-0005` tests cover `open_cwd` creating a disposable session for an explicit workspace cwd and returning the expected runtime target effect.

Confirm `W-0010` tests cover pi-webui using the canonical Pi agent session store without `PI_SESSION_DIR` or `sessionDir` product paths.

Confirm `W-0009` tests cover the sidebar build/static-serving prototype and the workspace index grouping, cursor, and list-version contract.

### Server Tests

Add focused tests for the workspace index service and tRPC API:

- Saved workspaces with exact cwd matches include matching sessions.
- Sessions from unsaved cwd values are omitted.
- Sessions with cwd values that merely share a prefix are omitted.
- Workspace groups are sorted deterministically.
- Workspace groups sort by stored workspace name, then absolute workspace path.
- Sessions inside a workspace are sorted by modified time descending.
- Empty saved workspaces remain in the returned payload.
- Initial workspace session windows are capped at 5 sessions.
- Workspace index requests do not accept active target hints and do not return active-session exception rows.
- Workspace session pagination uses stable cursors and list versions.
- Workspace list versions change when visible row freshness fields change.
- Workspace list versions do not change for active target or client-local UI state.
- Workspace session pagination returns 10 additional sessions per `show more` request.
- Unknown workspace page requests fail clearly.
- Unsupported page limits fail clearly.
- Missing cursors fail clearly.
- Malformed cursors fail clearly.
- Cursor workspace mismatches fail clearly.
- Stale cursor list versions fail clearly.
- tRPC workspace-index requests do not create or mutate a runtime.

### Client Tests

Add focused tests for sidebar state and tRPC helpers:

- Desktop visibility defaults to visible when local storage is unset.
- Desktop visibility persists when toggled.
- Mobile open state does not persist.
- Workspace expansion state defaults missing workspace paths to expanded.
- Workspace expansion state persists by workspace path.
- Sidebar command selection calls the expected bridge function.
- Sidebar reads the bridge from `window.piWebuiSidebarBridge`.
- Bounded index fetch replaces store state.
- Out-of-order bounded index responses are discarded.
- Sidebar manual refresh triggers a bounded index refetch.
- Sidebar manual refresh resets all loaded overflow pages.
- Initial bounded index loading renders a loading state without blocking the app.
- Initial bounded index failure renders a compact error state with refresh retry.
- Manual refresh ignores duplicate refresh actions while a refresh request is in flight.
- Current target bridge changes trigger active state refresh without forcing a bounded index refetch.
- Successful workspace session pages append and update that workspace's `nextCursor`/`hasMore` state.
- Stale cursor errors leave visible rows unchanged and require manual refresh.
- Duplicate `show more` clicks for the same workspace are ignored while a workspace page request is in flight.
- Failed `show more` requests leave existing workspace rows unchanged.
- `show more` sends the workspace path, current server-provided cursor, and limit through the tRPC API.

If client DOM tests would be brittle, prefer manual browser verification for layout and keep unit tests on pure state helpers.

## Verification Strategy

Run from the repository root:

```bash
npm test --prefix pi-webui
```

Also run:

```bash
npm run build --prefix pi-webui
```

Build verification should confirm:

- `pi-webui/dist/server/index.js` exists.
- `pi-webui/dist/client/sidebar.js` exists.
- `pi-webui/dist/client/sidebar.css` exists.
- `pi-webui/package.json` still includes `dist` in `files`.
- `pi-webui/public` does not contain generated sidebar build assets.
- Running `node pi-webui/dist/server/index.js` serves `/client/sidebar.js`.
- Running `node pi-webui/dist/server/index.js` serves `/client/sidebar.css`.
- `/client/*` responses use no-cache headers while asset names are stable.

Manual browser verification should cover:

- First desktop load shows the sidebar.
- `#workspace-sidebar-root` is inside `.app-shell` before the main chat surface.
- Desktop layout applies at `900px` and wider.
- Mobile drawer layout applies below `900px`.
- Desktop toggle hides the sidebar.
- Reload preserves the hidden desktop preference.
- Re-showing the sidebar persists across reload.
- Mobile load starts with the drawer hidden.
- Mobile toggle opens the drawer over the chat.
- Backdrop and Escape close the drawer.
- Saved workspace groups render.
- Empty saved workspace groups render without errors.
- Empty saved workspace groups render only the workspace header plus new-session action.
- Workspace groups expand and collapse.
- Workspace expansion state persists across reload.
- Workspace groups initially show at most 5 recent sessions.
- Workspaces with additional sessions show `show more`.
- `show more` loads and appends 10 additional sessions for that workspace.
- `show more` with a stale cursor leaves the visible rows unchanged and surfaces the refresh path.
- Manual refresh refetches the bounded workspace index.
- Manual refresh resets loaded overflow pages.
- Stale workspace pages do not corrupt the visible session list.
- Workspace `+` starts a new session in that workspace and updates the URL to cwd state.
- Session row click switches sessions and updates the URL to session state.
- Current workspace is highlighted before a durable session exists.
- Active session row is highlighted after opening a durable session.
- Active session outside the loaded recent window is not rendered as a synthetic row.
- Active session row becomes highlighted if `show more` loads that session normally.
- Sessions from unsaved cwd values do not appear in the sidebar.
- Existing `/resume` session picker still lists all sessions.
- Existing `/workspace` picker still works.
- Existing `/cwd` picker still works.
- Composer, status bar, slash menu, file completion menu, modal, and toast layer still render correctly with sidebar visible and hidden.

## Acceptance Criteria

- Sidebar ships as a React + TypeScript island mounted at `#workspace-sidebar-root`.
- `#workspace-sidebar-root` is placed inside `.app-shell` before `<main class="main">`.
- `public/app.js` exposes `window.piWebuiSidebarBridge` before `/client/sidebar.js` mounts.
- `npm run build --prefix pi-webui` emits `dist/server/index.js`, `dist/client/sidebar.js`, and `dist/client/sidebar.css`.
- `/client/sidebar.js` and `/client/sidebar.css` are served from `/client/*` with no-cache headers.
- Saved workspaces are the only top-level sidebar groups.
- Sessions appear under a workspace only when `session.cwd === workspace.path`.
- Workspaces are sorted by stored workspace name, then absolute workspace path.
- Workspace groups initially show at most 5 recent sessions.
- Workspace groups can load 10 more sessions at a time through the tRPC `sidebar.workspaceSessions` procedure.
- Workspace session page requests require a server-provided cursor and reject stale cursor versions.
- Desktop sidebar defaults visible and persists show/hide preference.
- Mobile drawer defaults hidden and does not persist open state.
- Workspace expansion defaults to expanded and persists by workspace path.
- Manual refresh refetches the bounded workspace index.
- Manual refresh resets all loaded overflow pages.
- Initial load, refresh, and `show more` loading/error states follow the minimal v1 rules.
- Out-of-order bounded index responses cannot replace newer sidebar state.
- Stale workspace page requests cannot append rows to the visible workspace list.
- Active workspace and active session highlighting comes from the runtime bridge without forcing a catalog refetch.
- Active sessions outside the loaded recent window are not rendered as synthetic rows.
- Workspace new-session and session-switch actions use the existing WebSocket command channel.
- URL state remains correct for cwd and session transitions.
- Existing `/resume`, `/workspace`, and `/cwd` picker flows still work.
- `npm test --prefix pi-webui` passes.
- Manual desktop and mobile browser verification passes.
