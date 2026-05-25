# Ticket 7: REST API, Local Settings, and Load Trace Review

Date: 2026-05-24  
Scope: `pipane/src/server/rest-api.ts`, `pipane/src/server/local-settings.ts`, `pipane/src/server/load-trace-store.ts`, `pipane/src/client/local-settings-modal.ts`, `pipane/src/client/load-trace.ts`, related tests.

## Summary

The local settings store has useful schema validation, defaulting, atomic-ish temp-file writes, and reload semantics that preserve the last good in-memory config on invalid external edits. The REST layer is thinner: malformed JSON commonly becomes a `500`, several filesystem endpoints accept absolute caller-supplied paths with only extension/existence checks, and trace ingestion accepts arbitrary unbounded-ish event field sizes inside bounded trace/event counts.

No code or test changes were made for this audit.

## REST Endpoint Contract Table

| Method | Path | Request | Success response | Error responses observed | Notes |
| --- | --- | --- | --- | --- | --- |
| `POST` | `/api/debug/load-trace/event` | JSON object; `traceId` string optional if `x-pi-trace-id` header exists; `name` optional; `durationMs` optional number; `attrs` optional object | `200 { ok: true }` | `404 { error: "Tracing disabled" }`; `400 { error: "Missing traceId" }`; malformed JSON or record exceptions -> `500 { error: err.message }` | Coerces `traceId` and `name` with `String(...)`; treats any non-null `durationMs` as span even when non-number, but only stores numeric duration. |
| `GET` | `/api/debug/load-trace/latest` | none | `200 { traces: LoadTrace[] }`, newest 10 | `404 { error: "Tracing disabled" }` | Store retains max 50 traces, max 1000 events per trace. |
| `GET` | `/api/debug/load-trace/:traceId` | route param | `200 LoadTrace` | `404 { error: "Tracing disabled" }`; `404 { error: "Trace not found" }` | No trace id validation beyond map lookup. |
| `GET` | `/api/sessions` | none | `200 SessionListItem[]` | `500 { error: err.message }` | Uses `SessionIndex.listSessions()`, with best-effort cache writes. |
| `GET` | `/api/settings/local` | none | `200 { path, exists, errors, settings, formatted }` | `500 { error: err.message }` | Returns the local settings path and active settings. |
| `POST` | `/api/settings/local/validate` | JSON object `{ content: string }` | `200 LocalSettingsValidationResult` | Missing content -> `400 { error: "Missing 'content' string" }`; malformed JSON body -> `500 { error: err.message }` | Invalid settings content intentionally returns `200 { valid: false, errors }`; invalid request envelope returns error. |
| `PATCH` | `/api/settings/local` | JSON object partial settings | `200 LocalSettingsValidationResult` | Non-object body -> `400 { error: "Request body must be a JSON object" }`; invalid resulting settings or write failure -> `400 LocalSettingsValidationResult`; malformed JSON body -> `500 { error: err.message }` | Arrays pass the `typeof body === "object"` check and then become invalid settings via patch/validate. |
| `PUT` | `/api/settings/local` | JSON object `{ content: string }` | `200 LocalSettingsValidationResult` | Missing content -> `400 { error: "Missing 'content' string" }`; invalid settings or write failure -> `400 LocalSettingsValidationResult`; malformed JSON body -> `500 { error: err.message }` | Saves formatted validated content and notifies clients after success. |
| `DELETE` | `/api/sessions` | JSON object `{ path: string }` | `200 { success: true }` | Missing path -> `400 { error: "Missing session path" }`; non-`.jsonl` or absent path -> `404 { error: "Session not found" }`; malformed JSON/unlink failure -> `500 { error: err.message }` | Accepts any existing path ending in `.jsonl`; not constrained to the agent sessions directory. |
| `GET` | `/api/sessions/messages?path=...` | `path` query string ending `.jsonl` | `200 { messages, model, thinkingLevel }` | Missing/invalid path -> `400`; absent file -> `404`; read/parse failure -> `500 { error: err.message }` | Accepts any existing `.jsonl` path. |
| `GET` | `/api/sessions/fork-messages?path=...` | `path` query string ending `.jsonl` | `200 { messages: Array<{ entryId, text }> }` | Missing/invalid path -> `400`; absent file -> `404`; read/parse failure -> `500 { error: err.message }` | Extracts text from user messages only. Accepts any existing `.jsonl` path. |
| `GET` | `/api/sessions/raw?path=...` | `path` query string ending `.jsonl` | `200 text/plain` raw file content | Missing/invalid path -> `400`; absent file -> `404`; read failure -> `500 { error: err.message }` | Raw JSONL endpoint intentionally returns full session content. Accepts any existing `.jsonl` path. |
| `GET` | `/api/browse?path=...` | optional path; defaults to `$HOME` or `/`; leading `~` replaced by `$HOME` | `200 { path, dirs: Array<{ name, path }> }` | absent path -> `404`; readdir/stat errors -> `500 { error: err.message }` | Lists non-hidden directories for any readable path, not limited to workspace/home. |

