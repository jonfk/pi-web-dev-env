# Ticket 4: Backend Process Pool and Session Lifecycle Correctness Review

Date: 2026-05-24
Scope: `pipane/src/server/process-pool.ts`, `session-lifecycle.ts`, `ws-handler.ts`, `attached-session.ts` / `session-jsonl.ts`, and related tests.
Mode: research-only audit. No implementation or test changes made.

## Evidence and Commands

- Read target modules with `sed`/`nl`: `process-pool.ts`, `session-lifecycle.ts`, `ws-handler.ts`, `attached-session.ts`, `session-jsonl.ts`, `server.ts`.
- Searched lifecycle/process coverage with:
  - `rg -n "WsHandler|prompt|hard_kill|abort|reload_processes|acquireForSession|agent_end|decommission|busyProcesses|steer|steering|PI_MAX_PROCESSES|PI_PREWARM_COUNT|prewarm|maxProcesses|process pool|session_attached|session_detached" pipane/src/server/*.test.ts pipane/src/server/*.ts`
  - `rg -n "PI_MAX_PROCESSES|PI_PREWARM_COUNT|ProcessPool|prewarm|ensurePool|new ProcessPool" pipane/src/server pipane/src/client pipane/src/shared`
- Ran targeted existing tests:
  - `cd pipane && npm test -- --run src/server/process-pool.test.ts src/server/session-lifecycle.test.ts src/server/attached-session.test.ts src/server/session-jsonl.test.ts`
  - Result: 4 files passed, 88 tests passed.

## Lifecycle Transition Table

| Path | Trigger | Process state | Lifecycle state | Attached session cache | Cleanup behavior |
| --- | --- | --- | --- | --- | --- |
| New prompt | `prompt("__new__")` | `acquireProcess()` returns a proc; later `busyProcesses.add(proc)` after `waitForReady`, `new_session`, `get_state` | `attach(sessionPath, proc)` sets `running` | `createAttachedSession(sessionPath)` | On `agent_end`, `releaseProcess()` removes listener/cache, detaches, pushes disk snapshot, clears busy |
| Existing prompt | `prompt(sessionPath)` | `acquireForSession()` returns existing attached proc or acquires idle proc and marks busy | New attach sets `running`; existing attached session is returned unchanged | Created if missing | `agent_end` releases as above |
| Normal completion | pi emits `agent_end` | Listener calls `releaseProcess()` | `detach()` sets `done` | Deleted | Listener removed, steering cleared, disk snapshot pushed, busy cleared, optional SIGTERM if decommissioned |
| Abort | `abort(sessionPath)` | Sends `abort` RPC to attached proc | No direct transition | No direct change | Relies on later pi `agent_end`; no local fallback cleanup on abort RPC failure |
| Hard kill | `hard_kill(sessionPath)` | Removes listener/cache, detaches, clears busy/decommission, sends `SIGKILL` | `detach()` sets `done` before process exit | Deleted immediately | Disk snapshot pushed if file exists; later process exit sees no attached lifecycle mapping |
| Crash/exit | child `exit`/`error` | `ProcessPool` removes proc from pool and rejects pending RPCs | `server.ts` `onProcessExit` calls `lifecycle.crash(sessionPath)` if attached | **Not deleted by crash path** | No `WsHandler.releaseProcess()` call; listener/busy/decommission maps are not cleaned |
| Steering enqueue | `steer(sessionPath)` | Sends `steer` RPC to attached proc | Queue appended before RPC | Lifecycle subscriber copies queue into cache and pushes update | Queue removed by matching user `message_end`, `clearSteering`, or detach |
| Reload/decommission | `reload_processes` | Attached procs marked decommissioned; idle procs SIGTERM | Attached sessions remain running | Existing cache remains | On later `releaseProcess`, decommissioned proc gets SIGTERM |
| Process reuse | `releaseProcess()` after normal completion | Proc removed from busy set and remains in pool unless decommissioned | Session done | Cache deleted | Available to same-cwd future session; `acquire()` filters by cwd and unavailable set |

## Findings

### P1 - Commands can reuse an already-running session process as if it were idle

Evidence:
- `acquireForSession()` returns the existing attached process immediately when `lifecycle.getAttachedProcess(sessionPath)` is set (`ws-handler.ts:850-852`).
- `handlePrompt()`, `handleCompact()`, `handleFork()`, and `handleSetSessionName()` all call `acquireForSession()` and then issue RPCs that are not steering/abort-safe (`ws-handler.ts:493`, `615-620`, `695-699`, `782-787`).
- `setupTurnEventForwarding()` removes any existing listener for the process before attaching the new turn listener (`ws-handler.ts:980-985`).

Impact:
- A second prompt for the same attached/running session can send `set_model`, replace the turn event listener, and send another `prompt` to the same pi process while the first turn is still running.
- `compact`, `fork`, or `set_session_name` against a running session can call `releaseProcess(sessionPath)` and detach/delete in-memory state while a prompt is still active.
- This risks dropped stream events, incorrect final detach, prompt response confusion, and stale or corrupted session state.

