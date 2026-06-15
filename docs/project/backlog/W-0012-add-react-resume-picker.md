# Add React Resume Picker

## Summary

Replace the current static JavaScript resume picker with a richer React resume picker that reads session catalogs through tRPC and keeps session activation on the existing WebSocket runtime command path.

## Context

`docs/project/backlog/W-0011-add-session-trash-delete.md` needs session deletion to be available from both the workspace sidebar and the resume picker. The current pi-webui resume picker is implemented in `pi-webui/public/app.js` as a static modal:

- slash `/resume` returns a WebSocket command-result payload containing session lists;
- invalid URL recovery sends `list_all_sessions` over WebSocket and receives a recovery result;
- `showSessionPicker(...)` renders rows in the shared static modal;
- selecting a session sends `switch_session` or runtime-free `select_session` over WebSocket.

The workspace sidebar has already established the newer pattern: React + TypeScript island, typed tRPC reads, and WebSocket only for active runtime mutations.

This ticket should also rename the browser-owned React bridge from `window.piWebuiSidebarBridge` to a shared shell bridge such as `window.piWebuiShellBridge`, because the resume picker and sidebar both need access to current target state and WebSocket-backed runtime commands.

## Desired Outcome

The resume picker becomes a React surface that can support richer session-management actions, visible help, keyboard shortcuts, and future deletion actions without expanding the static modal code.

The picker should use tRPC for session catalog reads and continue using WebSocket commands only when the user chooses a session to make active.

## Scope

- Add a React resume picker client entry or a shared React session-management island.
- Update the Vite client build to emit stable resume picker assets.
- Mount the React resume picker from `pi-webui/public/index.html` or from the existing shell as appropriate.
- Add a typed tRPC read API for resume picker session catalogs.
- Support current-project and all-project scopes.
- Require the current cwd as input when reading the current-project resume catalog.
- Preserve search by typing.
- Preserve current-session highlighting.
- Preserve path display, sort mode, and named-session filtering if they are already expected from Pi's picker semantics.
- Add a visible help affordance that documents keyboard shortcuts and available picker actions.
- Keep session activation on the existing WebSocket commands:
  - `switch_session` when a runtime exists;
  - `select_session` during runtime-free recovery.
- Handle all existing resume picker entry points:
  - slash `/resume`;
  - invalid URL recovery choose-session;
  - runtime-free startup recovery.
- Do not add session deletion in this ticket; `W-0011` adds deletion after this React picker exists.
- Do not add a second HTTP mutation path for active runtime switching.
- Do not reintroduce `PI_SESSION_DIR`, `sessionDir`, or mixed session storage roots.

## Transport Recommendation

Use tRPC for resume picker catalog reads. The old WebSocket payload should become an intent to open the React picker, not the catalog source of truth.

Recommended shape:

- `sessions.resumeCatalog({ scope: "currentProject", cwd, query?, sort?, namedOnly? })` returns sessions for the provided cwd.
- `sessions.resumeCatalog({ scope: "allProjects", query?, sort?, namedOnly? })` returns all sessions and does not require cwd.
- The browser shell exposes a shared bridge, for example `window.piWebuiShellBridge`, for current target state, opening the React picker, and sending runtime activation commands.
- The React picker calls the bridge to activate a selected session, using `switch_session` or `select_session` depending on whether the current tab has a runtime.
- Runtime-free recovery opens the picker in all-project scope because there is no current runtime cwd.

## Acceptance Criteria

- `/resume` opens the React resume picker instead of the old static modal.
- Invalid URL recovery choose-session opens the same React resume picker.
- Runtime-free startup recovery opens the same React resume picker.
- The picker can show current-project and all-project session scopes.
- Current-project catalog reads require a cwd supplied by the shared shell bridge.
- Runtime-free recovery opens all-project scope without sending a current-project catalog request.
- The picker supports search, current-session highlighting, and session selection.
- The picker exposes visible help for shortcuts and available actions.
- Choosing a session still sends `switch_session` or runtime-free `select_session` over WebSocket.
- Session catalog reads are served by tRPC and use the canonical Pi agent session store.
- The old static `showSessionPicker(...)` path is removed or reduced to a compatibility shim that opens the React picker without owning session catalog rendering.
- URL state still changes only through semantic command effects from WebSocket command results.
- Tests cover `/resume`, invalid URL recovery, runtime-free recovery, tRPC catalog reads, and WebSocket session activation from the React picker.
- `npm test --prefix pi-webui` passes.

## Notes

- This is a prerequisite for `docs/project/backlog/W-0011-add-session-trash-delete.md`.
- Use existing pi-webui vocabulary from `pi-webui/CONTEXT.md`: **URL Session Pointer**, **Selected Runtime Target**, **Runtime Target Host**, and **Invalid Session Message**.
- Keep the React picker visually consistent with the existing sidebar rather than the old static modal.
