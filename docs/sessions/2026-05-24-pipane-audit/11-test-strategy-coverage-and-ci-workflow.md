# Ticket 11: Test Strategy, Coverage, and CI Workflow Audit

Date: 2026-05-24
Scope: `pipane/AGENTS.md`, `pipane/package.json`, `pipane/vitest.config.ts`, `pipane/playwright.config.ts`, `pipane/e2e/*`, and unit tests under `pipane/src/**/*test.ts`.

## Executive Summary

The current unit suite gives useful confidence for core pure/domain behavior and several client regressions: JSONL sync, session JSONL reconstruction, session lifecycle state, process-pool accounting, local settings, auth guard, WebSocket client adapter routing, session picker behavior, token usage, tool renderers, and packaging metadata are all covered. `npm run check`, `npm run test`, and `npm run build` are fast enough for required CI.

The suite is not yet enough by itself for dependency upgrades or high-confidence release gating because several high-risk integration seams are only covered through Playwright, Playwright is not documented as an installable prerequisite, there is no visible CI workflow in this checkout, and the e2e suite currently mixes smoke, visual golden, performance, and walkthrough checks into one default command. The most important missing coverage is direct server WebSocket protocol coverage, REST API route coverage, install-flow server behavior, production static/font asset validation, and dependency-upgrade smoke coverage around `@mariozechner/*`/`pi` RPC behavior.

## Command Results

Commands were run from `pipane/`.

| Command | Result | Runtime observed | Notes |
|---|---:|---:|---|
| `npm run check` | Passed | 1.8s wall | Runs `tsc --noEmit`. |
| `npm run test` | Initially failed in sandbox, passed with localhost sockets allowed | 5.0s wall when allowed | 21 files, 301 passed, 6 skipped. Sandbox failure was `listen EPERM 127.0.0.1` from `auth-guard.test.ts`; with elevated localhost permission it passed. |
| `npm run build` | Passed | 7.6s wall | Vite emitted unresolved KaTeX font warnings from `@mariozechner/pi-web-ui` and large chunk warnings. |
| `npx playwright test --timeout 60000` | Blocked | 1.3s sandbox fail, 19.4s elevated fail | Sandbox run failed on `tsx` IPC pipe `listen EPERM`. Elevated run generated the large-session fixture and then all 21 tests failed because the Chromium headless shell was missing. Playwright requested `npx playwright install`. |
| `npm run test:screenshots` | Not separately run | N/A | Would hit the same missing Playwright browser prerequisite; this script only targets `e2e/ui-screenshots.e2e.ts`. |

Observed Playwright failure:

```text
Executable doesn't exist at ~/Library/Caches/ms-playwright/chromium_headless_shell-1208/...
Please run: npx playwright install
```

## Current Test Inventory

Unit test configuration:

- `vitest.config.ts` uses `happy-dom` by default and includes `src/**/*.test.ts`.
- Individual server/shared tests opt into `@vitest-environment node`.
- Timeout is 10s for Lit/component rendering.
- There is no configured coverage reporter or `npm run coverage` script.

Unit test files found:

- Client: `auto-collapse`, `canvas-panel`, `message-renderers`, `pi-install-flow`, `rerun-duplicate`, `session-picker`, `token-usage`, `tool-renderers`, `ws-agent-adapter`.
- Server: `attached-session`, `auth-guard`, `global-cli`, `local-settings`, `pi-launch`, `pi-runtime`, `process-pool`, `session-index`, `session-jsonl`, `session-lifecycle`, `update-check`.
- Shared: `jsonl-sync`.

E2E test files found:

- `real-stack.e2e.ts`: full UI -> WebSocket -> pipane server -> real pi RPC process -> mock OpenAI-compatible LLM -> UI path.
- `ui-screenshots.e2e.ts`: visual goldens for session picker, tool renderers, input, steering queue, tool in progress.
- `rerun-duplicate.e2e.ts`: duplicate tool-block regression.
- `steering.e2e.ts`: steering queue add/consume/remove.
- `session-cwd.e2e.ts`: new session CWD grouping stability.
- `focus-new-session.e2e.ts`: focus behavior for group `+`.
- `input-clear.e2e.ts`: prompt input clears on send.
- `wide-layout.e2e.ts`: wide viewport layout regression.
- `render-perf.e2e.ts`: large-session render and scroll performance.
- `video-walkthrough.e2e.ts`: gated internally by `RUN_WALKTHROUGH`, but still appears in the default Playwright discovery.

