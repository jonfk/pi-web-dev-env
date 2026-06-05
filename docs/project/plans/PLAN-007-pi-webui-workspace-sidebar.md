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
- Pre-work ticket: `docs/project/backlog/W-0004-add-typed-command-effects-for-url-state.md`
- Pre-work ticket: `docs/project/backlog/W-0005-support-new-session-cwd-payload.md`
- Pre-work ticket: `docs/project/backlog/W-0006-refactor-pi-webui-workspace-index-protocol.md`
- Existing URL/session tests: `pi-webui/test/url-state.test.mjs`
- Existing workspace tests: `pi-webui/test/workspace-store.test.mjs`
- Domain vocabulary: `pi-webui/CONTEXT.md`

Use this plan as the implementation checklist for the first workspace sidebar version after `W-0004`, `W-0005`, and `W-0006` have landed.

## Goal

Add a collapsible pi-webui sidebar that shows saved workspaces and the sessions that belong to those workspaces. The sidebar gives users a persistent workspace/session navigation surface similar to the Codex app while preserving the existing modal pickers for broader recovery, cwd, and all-session workflows.

This plan assumes typed command effects from `docs/project/backlog/W-0004-add-typed-command-effects-for-url-state.md`, the explicit new-session cwd payload from `docs/project/backlog/W-0005-support-new-session-cwd-payload.md`, and the workspace index protocol from `docs/project/backlog/W-0006-refactor-pi-webui-workspace-index-protocol.md` already exist. Do not add a sidebar-specific canonical state packet in this plan.

## Locked Decisions

- Scope this feature to `pi-webui` only.
- Show only saved workspaces as top-level sidebar groups.
- Do not infer sidebar workspace groups from arbitrary session cwd values.
- Sessions appear under a workspace only when the session `cwd` exactly matches that workspace path.
- Sessions outside saved workspaces remain accessible through existing session picker flows, but do not appear in the sidebar.
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
- Clicking a workspace new-session action starts a new disposable session in that workspace.
- Clicking a session switches to that session.
- Existing URL Session Pointer and URL Cwd Pointer behavior remains the source of truth for durable navigation.
- Sidebar data comes from the canonical `workspace_index_snapshot`, `workspace_index_event`, and `workspace_sessions_page` packets.
- Each workspace initially shows at most the 5 most recent sessions, plus an active-session exception if the active session belongs to that workspace but is outside the recent window.
- Workspaces with more matching sessions expose a `show more` action that requests 10 additional sessions for that workspace.
- Existing modal pickers remain available and are not replaced by this feature.

## First-Version Behavior

- A sidebar toggle is visible in pi-webui.
- At `900px` and wider, the app shell is a two-column layout when the sidebar is visible.
- At `900px` and wider, hiding the sidebar removes it from the layout and gives the chat surface the full width.
- Below `900px`, the sidebar opens over the chat as a drawer.
- The drawer closes when the user clicks the backdrop, presses Escape, selects a session, or starts a new workspace session.
- Saved workspaces render in a stable deterministic order, initially alphabetical by workspace name.
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
  - active state when the row matches the active `current.sessionFile`
- Workspace groups initially render the bounded `sessionsWindow` supplied by the workspace index.
- If `activeSessionOutsideWindow` is present, render that active session in the workspace group without counting it as part of the recent 5 window.
- Workspace groups with `hasMore` show a compact `show more` action.
- Clicking `show more` loads the next 10 workspace sessions and appends them to that workspace if the returned `listVersion` still matches the workspace list version.
- If a workspace list version changes after additional pages were loaded, discard loaded overflow pages for that workspace and return to the refreshed recent window.
- A workspace group shows an active workspace state when `current.cwd` exactly matches its path.
- If `current.cwd` matches a saved workspace but the current session is not durable yet, the workspace group remains highlighted and no fake session row is created.
- Empty workspace groups remain visible and show only the workspace header plus new-session action.
- Sidebar content updates from workspace index snapshots, workspace index events, and workspace session pages.

## Non-Goals

- Do not add inferred cwd groups.
- Do not add pinned sessions.
- Do not add session deletion, rename, export, or context menus.
- Do not add drag and drop reordering.
- Do not add a collapsed desktop rail.
- Do not replace `/resume`, `/workspace`, `/cwd`, or recovery pickers.
- Do not add new all-session pagination in this plan. Workspace-scoped pagination is provided by `W-0006`.
- Do not add fuzzy search in v1 unless implementation discovers the list is unusable without it.

## Data Model

