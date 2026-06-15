# PLAN-005: pi-webui @ File Completion

Status: Implemented.

## Source Material

- Prototype handoff: `docs/project/handoffs/2026-05-31-pi-webui-at-file-completion-prototypes-handoff.md`
- Client entry point: `pi-webui/public/app.js`
- Existing input router: `pi-webui/public/route-input.mjs`
- Server websocket controller: `pi-webui/src/server/index.ts`
- Prototype modules: `pi-webui/prototypes/*at-file*`, `pi-webui/prototypes/*file-completion*`
- Pi TUI reference source: `vendored/pi/packages/tui/src/autocomplete.ts`
- Pi TUI behavior tests: `vendored/pi/packages/tui/test/autocomplete.test.ts`

Use the handoff as the evidence trail. This plan is the implementation checklist.

## Goal

Add `@` file completion to the pi-webui composer. The browser detects an `@` file token at the cursor, asks the backend for file and directory matches over the existing websocket, renders a dedicated file completion menu, and inserts the selected ready-to-use path while preserving Pi TUI path semantics.

## Locked Decisions

- Copy or adapt Pi TUI behavior into pi-webui. Do not import from vendored Pi.
- Use websocket request/response, not HTTP.
- The frontend sends the user-visible `prefix`.
- The backend uses executable name exactly `fd`; do not resolve `fdfind` for v1.
- Return both files and directories.
- Missing `fd`, timeout, and unexpected backend errors log server-side and return `[]`.
- Do not add an `error` field to `file_completion_result`.
- Use a `100ms` frontend debounce.
- Add a backend search timeout for process hygiene.
- Use a dedicated `#file-completion-menu` element.
- Keep file completion state separate from slash completion state.
- Do not refactor slash completion into a general completion system in this plan.

## Shared Behavior

- `@` file completion works anywhere in prompt text where Pi TUI token boundaries allow it.
- `foo@src` does not open file completion.
- Selected text suppresses file completion unless the selection is collapsed.
- Relative input stays relative in returned values and descriptions.
- Absolute input stays absolute in returned values and descriptions.
- `../` input preserves the user-visible `../` form.
- `@~/` expands to the user's home directory only for backend search.
- `@~/` results preserve the user-visible `~/` form in values and descriptions.
- Bare `@~` does not get special v1 behavior unless implementation confirms Pi TUI parity requires it.
- Paths with spaces are quoted in inserted values.
- File completion insertion adds a trailing space.
- Directory completion insertion ends with `/` and does not add a trailing space.
- Quoted directory completion leaves the cursor before the closing quote.
- Existing closing quotes are not duplicated.
- Hidden files are included.
- `.git` is excluded.
- Symlinks follow Pi TUI behavior.

## Protocol

Client request:

```js
{ type: "file_completion_request", requestId, prefix }
```

Server response:

```js
{ type: "file_completion_result", payload: { requestId, prefix, items } }
```

Item shape:

```js
{
  insertText,
  label,
  description,
  isDirectory,
  addsTrailingSpace,
  cursorOffset,
  replaceFollowingText
}
```

`insertText` is ready to insert, including leading `@`, quotes when needed, and trailing `/` for directories. `addsTrailingSpace`, `cursorOffset`, and optional `replaceFollowingText` make insertion behavior explicit so the frontend does not infer cursor or quoting semantics from the string shape.

## Phase Split

1. Backend contract and search.
2. Frontend controller and menu.

Backend goes first because it fixes the protocol and item shape. Frontend should then be a thin consumer of a stable contract.

## Phase 1: Backend Contract And Search

### Files To Add

- `pi-webui/src/server/file-completion.ts`
- `pi-webui/test/server-file-completion.test.mjs`

Optional if the websocket controller logic grows too large:

- `pi-webui/src/server/file-completion-controller.ts`
- `pi-webui/test/server-file-completion-controller.test.mjs`

### Files To Update

- `pi-webui/src/server/index.ts`
- `pi-webui/package.json` if new focused test scripts are useful

### Backend Interface Sketch

```ts
export async function searchFileCompletions({
  cwd,
  homeDir,
  prefix,
  signal,
  limit,
  timeoutMs,
  logger,
}): Promise<FileCompletionItem[]>;
```

The exact types can change. The important constraints are:

- `cwd` is the current runtime cwd.
- `homeDir` is the server user's home directory.
- `prefix` includes the leading `@` and is the same string the user sees.
- `signal` cancels spawned work.
- `timeoutMs` aborts a slow `fd` search.
- normal no-match and inaccessible-path cases return `[]` without client-visible errors.

### Backend Implementation Sequence

1. Lift the validated backend prototype shape into `src/server/file-completion.ts`.
2. Parse user-visible prefixes into:
   - search base directory;
   - display base;
   - query;
   - quoted-prefix state;
   - path mode: relative, absolute, parent-relative, or home-relative.