## Coverage / Risk Matrix

| Risk area | Existing coverage | Confidence | Gaps / recommended tests |
|---|---|---:|---|
| Auth | `auth-guard.test.ts` covers HTTP 401s, login cookie, WebSocket close code, localhost bypass, disabled auth. | Medium-high | Keep in required CI, but tests need localhost/socket permission. Add proxy/header and fixed-token expiry/rotation cases if supported. |
| WebSocket protocol | `ws-agent-adapter.test.ts` covers client command routing, session switching, steering queue snapshots, sync resubscribe behavior. Real-stack e2e covers some happy paths. | Medium | No direct server `ws-handler.ts` unit/contract test. Add protocol-level tests for server message validation, unknown commands, `hard_kill`, `reload_processes`, model commands, session subscription lifecycle, error events, reconnect/resync, and malformed payloads. |
| Process lifecycle | `process-pool.test.ts`, `session-lifecycle.test.ts`, `attached-session.test.ts`, and real-stack e2e cover pool/state basics and some streaming. | Medium-high | Add integration tests for child-process crash during active prompt, hard kill, process reload, pool cleanup after WebSocket disconnect, and concurrent sessions with different CWDs. |
| JSONL sync / session state | `jsonl-sync.test.ts` has broad hash/patch/full-sync coverage; `session-jsonl.test.ts` covers server-side reconstruction and disk reads; e2e JSONL click focus exists. | High for pure sync, medium for UI integration | Add server/client end-to-end resync test where a delta mismatch forces full sync and UI recovers. Add corrupt/partial JSONL file route behavior through REST/WebSocket. |
| Settings | `local-settings.test.ts` covers schema/defaults/formatting; e2e mock serves `/api/settings/local`. | Medium | `rest-api.ts`, `local-settings-modal.ts`, and UI save/error flows have no direct tests. Add route tests for browse/read/write validation and UI tests for invalid JSON, save success, and hidden token/canvas settings. |
| Install flow | `pi-runtime.test.ts`, `pi-launch.test.ts`, and a small client `pi-install-flow.test.ts` cover detection/launch payload shape. | Low-medium | Server install command path in `ws-handler.ts` is not directly tested. Add tests for installable vs non-installable platforms, install failure messaging, reload after install, and no-prompt behavior when `pi` is missing. |
| UI rendering | Client component/unit tests cover session picker, renderers, auto-collapse, token usage, canvas, duplicate rendering; screenshots cover major visual states. | Medium | Main app wiring (`main.ts`), `pi-message-list.ts`, JSONL panel, model picker dialog, local settings modal, fork modal, and theme selector lack direct tests. Screenshot tests are useful but should not be the only check for behavior. |
| Dependency upgrades | Build/unit tests catch many TypeScript/API breaks; real-stack e2e is designed to catch pi RPC integration breaks. | Medium if Playwright runs, low if not | Add a small required real-stack smoke subset that runs in CI after `npm run build`. Keep visual/perf/walkthrough on demand. Consider explicit smoke tests for the package bin and production `npm pack` contents. |

## CI Recommendations

