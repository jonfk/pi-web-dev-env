# Ticket 14: Performance and Large Session Scalability Review

Date: 2026-05-24  
Scope: `pipane/scripts/bench-sessions.ts`, `pipane/e2e/render-perf.e2e.ts`, `pipane/e2e/fixtures/generate-large-session.ts`, `pipane/src/client/pi-message-list.ts`, `pipane/src/client/auto-collapse.ts`, `pipane/src/client/jsonl-panel.ts`, `pipane/src/server/session-jsonl.ts`

## Summary

Backend session listing has a usable baseline for the default synthetic fixture: `GET /api/sessions` warm p95 was `3.28 ms` for 250 sessions x 120 messages, and the direct JSONL parse/last-user scan p95 was `17.81 ms`.

Frontend render measurements are currently blocked as a repeatable benchmark because Playwright's managed Chromium is not installed in this environment. A temporary installed-Chrome harness confirmed the large session can auto-load and render, but did not produce stable, acceptance-quality timing data before this audit was stopped. The report treats frontend render, session switch, JSONL panel, and streaming-memory measurements as blocked follow-ups rather than guessed baselines.

Highest-risk scalability paths are: full DOM rendering for large histories, JSONL panel full-file parse/highlight on each render and poll, `SessionJsonl` full-state stringify/hash on every streaming update, and auto-collapse scanning all tool messages while only hiding DOM bodies.

## Environment Notes

| Item | Observed |
| --- | --- |
| Host OS | macOS 15.7.3 build 24G419 |
| Node / npm | Node `v23.11.1`, npm `10.9.2` |
| Project fixture | `e2e/fixtures/large-session-messages.json`, `4,145,314` bytes (`du`: 4.0M) |
| Built client | `pipane/dist/client`, `7.0M` |
| Browser | Google Chrome.app and Brave Browser.app installed; Playwright-managed Chromium missing |
| CPU / memory | `sysctl` hardware queries were blocked by sandbox permissions |

## Command Evidence

### Backend Session Benchmark

Command:

```sh
cd pipane
npm run bench:sessions -- --sessions 250 --messages 120 --warmup 3 --iterations 15
```

The sandbox blocked `tsx` IPC pipe creation, so the command was rerun outside the sandbox. It created temporary benchmark fixtures under the OS temp directory and cleaned them up. After printing results, the process did not exit cleanly and was stopped with a targeted `pkill` for the benchmark command.

Results:

| Measurement | Baseline |
| --- | ---: |
| Fixture | 250 sessions x 120 messages |
| JSONL parse mean | `17.43 ms` |
| JSONL parse p50 / p95 | `17.52 ms` / `17.81 ms` |
| JSONL parse min / max | `17.07 ms` / `17.81 ms` |
| `GET /api/sessions` cold | `45.04 ms` |
| `GET /api/sessions` warm mean | `2.27 ms` |
| `GET /api/sessions` warm p50 / p95 | `2.23 ms` / `3.28 ms` |
| `GET /api/sessions` warm min / max | `1.61 ms` / `3.28 ms` |

### Existing Render Performance E2E

Command:

```sh
cd pipane
npx playwright test -c playwright.config.ts e2e/render-perf.e2e.ts --reporter=line --output=/tmp/pipane-render-perf-results
```

Blocked attempts:

| Attempt | Result |
| --- | --- |
| Sandbox | Failed: `listen EPERM: operation not permitted 0.0.0.0` when the mock server called `server.listen(0)` |
| Outside sandbox | Mock server could start, but both tests failed before measurement because Playwright Chromium was missing: `Executable doesn't exist at /Users/jfokkan/Library/Caches/ms-playwright/chromium_headless_shell-1208/chrome-headless-shell-mac-arm64/chrome-headless-shell` |

I did not run `npx playwright install` because this is a research-only audit and browser installation would download/write outside the project.

### Temporary Chrome Harness

I created a disposable harness in `/private/tmp` to use installed Google Chrome with the same large fixture and a local mock server. This was not a project file edit. It hit the same sandbox local-listen block in-process; outside the sandbox it confirmed the app connected over WebSocket and rendered the large transcript, but the harness timed out waiting for `.session-item` entries in `session-picker` even while `bodyText` contained the rendered 1,940-message session. Because this was not an existing benchmark and did not reach its metric collection path, I am not treating it as a baseline.

Follow-up: fix the existing Playwright browser dependency first, then add supported perf measurements to `e2e/render-perf.e2e.ts` rather than relying on ad hoc harnesses.

## Baseline Table

| Area | Baseline | Status |
| --- | ---: | --- |
| Session JSONL parse scan, 250 x 120 | p95 `17.81 ms` | Measured |
| Backend `GET /api/sessions`, 250 x 120 | warm p95 `3.28 ms`, cold `45.04 ms` | Measured |
| Large session initial load/render, 1,940 messages / 4.0M fixture | Not captured | Blocked: Playwright browser missing |
| Session switch render time | Not captured | Blocked: Playwright browser missing |
| Scroll frame time after large render | Not captured | Blocked: Playwright browser missing |
| JSONL panel open time | Not captured | Blocked: no supported existing benchmark; ad hoc harness did not complete |
| Memory growth while streaming long outputs | Not captured | Blocked: no existing benchmark/harness; needs streaming update scenario and browser heap metrics |

