# Ticket 5: WebSocket Protocol and Client Adapter Contract Review

Date: 2026-05-24
Scope:
- `pipane/src/server/ws-handler.ts`
- `pipane/src/client/ws-agent-adapter.ts`
- `pipane/src/client/ws-agent-adapter.test.ts`
- `pipane/e2e/real-stack.e2e.ts`
- `pipane/e2e/rerun-duplicate.e2e.ts`
- `pipane/e2e/steering.e2e.ts`

Research only. No code or test changes were made.

## Summary

The WebSocket contract is functional but informal. Runtime behavior is split across `ws-handler.ts`, `ws-agent-adapter.ts`, `session-jsonl.ts`, and `jsonl-sync.ts`; only the sync diff primitive is centralized in `src/shared`. The server accepts `any` commands and validates only a subset of required fields before acquiring processes, mutating lifecycle state, reading files, or forwarding RPCs. The client has a local `WsCommand` union, but it is incomplete relative to the commands it actually sends and the server accepts.

Recovery behavior is stronger than the validation story: reconnect uses exponential backoff, re-subscribes to the current session, resets local sync hash state, refreshes session statuses, verifies full/delta sync hashes, and re-subscribes after hash mismatch. However, the most important recovery paths have sparse regression coverage in the scoped tests, and `session_sync` coalescing currently drops intermediate deltas in a way that can self-heal only by hash mismatch and re-subscribe.

## Protocol Inventory

### Client to Server Commands

| Command | Shape observed | Server action | Validation observed | Client type coverage |
|---|---|---|---|---|
| `install_pi` | `{ type, id?, __trace? }` | Install pi if supported, broadcast install state, `ensurePool()` | Checks installability and install result | Yes |
| `subscribe_session` | `{ type, id?, sessionPath }`; empty string unsubscribes | Sets per-socket subscription; sends full `session_sync`; reads disk for detached sessions | Only falsy sessionPath special-cased as unsubscribe; no path/schema authorization in handler | Yes |
| `prompt` | `{ type, id?, sessionPath, cwd?, message, model, thinkingLevel?, images? }` | Creates/acquires session process; sets model/thinking; forwards prompt RPC; streams events; responds with `newSessionPath` | Requires `sessionPath`; requires truthy `model`; does not validate `message`, `cwd`, model fields, thinking enum, images | Partially; client type omits `cwd` although it sends it for `__new__` |
| `steer` | `{ type, id?, sessionPath, message }` | Requires attached process; enqueues steering; forwards steer RPC | Requires `sessionPath`; does not validate `message` type/non-empty | Yes |
| `remove_steering` | `{ type, id?, sessionPath, index }` | Removes queued steering item by index | Requires `sessionPath`; checks `typeof index === "number"` only; no integer/range check | No, missing from `WsCommand` union despite being sent |
| `abort` | `{ type, id?, sessionPath? }` | Sends abort RPC if attached; always responds success | No required session path; malformed/no path becomes successful no-op | Yes |
| `hard_kill` | `{ type, id?, sessionPath }` | Detaches session, clears steering, kills process, pushes disk snapshot if present | Requires `sessionPath`; no path ownership/existence validation before lifecycle lookup | Yes |
| `compact` | `{ type, id?, sessionPath, customInstructions? }` | Acquires session process, forwards compact RPC, releases process | Requires `sessionPath`; does not validate instructions type | Yes |
| `get_available_models` | `{ type, id? }` | Uses any process and forwards RPC | No payload validation needed | Yes |
| `get_default_model` | `{ type, id? }` | Uses any process, returns `model` and `thinkingLevel` | No payload validation needed | No, missing from `WsCommand` union despite being sent by `loadDefaultModel()` |
| `get_session_statuses` | `{ type, id? }` | Returns lifecycle status map | No payload validation needed; allowed when pi unavailable | No, missing from `WsCommand` union despite being sent |
| `fork` | `{ type, id?, sessionPath, entryId }` | Acquires session, forwards fork RPC, returns text/cancelled/newSessionPath | Requires `sessionPath` and `entryId` | Yes |
| `fork_prompt` | `{ type, id?, sessionPath, message, model, thinkingLevel?, images? }` | Copies JSONL, attaches new process, switches, sets model/thinking, forwards prompt | Requires `sessionPath`, `message`, `model`; no deeper validation | No, missing from `WsCommand` union despite being sent |
| `set_session_name` | `{ type, id?, sessionPath, name }` | Acquires session, forwards set name RPC | Requires `sessionPath`; does not validate `name` | Yes |
| `get_commands` | `{ type, id? }` | Uses any process, returns slash command metadata | No payload validation needed | Yes |
| `reload_processes` | `{ type, id? }` | Kills idle processes and marks attached ones for draining | No payload validation needed | Yes |
| unknown/invalid JSON | Unknown `{ type }`; non-JSON raw | Sends failure response | Invalid JSON safely returns `response` with `command: "parse"`; unknown command safely fails | N/A |

