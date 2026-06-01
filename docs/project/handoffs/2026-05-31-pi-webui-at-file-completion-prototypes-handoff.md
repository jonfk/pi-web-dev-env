# pi-webui @ File Completion Prototype Handoff

Date: 2026-05-31

## Goal

Continue the `pi-webui` `@` file completion design by prototyping the uncertain implementation pieces before committing to the final frontend/backend shape.

No implementation has been done yet. The next step is investigation/prototyping to verify assumptions around token parsing, replacement, backend `fd` search, cancellation, websocket request shape, and frontend controller integration.

## References

- Client entry point: `pi-webui/public/app.js`
- Existing slash/input routing helper: `pi-webui/public/route-input.mjs`
- Server websocket controller: `pi-webui/src/server/index.ts`
- Pi TUI autocomplete source to adapt, not import: `vendored/pi/packages/tui/src/autocomplete.ts`
- Pi TUI autocomplete behavior tests: `vendored/pi/packages/tui/test/autocomplete.test.ts`

Important Pi TUI source areas:

- Token delimiters and `@` boundary behavior: `vendored/pi/packages/tui/src/autocomplete.ts:7`
- Quoted prefix handling: `vendored/pi/packages/tui/src/autocomplete.ts:54`
- Path prefix parsing and completion value quoting: `vendored/pi/packages/tui/src/autocomplete.ts:94`
- `fd` invocation and process cancellation: `vendored/pi/packages/tui/src/autocomplete.ts:123`
- `@` suggestion path: `vendored/pi/packages/tui/src/autocomplete.ts:290`
- `@` completion application: `vendored/pi/packages/tui/src/autocomplete.ts:404`
- Scoped fuzzy query and result display path handling: `vendored/pi/packages/tui/src/autocomplete.ts:518`
- Fuzzy search/scoring: `vendored/pi/packages/tui/src/autocomplete.ts:716`
- Behavior tests for `@` completion: `vendored/pi/packages/tui/test/autocomplete.test.ts:117`

## Decisions So Far

- `@` file completion should work anywhere in a prompt, matching Pi TUI token boundary and replacement behavior.
- Copy/adapt the relevant Pi TUI logic into pi-webui. Do not import it from vendored Pi.
- Use directories and files in results.
- Match Pi TUI semantics for relative paths, absolute paths, `../`, `~/`, hidden files, `.git` exclusion, symlinks, quoting, and directory/file insertion.
- Handle `@~/` with parity to Pi TUI: expand `~/` to the user's home directory only for backend search, but preserve the user-visible `~/` form in inserted values and descriptions. Do not add special v1 behavior for bare `@~` unless it is explicitly chosen as a pi-webui difference.
- Relative input should stay relative. Absolute input should stay absolute.
- Use a new frontend completion controller with state separate from the existing slash completion state.
- Use websocket request/response, not a separate HTTP endpoint.
- Use protocol option A: frontend sends the user-visible `prefix`.
- Use `fd` as the executable name. Do not resolve `fdfind` for v1.
- Missing `fd` should return empty results and log an error on the backend.
- Keep v1 ranking and limits simple. Start close to Pi TUI behavior unless prototyping shows a reason to simplify further.
- For a given websocket, allow only one active file search. Starting a new search cancels the previous one.

## Proposed Protocol Shape

Client request:

```js
{ type: "file_completion_request", requestId, prefix }
```

Server response:

```js
{ type: "file_completion_result", payload: { requestId, prefix, items } }
```

Suggested item shape:

```js
{ value, label, description, isDirectory }
```

`value` should be ready to insert, including the leading `@`, quotes where needed, and trailing slash for directories. The frontend still owns final replacement and trailing-space behavior.

## Prototype 1: Pure Text Parser/Replacer

Create or sketch a browser-compatible pure module before touching DOM wiring.

Suggested shape:

```js
findAtCompletionContext(text, cursorIndex)
applyAtCompletion(text, cursorIndex, context, item)
```

This should adapt Pi TUI logic from line/column-oriented code to full textarea text plus a cursor offset. Do not convert textarea text into line/column form unless a prototype proves that is cleaner.

Questions to verify:

- `hello @src` detects `@src`.
- `foo@src` does not detect a completion context.
- `@"my folder/te"` detects a quoted `@` context.
- multi-line textarea text works through cursor offsets.
- file completion adds a trailing space.
- directory completion keeps the cursor in the right place and does not add a trailing space.
- quoted replacement does not duplicate an existing closing quote.
- selected text/range behavior is clear; likely suppress completion unless the selection is collapsed.

