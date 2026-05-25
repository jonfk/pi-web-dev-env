# Ticket 6 Audit: Session JSONL, File Watching, and Path Safety

Date: 2026-05-24  
Scope: `pipane/src/server/session-jsonl.ts`, `session-index.ts`, `session-cwd.ts`, `src/shared/jsonl-sync.ts`, `src/client/jsonl-panel.ts`, related tests/fixtures/scripts.

## Summary

Session JSONL parsing is generally fail-soft: malformed middle lines and partial trailing writes are ignored by the upstream `parseSessionEntries()` parser, and unsupported entry shapes do not crash the session context builder in the spot checks below. Hash-verified sync prevents silent client corruption when deltas are stale or malformed.

The largest correctness/security issue is path safety. Several REST and WebSocket paths accept a client-supplied absolute `*.jsonl` path and only check suffix/existence. That permits authenticated users to read, subscribe to, fork/copy, run against, or delete JSONL files outside the pi agent sessions directory.

Watcher behavior has two notable correctness risks: burst events are collapsed to only the last changed file, and detached-session refresh is size-only, so same-size rewrites are missed. Large-session backend indexing looks fast with the existing synthetic bench, but raw JSONL panel and session reads remain full-file, unbounded operations.

## Evidence

- `readSessionFromDisk()` reads the whole file, calls `parseSessionEntries()`, builds context, and falls back to an empty non-streaming state on thrown errors: `pipane/src/server/session-jsonl.ts:284`.
- `SessionIndex` recursively lists only files under `agentDir/sessions`, reads each whole JSONL file, validates the first parsed entry as `type: "session"`, and extracts metadata in one pass: `pipane/src/server/session-index.ts:140`, `pipane/src/server/session-index.ts:164`.
- `getSessionCwd()` accepts any `sessionPath`, reads the whole file to parse the first line, caches by path, and returns header `cwd` if it is a string: `pipane/src/server/session-cwd.ts:14`.
- REST session endpoints accept `path` from request query/body and validate only `endsWith(".jsonl")` plus existence before read/delete: `pipane/src/server/rest-api.ts:183`, `pipane/src/server/rest-api.ts:205`, `pipane/src/server/rest-api.ts:231`, `pipane/src/server/rest-api.ts:273`.
- WebSocket subscribe reads any client-supplied detached `sessionPath` from disk: `pipane/src/server/ws-handler.ts:405`.
- Fork prompt copies any supplied `sessionPath` into the agent sessions directory before continuing: `pipane/src/server/ws-handler.ts:711`.
- Reusing an existing session uses the header `cwd` when it exists on disk, then sends `switch_session` with the same client-supplied path: `pipane/src/server/ws-handler.ts:850`.
- Session watcher uses one global `lastChangedFile` and one debounce timer for all changed files: `pipane/src/server/server.ts:356`.
- Detached watcher refresh skips when file size is unchanged: `pipane/src/server/ws-handler.ts:171`.
- Sync diffs are hash-verified and fall back to re-subscribe/full sync on verification failure: `pipane/src/shared/jsonl-sync.ts:229`, `pipane/src/client/ws-agent-adapter.ts:711`.
- Client session-sync coalescing intentionally keeps a pending full sync over deltas, but replaces older pending deltas with the latest pending delta: `pipane/src/client/ws-agent-adapter.ts:648`.
- Raw JSONL panel polls the full raw file every 1.5s and renders all non-empty lines: `pipane/src/client/jsonl-panel.ts:132`, `pipane/src/client/jsonl-panel.ts:153`, `pipane/src/client/jsonl-panel.ts:447`.

## Findings

### P1: Client-supplied session paths are not constrained to the agent sessions directory

The REST endpoints for delete/messages/fork-messages/raw and the WebSocket session operations accept arbitrary absolute paths as long as the string ends in `.jsonl` and the file exists. This is an out-of-agent-dir read/delete/copy/subscribe risk for any authorized user, and for remote deployments the auth boundary is the only thing preventing access.

Impact examples:

