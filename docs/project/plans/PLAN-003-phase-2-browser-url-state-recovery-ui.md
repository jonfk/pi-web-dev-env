# PLAN-003 Phase 2: Browser URL State, Synchronization, and Recovery UI

## Goal

Replace browser active-session localStorage with browser URL state, connect to the server with URL state on `/ws`, sync meaningful session and cwd identity changes into browser history, and render blocking invalid URL recovery.

Shared decisions and packet shape live in `PLAN-003-pi-webui-url-session-state.md`.

## Files To Add

- `pi-webui/public/url-state.mjs`
- `pi-webui/public/invalid-url-state.mjs`
- `pi-webui/test/url-state.test.mjs`
- `pi-webui/test/invalid-url-state.test.mjs`

## Files To Update

- `pi-webui/public/app.js`
- `pi-webui/public/styles.css`
- `pi-webui/test/storage.test.mjs` renamed or replaced by `url-state.test.mjs`

## Files To Remove

- `pi-webui/public/storage.mjs`

Remove the file only after `app.js` no longer imports it.

## Module Interfaces

### `public/url-state.mjs`

This is the browser-side URL State Module. Keep URL and history decisions here rather than scattering them through `app.js`.

```js
export const URL_SESSION_PARAM = "session";
export const URL_CWD_PARAM = "cwd";

export function parseBrowserUrl(href);
export function buildWebSocketUrl(locationLike);
export function makeSessionUrl(sessionFile, href);
export function makeCwdUrl(cwd, href);
export function createBrowserUrlState({ location, history, reload });
```

`parseBrowserUrl(href)` returns:

```js
{ kind: "new" }
{ kind: "cwd", cwd }
{ kind: "session", sessionFile }
{ kind: "invalid", invalidKind: "conflict", value: null }
```

Browser parsing only identifies grammar conflict. Server validation owns absolute path, existence, and cwd policy errors.

`buildWebSocketUrl(locationLike)`:

- chooses `ws:` for `http:` and `wss:` for `https:`;
- targets `/ws` on the same host;
- copies only `session` and `cwd` params from the browser URL;
- copies both params when both are present so the server can return `invalid_url_state`;
- does not copy unrelated search params.

`makeSessionUrl` and `makeCwdUrl`:

- return a pathname of `/`;
- set exactly one URL param;
- rely on `URLSearchParams.set` for encoding absolute paths;
- drop unrelated params.

`createBrowserUrlState(...)` returns an object with:

```js
{
  current(),
  webSocketUrl(),
  installPopstateReload(),
  canonicalizeDisposableCwd(defaultCwd),
  syncDurableSession(sessionFile, options),
  markDisposablePromptSent(),
  promoteAcceptedDisposablePrompt(sessionFile),
  syncDisposableCwd(cwd),
  navigateToSession(sessionFile),
  navigateToCwd(cwd)
}
```

History rules:

- `canonicalizeDisposableCwd(defaultCwd)` uses `replaceState` only when the current URL is `{ kind: "new" }`.
- `promoteAcceptedDisposablePrompt(sessionFile)` uses `replaceState` only after `markDisposablePromptSent()` and only when current URL is `new` or `cwd`.
- `syncDurableSession(sessionFile)` is a no-op when current URL is invalid, when there is no session file, or when the current URL already points to the same session file.
- `syncDurableSession(sessionFile)` uses `pushState` when the current URL points to a different session.
- `syncDurableSession(sessionFile, { allowFromDisposable: true })` uses `pushState` when an explicit in-place command moved from `new` or `cwd` mode to a durable session.
- `syncDurableSession(sessionFile)` without `allowFromDisposable` is a no-op from `new` or `cwd` mode. This prevents initial disposable bootstrap from encoding an unprompted session file.
- `syncDisposableCwd(cwd)` uses `pushState` unless the current URL already points to that cwd.
- `navigateToSession` and `navigateToCwd` assign `window.location.href`; they do not use WebSocket slash commands.
- `installPopstateReload()` registers one `popstate` listener that calls `reload()`.

### `public/invalid-url-state.mjs`

Own the Invalid Session Message model and recovery action decisions.

```js
export function invalidUrlStateToChatItem(payload);
export function recoveryActionForInvalidUrlState(action, payload);
```

`invalidUrlStateToChatItem(payload)` returns an extra chat item:

```js
{
  kind: "invalid-url-state",
  title: "Could not open URL session" | "Could not open URL working directory",
  blocks: [{ type: "text", text }],
  actions: [
    { id: "new-session", label: "New session" },
    { id: "choose-session", label: "Choose session" }
  ]
}
```

Copy rules:

- `cwd` uses title `Could not open URL working directory`.
- all other invalid kinds use title `Could not open URL session`.
- body text uses `payload.message` exactly when present.
- append `\n\nPath: <payload.value>` only when `payload.value` is a non-empty string and the message does not already include it.

`recoveryActionForInvalidUrlState(action, payload)` returns:

```js
{ kind: "navigate-cwd", cwd: payload.defaultCwd }
{ kind: "choose-session", sessions: payload.sessions }
```

No generic clear-URL action exists.

## Implementation Sequence

Follow this order with one red-green loop at a time.