## Validation and Error Handling Findings

| Severity | Finding | Evidence | Impact | Suggested follow-up |
| --- | --- | --- | --- | --- |
| High | Session file REST endpoints trust arbitrary caller-supplied `.jsonl` paths. | `DELETE /api/sessions` checks only string, `.jsonl`, and `existsSync` before `unlink`; message/raw/fork routes use the same extension/existence pattern before `readFileSync`. See `pipane/src/server/rest-api.ts:183-288`. | Any authorized user, or any local caller when local bypass applies, can read/delete any accessible `.jsonl` file outside the pi agent sessions tree. This is a privacy and data-loss risk if the server is exposed beyond a single trusted local user. | Resolve and constrain session paths to the expected agent sessions directory, ideally by session id or by paths returned from `SessionIndex`. Add traversal/out-of-root tests and arbitrary `.jsonl` read/delete denial tests. |
| Medium | Malformed request JSON returns `500` with parser details on several endpoints. | `readJsonBody` directly `JSON.parse`s and route catch blocks map all exceptions to `500`; load trace and delete routes duplicate this pattern. See `pipane/src/server/rest-api.ts:44-49`, `59-87`, `126-180`, `183-202`. | Invalid client payloads look like server faults and expose exception messages. Acceptance asks invalid payloads to produce safe, test-covered responses. | Add shared JSON parsing that returns `400 { error: "Invalid JSON" }` without raw parser text; cover malformed JSON for trace event, settings validate/patch/put, and delete. |
| Medium | Trace event ingestion accepts arbitrary attr object and event/name/trace id lengths. | `attrs` is stored whenever it is an object; `name` and `traceId` are string-coerced without length/schema checks. See `pipane/src/server/rest-api.ts:69-82`. | Trace storage is count-bounded but not byte-bounded. A client can put sensitive data or large payloads in memory and expose them via debug endpoints. | Define trace privacy contract: allowlisted attr keys or max serialized size, max `name`/`traceId` length, and redaction guidance. Add invalid/oversized trace payload tests. |
| Medium | `/api/browse` lists arbitrary readable directories. | Path defaults to home but accepts any path and resolves it directly. See `pipane/src/server/rest-api.ts:292-311`. | Directory names and absolute paths may leak outside the project/home context to any authorized/local client. | Decide intended browse root policy. If only project/home browsing is intended, constrain path roots and test forbidden roots. If arbitrary local browsing is intended, document that explicitly. |
| Low | Filesystem errors are returned with raw `err.message` in REST responses. | Settings read/write, session file reads/deletes, browse, sessions list all use `res.status(500).json({ error: err.message })`; settings write failure returns `Failed to write settings: ${message}`. See `pipane/src/server/rest-api.ts:113-179`, `200-313`; `pipane/src/server/local-settings.ts:260-276`. | Errors may include absolute paths and platform details. This is probably acceptable for a local tool, but it is a privacy footgun if remote access is enabled. | Standardize public error bodies and log details server-side when verbose logging exists. At minimum document local-tool assumption. |

## Local Settings Persistence and Reload Behavior

