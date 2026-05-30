# pi-webui Pre-Phase-3 Recovery Fixes Handoff

Date: 2026-05-30

## Goal

Fix two recovery correctness issues before implementing `PLAN-004 Phase 3: Target-Based Transitions`, and record one recovery transition issue that should be fixed inside Phase 3.

Phase 3 should carry the remaining `lastCwd` persistence fix for valid URL cwd startup. See `docs/project/plans/PLAN-004-phase-3-target-based-transitions.md`.

This handoff is for issues that are better fixed before Phase 3:

1. Successful recovery leaves stale blocked-startup errors in the UI.
2. Runtime-free recent cwd data can show cwd entries that selection will reject.

The overlapping runtime-free recovery issue is intentionally deferred to Phase 3 because the better fix belongs in the target transition applicator Module, not in a temporary recovery-only guard. See "Deferred To Phase 3" below.

The code under review is the staged Phase 2 runtime-free recovery work in `pi-webui`.

## References

- Plan: `docs/project/plans/PLAN-004-phase-2-runtime-free-recovery.md`
- Next plan: `docs/project/plans/PLAN-004-phase-3-target-based-transitions.md`
- PRD: `docs/project/prds/PRD-004-pi-webui-explicit-runtime-targets.md`
- Client entry point: `pi-webui/public/app.js`
- Client chat state: `pi-webui/public/chat-state.mjs`
- Runtime-free recovery server helper: `pi-webui/src/server/runtime-free-recovery.ts`
- Server controller: `pi-webui/src/server/index.ts`
- Cwd validation and browsing policy: `pi-webui/src/server/cwd.ts`
- Existing recovery tests: `pi-webui/test/server-runtime-free-recovery.test.mjs`
- Existing invalid URL action tests: `pi-webui/test/invalid-url-state.test.mjs`

## Issue 1: Stale Startup Error After Successful Recovery

### Symptom

When pi-webui starts in `invalid_url_state` or `cwd_required`, the client renders a blocking chat item and sets `chatState.lastError`.

After the user recovers by choosing a cwd or session, the server sends normal `connected`, `session_reset`, `session_state`, `message_history`, and `command_result` packets. The blocked runtime is recovered, but the old status-bar error can remain visible.

### Cause

In `pi-webui/public/app.js`:

- `handleInvalidUrlState(payload)` calls `csSetError(chatState, ...)`.
- `handleCwdRequired(payload)` calls `csSetError(chatState, ...)`.
- The `"connected"` packet handler clears `invalidUrlState`, `recoveryState`, and `startupBlocked`, but does not clear `chatState.lastError`.
- `session_reset` intentionally resets streamed UI state only. `resetHistory` in `public/chat-state.mjs` does not clear `lastError`.

Relevant current area:

```js
case "connected":
  const wasStartupBlocked = startupBlocked;
  invalidUrlState = null;
  recoveryState = null;
  startupBlocked = false;
  setComposerBlocked(false);
  slashCommands = packet.payload.slashCommands || [];
  homeDir = packet.payload.homeDir || "";
  if (!wasStartupBlocked) urlState.canonicalizeCwdPointer(packet.payload.cwd);
  ...
```

### Recommended Fix

Import `clearError` from `public/chat-state.mjs` and clear the startup error when a formerly blocked startup reaches `connected`.

Suggested shape:

```js
import {
  createChatState,
  submitUser as csSubmitUser,
  setHistory as csSetHistory,
  resetHistory as csResetHistory,
  setError as csSetError,
  clearError as csClearError,
  selectItems as csSelectItems,
} from "./chat-state.mjs";
```

Then in the `"connected"` handler:

```js
case "connected":
  const wasStartupBlocked = startupBlocked;
  invalidUrlState = null;
  recoveryState = null;
  startupBlocked = false;
  if (wasStartupBlocked) csClearError(chatState);
  setComposerBlocked(false);
  ...
  renderStatusBar();
  return;
```