3. Implement `@~/` by expanding `~/` to `homeDir` for search only.
4. Spawn `fd` with executable name `fd`.
5. Include files, directories, hidden paths, and symlinks according to Pi TUI parity.
6. Exclude `.git`.
7. Normalize `fd` output before appending directory slashes, because `fd` may already emit directories with `/`.
8. Build insert-ready values and user-visible descriptions from the original path mode.
9. Return `[]` and log server-side for missing `fd`, timeout, abort, and unexpected spawn failures.
10. Add one active search slot to each `NativePiSessionController`.
11. Handle `file_completion_request` before the generic unknown-command branch.
12. On new request, abort the previous websocket-local search before starting the next.
13. On websocket close, abort the active search.
14. Emit a result only when the saved slot is still current, the signal is not aborted, and the websocket is open.

### Backend Verification

- Bare `@` returns files and directories.
- `@src`, `@src/`, and nested relative prefixes preserve relative values.
- `@../sibling/path` searches the parent-relative target and preserves `../` output.
- Absolute prefixes preserve absolute output.
- `@~/project` searches under `homeDir` and returns `@~/project...`.
- Quoted `@"my folder/s"` returns values such as `@"my folder/space file.txt"`.
- Hidden paths are included.
- `.git` contents are excluded.
- Directories have exactly one trailing `/`.
- Missing `fd` logs and returns `[]`.
- Search timeout logs and returns `[]`.
- Aborted searches do not emit stale websocket results.
- Replacing `req-1` with `req-2` emits only `req-2`.
- Socket close aborts current work and suppresses late results.

## Phase 2: Frontend Controller And Menu

### Files To Add

- `pi-webui/public/file-completion-controller.mjs`
- `pi-webui/test/file-completion-controller.test.mjs`

### Files To Update

- `pi-webui/public/app.js`
- `pi-webui/public/index.html`
- `pi-webui/public/styles.css`
- `pi-webui/test/route-input.test.mjs` only if input routing changes are required

### Frontend Controller Responsibilities

- Detect the current `@` completion context from textarea text plus cursor offset.
- Suppress completion when there is no valid context or the selection is not collapsed.
- Debounce requests by `100ms`.
- Send `{ type: "file_completion_request", requestId, prefix }`.
- Track the current request id.
- Ignore stale result packets.
- Re-check the current textarea context before opening the menu from a result.
- Apply selected completion through a pure replacement helper.
- Keep file completion state independent from slash completion state.

### Frontend Integration Sequence

1. Add `#file-completion-menu` to the composer DOM.
2. Add menu styling that can reuse slash menu visual conventions without sharing slash state or DOM.
3. Add `findAtCompletionContext(...)` and `applyAtCompletion(...)` in the controller module.
4. Instantiate the file completion controller in `app.js`.
5. On input events, resize the composer, update slash menu as today, and notify file completion.
6. Route `file_completion_result` packets from the websocket message switch to the controller.
7. Call `fileCompletionController.handleKeydown(event)` before slash/history/submit key handling.
8. While the file menu is open, consume:
   - `ArrowDown`;
   - `ArrowUp`;
   - `Tab`;
   - `Enter` when not composing and not Shift+Enter;
   - `Escape`.
9. Leave slash completion, history navigation, prompt submit, and abort behavior unchanged when the file menu is closed.
10. Hide the file menu on blur, context loss, stale result, successful apply, and socket disconnect.

### Frontend Verification

- Typing `hello @src` sends one debounced request after `100ms`.
- Typing `foo@src` sends no request.
- Typing `@"my folder/te"` sends the quoted prefix.
- Multiline textarea cursor offsets detect only the current line token.
- Selected range sends no request.
- Stale results are ignored.
- Result for an outdated prefix is ignored after the user keeps typing.
- `Tab` applies the selected file item while file menu is open.
- `Enter` applies the selected file item while file menu is open and does not submit.
- `Escape` closes only the file menu when it is open.
- Slash completion still owns `/mo` and `Tab` when file menu is closed.
- History navigation still works at textarea boundaries when file menu is closed.
- File insertion adds trailing space.
- Directory insertion does not add trailing space.
- Quoted directory insertion places the cursor before the closing quote.

## Cross-Phase Validation

Run:

```bash
npm test --prefix pi-webui
```

Also perform one browser smoke test against a real workspace:

- Start pi-webui.
- Type `@` and confirm files/directories appear.
- Type `@src` and confirm results narrow.
- Type `@"my folder/` in a workspace with spaces and confirm quoted insertion.
- Type `@~/` and confirm home-relative suggestions insert as `@~/...`.
- Rapidly type several prefixes and confirm stale results do not flash into the menu.
- Confirm slash completion still works.
- Confirm prompt submit still works after applying a file completion.

## Out Of Scope

- General completion abstraction.
- HTTP endpoint.
- `fzf`.
- `fdfind` resolution.
- Client-visible backend error reporting for file completion.
- File preview or metadata beyond the explicit insertion contract fields.
- Polished redesign of the composer beyond the dedicated file completion menu.

## Done Criteria

- Backend search returns insert-ready file completion items over websocket.
- `@~/` searches home and preserves user-visible `~/` output.
- Backend errors, missing `fd`, timeout, and abort are quiet in the client and logged server-side.
- Each websocket has at most one active file completion search.
- Stale backend and frontend results are suppressed.
- Frontend menu is separate from slash completion state.
- Keyboard precedence is correct for file completion, slash completion, history, submit, and abort.
- Tests cover parser/replacer, backend search behavior, cancellation/stale suppression, and frontend controller precedence.