Current coverage:
- `SessionLifecycle` tests prove idempotent attach (`session-lifecycle.test.ts:58-67`), but there are no `WsHandler` tests asserting that unsafe commands reject or queue when a session is already running.

Recommended regression tests:
- Existing session receives two `prompt` commands before `agent_end`: assert the second command is rejected or queued, and the first listener remains installed.
- Running session receives `compact`, `fork`, or `set_session_name`: assert no detach/release occurs and no non-steering RPC is sent to the busy process.

### P1 - Crash path detaches lifecycle but leaves `WsHandler` process/session cleanup behind

Evidence:
- `ProcessPool` removes exited processes from the pool and rejects pending requests (`process-pool.ts:185-203`).
- `server.ts` crash callback only calls `lifecycle.crash(sessionPath)` and prewarms (`server.ts:255-265`).
- `lifecycle.crash()` is just `detach()` (`session-lifecycle.ts:121-126`).
- `WsHandler.releaseProcess()` is the only audited path that removes `procEventCleanup`, deletes `attachedSessions`, pushes final disk state, handles decommission, and clears busy (`ws-handler.ts:900-928`), but crash does not call it.

Impact:
- After an attached pi process crashes, `attachedSessions` can retain a stale in-memory session until a future subscribe path notices and deletes it.
- `busyProcesses`, `decommissionProcesses`, and `procEventCleanup` can retain dead process references.
- Subscribed clients may receive a status change to done, but not the final disk snapshot/error state produced by `releaseProcess()`.

Current coverage:
- `SessionLifecycle` has a pure `crash is equivalent to detach` test (`session-lifecycle.test.ts:81-97`), but there is no integrated process-exit test for `WsHandler` cleanup.

Recommended regression tests:
- Simulate child process exit while attached; assert lifecycle done, `attachedSessions` empty, busy/decommission maps do not contain the proc, listener cleanup ran, and subscribers receive a full disk snapshot.
- Simulate crash while decommissioned; assert no stale decommission entry remains.

### P1 - Newly acquired processes are not reserved immediately in new/fork prompt paths

Evidence:
- `handlePrompt("__new__")` calls `acquireProcess(cwd)` and only marks busy after `waitForReady`, `new_session`, and `get_state` (`ws-handler.ts:470-480`).
- `handleForkPrompt()` calls `acquireProcess(cwd)` and only marks busy after `waitForReady` (`ws-handler.ts:724-728`).
- `acquireProcess()` returns a process from `pool.acquire()` without reserving it (`ws-handler.ts:881-884`).

Impact:
- While a new/fork prompt is waiting for readiness or session setup, that same process still appears available to other acquisition paths.
- A concurrent prompt for a different session/cwd-compatible operation can attach or switch the same process before the first caller marks it busy.
- This is most visible for prewarmed processes, where `pool.acquire()` can return an already-live process instantly.

Current coverage:
- `process-pool.test.ts` verifies that a provided busy set is respected (`process-pool.test.ts:89-98`), but no `WsHandler` test covers reservation timing around `waitForReady` or `new_session`.

Recommended regression tests:
- Two concurrent `prompt("__new__")` calls against a single prewarmed process: assert they do not share one process.
- `prompt("__new__")` stalled in `waitForReady` while an existing-session prompt arrives: assert the existing prompt does not acquire the reserved process.

### P2 - `getAnyProcess()` can issue metadata RPCs to busy processes and can bypass the process cap

Evidence:
- `ProcessPool.getAny()` prefers idle, then falls back to any live process even if it is in the busy set (`process-pool.ts:254-264`).
- `getAnyProcess()` uses that result for `get_available_models`, `get_commands`, and `get_default_model`; if none exists, it calls `pool.spawn(this.defaultCwd)` directly (`ws-handler.ts:624-633`, `677-682`, `931-935`).
- Direct `spawn()` does not enforce `maxProcesses`; enforcement is only in `acquire()` (`process-pool.ts:235-247`).

Impact:
- Metadata requests may share an active prompt process. If pi cannot safely service non-turn RPCs during a running prompt, these requests can time out or perturb state.
- In the no-process case with `PI_MAX_PROCESSES=0`, `getAnyProcess()` still spawns, bypassing the configured cap.

Current coverage:
- The fallback-to-busy behavior is explicitly tested in `process-pool.test.ts:134-142`, but no test documents that pi supports those RPCs while a prompt is active.

Recommended regression tests/follow-up:
- Decide whether metadata RPCs are allowed on busy pi processes. If yes, document the invariant with a fake RPC that handles concurrent prompt + metadata. If no, reject/wait/use a separate reserved process.
- Add a cap test for `getAnyProcess()`/metadata when `maxProcesses` is `0` or all processes are busy.

### P2 - Invalid process-count environment values are not validated

Evidence:
- `PI_MAX_PROCESSES` and `PI_PREWARM_COUNT` are parsed with `parseInt` and passed through directly (`server.ts:62-63`, `server.ts:253-254`).
- `ProcessPool.prewarm()` computes `Math.min(this.prewarmCount, this.maxProcesses)` and `acquire()` compares `totalProcesses >= this.maxProcesses` (`process-pool.ts:242-247`, `295-305`).