Keep this scoped to successful recovery from blocked startup. Do not broadly clear command errors on every reconnect unless that is intentional; a normal reconnect should not silently erase an unrelated runtime error.

### Tests

There is not currently a focused unit harness for `public/app.js` packet handling. Options:

- Add one if a lightweight app-level harness already exists after local inspection.
- Otherwise add a narrow browser/integration test if the project has or introduces WebSocket-level testing.
- At minimum, manually validate with the local app:
  1. Start from a missing/invalid URL cwd or no `lastCwd`.
  2. Confirm status bar shows the blocked-startup error.
  3. Use recovery to choose a cwd.
  4. Confirm the runtime connects and the status bar error is cleared.

Acceptance:

- Successful cwd recovery clears the blocked-startup error.
- Successful session recovery clears the blocked-startup error.
- Failed recovery selection still shows the failure.
- Normal command errors are not erased merely by unrelated UI rendering.

## Deferred To Phase 3: Overlapping Runtime-Free Recovery Starts

### Symptom

During blocked startup, the user can trigger two recovery selections quickly, for example double-clicking a cwd or choosing a session while another recovery request is still in flight.

Both messages can enter recovery handling before `startupBlock` is cleared. Each can call `recoverRuntime`, creating or replacing `this.runtime` independently. This can produce duplicate subscriptions, duplicate file watchers, interleaved bootstrap packets, or a runtime that is overwritten without cleanup.

### Cause

In `pi-webui/src/server/index.ts`, blocked startup requests are routed through:

```ts
if (this.startupBlock) {
  if (payload?.type === "ready") return;
  const handled = await this.handleRuntimeFreeRecovery(payload);
  if (handled) return;
  ...
}
```

`handleRuntimeFreeRecovery` can call:

```ts
await this.recoverRuntime(command, result.target);
```

`recoverRuntime` then calls:

```ts
await this.startRuntimeForTarget(target);
setLastCwd(agentDir, this.runtime.cwd);
this.startupBlock = null;
this.sendConnected();
await this.sendBootstrap({ reset: true });
...
```

The guard state is cleared only after `startRuntimeForTarget` completes. While that await is pending, another recovery selection can also pass the `startupBlock` check.

Also, `startRuntimeForTarget` creates a runtime and binds a session. It does not stop an existing watch, unsubscribe, or dispose an existing runtime. That is acceptable during initial startup, but it is not safe for overlapping recovery attempts.

### Phase 3 Fix

Do not implement a recovery-only guard before Phase 3 if carrying the temporary bug is acceptable.

The deeper fix is for the target transition applicator Module to own this invariant: one controller may have at most one runtime-creating target transition in flight. Command transitions, URL cwd startup transitions, and runtime-free recovery should all get the same ordering guarantee through one Interface.

The applicator should own watcher cleanup, runtime disposal, runtime creation, target/runtime cwd assertion, `lastCwd` persistence, session binding, bootstrap ordering, and transition serialization or rejection. Callers should submit a selected target transition and should not know the ordering mechanics.

The chosen policy can be either:

- serialize later transitions behind the active transition; or
- reject overlapping transitions with a clear command result.

Pick one policy in Phase 3, document it in the plan or tests, and make all runtime-creating target transitions use it. Do not preserve a separate recovery-only mechanism.

### Tests

Prefer a WebSocket/controller integration test, because this is about async message ordering. If the controller is not exportable, a focused unit test can cover a factored helper or a small recovery gate.

Test behavior to cover:

- Put the controller in blocked startup state.
- Make runtime creation artificially awaitable or slow.
- Send two `select_cwd` or `select_session` messages before the first completes.
- Assert only one runtime creation path runs.
- Assert only one connected/bootstrap success sequence is sent.
- Assert the duplicate receives a clear failure or is ignored, according to the chosen behavior.
- Cover double `select_cwd`, double `select_session`, and mixed cwd/session recovery races.
- Cover at least one normal runtime-changing command race if the applicator can be driven directly in tests.

Manual validation:

- Start in cwd-required state.
- Double-click a cwd in the recovery picker.
- Confirm only one runtime connects and no duplicate bootstrap/state messages appear in the browser log.

Acceptance:

- A controller cannot run two runtime-creating target transitions concurrently.
- No duplicate session bindings or file watches are created by repeated recovery selection.
- The first valid recovery still succeeds.
- Failed first transition clears the applicator's in-flight state so the user can try again.
- Runtime-free recovery uses the same transition applicator as normal runtime-changing commands.
- There is no separate recovery-only concurrency guard after Phase 3.

## Issue 2: Recovery Recent Cwds Include Unselectable Paths

### Symptom

The runtime-free cwd picker can show cwd entries derived from prior sessions even when those cwd paths are outside the current cwd policy, missing, or otherwise invalid. Selecting one then fails with an error.

### Cause

In `pi-webui/src/server/runtime-free-recovery.ts`, `listRecentRecoveryCwds` filters `registry.lastCwd` through `validateIfReachable`, but it adds session cwd values directly:

```ts
for (const session of sessions) {
  if (!session?.cwd) continue;
  addRecent(seen, session.cwd, modifiedTime(session.modified), 1);
}

const registry = loadWorkspaceRegistry(args.agentDir);
if (registry.lastCwd) {
  const resolved = validateIfReachable(registry.lastCwd, args.policy);
  if (resolved) addRecent(seen, resolved, Date.now(), 0);
}
```

Later selection does validate:

```ts
cwd: validateCwdTarget(args.cwd, args.policy)
```

So listing and selection use inconsistent rules.

### Recommended Fix

Use the same validation policy for every cwd source shown in recovery recents.

Suggested shape:

```ts
for (const session of sessions) {
  if (!session?.cwd) continue;
  const resolved = validateIfReachable(session.cwd, args.policy);
  if (!resolved) continue;
  addRecent(seen, resolved, modifiedTime(session.modified), 1);
}
```

Keep the existing `lastCwd` validation. This makes the picker show only cwd targets that selection should accept at the time the list is generated.

Do not add loose parsing or partial cleanup. If a sender/session records an invalid cwd, recovery should omit it from selectable cwd recents. Session recovery can still be offered separately through "Choose session"; selecting a session with an invalid header cwd should continue to fail clearly.

### Tests

Update `pi-webui/test/server-runtime-free-recovery.test.mjs`.

Add coverage for:

- A session with cwd outside `policy.homeDir` is omitted from `listRecentRecoveryCwds`.
- A session with a missing/deleted cwd is omitted.
- A valid session cwd remains listed and count aggregation still works.
- `lastCwd` remains filtered as it is today.

If testing deleted cwd:

1. Create a fixture cwd under home.
2. Write a session file that references it.
3. Remove the directory before calling `listRecentRecoveryCwds`.
4. Assert it does not appear.

Acceptance:

- Every cwd entry returned by `listRecentRecoveryCwds` can pass `selectRecoveryCwd` under the same policy at list time.
- Invalid session cwd entries do not appear in recovery recents.
- `listAllRecoverySessions` still lists sessions independently; this fix should not hide sessions from the session picker.

## Verification

Run from the repository root:

```bash
npm test --prefix pi-webui
```

If app-level or browser coverage is added, also run the relevant local browser/e2e command documented in `pi-webui`.

Manual smoke checks:

- Start with no valid runtime target. Recover by cwd. Confirm error clears and one runtime starts.
- Start with an invalid URL session. Recover by choosing session. Confirm error clears and one runtime starts.
- Double-click a recovery cwd. Confirm one recovery wins and the app remains usable.
- Seed sessions with invalid cwd paths. Confirm invalid cwd paths are absent from cwd recents but sessions still appear in the session picker.

## Out Of Scope

- Do not implement Phase 3's target-transition module here.
- Do not change normal runtime command persistence beyond what is necessary for these recovery fixes.
- Do not change URL cwd startup `lastCwd` persistence here; that decision belongs to Phase 3 and is now recorded in `PLAN-004-phase-3-target-based-transitions.md`.
