# Explicit Cwd Selection Handoff

Date: 2026-05-29

## Goal

Remove places where `pi-webui` or adjacent first-party code silently chooses a working directory when the user, URL, session file, or explicit configuration did not provide a clear cwd.

The desired behavior is fail-loud or blocked-startup behavior:

- If a cwd is required and no cwd is clear, do not create an agent runtime.
- Show/select an explicit cwd instead of using `process.cwd()`, install directories, or a generic default.
- If a session claims a cwd that is missing or invalid, do not silently fall back to another cwd.

This handoff is investigative only. No code changes were made.

## Key Finding

`pi-webui` has a direct initial-cwd fallback to `process.cwd()`, and the Docker entrypoint for `pi-webui` changes the process cwd to `/opt/pi-webui`.

That explains how a production deployment can start a session in `/opt/pi-webui`:

1. `docker/entrypoint.sh` handles `pi-webui` by running `cd /opt/pi-webui`.
2. `pi-webui` starts with process cwd `/opt/pi-webui`.
3. If `${PI_AGENT_DIR}/workspaces.json` has no `lastCwd`, `getInitialCwd()` returns `resolve(process.cwd())`.
4. Later successful commands call `setLastCwd(agentDir, ctrl.runtime.cwd)`, which can persist `/opt/pi-webui` as the remembered cwd.

## pi-webui Fallbacks

### Initial server cwd falls back to process cwd

File: `pi-webui/src/server/index.ts`

Code:

```ts
function getInitialCwd() {
  const registry = loadWorkspaceRegistry(agentDir);
  if (!registry.lastCwd) return resolve(process.cwd());
  return validateCwdTarget(registry.lastCwd);
}
```

Impact:

- Blank `/` and missing URL state call `getInitialCwd()` before runtime creation.
- If `lastCwd` is absent, the server process cwd becomes the agent cwd.
- In Docker production, the process cwd is currently `/opt/pi-webui` because of the entrypoint.

Suggested removal:

- Replace this with an explicit "no cwd selected" state when `lastCwd` is absent.
- Do not construct `createAgentSessionRuntime(...)` until the client chooses a cwd or the URL provides `?cwd=<absolute-path>`.
- If keeping an env-configured default is desired, make it explicit and named for `pi-webui`, for example `PI_WEBUI_CWD`, and validate it. Do not use `process.cwd()` as a fallback.

### Missing URL state becomes a disposable session in default cwd

File: `pi-webui/src/server/url-session-startup.ts`

Code path:

```ts
if (urlState.kind === "new") {
  return {
    kind: "valid",
    source: "new",
    cwd: defaultCwd,
    sessionManager: SessionManager.create(defaultCwd, sessionDir),
  };
}
```

Impact:

- `/` with no `session` or `cwd` creates a valid runtime using `defaultCwd`.
- Because `defaultCwd` currently comes from `getInitialCwd()`, this inherits the `process.cwd()` fallback.

Suggested removal:

- Change `resolveInitialUrlSession` so `urlState.kind === "new"` can return a "needs cwd selection" result when there is no explicit persisted/configured cwd.
- Keep `?cwd=<absolute-path>` as the explicit disposable-session path.

### Invalid URL recovery uses `defaultCwd`

File: `pi-webui/src/server/url-session-startup.ts`

Code path:

```ts
sessions: await listSerializedSessions({
  cwd: args.defaultCwd,
  sessionDir: args.sessionDir,
}),
```

Impact:

- Even invalid URL state requires a `defaultCwd` to populate recovery session lists and the "New session" action.
- This can force computing a cwd even when the URL/session is invalid.

Suggested removal:

- Let invalid URL state carry `defaultCwd?: string` instead of requiring one.
- When no explicit default exists, recovery should offer cwd selection and maybe "Choose session" from all projects only.
- Do not let invalid `?cwd` or invalid `?session` fall back into a new runtime.

### Browser invalid-state recovery navigates to `payload.defaultCwd`

File: `pi-webui/public/invalid-url-state.mjs`

Code path:

```js
return { kind: "navigate-cwd", cwd: payload.defaultCwd };
```

Impact:

- The client assumes invalid URL recovery always has a concrete default cwd.

Suggested removal:

- Support a recovery action like `select-cwd` when `defaultCwd` is absent.
- Only navigate to `/?cwd=...` when the server provided an explicit, validated cwd.

### `lastCwd` is persisted after many commands

File: `pi-webui/src/server/index.ts`

Examples:

- `/new`
- `/import`
- `/clone`
- `/fork`
- `/resume`
- `new_session`
- `switch_session`
- `switchCwd(...)`
- generic `runCommand(...)`

Impact:

- Once a fallback cwd is used, it can be written to `workspaces.json:lastCwd`.
- This makes the fallback durable and harder to identify later.

Suggested removal:

- After removing fallback startup, only persist `lastCwd` when cwd came from an explicit source: URL cwd, chosen workspace, chosen cwd picker entry, or trusted session header.
- Consider tagging/structuring startup source internally so accidental defaults cannot be persisted.