- `GET /api/sessions/raw?path=/tmp/private.jsonl` returns that file if it exists.
- `DELETE /api/sessions` can unlink any existing `*.jsonl` visible to the process.
- `subscribe_session` can read arbitrary JSONL-ish files into the session state.
- `fork_prompt` can copy an arbitrary JSONL file into `getAgentDir()/sessions`.
- `prompt`/`steer` reuse paths ultimately pass the path to pi via `switch_session`, with CWD derived from that file's header when valid.

Recommended follow-up: centralize `resolveSessionPath()` validation that realpath-resolves the requested path, requires it to be under `realpath(getAgentDir()/sessions)`, requires a regular `.jsonl` file, rejects symlink escapes, and use it for REST and WS commands. For new-session sentinel paths like `__new__`, keep an explicit separate branch.

### P2: Session watcher drops all but the last JSONL file in a burst

`startSessionsWatcher()` stores one `lastChangedFile` and resets one debounce timer. If several JSONL files change within 300ms, only the last filename is sent to `notifySessionFileChanged()` and in the `sessions_changed` event. Sidebar refreshes may still eventually re-list sessions when the last event arrives, but detached subscribers to earlier changed files will not receive their snapshot through this path.

Recommended follow-up: collect a `Set<string>` of changed filenames during the debounce window and process/broadcast each file, or broadcast a directory-level invalidation plus per-subscribed-session refresh.

### P2: Detached subscribed-session refresh misses same-size rewrites

`notifySessionFileChanged()` compares only old and new file sizes before reading. Auto-compaction, manual edits, or finalization rewrites that preserve byte size can be missed, leaving subscribed detached clients stale until they resubscribe. This is especially relevant because detached sessions are read from disk only on subscribe or watcher notification.

Recommended follow-up: track `mtimeMs` plus size, or hash the file when a watcher event arrives for a subscribed detached session. The session index cache already uses mtime and size, so this can follow that precedent.

### P3: Sessions directory watcher does not start if the directory is absent at boot

If `getAgentDir()/sessions` does not exist when the server starts, `startSessionsWatcher()` returns `null` and there is no retry after the directory is created. New installations can therefore miss file-based sidebar/session refresh until restart.

Recommended follow-up: ensure the sessions directory exists before watcher startup, or watch the agent dir and install the recursive sessions watcher when `sessions` appears.

### P3: JSONL raw panel has unbounded full-file polling/rendering

When visible, the raw JSONL panel fetches the complete raw file every 1.5s, splits all lines, compares all lines, and renders an entry for every non-empty line. Long strings are truncated, which helps per-line content, but there is no file-size/line-count cap, incremental range fetch, or virtualization.

Recommended follow-up: add a raw panel cap or tail mode, show truncation state for huge sessions, and avoid polling when the server can push a known content version.

## JSONL Parsing Assessment

Observed via a local Node probe against `@mariozechner/pi-coding-agent`:

- Valid header plus message: 2 entries, 1 context message.
- Malformed middle line: parser returned header plus valid message after the bad line; no throw.
- Partial trailing line: parser returned complete earlier entries; no throw.
- Unsupported shapes (`42`, `{type:"weird"}`): parser returned them as entries; `buildSessionContext()` ignored them for messages.

Existing tests cover happy-path disk read and missing-file fallback in `session-jsonl.test.ts`, plus session index cache/listing behavior in `session-index.test.ts`. I did not find explicit tests for malformed lines, partial trailing writes, unsupported non-object entries, huge single lines, or truncated headers. The behavior appears tolerant today, but it depends on upstream parser semantics and should be pinned with local tests.

## Path Safety Assessment

| Surface | Current check | Risk | Recommendation |
| --- | --- | --- | --- |
| `SessionIndex.listSessionFiles()` | Starts from `agentDir/sessions`; recursive file scan | Low for listing, except symlink semantics should be confirmed | Keep; consider realpath/symlink test |
| REST raw/messages/fork-messages | `path` string, `.jsonl`, exists | High: arbitrary file read/parse outside agent dir | Central `resolveSessionPath()` |
| REST delete | `path` string, `.jsonl`, exists | High: arbitrary `.jsonl` deletion | Central `resolveSessionPath()` and maybe require listed session id/path |
| WS subscribe/prompt/steer/compact/fork | client `sessionPath` string | High: arbitrary disk read/copy and pi `switch_session` path | Validate all non-`__new__` paths |
| `getSessionCwd()` | none beyond parse first line | Medium: arbitrary CWD trusted if path is accepted | Validate path first; optionally validate cwd policy |
| Session header `cwd` | any existing directory | Medium: process may run in unexpected existing directory | Accept only from trusted session files |