Consume the workspace index protocol from `W-0006`. The sidebar must not reconstruct workspace grouping from `session_state`, `sessions`, or command-specific picker payloads.

Bounded bootstrap and refresh packets have this shape:

```js
{
  type: "workspace_index_snapshot",
  payload: {
    revision: 12,
    current: {
      cwd: "/abs/workspace",
      sessionFile: "/abs/session.jsonl"
    },
    workspaces: [
      {
        name: "project",
        path: "/abs/workspace",
        createdAt: "2026-06-05T00:00:00.000Z",
        updatedAt: "2026-06-05T00:00:00.000Z",
        sessionCount: 27,
        sessionsWindow: {
          limit: 5,
          sessions: [],
          nextCursor: "opaque-cursor",
          hasMore: true,
          listVersion: 4
        },
        activeSessionOutsideWindow: null
      }
    ]
  }
}
```

The exact session field names should follow `SerializedSessionInfo`. Do not create loose client-side aliases if the server already has a stable serialized shape.

Additional workspace-specific pages arrive as:

```js
{
  type: "workspace_sessions_page",
  payload: {
    workspacePath: "/abs/workspace",
    listVersion: 4,
    sessions: [],
    nextCursor: "opaque-cursor-2",
    hasMore: true
  }
}
```

Canonical updates arrive as `workspace_index_event`. The browser-side workspace index store should own event and page application so sidebar rendering stays direct.

## Server Plan

This plan should not add sidebar-specific server state. Typed command effects are pre-work owned by `W-0004`; the target-specific new-session protocol is pre-work owned by `W-0005`; the canonical workspace index protocol and pagination endpoint are pre-work owned by `W-0006`.

### Files To Update

- None expected for sidebar state construction.
- `pi-webui/src/server/index.ts` only if implementation discovers a small protocol wiring gap in the already-landed workspace index API.

### Required Existing Server Behavior

- `workspace_index_snapshot` is sent during bootstrap and after canonical reset/refresh flows.
- `workspace_index_snapshot` is also sent in invalid URL and cwd-required no-runtime states so the sidebar can render saved workspaces and workspace actions without a live runtime.
- `workspace_index_event` is sent after current-target, workspace, or matching-session window changes.
- `list_workspace_sessions` returns `workspace_sessions_page` for one saved workspace.
- Target-specific new-session requests can create a new session in a supplied workspace cwd.
- Target-changing command results include typed semantic effects for URL synchronization.

If any of these behaviors are missing, complete `W-0004`, `W-0005`, or `W-0006` first rather than patching sidebar-specific workarounds into this plan.

## Client Plan

### Files To Update

- `pi-webui/public/index.html`
- `pi-webui/public/app.js`
- `pi-webui/public/styles.css`

### Optional File To Add

- `pi-webui/public/sidebar.mjs`

Add a separate module if sidebar rendering starts to crowd `app.js`. Keep it in `app.js` only if the implementation remains small and direct.

### Implementation Sequence

1. Add sidebar shell markup next to the main chat surface.
2. Add a desktop/mobile sidebar toggle button.
3. Track sidebar UI state:
   - latest workspace index store state
   - desktop visible preference
   - mobile drawer open state
   - expanded workspace paths
4. Initialize desktop visible preference from `pi-webui:sidebar-visible`, defaulting to visible when unset.
5. Render saved workspace groups from the workspace index store.
6. Render active workspace and active session states from `current`.
7. Initialize workspace expansion state from `pi-webui:sidebar-expanded-workspaces`, defaulting missing workspace paths to expanded.
8. Wire workspace header click to expand/collapse and persist the path-specific expansion state.
9. Wire workspace new-session action to start a new session in that workspace.
10. Wire session row click to switch to that session.
11. Wire `show more` to request the next page for that workspace.
12. Append returned pages only when `listVersion` matches the workspace's current list version.
13. Close the mobile drawer after session or workspace new-session selection.
14. Handle Escape to close only the mobile drawer when it is open.
15. Keep existing modal keyboard behavior intact.
16. Re-render the sidebar after workspace index snapshots, workspace index events, and workspace session pages.

### Command Wiring

- Session row click should use the existing runtime-aware session switch path:

```js
send({ type: "switch_session", sessionPath: session.path });
```

- Workspace new-session action should use the target-specific new-session protocol from `W-0005`, for example:

```js
send({ type: "new_session", cwd: workspace.path });
```

- `show more` should request the next page for a single workspace:

```js
send({ type: "list_workspace_sessions", workspacePath: workspace.path, cursor, limit: 10 });
```