| Check | CI tier | Command | Rationale |
|---|---|---|---|
| TypeScript | Required on every PR | `npm run check` | Fast, catches broad compile/API breakage. |
| Unit tests | Required on every PR | `npm run test` | Fast enough and covers most pure/server/client behavior. CI must allow localhost sockets. |
| Production build | Required on every PR | `npm run build` | Required before e2e and catches Vite/server compilation issues. |
| E2E smoke | Required on every PR after build | Prefer a new script targeting real-stack smoke plus focused regressions, e.g. `real-stack`, `input-clear`, `rerun-duplicate`, `session-cwd`, `steering` | The current default e2e command includes screenshot/perf/walkthrough concerns. Split a deterministic smoke set from visual/perf tests. |
| Screenshot goldens | Optional / label or manual workflow | `npm run test:screenshots` | Valuable for UI review, but image diffs are environment-sensitive and should not block every backend/dependency PR by default. Run on UI changes or manually. |
| Render performance | Optional scheduled/manual, or required only for rendering changes | `npx playwright test e2e/render-perf.e2e.ts --timeout 60000` | Performance thresholds are machine-sensitive and slower. Keep trend visibility without making unrelated PRs flaky. |
| Video walkthrough | Manual release artifact workflow | `RUN_WALKTHROUGH=1 npx playwright test e2e/video-walkthrough.e2e.ts --timeout 180000` | This is a demo artifact generator, not a normal correctness gate. |
| Package smoke | Required before release | `npm pack --dry-run` plus `npm run prepack` | Packaging metadata has unit checks, but release should verify actual packed files and executable path. |

There is no `.github` workflow under `pipane/` in this checkout. If CI exists outside this subtree, it is not discoverable from the audited project root.

## Flaky / Slow Notes

- `auth-guard.test.ts` is the slowest unit file in the observed run at about 3.9s, because it starts real HTTP/WebSocket servers. It is still acceptable for required CI.
- `session-picker.test.ts` is the next slowest unit file at about 1.6s.
- `ws-agent-adapter.test.ts` passes but emits many `ECONNREFUSED localhost:3000` errors. That noise can hide real regressions and suggests some tests instantiate behavior that tries to reach the default server instead of fully stubbing transport/fetch.
- Playwright default parallelism used 7 workers. Real-stack tests start servers and pi RPC processes; the harness uses random temp directories and free ports, which helps, but the suite should still be watched for port/process leaks under CI load.
- `ui-screenshots.e2e.ts` writes `e2e/latest/*.png` and deletes prior latest screenshots at module load. That is fine for local review, but it is a side effect that should be documented and artifacted if run in CI.
- `render-perf.e2e.ts` generates a 10x large-session fixture before running and asserts wall-clock rendering/scroll thresholds. This is inherently environment-sensitive.
- `video-walkthrough.e2e.ts` is internally skipped unless `RUN_WALKTHROUGH=1`, but keeping it in default discovery still adds cognitive noise to default e2e output.

## Documentation Gaps

- `AGENTS.md` is stale: it says 136 unit tests across 13 files and 10 e2e tests across 3 files. Current observed inventory is 301 unit tests across 21 files and 21 Playwright tests across 9 e2e files.
- `AGENTS.md` says run `npm run test && npx playwright test --timeout 60000`, but also says build before e2e. The top command should include `npm run build` or point to `./test.sh`.
- `package.json` has no general `test:e2e` script, no smoke-vs-full e2e split, and no `coverage` script.
- Playwright browser installation is undocumented. At minimum, CI/local setup should mention `npx playwright install` or `npx playwright install --with-deps chromium`.
- README has user quickstart/auth docs only; it does not document development test commands, expected runtimes, or e2e prerequisites.
- `test.sh` runs build, unit, and all e2e, but package scripts and `AGENTS.md` do not reference it as the canonical full verification command.
- There is no documented policy for screenshot tests: when to run them, how to review diffs, where `e2e/latest` artifacts live, and when to update goldens.
- There is no CI workflow documentation in the audited tree.

## Follow-ups

1. Add or document CI with required `npm run check`, `npm run test`, `npm run build`, and a focused Playwright smoke script.
2. Add package scripts for `test:e2e:smoke`, `test:e2e:full`, `test:e2e:perf`, and keep `test:screenshots` optional/on-demand.
3. Update `AGENTS.md` and README development docs with current test inventory, prerequisites, commands, expected runtimes, and screenshot update policy.
4. Add direct contract tests around `src/server/ws-handler.ts` and `src/server/rest-api.ts`; these are core surfaces without adjacent unit tests.
5. Add install-flow server tests for missing `pi`, install command success/failure, reload, and user-facing failure messages.
6. Reduce unit-test log noise from `ws-agent-adapter.test.ts` by stubbing default localhost fetch/WebSocket attempts or asserting them explicitly.
7. Add a release/dependency-upgrade smoke path that runs a built production server against the mock LLM and verifies package/bin behavior.
