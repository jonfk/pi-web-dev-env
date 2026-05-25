# pi-webui `/resume` Scope Handoff

Date: 2026-05-25

## Context

The user reported that `/resume` in `pi-webui` shows sessions from all working directories, while upstream `pi` initially shows only sessions for the current working directory. We verified this against local source.

Relevant source references:

- `pi-webui/src/server/index.ts`
- `pi-webui/public/app.js`
- `vendored/pi/packages/coding-agent/src/modes/interactive/interactive-mode.ts`
- `vendored/pi/packages/coding-agent/src/modes/interactive/components/session-selector.ts`
- `vendored/pi/packages/coding-agent/src/core/session-manager.ts`

## Findings

`pi-webui` explicitly returns both current-project and all-project sessions for `/resume`:

- `pi-webui/src/server/index.ts` calls `SessionManager.list(ctrl.runtime.cwd, sessionDir)` and `SessionManager.listAll()`.
- `pi-webui/public/app.js` merges `payload.sessions.currentProject` and `payload.sessions.allProjects` into a single picker list.

Upstream `pi` also supports both scopes, but its selector starts in current-folder scope and lets the user toggle to all sessions:

- `SessionSelectorComponent` defaults `scope` to `"current"`.
- Tab toggles between current-folder and all-session scopes.
- Interactive `/resume` wires both loaders into the selector, but keeps the lists scoped in the UI.

Conclusion: `pi-webui` behavior is likely intentional as a convenience, but it is inconsistent with upstream `pi` and should be treated as a product bug for parity.

## Agreed Behavior

`pi-webui` `/resume` should default to current-project sessions only.

The picker should expose an explicit way to switch to all-project sessions. Recommended UI:

- Keyboard parity with upstream: Tab toggles scope.
- Visible web affordance: a small, per-use segmented control in the modal header for `Current project` / `All projects`.

`All projects` means all sessions, including sessions from the current project. Deduplicate by session `path` before rendering that scope.

Switching scope should preserve the current search query and re-filter that query against the newly active scope.

When the current project has no sessions, do not auto-switch to all projects. Show an empty current-project state with an obvious way to switch to `All projects`.

When both current-project and all-project scopes are empty, still open the picker in the current-project scope and show an empty state. Do not preserve the old early `No sessions to resume` toast behavior for `/resume`.

Empty-state copy:

- Current scope empty: `No sessions in current project`
- Current scope empty while search is active: `No matches in current project`
- All scope empty: `No sessions found`
- All scope empty while search is active: `No matches in all projects`

## Suggested Implementation

Keep the server response shape as-is for now:

- `sessions.currentProject`
- `sessions.allProjects`

Change `showSessionPicker(payload)` in `pi-webui/public/app.js` so it:

1. Starts with `currentProject` as the active scope.
2. Builds modal items only from the active scope.
3. Sorts by modified time within the active scope.
4. Searches only within the active scope.
5. Allows switching to `allProjects` via Tab and a clickable modal-header scope control.
6. Deduplicates defensively when showing all projects.
7. Opens even when the active scope has no items, rendering an empty state instead of closing or showing a toast.
8. Preserves the search query when switching scope.

Recommendation: do not create a new picker module for this change. The existing modal already has the needed `modalTabHandler` hook, and the scope behavior is specific to session resume. Factor session item derivation into a small helper first, then add a minimal modal-header affordance slot that `showSessionPicker` owns for this session-only scope control.

Do not generalize the modal into a broad picker extension interface yet. There is only one adapter for header actions, so a generic seam would be premature until another picker needs similar behavior.

## Verification Notes

Recommended tests:

- Initial `/resume` picker contains only `currentProject` sessions.
- Toggling scope shows `allProjects` sessions.
- Empty current-project scope does not auto-switch to all projects.
- Empty current-project and empty all-project scopes still open the picker with an empty state.

Manual check:

1. Start `pi-webui`.
2. Open a workspace with existing local sessions and sessions in other workspaces.
3. Run `/resume`.
4. Confirm only current workspace sessions appear.
5. Toggle to all projects and confirm cross-workspace sessions appear.
6. Resume a cross-workspace session and confirm the existing switch flow still works.