## Bottleneck Findings

1. `pi-message-list.ts` has no virtualization. With `messages.initialCount = 0`, large sessions render every visible user/assistant message and inline tool result into the DOM. Even with `initialCount > 0`, `render()` still builds `toolResultsById` over every message and calls `buildRenderItems()` for all renderable messages before slicing to the visible tail.

2. `jsonl-panel.ts` renders every JSONL line at once. Opening the panel fetches the full raw file, splits all lines, maps every line to DOM, and calls `highlightJson()`/`JSON.parse()` for each expanded line. The 1.5s poll refetches the full file and compares every line for changes.

3. `jsonl-panel.ts` jump helpers parse line JSON repeatedly. `findToolResultLineByToolCallId()` and `findLineByDisplayedMessageOrdinal()` walk and parse the full `jsonlLines` array on demand.

4. `auto-collapse.ts` scans the full document for `tool-message[data-tool-call-id]` and hides older tool bodies after render. This can reduce visual height but does not remove heavy DOM nodes or avoid the initial render cost.

5. `session-jsonl.ts` rebuilds full serialized state on each meaningful event. `applyEvent()` calls `rebuildJson()`, which `JSON.stringify()`s the complete state and hashes it. For long streaming tool output, this risks repeated O(session-size) allocation/hashing on the server before any client render work begins.

6. Existing perf coverage is too narrow to catch the above. `render-perf.e2e.ts` measures large render and scroll only when Playwright is installed, but it does not report initial load, session switch, JSONL panel open, heap growth, or streaming update behavior in machine-readable output.

## Proposed Regression Thresholds

Use these as provisional thresholds until frontend baselines are captured on a stable machine/browser:

| Area | Proposed threshold |
| --- | --- |
| `bench:sessions` default JSONL parse p95 | `<= 25 ms` for 250 sessions x 120 messages |
| `bench:sessions` default `GET /api/sessions` warm p95 | `<= 10 ms` |
| `bench:sessions` default cold `GET /api/sessions` | `<= 100 ms` |
| Large render e2e, existing 1,940-message fixture | Keep current hard budget `< 10,000 ms`; after 3 clean runs, add warning threshold at baseline median + 25% |
| Scroll after large render | Prefer `0` frames over 50ms; fail if `> 2/20` frames exceed 50ms or max frame exceeds 75ms |
| JSONL panel open, 1,940 lines | Capture baseline first; provisional target `< 2,000 ms` after chunking/virtualization |
| Browser heap after opening JSONL | Capture baseline first; fail on >25% growth over committed baseline for same fixture |
| Streaming long output | Capture baseline first; target bounded per-update work, with no monotonic heap growth after stream completion and GC |

## Recommended Follow-Up Tickets

1. **Fix perf test environment and artifact policy.** Install/document Playwright browser setup for local/CI perf runs, set output paths explicitly, and make `render-perf.e2e.ts` runnable without writing tracked artifacts.

2. **Make perf benchmarks emit structured metrics.** Update `bench-sessions.ts` and `render-perf.e2e.ts` to print JSON summaries for cold load, session switch, scroll frames, DOM element counts, JSONL open, and browser heap.

3. **Avoid full message template construction when `initialCount` is enabled.** In `pi-message-list.ts`, compute the visible message window before creating templates. Keep only the tool results required for visible assistant messages.

4. **Add message-list virtualization for large histories.** Window rendered chat items around the viewport and preserve scroll anchoring when prepending older messages. Treat tool result bodies as independently collapsible/windowed heavy content.

5. **Chunk and virtualize the JSONL panel.** Fetch/render JSONL in chunks or visible ranges, cache parsed line metadata, collapse all lines by default for large files, and avoid full-file polling when the session size/version has not changed.

6. **Reduce server streaming full-state rebuilds.** In `SessionJsonl`, debounce or batch partial tool updates and explore append/incremental sync so long output streaming does not stringify/hash the entire session for every update.

7. **Make auto-collapse incremental.** Track completed tool messages as they mount instead of querying all tools after each render. For old completed tools, consider replacing heavy body content with a lightweight placeholder until expanded.

8. **Add a long-output streaming memory benchmark.** Simulate repeated partial tool output updates against a large existing session, collect Chrome CDP `JSHeapUsedSize`, DOM node counts, and server process memory before/during/after stream completion.

9. **Fix `bench:sessions` process shutdown.** The benchmark printed results but did not exit cleanly in this run. Add explicit teardown or open-handle diagnostics so automated perf jobs can rely on exit status without manual cleanup.

## Follow-Ups / Blocked Work

- Re-run `e2e/render-perf.e2e.ts` after `npx playwright install` or equivalent CI browser provisioning.
- Capture frontend baselines on one named machine/browser, then repeat 3-5 times and record median/p95 rather than a single run.
- Add a supported JSONL-panel benchmark path before optimizing; current code makes likely bottlenecks clear, but baseline numbers are blocked.
- Add a streaming-memory scenario before changing `SessionJsonl`; otherwise improvements may optimize initial load while missing the long-output case.
