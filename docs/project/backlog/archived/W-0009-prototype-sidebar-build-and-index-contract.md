# Prototype Sidebar Build And Index Contract

Status: Implemented 2026-06-12

## Summary

Run two small pre-implementation spikes for `PLAN-007` before building the full pi-webui workspace sidebar.

## Context

`docs/project/plans/archived/PLAN-007-pi-webui-workspace-sidebar.md` is coherent, but two areas should be proven in isolation before the full sidebar implementation:

- the Vite React TypeScript island build and static serving integration;
- the workspace index read-model contract, especially exact workspace grouping, cursor encoding, and list-version semantics.

The architecture decisions are captured in:

- `docs/project/adrs/0001-incremental-react-typescript-frontend-migration.md`
- `docs/project/adrs/0002-frontend-transport-ownership.md`

Do not implement the full sidebar UI in this ticket.

## Desired Outcome

Prove the client build/server serving seam and lock the server-side workspace index contract with focused code and tests so `PLAN-007` can proceed without inventing those details during UI implementation.

## Scope

- Add the minimal Vite, React, and TypeScript build wiring needed to emit a static sidebar island.
- Add an empty `#workspace-sidebar-root` mount point.
- Add a minimal React island that renders a temporary static label and imports sidebar CSS.
- Serve generated client assets from `/client/*` before the existing public static fallback.
- Serve tRPC from `/api/trpc` before `/client/*` and the public fallback if the tRPC adapter is introduced during the spike.
- Confirm missing client assets fail as ordinary static 404s.
- Add or sketch the `WorkspaceIndexService` contract with focused tests for exact workspace/session grouping and pagination semantics.
- Use `zod` for tRPC input validation if the tRPC procedure surface is introduced during the spike.
- Use opaque page cursors containing server-owned `{ workspacePath, listVersion, offset }` semantics.

## Non-Goals

- Do not build the real sidebar UI.
- Do not add automatic sidebar refresh or SSE invalidation.
- Do not add tRPC or HTTP mutations for `open_cwd` or `switch_session`.
- Do not move `public/app.js` into the Vite build.
- Do not add Vite dev-server integration.

## Acceptance Criteria

- `npm run build --prefix pi-webui` emits `pi-webui/dist/server/index.js`, `pi-webui/dist/client/sidebar.js`, and `pi-webui/dist/client/sidebar.css`.
- Running `node pi-webui/dist/server/index.js` serves `/`, `/app.js`, `/client/sidebar.js`, and `/client/sidebar.css`.
- `/client/*` responses use no-cache headers while asset names are stable.
- Existing public static files are still served by the existing public fallback.
- Focused workspace index tests cover:
  - saved workspaces are the only top-level groups;
  - sessions are included only when `session.cwd === workspace.path`;
  - prefix-sharing cwd values are excluded;
  - empty saved workspaces remain visible;
  - sessions are sorted by modified time descending;
  - initial windows are capped at 5;
  - page requests return 10 additional sessions;
  - malformed cursors, unknown workspaces, and unsupported limits fail clearly.
- `npm test --prefix pi-webui` passes.

## Notes

- Remove the temporary static sidebar label when the real `PLAN-007` UI work starts.
- Keep malformed input failures at the API or service boundary; do not add loose parsing or fallback behavior.