Do not overload workspace header clicks with side effects.

## URL State Requirements

- Selecting a session must update the URL to the selected durable session through typed command effects from `switch_session`.
- Starting a new workspace session must update the URL to `?cwd=<workspace.path>` through typed command effects from the target-specific new-session protocol.
- Hiding or showing the sidebar must not change the URL.
- Expanding or collapsing workspace groups must not change the URL.
- Loading more workspace sessions must not change the URL.
- Mobile drawer open state must not change the URL.

## Styling Requirements

- Match the existing pi-webui dark, monospace, low-chrome visual style.
- Keep the sidebar work-focused and dense.
- Do not introduce cards inside the sidebar.
- Do not add decorative gradients or large empty hero-like surfaces.
- Use stable sidebar width on desktop, suggested `280px`.
- Use `@media (min-width: 900px)` for the docked desktop sidebar and `@media (max-width: 899px)` for the mobile drawer.
- Mirror the CSS breakpoint in JavaScript with `const DESKTOP_SIDEBAR_QUERY = "(min-width: 900px)"`.
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

The server-side workspace index behavior should be covered by `W-0006`, not by this sidebar implementation plan. Confirm those tests exist before implementing the sidebar:

- Saved workspaces with exact cwd matches include matching sessions.
- Sessions from unsaved cwd values are omitted.
- Sessions with cwd values that merely share a prefix are omitted.
- Workspace groups are sorted deterministically.
- Sessions inside a workspace are sorted by modified time descending.
- Empty saved workspaces remain in the returned payload.
- Initial workspace session windows are capped at 5 sessions.
- Active session outside the initial window is exposed separately.
- Workspace session pagination uses stable cursors and list versions.
- Workspace session pagination returns 10 additional sessions per `show more` request.
- Invalid URL and cwd-required states still send enough workspace index state to render saved workspaces and workspace actions.

### Client Tests

Add focused module tests for the workspace index store and sidebar UI helpers:

- Desktop visibility defaults to visible when local storage is unset.
- Desktop visibility persists when toggled.
- Mobile open state does not persist.
- Workspace expansion state defaults missing workspace paths to expanded.
- Workspace expansion state persists by workspace path.
- Sidebar command selection calls the expected send function.
- Workspace index snapshots replace store state.
- Workspace index events update current target and workspace session windows.
- Workspace session pages append only when `listVersion` matches.
- Workspace session pages with stale `listVersion` are ignored or trigger the documented reset behavior.
- `show more` sends `list_workspace_sessions` with the workspace path and cursor.

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

Manual browser verification should cover:

- First desktop load shows the sidebar.
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
- Stale workspace pages do not corrupt the visible session list.
- Workspace `+` starts a new session in that workspace and updates the URL to cwd state.
- Session row click switches sessions and updates the URL to session state.
- Current workspace is highlighted before a durable session exists.
- Active session row is highlighted after opening a durable session.
- Active session is visible when it belongs to a saved workspace but is outside the recent 5 session window.
- Sessions from unsaved cwd values do not appear in the sidebar.
- Existing `/resume` session picker still lists all sessions.
- Existing `/workspace` picker still works.
- Existing `/cwd` picker still works.
- Composer, status bar, slash menu, file completion menu, modal, and toast layer still render correctly with sidebar visible and hidden.

## Acceptance Checklist

- Desktop sidebar defaults visible.
- Desktop show/hide preference persists.
- Desktop layout applies at `900px` and wider.
- Mobile drawer defaults hidden and does not persist open state.
- Mobile drawer layout applies below `900px`.
- Saved workspaces are the only top-level sidebar groups.
- Exact cwd match is required for sessions to appear under a workspace.
- Unsaved workspace sessions remain absent from the sidebar.
- Workspace groups initially show at most 5 recent sessions.
- Workspace groups default to expanded when no persisted expansion state exists.
- Workspace expansion state persists by workspace path.
- Workspace groups can load 10 more sessions at a time with `show more`.
- Active session remains visible even when it is outside a workspace's recent session window.
- Workspace groups can expand and collapse.
- Workspace new-session action starts a new session in that workspace.
- Session click switches to the selected session.
- URL state remains correct for cwd and session transitions.
- Active workspace and active session states render correctly.
- Existing modal pickers continue to work.
- `W-0004` tests cover typed command effects for URL state.
- `W-0006` workspace index tests cover server grouping, windowing, pagination, and no-runtime snapshots.
- `npm test --prefix pi-webui` passes.
- `npm run build --prefix pi-webui` passes.
