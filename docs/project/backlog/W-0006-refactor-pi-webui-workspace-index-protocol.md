# Refactor pi-webui Workspace Index Protocol

## Summary

Add a bounded, server-owned workspace index protocol before implementing `PLAN-007`.

## Context

`docs/project/plans/PLAN-007-pi-webui-workspace-sidebar.md` originally proposed a sidebar-specific state packet. That risks duplicating information from `session_state`, `sessions`, and command results, and it would grow poorly if workspaces have many sessions.

The sidebar needs canonical facts about saved workspaces, recent sessions per workspace, session counts, and the current runtime target. Those facts should be owned by a reusable workspace index protocol rather than by sidebar rendering code.

## Desired Outcome

Implement a workspace index protocol that the sidebar can consume without requesting or receiving every session for every saved workspace on each refresh.

This work depends on:

- `docs/project/backlog/W-0004-add-typed-command-effects-for-url-state.md`, which owns typed command effects for URL synchronization.
- `docs/project/backlog/W-0005-support-new-session-cwd-payload.md`, which owns the explicit `new_session.cwd` protocol needed by workspace-level sidebar actions.

## Scope

- Add a server module, such as `pi-webui/src/server/workspace-index.ts`.
- The module owns:
  - saved workspace ordering;
  - exact `session.cwd === workspace.path` membership;
  - deterministic session sorting;
  - a default recent-session window of 5 sessions per saved workspace;
  - session counts per saved workspace;
  - cursor-based pagination for additional workspace sessions, returning 10 additional sessions per page request;
  - active-session-outside-window detection.
- Add websocket packets:
  - `workspace_index_snapshot` for bounded bootstrap state.
  - `workspace_index_event` for canonical updates after workspace/session/current-target changes.
  - `list_workspace_sessions` for loading more sessions in one workspace.
  - `workspace_sessions_page` for the paged response.
- Add a browser-side store module, such as `pi-webui/public/workspace-index-state.mjs`, that applies snapshots, events, and pages.
- The browser-side store module owns:
  - replacing state from `workspace_index_snapshot`;
  - applying canonical `workspace_index_event` updates;
  - appending `workspace_sessions_page` results only when the page `listVersion` matches the workspace's current `listVersion`;
  - discarding or ignoring stale loaded workspace pages when a workspace list version changes;
  - exposing state that sidebar rendering can consume directly without reconstructing workspace grouping from `session_state`, `sessions`, or command results.
- Use typed semantic command effects from `W-0004`; do not add workspace-index-specific URL synchronization rules here.
- Use the target-specific new-session protocol from `W-0005`; do not add another sidebar-specific new-session packet here.
- Send workspace index snapshots in invalid URL and cwd-required no-runtime states so saved workspaces and workspace actions can still render without a live runtime.

## Protocol Sketch

Initial and refresh snapshots should be bounded:

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

In invalid URL or cwd-required no-runtime states, `current.cwd` and `current.sessionFile` may be `null`. The sidebar can still render saved workspaces and workspace actions; it simply has no active workspace or active session to highlight.

Updates should be canonical state events, not sidebar-specific events:

```js
{
  type: "workspace_index_event",
  payload: {
    revision: 13,
    event: {
      type: "workspace_sessions_window_replaced",
      workspacePath: "/abs/workspace",
      sessionCount: 28,
      sessionsWindow: {
        limit: 5,
        sessions: [],
        nextCursor: "opaque-cursor",
        hasMore: true,
        listVersion: 5
      },
      activeSessionOutsideWindow: null
    }
  }
}
```

Pagination should be scoped to one workspace:

```js
{ type: "list_workspace_sessions", workspacePath: "/abs/workspace", cursor: "opaque-cursor", limit: 10 }
```

```js
{
  type: "workspace_sessions_page",
  payload: {
    workspacePath: "/abs/workspace",
    listVersion: 5,
    sessions: [],
    nextCursor: "opaque-cursor-2",
    hasMore: true
  }
}
```

`W-0004` successful target-changing commands should report semantic effects, for example:

```js
{
  type: "command_result",
  payload: {
    command: "new_session",
    ok: true,
    data: { cwd: "/abs/workspace" },
    effects: [
      {
        type: "runtime_target_changed",
        target: { kind: "cwd", cwd: "/abs/workspace" }
      }
    ]
  }
}
```

The server reports what happened. `pi-webui/public/url-state.mjs` remains responsible for deciding how that semantic effect maps to browser URL behavior.

## Notes

- Do not reintroduce a large `navigation_state` or `sidebar_state` packet containing all sessions.
- Do not infer workspace groups from arbitrary session cwd values.
- Keep workspace index packet semantics in the browser-side store module, not in sidebar DOM rendering code.
- If a workspace `listVersion` changes, loaded overflow pages for that workspace may be discarded and reloaded.
- Prefer opaque cursors over offset pagination because session modification can reorder rows.
- Keep malformed data handling simple: registry/session data should fail at existing boundaries rather than being loosely repaired in the workspace index.