- Path: `~/.piweb/settings.json` by default via `getLocalSettingsPath`.
- Read behavior: if missing, defaults are used and `exists: false` is returned. If unreadable or invalid at process startup, current settings fall back to defaults and `errors` captures the failure.
- Validation: root object with `version: 1`; required `sidebar.cwdTitle.filters`; optional/defaulted `sidebar.sessionsPerProject`, `canvas.enabled`, `appearance.colorTheme`, `appearance.darkMode`, `appearance.showTokenUsage`, `toolCollapse.keepOpen`, and `messages.initialCount`. Regex filters are compiled during validation.
- Save behavior: validates content, creates the parent directory, writes `${settingsPath}.tmp`, then renames it over the target. On write/rename failure it returns `{ valid: false, errors: ["Failed to write settings: ..."] }` and does not update in-memory settings.
- Patch behavior: starts from current in-memory settings, ignores `version`, shallow-merges one level for object-valued top-level sections, validates/saves the merged result.
- Reload behavior: `watchFile` polls the settings file. `reloadFromDiskIfValid()` applies valid external edits, preserves the last good config on invalid/unreadable edits, and returns `true` only when effective formatted settings changed.
- Notification behavior: successful REST `PATCH`/`PUT`, and valid changed external reloads, call `sessionIndex.invalidateAll()` and `onLocalSettingsReloaded`. In `server.ts`, this broadcasts a WebSocket event `{ type: "sessions_changed", file: "__local_settings__" }`; client `main.ts` re-fetches settings, updates feature flags/appearance, and re-renders.

### Reload/Notification Ambiguities

- `localSettingsWatcherStarted`, `localSettingsStore`, and `sessionIndex` are module-level globals. If `registerRestApi` is called more than once in-process with different stores, the watcher starts only once and its callback closes over the latest globals indirectly. This may only matter in tests or embedded use, but it makes isolated REST testing harder.
- Invalid external edits update `store.errors` but do not broadcast. Existing clients will not learn about the new validation errors until some later settings read/reload path is triggered.
- `PATCH`/`PUT` notify clients only after a valid save and cache invalidation, which is the desired user-visible behavior.

## Trace Persistence and Privacy

- Persistence is memory-only; no trace data is written to disk by `LoadTraceStore`.
- Retention is bounded by count: max 50 trace IDs and max 1000 events per trace. `GET /latest` returns only the newest 10 traces.
- Client trace ID is generated with `crypto.getRandomValues`, stored in `sessionStorage`, sent on traced fetches, and used in the WebSocket URL query parameter.
- Backend HTTP spans record method/path and status code only, not query strings. Frontend events currently include navigation timing, bootstrap/init markers, and caller-provided attrs.
- Privacy expectation is not documented near the API: trace attrs are arbitrary and exposed through debug endpoints, so callers should not include prompts, file contents, auth tokens, or session raw data unless an explicit redaction/retention policy is added.

## Test Coverage Observed

Covered:

- `local-settings.test.ts` covers defaults, save formatting, invalid regexes, external reload success, invalid external reload preserving last good config, cwd formatting/filtering, appearance validation/defaulting, `sessionsPerProject`, patch behavior, and `toolCollapse`.
- `auth-guard.test.ts` verifies protected HTTP endpoints are blocked without auth when local bypass is disabled, and allowed with the auth cookie.

Gaps:

- No dedicated REST API tests found for endpoint contracts, request/response shapes, malformed JSON, status codes, or filesystem failures.
- No tests found for load trace store retention/compaction or trace REST validation.
- No tests found for arbitrary path rejection on session raw/messages/delete routes; current code does not reject arbitrary existing `.jsonl` paths.
- No tests found for `/api/browse` path bounds or unreadable/non-directory behavior.
- No tests found for settings REST write failure mapping, notification count/ordering, or invalid external edits not notifying clients.
- No tests found for `messages.initialCount` validation despite implementation support.
- Client modal behavior is not covered for failed GET/PUT/validate responses or `onSaved` callback semantics.

## Follow-ups

1. Decide the intended trust boundary for REST routes: strictly local single-user, authenticated remote, or browser-accessible from untrusted local pages. This decision changes severity for arbitrary path read/delete and directory browsing.
2. Decide whether `/api/sessions/raw` is an intentional debug feature or should be narrowed/redacted; it returns full conversation JSONL.
3. Define a trace data policy: allowed attrs, maximum event payload size, retention expectations, and whether debug endpoints should be disabled or auth-gated differently in production.
4. Add REST integration tests around invalid JSON, invalid envelopes, write/read/unlink/readdir failures, and expected safe error bodies.
5. Add path-root validation tests before changing filesystem endpoint behavior, so the desired contract is pinned down.