### Server to Client Events and Responses

| Event | Shape observed | Source | Client behavior |
|---|---|---|---|
| `response` | `{ id?, type: "response", command?, success, data?, error? }` | Command handlers and catch path | Resolves/rejects pending request by `id`; ignores unmatched response |
| `init` | `{ type, sessionStatuses, steeringQueues }` | On connection | Replaces global statuses and steering queue cache |
| `pi_install_required` | `{ type, command, installable, installing, message }` | On connection or blocked commands | Emits install-required listener |
| `session_status_change` | `{ type, sessionPath, status: "running" | "done" }` | Lifecycle subscription | Updates global session status map |
| `session_sync` full | `{ type, sessionPath, op: "full", data, hash }` | Subscribe, disk change, detach, hard kill, attached-session updates | Validates hash via `applySyncOp`, parses state, replaces flat state |
| `session_sync` delta | `{ type, sessionPath, op: "delta", patches, baseHash, hash }` | Attached-session updates | Requires local hash; validates base/result hash; re-subscribes on mismatch |
| `session_attached` | `{ type, sessionPath, cwd?, firstMessage? }` | New/fork prompt setup | Marks session running; adopts if current/pending virtual; subscribes; creates optimistic session |
| `session_detached` | `{ type, sessionPath }` | Not directly sent by `ws-handler.ts`; client supports it as authoritative turn end | Marks done, clears streaming, resolves running promise |
| `sessions_changed` | `{ type, file }` | `server.ts` file watcher | Notifies sessions-changed listeners |
| `agent_event` | `{ type, sessionPath, event }` | Process line forwarding side-channel | Emits raw agent event to subscribers; does not update flat state except listener side effects |
| `steering_queue_update` | `{ type, sessionPath, queue }` | Lifecycle event; also folded into `session_sync` for attached sessions | Client keeps backward-compatible handler; server `WsHandler` mutates attached session and pushes sync rather than broadcasting this event directly |
| `session_messages` | `{ type, sessionPath, messages, model?, thinkingLevel? }` | Legacy/mock tests only in scoped files | Client still supports as backward compatibility; real `ws-handler.ts` now emits `session_sync` |
| legacy raw agent event | Any agent event with optional `sessionPath` | Legacy support | `updateState()` handles only `agent_start`, `agent_end`, `turn_end` |

## Validation and Fail-Safe Findings

1. **High: Command validation is ad hoc and many malformed commands can still trigger actions.**
   `handleMessage()` parses JSON and switches on `command.type`, but command payloads are `any`. Individual handlers check only selected fields. Examples: `prompt` requires `sessionPath` and `model`, but forwards `command.message`, `command.images`, `command.model.provider`, and `command.model.modelId` without schema validation; `steer` forwards `command.message`; `set_session_name` forwards `command.name`; `subscribe_session` reads disk for any truthy `sessionPath`.

2. **High: `subscribe_session` has the largest unsafe surface because it performs disk reads based on client input.**
   The handler treats empty `sessionPath` as unsubscribe, but for any non-empty value it either uses attached state or calls `readSessionFromDisk(sessionPath)`. The scoped code does not show validation that the path is a known session JSONL under the sessions directory before the read. This needs follow-up with the API/session path guard code outside this ticket scope before deciding severity as security vs. robustness.

3. **Medium: Missing or malformed request IDs lead to inconsistent client behavior.**
   The client always sends an `id`, but the server does not require it. It will send responses with `id: undefined` for many commands. This is safe for the official adapter but weakens the protocol as a general contract and makes diagnostics for malformed clients harder.