1. Replace the storage helper with URL state tests.
   - RED: replace `storage.test.mjs` coverage with `url-state.test.mjs` for parsing `session`, parsing `cwd`, no-param disposable state, conflict, encoded absolute paths, `buildWebSocketUrl`, `makeSessionUrl`, and `makeCwdUrl`.
   - GREEN: add `public/url-state.mjs`.
   - REFACTOR: remove `public/storage.mjs` only after `app.js` is updated.

2. Add browser history behavior.
   - RED: add `url-state.test.mjs` cases for:
     - no params to cwd canonicalization uses replace;
     - first accepted prompt from cwd mode to session mode uses replace;
     - existing session to different session uses push;
     - same session is no-op;
     - invalid current URL is no-op;
     - cwd switch uses push;
     - Back/Forward installs reload.
   - GREEN: implement `createBrowserUrlState(...)` with a fakeable `location`, `history`, and `reload`.
   - REFACTOR: keep the state tracker small; do not let `app.js` duplicate history rules.

3. Wire WebSocket URL startup.
   - In `app.js`, replace the `storage.mjs` import with `url-state.mjs`.
   - Create one URL state tracker near the top-level app state.
   - `connect()` must call `urlState.webSocketUrl()` and pass that to `new WebSocket(...)`.
   - On WebSocket `open`, send `{ type: "ready", lastSeq }` only.
   - Remove `loadStoredSessionFile`, `saveStoredSessionFile`, and `extractSessionFileFromState` usage.
   - On `connected`, call `urlState.canonicalizeDisposableCwd(packet.payload.cwd)`.

4. Wire durable and disposable URL sync.
   - On `session_state`, update `currentSessionState` and call `urlState.syncDurableSession(next.sessionFile)`. The Module must no-op from disposable URL modes unless explicitly allowed.
   - When a plain prompt is sent from `new` or `cwd` URL mode, call `urlState.markDisposablePromptSent()`.
   - On successful `command_result` for `prompt`, call `urlState.promoteAcceptedDisposablePrompt(currentSessionState?.sessionFile)`.
   - On successful slash `/cwd` or `/workspace`, call `urlState.syncDisposableCwd(data.cwd)` before showing the toast.
   - On successful slash `/new` or `new_session`, call `urlState.syncDisposableCwd(data.cwd)`.
   - For typed slash `/resume <path>`, `/import`, `/clone`, and `/fork`, rely on successful command completion plus the latest `currentSessionState.sessionFile` to call `urlState.syncDurableSession(currentSessionState.sessionFile, { allowFromDisposable: true })`.

5. Make session picker selections URL navigation.
   - Change `showSessionPicker(payload)` so selecting an item calls `urlState.navigateToSession(item.path)`.
   - Do not send `/resume` from picker selection.
   - Keep typed `/resume <path>` as an in-place slash command.
   - Preserve the existing current-project/all-project scope behavior from the prior resume work.

6. Add invalid URL state model tests.
   - RED: add `invalid-url-state.test.mjs` cases for title selection, message body path inclusion, New session action, Choose session action, and empty session lists.
   - GREEN: implement `public/invalid-url-state.mjs`.

7. Render invalid URL state.
   - Add `let invalidUrlState = null` in `app.js`.
   - On `invalid_url_state` packet:
     - set `invalidUrlState`;
     - reset chat history to empty;
     - append the item from `invalidUrlStateToChatItem(payload)` to `chatState.streamExtras`;
     - disable `input` and `sendButton`;
     - add a visible disabled state class to the composer;
     - render log and status;
     - do not call any URL sync function.
   - In the submit handler, return immediately when `invalidUrlState` is set.
   - In `buildMessageElement` or the extra-item rendering path, append `.message-actions` buttons when an item has `actions`.
   - On Invalid Session Message button click:
     - `new-session` uses `urlState.navigateToCwd(payload.defaultCwd)`;
     - `choose-session` calls `showSessionPicker({ currentSessionFile: null, sessions: payload.sessions })`.

8. Style invalid actions.
   - Add minimal styles for `.message.invalid-url-state` if needed and `.message-actions`.
   - Use existing button visual language. Do not create a page-level empty state.
   - Composer disabled state must make the blocked input obvious without hiding the bad URL or the message.

## Phase 2 Verification

Run:

```bash
npm test --prefix pi-webui
```

Manual browser checks:

- Open `/`; confirm it becomes `/?cwd=<resolved cwd>` after connect and does not become `?session=...`.
- Send the first prompt; after it finishes, confirm the URL becomes `/?session=<session jsonl path>` with replace behavior.
- Open two tabs with different session URLs and confirm reload keeps each tab's session.
- Use `/cwd <path>` and `/workspace <name>`; confirm URL becomes `/?cwd=<path>`.
- Use `/new`; confirm URL becomes `/?cwd=<current cwd>`.
- Open a missing session URL; confirm the bad URL remains, the composer is disabled, and New session and Choose session work.
- Use Back and Forward after session and cwd switches; confirm the page reloads into the URL state.

## Phase 2 Done Criteria

- Browser no longer imports or writes active-session localStorage.
- Browser connects to `/ws` with `session` or `cwd` params copied from the page URL.
- URL history follows the PRD rules through `public/url-state.mjs`.
- Invalid URL state is rendered as a blocking Invalid Session Message in the transcript.
- Recovery actions navigate rather than mutating a nonexistent invalid runtime.
- Existing input history and debug localStorage still work.