## Watcher/Diff Risk Matrix

| Case | Current behavior | Risk | Notes |
| --- | --- | --- | --- |
| Duplicate watcher events | Debounced; full snapshot for detached subscribers | Low | Duplicate full sync is safe, only extra work |
| Burst changes to multiple files | Only last file processed | Medium | Can miss detached subscribed updates |
| Same-size rewrite | Skipped by size check | Medium | Can leave detached client stale |
| Attached session file changes | Watcher ignored; streaming events authoritative | Low/Medium | Fine during normal turns; external same-file edits during attached state are intentionally ignored |
| Detach finalization | `releaseProcess()` deletes attached state, reads disk, pushes full snapshot | Low | Good explicit final sync path |
| Delta arrives with wrong base | Client rejects and resubscribes | Low for corruption, Medium for extra full sync/stutter | Hash protects visible state |
| Multiple deltas in one animation frame | Client keeps latest pending delta only | Low for corruption, Medium for resync churn | If latest delta depends on discarded delta, hash fails and full sync is requested |
| Full sync plus deltas in same frame | Pending full is preserved | Low | Covered by adapter test |

## Performance Notes

Existing focused tests:

- `npm test -- --run src/server/session-jsonl.test.ts src/server/session-index.test.ts src/shared/jsonl-sync.test.ts src/client/ws-agent-adapter.test.ts`
- Result: 4 files passed, 112 tests passed. The client adapter test emitted sandbox-only localhost `EPERM` connection noise but completed successfully.

Existing backend synthetic benchmark:

- Command: `npm run bench:sessions -- --sessions 250 --messages 120 --warmup 2 --iterations 5`
- Initial sandbox run failed because `tsx` could not create its IPC pipe; reran with approval. The script printed results then remained alive due to a watcher from REST registration, so I stopped the benchmark process after recording output.
- JSONL parse benchmark: mean 17.42ms, p50 17.35ms, p95 17.75ms, min/max 17.05/17.75ms for 250 sessions x 120 messages.
- Backend `GET /api/sessions`: cold 45.57ms; warm mean 2.22ms, p50 2.23ms, p95 2.79ms, min/max 1.87/2.79ms.

Large-session render validation:

- `pipane/e2e/render-perf.e2e.ts` references a large generated fixture, but `pipane/e2e/fixtures/large-session-messages.json` is not present in this checkout.
- Running that E2E would auto-generate the fixture, which would create a non-report file and violate this research-only task.
- Also, that E2E still mocks the legacy `session_messages` path rather than current `session_sync`, so it does not directly validate JSON diff sync render behavior.

## Test/Perf Gaps

- Add local tests that pin malformed middle-line and partial trailing-line behavior for `readSessionFromDisk()` and `SessionIndex`.
- Add tests for unsupported parsed shapes before/after valid messages.
- Add path traversal tests for every REST and WS session-path entry point.
- Add watcher tests for multi-file bursts and same-size rewrites.
- Add a `session_sync` render/perf fixture that does not rely on legacy `session_messages`.
- Add raw JSONL panel stress coverage for high line counts and very long single lines.
- Consider making `bench-sessions.ts` close/unwatch REST-created watchers so it exits cleanly.

## Follow-ups / Ambiguities

- Decide policy: should authorized users ever be allowed to open JSONL files outside `getAgentDir()/sessions` for debugging/import? Recommendation: default deny; if import is desired, build an explicit import endpoint that copies into the sessions dir after confirmation.
- Decide whether header `cwd` should be trusted only for files discovered by `SessionIndex`, or whether it should also be constrained to an allowlist/local filesystem policy.
- Validate actual `fs.watch({ recursive: true })` behavior on target Linux/macOS deployment environments; recursive support and event coalescing differ by platform.
