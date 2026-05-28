# pi-webui URL Session State Handoff

Date: 2026-05-27

## Context

This handoff captures exploration only. No implementation has been started.

The user wants to continue planning a feature for `pi-webui`: move the active session pointer out of browser `localStorage` and into URL search params, so loading or sharing a URL can select the session to resume.

Relevant existing context:

- `pi-webui/README.md` documents current configuration and notes that workspace shortcuts and last cwd are persisted in `PI_AGENT_DIR/workspaces.json`.
- `docs/sessions/2026-05-25-pi-webui-resume-scope-handoff.md` may contain adjacent resume/session context from earlier work.
- Main server code: `pi-webui/src/server/index.ts`
- Browser app code: `pi-webui/public/app.js`
- Current active-session storage helper: `pi-webui/public/storage.mjs`
- Workspace persistence: `pi-webui/src/server/workspace-store.ts`

## Current Behavior Observed

`pi-webui` does not store conversation history itself. Pi owns the durable sessions through its session JSONL files and agent directory state.

`pi-webui` adds these pieces of state:

- Browser `localStorage`
  - `pi-webui:session-file`: active Pi session file path.
  - `pi-webui:input-history`: composer history.
  - `pi-webui:debug`: optional client debug logging flag.
- Server-side file
  - `${PI_AGENT_DIR}/workspaces.json`: saved workspaces plus `lastCwd`.
- Extension-side file
  - `~/.pi/extensions/webui.pid`: process tracking for `/webui start/status/stop`.

The current reload flow is:

1. Browser opens `/`.
2. Browser connects to `/ws`.
3. Browser sends `ready` with `sessionFile` from `localStorage["pi-webui:session-file"]`.
4. Server calls `runtime.switchSession(sessionFile)` when present and different from the runtime's initial session.
5. Server sends `session_state`, `message_history`, and `sessions`.
6. Browser writes `session_state.sessionFile` back to `localStorage`.

Important code references:

- Client reads/writes active session storage in `pi-webui/public/app.js` near `loadStoredSessionFile()` / `saveStoredSessionFile()`.
- Client sends the value in the WebSocket `ready` packet in `connect()`.
- Server handles `ready` in `NativePiSessionController.handleReady(lastSeq, sessionFile)`.
- Each WebSocket connection gets a fresh `NativePiSessionController`.
- The server's initial cwd comes from `workspaces.json:lastCwd` or falls back to `process.cwd()`.
- The initial runtime uses `SessionManager.create(initialCwd, sessionDir)`, then may switch to the browser-requested session file.

## Proposed Direction Discussed

Replace the active-session `localStorage` key with a URL search param. The likely first shape is:

```text
/?session=<url-encoded absolute session jsonl path>
```

Frontend helper concept:

```js
const SESSION_PARAM = "session";

function loadSessionFileFromUrl() {
  const params = new URLSearchParams(window.location.search);
  const value = params.get(SESSION_PARAM);
  return value && value.trim() ? value : null;
}

function syncSessionFileToUrl(file) {
  const url = new URL(window.location.href);
  if (file) url.searchParams.set(SESSION_PARAM, file);
  else url.searchParams.delete(SESSION_PARAM);
  window.history.replaceState(null, "", url);
}
```

The intended flow would become:

1. Browser opens `/?session=...`.
2. Browser connects to `/ws`.
3. Browser sends `ready` with `sessionFile` from `URLSearchParams`, not `localStorage`.
4. Server uses its existing `runtime.switchSession(sessionFile)` path.
5. Browser updates the URL from `session_state.sessionFile`.

This should also cover new sessions, resumes, forks, imports, and clones because those operations eventually send a fresh `session_state` or bootstrap.

## Product Decisions

Decided in follow-up on 2026-05-27:

- URL value format: use the absolute session JSONL file path. This matches the existing server protocol and avoids maintaining a separate session lookup table for now.
- Privacy/security posture: absolute paths in URLs are acceptable for this local software. Deployments are assumed to use HTTPS.
- Browser history behavior: URL history follows meaningful session identity changes. No **URL Session Pointer** to first real **URL Session Pointer** uses `replaceState`. Existing **URL Session Pointer** to a different **URL Session Pointer** uses `pushState`. Same **URL Session Pointer** is a no-op. Invalid **URL Session Pointer** leaves the URL unchanged.
- Invalid or deleted URL session: show an app-level invalid-session message in the transcript and keep the bad URL visible so the user can correct it manually or navigate to `/new`. The message should look like a frontend pseudo message, similar to the initial message the TUI shows on startup. The server must not silently bootstrap a fallback/default session for an invalid **URL Session Pointer**. The client should disable the composer while the URL session is invalid.
- URL sessions whose stored cwd no longer exists are invalid URL state for v1. Do not automatically fall back to the current/default cwd. This could be improved later with an explicit TUI-like recovery flow that lets the user choose a replacement cwd before opening the session.
- New/empty sessions: sessions without an accepted prompt do not have identity worth preserving. `/` without params and `/new` are aliases for the same disposable new-session flow. Do not encode an unprompted session file in the URL. Once the first prompt is accepted by Pi, the session becomes meaningful and the client updates the URL to `/?session=<absolute-jsonl-path>`.
- Disposable new sessions encode cwd, not session identity. Canonical disposable URL shape is `/?cwd=<absolute-path>`. `/` and `/new` are accepted aliases; when no `cwd` param is present, the client should populate `cwd` from the server's resolved initial cwd. When `cwd` is present on first request, the server should validate it and use it as the canonical cwd for the disposable runtime.
- URL grammar: `session` and `cwd` are mutually exclusive. `?session=<path>` opens a durable existing Pi session. `?cwd=<path>` opens a **Disposable New Session** in that cwd. A URL containing both should be rejected with `invalid_url_state` using `kind: "conflict"`.
- `/cwd` and `/workspace` switches move the URL into cwd mode: `/?cwd=<new-cwd>`. They drop any existing `session` param because switching cwd disposes the current runtime and starts a new disposable session in that cwd. This is a meaningful navigation and should use `pushState`.
- Browser Back/Forward should reload the page for v1. The normal startup flow then reopens the session or cwd from the URL, avoiding duplicate in-place switching logic in the browser.
- Replace `pi-webui/public/storage.mjs` with a small `url-state.mjs` module. The old active-session localStorage concept is going away, so the module name should reflect the new URL-state interface. Existing storage tests should become URL-state tests.
- Add a small server-side URL-state helper module, such as `pi-webui/src/server/url-state.ts`, instead of parsing WebSocket URL state inline in `index.ts`. It should own the server URL grammar and return a parsed state shape (`session`, `cwd`, `new`, or `invalid`) for `NativePiSessionController` initialization.
- Pass URL state on the WebSocket URL before controller runtime initialization, for example `/ws?cwd=<path>` or `/ws?session=<path>`. The server should validate mutually exclusive URL params before constructing the runtime. URL `cwd` creates the initial runtime directly in that cwd. Missing URL state uses `getInitialCwd()` for a disposable new session. URL `session` should create a `SessionManager.open(sessionPath, sessionDir)` first, then create the runtime with `sessionManager.getCwd()` and that session manager.
- Multi-tab behavior: keep one runtime/controller per WebSocket. URL state makes browser tabs independent, and a shared controller is out of scope for the first implementation.
- Invalid URL state should use a dedicated WebSocket packet rather than `server_error`:

  ```js
  {
    type: "invalid_url_state",
    payload: {
      kind,
      value,
      message,
      defaultCwd,
      sessions: {
        currentProject,
        allProjects
      }
    }
  }
  ```

  The client renders an **Invalid Session Message**, disables the composer, and leaves the URL unchanged. This packet covers invalid **URL Session Pointer** values and invalid `cwd` values. `defaultCwd` powers the `New session` action. `sessions` powers the `Choose session` action without requiring a follow-up request while the app is in invalid URL state. For invalid `cwd`, session lists may be based on `defaultCwd` because the requested cwd cannot be used.

- Invalid URL-state pseudo message actions:
  - `New session`: navigate to `/?cwd=<server-default-cwd>` when the server includes a fallback/default cwd, otherwise `/new`.
  - `Choose session`: open the existing resume/session picker when the client has enough session list data.
  - Do not include a vague "clear URL" action; blank `/` now means disposable session in the initial cwd, so the action should say "New session".

  Suggested copy:

  ```text
  Could not open URL session

  The URL points to a session pi-webui cannot open. The session path or stored working directory may no longer exist.
  ```

## Implementation Questions To Explore

- `serveStatic()` must serve the app shell for `/new`; otherwise the alias route returns a JSON 404 today.
- The WebSocket connection path needs URL-state parsing before `NativePiSessionController` constructs its runtime.
- `NativePiSessionController.handleReady()` should stop accepting `sessionFile`; URL session selection moves to controller initialization.
- `session_state` URL sync should only canonicalize no-pointer disposable URLs after first prompt acceptance and should push only when an existing URL pointer changes to a different pointer.
