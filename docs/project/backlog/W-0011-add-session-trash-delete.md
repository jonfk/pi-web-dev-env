# Add Session Deletion With Trash Recovery

## Summary

Add pi-webui functionality to delete persisted Pi sessions with confirmation, using trash-based deletion when available so recovery remains possible. The deletion action must be accessible from both the workspace sidebar and the React resume picker from `docs/project/backlog/W-0012-add-react-resume-picker.md`, except for the current tab's active session.

## Context

`docs/project/plans/archived/PLAN-007-pi-webui-workspace-sidebar.md` shipped the first workspace sidebar and explicitly left session deletion, export, and context menus out of v1. The sidebar now shows saved workspaces and their matching sessions from the canonical Pi agent session store, but users cannot remove old or unwanted sessions from the catalog.

`docs/project/adrs/0003-pi-webui-canonical-session-store.md` establishes that pi-webui reads persisted sessions from the canonical Pi agent dir. Deletion must operate on that same server-owned store and must not reintroduce `PI_SESSION_DIR`, `sessionDir`, or mixed storage roots.

Pi already supports deleting sessions from the interactive `/resume` picker with `Ctrl+D`, then confirmation. The Pi docs state that when the `trash` CLI is available, Pi uses it instead of permanently removing files. The vendored Pi implementation has the matching behavior in `vendored/pi/packages/coding-agent/src/modes/interactive/components/session-selector.ts`.

The current pi-webui `/resume` flow is still the older static modal path in `pi-webui/public/app.js`: the server returns a session picker payload over the WebSocket command path, the browser renders it with `showSessionPicker(...)`, and selection sends `switch_session` or runtime-free `select_session` over WebSocket. The workspace sidebar is already a React island that uses tRPC for session catalog reads and the WebSocket bridge only for active runtime mutations.

`docs/project/backlog/W-0012-add-react-resume-picker.md` owns replacing the old static resume picker with a richer React picker and typed tRPC catalog reads. This ticket builds on that prerequisite and adds deletion to both React session surfaces.

## Desired Outcome

Users can delete sessions they no longer want to see in normal pi-webui session lists. The deletion flow mirrors Pi's picker behavior: require confirmation, try the `trash` CLI first, and fall back to direct file deletion when trash-based deletion is unavailable or fails. pi-webui must not delete the current tab's active session from the sidebar or resume picker.

The implementation should keep session catalog reads and deletion mutations on tRPC, keep active runtime target switching on the WebSocket command channel, preserve URL/target invariants, and refresh visible session catalogs after successful deletion.

## Deletion Model

Use Pi's existing deletion model instead of adding pi-webui-specific archive semantics:

1. The user initiates deletion for a persisted session.
2. pi-webui asks for explicit confirmation.
3. If the session is the current tab's active session, pi-webui blocks deletion before mutating session files.
4. The server attempts to move the target session file to trash through the tRPC deletion mutation.
5. If trash is unavailable or fails, the server falls back to direct file deletion, matching Pi's current behavior.
6. The deleted session is removed from visible session catalogs.

Do not add an archive store, archived-session view, archived-session restore UI, or separate permanent-delete path in this ticket.

## Scope

- Add a server-side session deletion Module that mirrors Pi's trash-first deletion behavior.
- Add a tRPC session deletion mutation alongside the session catalog API from `W-0012`.
- Add sidebar UI affordances for deleting loaded non-active session rows.
- Disable or reject sidebar deletion for the current tab's active session.
- Build on the richer React resume picker from `docs/project/backlog/W-0012-add-react-resume-picker.md`.
- Add deletion to the React resume picker from `W-0012`.
- Disable or reject resume picker deletion for the current tab's active session.
- Keep resume picker session activation on WebSocket commands: `switch_session` when a runtime exists, `select_session` during runtime-free recovery.
- Confirm deletion before mutating session files.
- Refresh or invalidate both sidebar and resume picker catalogs after successful deletion.
- Remove deleted sessions from `sidebar.workspaceIndex()` and `sidebar.workspaceSessions()` results.
- Reuse or closely mirror Pi's delete implementation where practical, including `trash` invocation details.
- Keep existing session switching on the WebSocket command channel.
- Keep sidebar catalog reads and mutations on the canonical Pi agent session store.
- Do not add loose session-path parsing, cwd inference, or best-effort repair of malformed session files.
- Do not thread `PI_SESSION_DIR`, `sessionDir`, or other per-invocation storage overrides through the feature.
- Do not implement an archive feature or archived-session browsing.
- Do not add a second HTTP mutation path for active runtime switching.

## Transport Recommendation