## Docker / Deployment Cwd Trap

### Entrypoint overrides compose working_dir for pi-webui

File: `docker/entrypoint.sh`

Code:

```bash
pi-webui)
  shift
  cd /opt/pi-webui
  exec node dist/server/index.js "$@"
  ;;
```

Impact:

- `docker/docker-compose.yml` says `working_dir: /workspace` for `pi-webui`, but this `cd` runs after container startup.
- Any `process.cwd()` fallback inside `pi-webui` resolves to `/opt/pi-webui`.

Suggested removal:

- Run the server by absolute path without changing cwd:

```bash
exec node /opt/pi-webui/dist/server/index.js "$@"
```

- If static/public path resolution needs package-root behavior, keep that based on `import.meta.url`, not process cwd. `pi-webui` already resolves `publicDir` from `import.meta.url`.

### `PI_PROJECT_CWD` is configured but unused by pi-webui

Files:

- `docker/docker-compose.yml`
- `docker/Dockerfile`
- `pi-webui/ROADMAP.md`

Impact:

- Docker sets `PI_PROJECT_CWD: /workspace`, and the roadmap claims this override exists.
- Current `pi-webui/src/server/index.ts` does not read `PI_PROJECT_CWD`.
- This gives a false sense that `/workspace` is the configured default.

Suggested decision:

- Either remove/document `PI_PROJECT_CWD` as unsupported for `pi-webui`, or intentionally support an explicit env default.
- Recommendation: prefer a `pi-webui`-specific name such as `PI_WEBUI_CWD` if an env default remains. Avoid overloading Pi CLI/project semantics.

## pipane Fallbacks

These are adjacent, not necessarily part of the first `pi-webui` cleanup, but they follow the same implicit-cwd pattern.

### Server default cwd falls back to process cwd

File: `pipane/src/server/server.ts`

Code:

```ts
const PI_CWD = process.env.PI_CWD || process.cwd();
```

Impact:

- If `PI_CWD` is not set, `pipane` uses whatever directory started the server.
- This default feeds `WsHandler.defaultCwd`, prewarming, and fallback process spawning.

Suggested removal:

- Require `PI_CWD` or add an explicit no-cwd selection flow for new sessions.
- In Docker, `PI_CWD` is already set to `/workspace`, so production compose is clearer for `pipane` than `pi-webui`.

### New session prompt falls back to default cwd

File: `pipane/src/server/ws-handler.ts`

Code:

```ts
if (sessionPath === "__new__") {
  const cwd = command.cwd as string || this.defaultCwd;
  proc = await this.acquireProcess(cwd);
  ...
}
```

Impact:

- A client can request a new session without cwd, and the server silently uses `defaultCwd`.

Suggested removal:

- Require `command.cwd` for `__new__`, or return a typed error that the client turns into cwd selection.

### Fork prompt falls back when source session cwd is missing

File: `pipane/src/server/ws-handler.ts`

Code:

```ts
const forkCwd = getSessionCwd(sessionPath);
const cwd = (forkCwd && existsSync(forkCwd)) ? forkCwd : this.defaultCwd;
```

Impact:

- Forking a session whose header cwd is absent/deleted silently runs in `defaultCwd`.

Suggested removal:

- Treat missing/deleted source cwd as an error or require an explicit replacement cwd in the fork command.

### Existing session attach falls back when session cwd is missing

File: `pipane/src/server/ws-handler.ts`

Code:

```ts
const sessionCwd = getSessionCwd(sessionPath);
const cwd = (sessionCwd && existsSync(sessionCwd)) ? sessionCwd : this.defaultCwd;
```

Impact:

- Opening an existing session with missing/deleted cwd silently attaches it to `defaultCwd`.

Suggested removal:

- Fail and expose a recovery flow asking for replacement cwd.
- If replacement is chosen, pass it explicitly and consider whether the session file should be migrated or only opened with an override.

### Generic process operations spawn in default cwd

File: `pipane/src/server/ws-handler.ts`

Code:

```ts
let proc = this.pool.getAny(this.getUnavailableProcesses());
if (!proc) {
  proc = this.pool.spawn(this.defaultCwd);
}
```

Impact:

- Commands like model/default-model/command listing can create a Pi process in `defaultCwd` even without a user-selected cwd.

Suggested removal:

- Split cwd-independent operations from cwd-bound Pi processes if possible.
- If Pi requires cwd for these operations, require an explicit selected cwd before spawning.

## Vendored Pi Fallbacks To Account For

These are vendored reference code. Do not patch vendored code as part of a focused first-party change unless intentionally updating the vendored subtree. The important point is that callers must pass explicit cwd/sessionManager so these defaults are not reached.

### SDK createAgentSession defaults to process cwd

File: `vendored/pi/packages/coding-agent/src/core/sdk.ts`

Code:

```ts
const cwd = resolvePath(options.cwd ?? options.sessionManager?.getCwd() ?? process.cwd());
const sessionManager = options.sessionManager ?? SessionManager.create(cwd, getDefaultSessionDir(cwd, agentDir));
```

Impact:

- Any first-party caller that uses `createAgentSession()` or `createAgentSessionServices()` without cwd can inherit process cwd.

Suggested guardrail:

- In first-party `pi-webui`, keep constructing runtimes only after an explicit cwd is known, and always pass both `cwd` and `sessionManager`.

### SessionManager.open falls back to process cwd if header cwd is absent

File: `vendored/pi/packages/coding-agent/src/core/session-manager.ts`

Code:

```ts
const cwd = cwdOverride ?? header?.cwd ?? process.cwd();
```

Impact:

- Opening a session file without a valid header cwd can silently use process cwd.
- `pi-webui` currently prevalidates URL session files so headerless/missing-cwd files are invalid before `SessionManager.open(...)`.

Suggested guardrail:

- Keep or strengthen first-party prevalidation before `SessionManager.open(...)`.
- For explicit recovery from missing cwd, pass a user-chosen `cwdOverride`; do not rely on this fallback.

### SessionManager.inMemory defaults to process cwd

File: `vendored/pi/packages/coding-agent/src/core/session-manager.ts`

Code:

```ts
static inMemory(cwd: string = process.cwd()): SessionManager
```

Impact:

- Any in-memory runtime created without cwd inherits process cwd.

Suggested guardrail:

- Search first-party code for `SessionManager.inMemory()` before using in pi-webui. Current hits are vendored Pi CLI paths, not `pi-webui`.

### Pi CLI intentionally offers current-cwd fallback for missing session cwd

Files:

- `vendored/pi/packages/coding-agent/src/core/session-cwd.ts`
- `vendored/pi/packages/coding-agent/src/main.ts`
- `vendored/pi/packages/coding-agent/src/modes/interactive/interactive-mode.ts`

Impact:

- The TUI has a user-confirmed flow for "session cwd missing; continue in current cwd".
- That is different from silent server fallback, but it is still a cwd replacement path.

Suggested guardrail:

- If `pi-webui` adds missing-session-cwd recovery, model it as explicit user selection/confirmation, not as an automatic default.

## Existing TODO Context

`TODO.md` already has a matching `pi-webui` note:

```md
## No cwd state. picker fallback

Start pi-webui without an agent runtime when no persisted `lastCwd` or valid session cwd exists.

- Add an explicit “no cwd selected” server/client state.
- Disable agent commands until a cwd is selected.
- Let the user pick/add a cwd from the UI.
- Create the runtime only after cwd selection.
- Persist the selected cwd as `lastCwd`.
- Remove the `process.cwd()` startup fallback once this flow exists.
```

This handoff expands that TODO into the concrete fallback inventory.

## Recommended First Implementation Slice

1. Add an explicit server startup result for "needs cwd" in `pi-webui`.
2. Change `getInitialCwd()` so absence of `lastCwd` returns no cwd instead of `process.cwd()`.
3. Change WebSocket initialization to send a blocking `cwd_selection_required` packet instead of constructing a runtime when no cwd is available.
4. Update the client to disable the composer and show an explanatory message only. Cwd/session pickers are out of band for this change.
5. Keep `?cwd=<absolute-path>` working as the explicit way to start a disposable session.
6. Change invalid URL recovery payloads to explanation-only packets with no `defaultCwd`, session lists, cwd lists, or picker actions.
7. Update Docker entrypoint to stop `cd /opt/pi-webui`, or make sure no behavior depends on process cwd before landing the fallback removal.
8. Add tests that prove opening `/` with no `lastCwd` does not create a runtime and does not write `lastCwd`.

## Tests To Add Or Update

- Server startup: no `lastCwd`, no `cwd` URL, no `session` URL returns cwd-required state.
- Server startup: valid `?cwd=...` creates runtime in that cwd.
- Server startup: valid `lastCwd` still creates runtime in that cwd for `/`.
- Server startup: invalid `lastCwd` does not fall back to process cwd.
- Invalid URL state: no default cwd still renders recovery without creating runtime.
- Docker/entrypoint or integration smoke: `pi-webui` startup does not derive cwd from `/opt/pi-webui`.
- Regression: no successful command can persist `/opt/pi-webui` as `lastCwd` unless it was explicitly chosen.

## Open Decisions

- Should `pi-webui` support an explicit env default cwd? Recommendation: yes only if product wants unattended deployments to open directly into a workspace. Use `PI_WEBUI_CWD`, validate it, and treat invalid values as startup/config errors.
- Should `lastCwd` remain a default? Recommendation: yes, because it is explicit app state from prior user selection. Invalid/deleted `lastCwd` should trigger cwd selection, not fallback.
- Should invalid session cwd recovery edit the session header? Recommendation: no for the first pass. Open with explicit override or start new cwd session; only add migration/edit behavior with a separate decision.