4. **Medium: Some commands intentionally no-op on missing state, but the response does not distinguish malformed input from benign idempotence.**
   `abort` succeeds even with no `sessionPath` or unattached session. `hard_kill` returns success with `{ killed: false, reason: "not_attached" }` for unattached sessions. That is reasonable for idempotent UI controls, but it should be explicit in the protocol contract.

5. **Medium: `remove_steering` validates only `typeof index === "number"`.**
   Non-integer, negative, `NaN`, or out-of-range values pass the handler check. Whether this fails safely depends on `SessionLifecycle.removeSteeringByIndex()`, which was outside the explicit file list except through call references.

6. **Low: Client-side server-event validation is best-effort.**
   The adapter ignores invalid JSON and unknown responses/events, filters most session-scoped events by `sessionPath`, and normalizes some install payload fields. But `session_sync` shape is trusted until `applySyncOp`; malformed `patches` can still throw during application and there is no local try/catch around `applySessionSync()` beyond the hash mismatch path.

## Recovery, Reconnect, Diff, Hash, and Version Review

- **Reconnect/resubscribe exists.** On close, the adapter rejects all pending requests, clears the pending map, emits disconnected state, schedules exponential backoff from 500ms capped at 10s, reconnects, then calls `onReconnected()`. Reconnect clears `_syncJson`/`_syncHash`, re-subscribes to the current non-virtual session, and refreshes session statuses.

- **Server-side keepalive exists outside the handler.** `server.ts` pings every 30 seconds and terminates dead sockets so the browser gets an `onclose` and the adapter can reconnect.

- **Full sync is the recovery baseline.** Server sends full `session_sync` on subscribe, disk change, detach/release snapshot, and hard kill snapshot. Attached sessions use `SessionJsonl.computeSyncOp()` to choose full vs. delta.

- **Hash verification is solid at the primitive level.** `applySyncOp()` verifies full sync hash, delta `baseHash`, and post-patch hash. On mismatch, the adapter clears sync state and re-subscribes for a full sync.

- **Version is server-local only.** The server tracks `lastVersion` per socket and `SessionJsonl.version`, but no version is sent over the wire. This is sufficient for server optimization, not client protocol versioning. There is no protocol version field or capability negotiation.

- **Coalescing is a possible reliability trap.** `enqueueSessionSync()` keeps only one pending sync per animation frame. If only deltas are queued, latest delta wins. Because deltas are based on the immediately previous hash, dropping an intermediate delta can produce a base-hash mismatch and force re-subscribe. That self-heals, but under high-frequency streaming it can amplify full-sync traffic and flicker/error logs.

- **Interrupted stream recovery is partially covered by design.** `session_detached` clears streaming state if received; focus regain refreshes statuses and re-subscribes, and clears stale streaming if the adapter believes a detached session is streaming. In scoped real-stack tests, there is no explicit WebSocket disconnect while a turn is running.

- **Duplicate event handling is mostly avoided by flat state.** The adapter ignores legacy `message_end` for state mutation and treats `session_sync` as authoritative flat state. Scoped tests include duplicate rendering coverage, but one e2e still uses legacy `session_messages` plus raw events rather than the real `session_sync` path.

## Test Coverage Observed

Covered in scoped files:
- Prompt vs. steer routing, including cross-session isolation and virtual sessions.
- Per-session steering queues and stale consumer behavior.
- Stop button/`isStreaming` behavior when switching to running sessions.
- Basic `session_sync` coalescing rules.
- Error visibility for failed responses.
- Real-stack happy paths for prompt, tool call, bash streaming output, session picker updates, and JSONL navigation.
- Real-stack steering queue appears, remove button works, and queued steering is consumed.
- Duplicate rendering regression around raw message events and legacy snapshot path.

Covered outside the primary scoped test list but relevant:
- `src/shared/jsonl-sync.test.ts` covers hash mismatch, base-hash mismatch, large strings, and patch roundtrips.
- `src/server/session-jsonl.test.ts` covers version/hash behavior and large session-ish sync behavior.
- `src/client/rerun-duplicate.test.ts` covers flat `session_sync` duplicate rendering behavior more directly than the e2e mock.