Good tests to adapt are in `vendored/pi/packages/tui/test/autocomplete.test.ts:391` and `vendored/pi/packages/tui/test/autocomplete.test.ts:409`.

## Prototype 2: Backend `fd` Wrapper

Prototype the backend search outside `index.ts`, likely as the beginning of `pi-webui/src/server/file-completion.ts`.

Suggested shape:

```js
searchFileCompletions({ cwd, prefix, signal, limit })
```

The wrapper should parse the `prefix`, spawn `fd`, and return ready-to-insert completion items.

Verify:

- executable name is exactly `fd`;
- missing `fd` logs a backend error and returns `[]`;
- bare `@` returns files and directories;
- directories end in `/`;
- paths with spaces return quoted values such as `@"my folder/"`;
- relative, absolute, `~/`, and `../` inputs preserve their user-visible form;
- `@~/` searches from the server home directory while returning insert-ready values such as `@~/project/` or `@"~/my folder/"`;
- hidden files are included;
- `.git` is excluded;
- symlinks match Pi TUI behavior.

Keep normal no-match and inaccessible-path cases quiet in the client. Unexpected backend failures should be logged server-side.

## Prototype 3: One Active Search Per Websocket

Prototype cancellation with a fake async searcher before relying on real `fd`.

Desired controller behavior:

- Each websocket/controller stores one active file completion search.
- A new `file_completion_request` aborts the previous search.
- Socket close aborts the current search.
- Only the still-current `requestId` can emit a result.
- Races between abort and process close do not send stale results.

Pi TUI kills the spawned `fd` process on abort with `SIGKILL`; see `vendored/pi/packages/tui/src/autocomplete.ts:177`. Use that as the starting point unless prototyping shows a better reason to use `SIGTERM`.

## Prototype 4: Websocket Contract

Add only enough server/client plumbing to prove request/result flow.

Server-side placement:

- `pi-webui/src/server/index.ts` should only dispatch the websocket message and manage the per-controller active search slot.
- Search/parsing logic should live outside `index.ts`, likely `pi-webui/src/server/file-completion.ts`.

Client-side placement:

- Keep `pi-webui/public/app.js` as the integration point.
- Put the new controller in a separate module, likely `pi-webui/public/file-completion-controller.mjs` or similar.

The frontend should ignore result packets whose `requestId` is no longer current.

## Prototype 5: Frontend Controller Integration

Prototype keyboard and menu precedence without doing a slash completion refactor.

Expected behavior:

- File completion has separate state from slash completion.
- If there is no `@` context at the cursor, the controller does nothing.
- If the file completion menu is open, it handles arrow keys, `Tab`, `Enter`, and `Escape`.
- `Tab` accepts the selected completion.
- `Enter` accepts the selected completion while the menu is open.
- `Escape` closes the file completion menu.
- History navigation and prompt submit should not run for key events consumed by the file completion controller.
- Slash completion should remain otherwise unchanged.

Suggested integration shape:

```js
if (fileCompletionController.handleKeydown(event)) return;
```

Call this before the existing slash/history/submit key handling in `app.js`.

## Open Details For The Prototype To Resolve

- Whether the file completion menu can reuse existing slash menu styling or should get its own element and CSS.
- Exact debounce interval; start simple, around 75-150 ms, and adjust after latency is observed.
- Whether the server should include an `error` field in `file_completion_result` for debugging, while still keeping the client UX quiet.
- Whether to add a search timeout as process hygiene.
- What minimal tests give confidence without needing heavy DOM tests.

## Suggested Order

1. Pure text parser/replacer prototype and tests.
2. Backend `fd` wrapper prototype and temp-directory tests.
3. Cancellation prototype with fake searcher, then smoke-test with real `fd`.
4. Minimal websocket request/result contract.
5. Frontend controller/menu integration.

## Out Of Scope For The Prototype Pass

- Do not refactor slash completion into a general completion system yet.
- Do not add `fzf`; use `fd` only for v1.
- Do not import Pi TUI autocomplete code from the vendored package.
- Do not add an HTTP API unless the websocket prototype uncovers a concrete blocker.
- Do not implement final polished UI before the pure parsing/search/cancellation assumptions are verified.
