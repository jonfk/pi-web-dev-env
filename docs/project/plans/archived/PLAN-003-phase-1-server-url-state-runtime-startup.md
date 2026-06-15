# PLAN-003 Phase 1: Server URL State and Runtime Startup

Status: Superseded after implementation by PLAN-004 explicit runtime targets.

## Goal

Move session and cwd selection to a server-side URL state path that runs before Pi runtime creation. At the end of this phase, the server can accept `/ws?session=...`, `/ws?cwd=...`, `/ws`, or invalid combinations, and it can either create the correct initial runtime config or emit `invalid_url_state` without bootstrapping a fallback runtime.

Shared decisions and packet shape live in `PLAN-003-pi-webui-url-session-state.md`.

## Files To Add

- `pi-webui/src/server/cwd.ts`
- `pi-webui/src/server/session-info.ts`
- `pi-webui/src/server/url-state.ts`
- `pi-webui/src/server/url-session-startup.ts`
- `pi-webui/test/server-cwd.test.mjs`
- `pi-webui/test/server-url-state.test.mjs`
- `pi-webui/test/server-url-session-startup.test.mjs`

## Files To Update

- `pi-webui/src/server/index.ts`
- `pi-webui/CONTEXT.md` only if implementation introduces a new domain term. The current plan uses existing terms, so this should not be needed.

## Module Interfaces

### `src/server/cwd.ts`

Move the existing cwd policy out of `index.ts` without changing behavior.

```ts
export type CwdPolicy = {
  homeDir: string;
  allowAnyCwd: boolean;
};

export function expandTildePath(path: string, policy: CwdPolicy): string;
export function validateCwdTarget(target: string, policy: CwdPolicy): string;
export function isCwdReachable(resolved: string, policy: CwdPolicy): boolean;
export function listDirectories(target: string, policy: CwdPolicy): {
  path: string;
  entries: Array<{ name: string; path: string }>;
};
```

`validateCwdTarget` keeps the existing constraints: required, absolute after tilde expansion, exists, directory, inside `$HOME` unless `allowAnyCwd` is true.

### `src/server/session-info.ts`

Move session-list serialization out of `index.ts` so invalid URL state can reuse it without a runtime.

```ts
export function serializeSessionInfo(info: SessionInfo): SerializedSessionInfo;
export async function listSerializedSessions(args: {
  cwd: string;
  sessionDir?: string;
}): Promise<{
  currentProject: SerializedSessionInfo[];
  allProjects: SerializedSessionInfo[];
}>;
```

`listSerializedSessions` must call `SessionManager.list(cwd, sessionDir)` and `SessionManager.listAll()`.

### `src/server/url-state.ts`

Own only URL grammar and cwd URL validation.

```ts
export type InvalidUrlStateKind = "conflict" | "cwd" | "session" | "session_cwd";

export type ServerUrlState =
  | { kind: "new" }
  | { kind: "cwd"; cwd: string }
  | { kind: "session"; sessionPath: string }
  | { kind: "invalid"; invalidKind: "conflict" | "cwd" | "session"; value: string | null; message: string };

export function parseServerUrlState(searchParams: URLSearchParams, policy: CwdPolicy): ServerUrlState;
```

Rules:

- Use `searchParams.has("session")` and `searchParams.has("cwd")`; empty values are present and invalid.
- Both present returns `invalidKind: "conflict"` with `value: null`.
- `cwd` present calls `validateCwdTarget`. On success, return the resolved cwd.
- `session` present must be a non-empty absolute path. Do not check existence or read the file here.
- No params returns `{ kind: "new" }`.

### `src/server/url-session-startup.ts`

Own the URL state to initial session decision.

```ts
export type InvalidUrlStatePayload = {
  kind: InvalidUrlStateKind;
  value: string | null;
  message: string;
  defaultCwd: string;
  sessions: {
    currentProject: SerializedSessionInfo[];
    allProjects: SerializedSessionInfo[];
  };
};

export type InitialUrlSession =
  | { kind: "valid"; source: "new" | "cwd" | "session"; cwd: string; sessionManager: SessionManager }
  | { kind: "invalid"; payload: InvalidUrlStatePayload };

export async function resolveInitialUrlSession(args: {
  urlState: ServerUrlState;
  defaultCwd: string;
  sessionDir?: string;
  policy: CwdPolicy;
}): Promise<InitialUrlSession>;
```

Rules:

- For `new`, create `SessionManager.create(defaultCwd, sessionDir)` and return `source: "new"`.
- For `cwd`, create `SessionManager.create(urlState.cwd, sessionDir)` and return `source: "cwd"`.
- For an invalid parsed state, return `kind: "invalid"` with recovery data from `defaultCwd`.
- For `session`, validate before `SessionManager.open(...)`:
  - path is absolute;
  - path exists;
  - path is a file;
  - first line is readable JSON;
  - first line has `type: "session"`;
  - first line has non-empty string `id`;
  - first line has non-empty string `cwd`.