Impact:
- `PI_MAX_PROCESSES=abc` makes the cap comparison false (`>= NaN`), effectively allowing unbounded `acquire()` spawning.
- `PI_MAX_PROCESSES=0` causes acquisition to wait until timeout for prompt paths, but metadata `getAnyProcess()` can still spawn directly.
- Negative values disable normal acquisition/prewarm in surprising ways.

Current coverage:
- Existing tests cover normal cap behavior (`process-pool.test.ts:224-232`), not `NaN`, zero, negative, or prewarm greater than cap edge cases.

Recommended regression tests:
- Server/config parser test for non-numeric, zero, and negative env values.
- Pool tests for `prewarmCount > maxProcesses`, `maxProcesses=0`, and `prewarmCount<0`.

### P3 - Steering queue can remain stale if the `steer` RPC fails after enqueue

Evidence:
- `handleSteer()` enqueues before sending the RPC (`ws-handler.ts:543-551`).
- The catch path in `handleMessage()` only sends an error response; it does not remove the queued message.
- Queue cleanup otherwise depends on matching user `message_end`, `clearSteering`, or detach (`session-lifecycle.ts:153-190`, `ws-handler.ts:1026-1041`).

Impact:
- If `sendRpc({ type: "steer" })` fails or times out while the process remains attached, the UI can show a steering message the agent never received.

Current coverage:
- Queue operations are covered at the lifecycle unit level (`session-lifecycle.test.ts:134-223`), but no integrated failure-path test covers steer RPC failure after enqueue.

Recommended regression test:
- Force `steer` RPC rejection after enqueue and assert the queue is rolled back or explicitly documented as "pending until detach".

## Race and Cleanup Matrix

| Area | Race/cleanup risk | Existing guard | Test status | Audit status |
| --- | --- | --- | --- | --- |
| Same-session concurrent prompt | Second prompt reuses existing attached process and replaces listener | None observed in `handlePrompt()` | Missing | High risk |
| Different-session concurrent prompt | Process can be acquired before busy reservation in new/fork paths | Busy set after reservation, but delayed in some paths | Missing | High risk for new/fork setup windows |
| Existing-session non-prompt command during run | `compact`/`fork`/`set_session_name` can release a running session | None observed | Missing | High risk |
| Normal `agent_end` | Listener calls `releaseProcess()` | Listener identity guard and cleanup map | Partially covered only by state units | Looks coherent |
| Hard kill | Explicit listener/cache/busy/decommission cleanup before SIGKILL | Direct cleanup in handler | Missing integrated test | Looks mostly coherent |
| Crash/exit | Lifecycle detached by server callback only | ProcessPool rejects pending RPCs | Missing integrated test | Cleanup gap |
| Steering enqueue/dequeue | Queue removed by matching user message or detach | Lifecycle queue API | Unit covered; failure path missing | Small stale UI risk |
| Decommission after reload | Attached procs marked and killed on release | `decommissionProcesses` set | Missing integrated test | Depends on normal release; crash leaks set |
| Pool cap | `acquire()` enforces cap | `totalProcesses >= maxProcesses` | Basic unit covered | Env/direct-spawn edge gaps |
| Prewarm | Spawns up to min(prewarm, max), waits between all but last | `totalProcesses` check | Missing edge tests | Needs env/cap validation |

## Test Gaps

- Add `WsHandler` tests with a fake `ProcessPool`/`RpcProcess` and controllable RPC promises. The current server tests do not directly instantiate `WsHandler`.
- Cover concurrent WebSocket commands for:
  - same session prompt while running,
  - different sessions during `__new__` readiness/session creation,
  - compact/fork/set-name while session is running,
  - hard kill while prompt RPC is pending,
  - process exit while attached and while decommissioned.
- Cover configuration/pool edge cases:
  - `PI_MAX_PROCESSES=0`, negative, and non-numeric,
  - `PI_PREWARM_COUNT=0`, greater than max, negative, and non-numeric,
  - metadata RPC behavior when all processes are busy.

## Follow-Ups and Ambiguities

- Confirm desired policy: should a running session accept a second `prompt`, or should the backend reject with "session already running"? Recommendation: reject unsafe commands while attached; allow only `steer`, `abort`, `hard_kill`, subscription/status, and possibly read-only metadata commands with documented guarantees.
- Confirm whether pi RPC supports concurrent metadata calls while a prompt is active on the same process. Recommendation: do not rely on this unless pi explicitly guarantees it.
- Decide where crash cleanup should live. Recommendation: keep `SessionLifecycle` as pure state, but have `WsHandler` own process-exit cleanup for attached sessions or subscribe to a process-exit event that calls the same cleanup pieces as `releaseProcess()` without double-killing.
- Decide env validation behavior. Recommendation: clamp to safe integers or fail fast on invalid `PI_MAX_PROCESSES` / `PI_PREWARM_COUNT` at startup.