Use one shared tRPC-backed deletion mutation for both access paths:

- `sessions.delete(...)` or equivalent for deletion from either sidebar or resume picker.
- `sessions.resumeCatalog(...)` from `W-0012` remains the resume picker catalog read path.
- `sidebar.workspaceIndex()` and `sidebar.workspaceSessions(...)` can keep their current sidebar-specific read model.

The React resume picker should fetch its catalog over tRPC, then use the shared shell bridge from `W-0012` only when it needs current target state or when the user chooses a session to make active.

Because tRPC mutations are not owned by a specific `NativePiSessionController`, active-session protection should be scoped to the current browser tab and coordinated by the React caller:

1. Capture the target session path and cwd from the session row before mutation.
2. Read the latest current target from the shared shell bridge at confirmation time.
3. If the target matches the current tab's active session path, block deletion and show a clear message.
4. Otherwise, call the tRPC delete mutation for the original target path.
5. Refresh or invalidate the sidebar and resume picker catalogs.

This keeps active runtime target changes owned by the WebSocket controller and keeps filesystem/session catalog mutation owned by tRPC. The server-side delete mutation must validate canonical persisted session membership, but it does not enforce active-session protection or track sessions that may be active in other tabs or stale browser contexts. If a different tab keeps pointing at a deleted session, the next prompt can fail and a refresh should surface the existing **Invalid Session Message** behavior.

## Decisions

- Delete fallback policy:
  - Match Pi exactly: try `trash`, then fall back to direct file deletion.
- Active-session deletion:
  - Do not allow deleting the current tab's active session.
  - Do not track or protect sessions that may be active in other tabs.
  - Prefer a disabled visible delete affordance with explanatory text over hiding the action entirely.
- Resume picker rollout:
  - Split the richer React resume picker into prerequisite ticket `docs/project/backlog/W-0012-add-react-resume-picker.md`.

## Acceptance Criteria

- A user can delete a loaded, non-active sidebar session from that session row.
- The current tab's active sidebar session cannot be deleted.
- A user can delete a loaded resume picker session from the richer React resume picker.
- If the resume picker target is the current tab's active session, deletion is disabled or rejected before mutation.
- The resume picker includes a visible help affordance that exposes keyboard shortcuts and available session actions.
- The action requires explicit confirmation that names the affected session.
- Active-session status is checked again at confirmation time, not only when the row first renders.
- The server attempts trash-based deletion before direct file deletion.
- When trash-based deletion succeeds, the result makes clear that the session was moved to trash.
- When direct deletion fallback succeeds, the result makes clear that the session was deleted.
- After successful deletion, the deleted session no longer appears in the sidebar bounded index or paginated session results.
- After successful deletion, the deleted session no longer appears in the resume picker catalog.
- Sidebar counts, pagination cursors, loaded rows, and resume picker rows are refreshed or invalidated after mutation.
- The mutation fails clearly when the session path does not exist, is outside the canonical session store, or is not a known persisted session.
- The mutation does not create, repair, or rewrite malformed session files as a side effect.
- The current **URL Session Pointer** and **Selected Runtime Target** remain unchanged after deleting a non-active session.
- The current **URL Session Pointer** and **Selected Runtime Target** remain unchanged when active-session deletion is rejected.
- Choosing a session in the React resume picker still uses `switch_session` or runtime-free `select_session` over WebSocket so URL effects continue to come from semantic command results.
- Existing URL state rules remain driven by semantic effects and are not updated by guessing from sidebar UI actions.
- Tests cover trash success, direct deletion fallback success, missing session failure, outside-store rejection, current-tab active-session deletion rejection, sidebar result exclusion, resume picker result exclusion, and the resume picker transport split.
- `npm test --prefix pi-webui` passes.

## Notes

- Use the existing pi-webui vocabulary from `pi-webui/CONTEXT.md`: **URL Session Pointer**, **Invalid Session Message**, **Selected Runtime Target**, and **Runtime Target Host**.
- Use the Pi docs as the product reference: `https://pi.dev/docs/latest/sessions`.
- Use the vendored Pi implementation as the behavioral reference: `vendored/pi/packages/coding-agent/src/modes/interactive/components/session-selector.ts`.
- Current resume picker entry points to account for: slash `/resume`, invalid URL recovery choose-session, and runtime-free startup recovery.
- If `docs/project/backlog/W-0008-add-sidebar-auto-refresh-invalidation.md` has shipped, emit the relevant sidebar invalidation event after successful deletion. If not, use the existing manual refresh or local refetch path.
- Prefer a small, explicit storage mutation boundary over scattering direct filesystem operations through UI route handlers.