- Do not use Pi's `loadEntriesFromFile` behavior for URL validation because it silently returns `[]` for missing, empty, corrupt, or headerless files. Read only the first line in pi-webui for this precheck.
- Do not parse or validate the full session transcript in pi-webui. After the precheck, call `SessionManager.open(sessionPath, sessionDir)`.
- After `SessionManager.open(...)`, validate `sessionManager.getCwd()` with `validateCwdTarget`. If it fails, return `kind: "invalid"` with payload kind `session_cwd`.
- Never let a missing, empty, corrupt, or headerless URL Session Pointer reach `SessionManager.open(...)`.

## Implementation Sequence

Follow this order with one red-green loop at a time.

1. Extract cwd policy.
   - RED: add `server-cwd.test.mjs` coverage for valid cwd, missing path, file path, relative path, outside-home rejection, allow-any acceptance, tilde expansion, reachable ancestor listing.
   - GREEN: move `expandTilde`, `validateCwdTarget`, `isCwdReachable`, and `listDirectories` from `index.ts` to `cwd.ts`.
   - REFACTOR: update `index.ts` to create `const cwdPolicy = { homeDir: HOME_DIR, allowAnyCwd: ALLOW_ANY_CWD }` and call the new Module.

2. Add URL grammar.
   - RED: add `server-url-state.test.mjs` cases for no params, valid cwd, invalid cwd, valid absolute session path string, empty session, empty cwd, and `session` plus `cwd` conflict.
   - GREEN: implement `parseServerUrlState`.
   - REFACTOR: keep all URL param names in `url-state.ts`; `index.ts` should not read `session` or `cwd` params directly.

3. Add URL startup resolution.
   - RED: add tests using temp dirs and real JSONL files:
     - `new` returns `SessionManager.create(defaultCwd, sessionDir)`.
     - `cwd` returns a fresh manager whose header cwd is the requested cwd.
     - valid `session` returns a manager opened from the requested file and cwd from the session header.
     - missing session file returns invalid and the path is still missing afterward.
     - empty, corrupt, headerless, and missing-cwd files return invalid and file contents are unchanged.
     - stored cwd missing returns `session_cwd`.
     - invalid parsed state returns invalid with default-cwd session lists.
   - GREEN: implement `resolveInitialUrlSession`.
   - REFACTOR: if session serialization was still in `index.ts`, move it to `session-info.ts`.

4. Wire WebSocket startup.
   - Parse `req.url` in the `wss.on("connection")` handler and pass `parseServerUrlState(...)` into `NativePiSessionController`.
   - Change `NativePiSessionController` constructor to accept `urlState`.
   - In `init()`, compute `const defaultCwd = getInitialCwd()` first.
   - Call `resolveInitialUrlSession(...)`.
   - If invalid, set an internal invalid flag, send only `{ type: "invalid_url_state", payload }`, and return without creating runtime, binding a session, or sending `connected`.
   - If valid, create the runtime with:

```ts
this.runtime = await createAgentSessionRuntime(createRuntime, {
  cwd: resolved.cwd,
  agentDir,
  sessionManager: resolved.sessionManager,
});
```

5. Stop ready-time session switching.
   - Change `handleReady(lastSeq, sessionFile)` to `handleReady(lastSeq)`.
   - Remove `runtime.switchSession(sessionFile)` from `handleReady`.
   - In `handle`, read only `payload.lastSeq` for `ready`.
   - If the controller is in invalid URL state, `ready` is a no-op and any other inbound packet receives a failed `command_result` without touching `this.session`.

6. Keep cwd-switch behavior aligned.
   - `switchCwd(newCwd)` continues to use `SessionManager.create(newCwd, sessionDir)`.
   - Successful slash `/new` and `new_session` command results must include the active cwd, so Phase 2 can push `/?cwd=<cwd>`.
   - Successful `/cwd` and `/workspace` already return `cwd`; preserve that shape.

## Phase 1 Verification

Run:

```bash
npm test --prefix pi-webui
```

Manual smoke check after Phase 2 wiring exists, not during this phase:

- `/ws?session=<valid-file>` creates runtime in the session header cwd.
- `/ws?session=<missing-file>` emits `invalid_url_state` and creates no file.

## Phase 1 Done Criteria

- `index.ts` no longer owns cwd policy details or URL grammar.
- `ready` no longer accepts or switches by `sessionFile`.
- A valid URL Session Pointer determines cwd before `createAgentSessionRuntime(...)`.
- Invalid URL state emits the dedicated packet and no normal bootstrap packets.
- Missing, empty, corrupt, and headerless session files are not mutated.