Not covered or weakly covered in the scoped acceptance area:
- Malformed command schema tests against `ws-handler.ts` beyond parse/unknown-command behavior.
- `subscribe_session` with invalid/non-session paths.
- `remove_steering` invalid indexes.
- Reconnect while a turn is actively streaming.
- Pending prompt rejection on disconnect followed by successful resubscribe and UI recovery.
- Hash mismatch recovery at `WsAgentAdapter` level, including re-subscribe assertion.
- Coalesced dropped-delta recovery under high-frequency streaming.
- Large session full `session_sync` through the current protocol; existing large render e2e uses legacy `session_messages`.
- Duplicate/out-of-order `session_sync` events and stale full/delta mixes.
- Protocol compatibility/version behavior.

## Severity-Ranked Risks

1. **High: No centralized runtime schema means invalid commands can reach side effects.**
   The server relies on scattered truthiness checks and downstream failures. A malformed command should fail before process acquisition, filesystem reads, lifecycle mutation, or RPC forwarding.

2. **High: Session path validation for `subscribe_session` is not evident in the handler.**
   A malicious or buggy client can ask the handler to read arbitrary truthy paths unless another layer constrains session paths. This needs targeted follow-up.

3. **Medium: Client and server protocol definitions have drifted.**
   `WsCommand` omits `cwd`, `remove_steering`, `get_default_model`, `get_session_statuses`, and `fork_prompt` usage. Server events are not typed centrally. This makes changes easy to break silently.

4. **Medium: Recovery exists but lacks end-to-end regression coverage.**
   Reconnect/resubscribe/hash-mismatch behavior is important and non-trivial, but scoped tests mostly cover happy-path streaming and UI routing.

5. **Medium: Delta coalescing can intentionally drop required deltas.**
   Hash mismatch recovery should fix correctness, but the current approach may turn normal high-frequency streams into re-subscribe/full-sync churn.

6. **Low: Legacy event paths remain active and tested.**
   Backward compatibility is useful, but tests using `session_messages` can give false confidence for the real `session_sync` protocol.

## Centralization Recommendation

Yes: centralize protocol types in `pipane/src/shared`.

Recommended shape:
- Add `src/shared/ws-protocol.ts` with discriminated unions for client commands, server events, command responses, session status values, and install-required payloads.
- Export runtime validators from the same module or a sibling such as `ws-protocol-validators.ts`. Keep validation dependency-light if bundle size matters, or use a schema library already accepted by the project.
- Make `WsAgentAdapter.send()` accept the shared `WsClientCommand` union instead of the local incomplete `WsCommand`.
- Make `WsHandler.handleMessage()` parse into a validated command before dispatch. Dispatch handlers should receive typed, already-validated payloads.
- Include a protocol version/capability field in `init`, for example `{ type: "init", protocolVersion: 1, capabilities: ["session_sync_v1"] }`, before removing legacy paths.
- Keep `jsonl-sync.ts` focused on the diff primitive, but re-export `SessionSyncEvent` from the protocol module using its `SyncOp`.

## Follow-Ups

1. Add server-side malformed command tests for every command that mutates state or touches disk/processes.
2. Confirm and document session path authorization rules for `subscribe_session`, `prompt`, `fork`, `fork_prompt`, `compact`, `set_session_name`, and `hard_kill`.
3. Add adapter-level tests for reconnect while streaming: disconnect, reject pending prompt, reconnect, receive `init`, re-subscribe, full sync, preserve/clear streaming according to server state.
4. Add hash mismatch recovery tests that assert `subscribe_session` is resent after a bad full hash, bad delta base hash, and bad post-patch hash.
5. Replace scoped e2e mocks that still use `session_messages` with `session_sync` equivalents, or mark them explicitly as legacy compatibility tests.
6. Add large-session coverage using full `session_sync` JSON state instead of legacy message snapshots.
7. Decide whether delta coalescing should queue all deltas until the next full sync, keep latest full only, or request a full sync proactively when an intermediate delta is dropped.
8. Add protocol version/capability negotiation before making future breaking changes.

## Open Ambiguities for Further Exploration

- Whether session path access is protected elsewhere before WebSocket commands reach `WsHandler`. The scoped handler does not show it.
- Whether `SessionLifecycle.removeSteeringByIndex()` rejects invalid indexes safely or silently ignores them.
- Whether `session_detached` is intentionally a client-only supported event now, because `WsHandler` broadcasts `session_status_change` and final `session_sync` on lifecycle detach but does not directly send `session_detached`.
- Whether legacy `session_messages` support is still required for external/mock clients or can be retired after test migration.
