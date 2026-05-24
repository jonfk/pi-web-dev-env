# Pipane Codebase Audit Tickets

Generated: 2026-05-22

## High-Level Assessment

`pipane` is a TypeScript/Vite web app with a local Express/WebSocket backend that launches and manages `pi` RPC processes. The codebase already has a useful test shape: Vitest unit tests for client/server modules, Playwright e2e coverage, screenshot goldens, and a real-stack harness with a mock OpenAI-compatible LLM. That is a good foundation for a thorough health audit.

The highest-leverage audit areas are:

- Dependency freshness and security: current package metadata shows several stale direct dependencies and audit advisories, including vulnerable direct dev/runtime packages.
- Backend process/session safety: process pooling, session lifecycle, WebSocket routing, file watching, and detached/attached session state are core correctness surfaces.
- Client state and UI complexity: `main.ts`, `ws-agent-adapter.ts`, and `session-picker.ts` are large and central, so they deserve focused maintainability and state-flow review.
- Security posture: auth cookies, local bypass behavior, WebSocket authorization, REST endpoints, local settings, file/session path handling, and reverse-proxy assumptions should be reviewed together.
- Packaging and patches: this package is published with `patch-package` patches against upstream `@mariozechner/*` packages, a CLI bin, and production scripts, which creates upgrade and release risk.
- Test strategy and CI confidence: the project has meaningful tests, but the audit should confirm coverage maps to the highest-risk paths and that e2e/screenshot/performance tests are stable and cheap enough to run.

Recommended order:

1. Start with dependency/security tickets because they may affect every other review.
2. Review backend lifecycle/process/session modules before client behavior, since frontend state depends on backend protocol guarantees.
3. Review client state/rendering after backend protocol boundaries are understood.
4. Finish with packaging, documentation, and CI workflow hardening.

## Ticket 1: Dependency Freshness and Upgrade Risk Audit

### Goal

Audit direct and transitive dependencies for freshness, upgrade constraints, known breaking changes, and risk from pinned upstream `@mariozechner/*` packages.

### Scope

- `pipane/package.json`
- `pipane/package-lock.json`
- `pipane/patches/*`
- `pipane/vite.config.ts`
- `pipane/vitest.config.ts`
- `pipane/playwright.config.ts`

### Current Signals

`npm outdated --json` reported these notable direct dependency gaps:

- `@mariozechner/pi-agent-core`, `@mariozechner/pi-ai`, `@mariozechner/pi-coding-agent`, `@mariozechner/pi-web-ui`: current `0.55.3`, latest `0.73.1`
- `vite`: current `7.3.1`, wanted `7.3.3`, latest `8.0.14`
- `ws`: current `8.19.0`, wanted/latest `8.20.1`
- `happy-dom`: current `20.7.0`, wanted/latest `20.9.0`
- `@playwright/test`: current `1.58.2`, wanted/latest `1.60.0`
- `typescript`: current/wanted `5.9.3`, latest `6.0.3`
- `lucide`: current/wanted `0.544.0`, latest `1.16.0`

### Review Tasks

- Classify each outdated direct dependency as patch/minor/major risk.
- Identify whether `patch-package` patches still apply cleanly after candidate upgrades.
- Check whether the pi packages must be upgraded as a coordinated set.
- Decide whether Vite 8 and TypeScript 6 should be deferred or trialed behind a separate branch.
- Document a recommended upgrade sequence with rollback points.

### Acceptance Criteria

- A dependency upgrade matrix exists with current, target, risk level, and owner notes.
- The audit identifies the smallest safe upgrade batch that removes urgent risk.
- Tests required for each upgrade batch are listed explicitly.

## Ticket 2: npm Security Advisory Triage

### Goal

Triage `npm audit` findings by exploitability in pipane's actual runtime and produce a remediation plan.

### Scope

- Runtime server dependencies
- Browser build dependencies
- Test-only/dev dependencies
- Transitive dependencies pulled by `@mariozechner/*`, Vite, Playwright, and test tooling

### Current Signals

`npm audit --json` reported 17 vulnerabilities: 1 critical, 8 high, 8 moderate. Notable direct or high-impact findings include:

- `protobufjs`: critical transitive arbitrary code execution advisory
- `vite`: high direct dev-server advisories
- `happy-dom`: high direct dev dependency advisories
- `ws`: moderate direct runtime advisory
- Additional high/moderate transitive findings in `basic-ftp`, `fast-uri`, `fast-xml-parser`, `path-to-regexp`, `picomatch`, `undici`, `postcss`, `yaml`, and related packages

### Review Tasks

- Map each advisory to the dependency chain that introduces it.
- Separate runtime exposure from dev/test-only exposure.
- Determine which findings are fixed by direct upgrades versus upstream `@mariozechner/*` upgrades.
- Check if any advisory affects user-provided input paths: attachments, JSONL parsing, WebSocket data, REST endpoints, or dev server file access.
- Produce a short remediation order: urgent patch, coordinated upgrade, defer with rationale.

### Acceptance Criteria

- Every audit finding is marked `runtime`, `dev-only`, or `not reachable / low practical exposure`.
- High and critical findings have an explicit fix or documented blocker.
- `npm audit --json` output after proposed fixes is captured or the remaining advisories are justified.

## Ticket 3: Backend Auth and Local Access Security Review

### Goal

Review whether pipane's local/remote auth model is safe for expected usage, especially when exposed through a reverse proxy.

### Scope

- `pipane/src/server/server.ts`
- `pipane/src/server/auth-guard.test.ts`
- `pipane/src/server/rest-api.ts`
- `pipane/src/server/ws-handler.ts`
- Auth-related environment variables:
  - `PIPANE_AUTH_TOKEN`
  - `PIPANE_AUTH_DISABLED`
  - `PIPANE_DISABLE_LOCAL_BYPASS`
  - `PIPANE_SECURE_COOKIE`
  - `PIPANE_PUBLIC_URL`
  - `PI_PUBLIC_HOSTNAME`

### Review Tasks

- Validate cookie flags, token handling, local bypass behavior, and remote URL assumptions.
- Confirm WebSocket auth checks match HTTP auth checks.
- Review reverse-proxy deployment guidance and failure modes.
- Check whether REST endpoints expose local files, settings, traces, or session state without sufficient guardrails.
- Add or improve tests for remote unauthorized HTTP and WebSocket access.

### Acceptance Criteria

- Auth behavior is documented as a clear local-only and reverse-proxy threat model.
- Tests cover authorized local, unauthorized remote, token-authenticated remote, and disabled-auth modes.
- Any insecure default or risky env combination is documented or changed.

## Ticket 4: Backend Process Pool and Session Lifecycle Correctness Review

### Goal

Audit process management for leaks, race conditions, zombie processes, incorrect session attachment, and hard-kill behavior.

### Scope

- `pipane/src/server/process-pool.ts`
- `pipane/src/server/session-lifecycle.ts`
- `pipane/src/server/ws-handler.ts`
- `pipane/src/server/attached-session.ts`
- Tests for those modules

### Review Tasks

- Trace lifecycle transitions for prompt, abort, hard kill, crash, steering queue update, and process reuse.
- Check whether concurrent prompts for the same or different sessions can attach incorrectly.
- Inspect cleanup paths for event listeners, pending requests, busy processes, and decommissioned processes.
- Validate `PI_MAX_PROCESSES` and `PI_PREWARM_COUNT` edge cases.
- Add targeted regression tests for races or cleanup gaps found during review.

### Acceptance Criteria

- A lifecycle state diagram or transition table exists for normal and failure paths.
- Race-prone paths have unit tests or documented invariants.
- No known process cleanup path leaves stale attached sessions or unreachable busy processes.

## Ticket 5: WebSocket Protocol and Client Adapter Contract Review

### Goal

Review the frontend/backend WebSocket command and event contract for reliability, versioning, validation, and recovery behavior.

### Scope

- `pipane/src/server/ws-handler.ts`
- `pipane/src/client/ws-agent-adapter.ts`
- `pipane/src/client/ws-agent-adapter.test.ts`
- Related e2e tests:
  - `pipane/e2e/real-stack.e2e.ts`
  - `pipane/e2e/rerun-duplicate.e2e.ts`
  - `pipane/e2e/steering.e2e.ts`

### Review Tasks

- Inventory all WebSocket command and event shapes.
- Check whether incoming messages are validated before acting on them.
- Review reconnect, resubscribe, diff/snapshot, hash, and version handling.
- Test large sessions, interrupted streams, duplicate events, and reconnect while a turn is running.
- Decide whether protocol types should be centralized in `src/shared`.

### Acceptance Criteria

- The protocol surface is documented in one place.
- Invalid or malformed commands fail safely.
- Reconnect and duplicate-event behavior has explicit regression coverage.

## Ticket 6: Session JSONL, File Watching, and Path Safety Review

### Goal

Audit session persistence and file access for correctness, performance, and path safety.

### Scope

- `pipane/src/server/session-jsonl.ts`
- `pipane/src/server/session-index.ts`
- `pipane/src/server/session-cwd.ts`
- `pipane/src/shared/jsonl-sync.ts`
- `pipane/src/client/jsonl-panel.ts`
- Related tests and large-session fixture

### Review Tasks

- Check JSONL parsing behavior for malformed lines, partial writes, very large files, and unsupported message shapes.
- Review path handling for session files and project CWD extraction.
- Validate file watcher behavior for missed events, duplicate events, and detached versus attached sessions.
- Benchmark large-session load/render behavior using existing scripts and fixtures.
- Identify whether streaming/diff sync can corrupt or reorder visible messages.

### Acceptance Criteria

- Malformed and large JSONL cases have tests or documented handling.
- Path traversal or out-of-agent-dir access risks are assessed.
- Performance limits for session loading are measured and recorded.

## Ticket 7: REST API, Local Settings, and Load Trace Review

### Goal

Review local settings, trace endpoints, and REST API contracts for validation, persistence safety, and privacy.

### Scope

- `pipane/src/server/rest-api.ts`
- `pipane/src/server/local-settings.ts`
- `pipane/src/server/load-trace-store.ts`
- `pipane/src/client/local-settings-modal.ts`
- `pipane/src/client/load-trace.ts`
- Related tests

### Review Tasks

- Inventory REST endpoints and their request/response shapes.
- Check input validation and error responses.
- Review where settings and trace data are persisted, how long they live, and whether sensitive data can leak.
- Verify local settings reload behavior and client notification semantics.
- Add missing tests for invalid payloads and persistence failures.

### Acceptance Criteria

- REST endpoints have documented contracts.
- Invalid payloads and filesystem errors produce safe, test-covered responses.
- Trace and settings data privacy expectations are documented.

## Ticket 8: Client State, Rendering, and Component Maintainability Review

### Goal

Audit the largest client modules for state complexity, rendering performance, and maintainability.

### Scope

- `pipane/src/client/main.ts`
- `pipane/src/client/ws-agent-adapter.ts`
- `pipane/src/client/session-picker.ts`
- `pipane/src/client/pi-message-list.ts`
- `pipane/src/client/message-renderers.ts`
- `pipane/src/client/tool-renderers.ts`
- `pipane/src/client/app.css`

### Current Signals

Largest client files by line count include:

- `session-picker.ts`: ~1465 lines
- `ws-agent-adapter.ts`: ~1466 lines
- `app.css`: ~1186 lines
- `main.ts`: ~790 lines
- `tool-renderers.ts`: ~663 lines

### Review Tasks

- Identify modules that combine transport, state, rendering, and DOM side effects.
- Review Lit/component patterns and consistency with `pi-web-ui` usage.
- Check whether global state and document-level listeners are cleaned up correctly.
- Profile large-session rendering and auto-collapse behavior.
- Propose focused extractions only where they reduce risk or improve testability.

### Acceptance Criteria

- The review lists concrete refactor candidates with expected benefit and risk.
- Performance-sensitive render paths have measurements or targeted tests.
- Any recommended refactor is split into smaller implementation tickets.

## Ticket 9: UI, Accessibility, and Responsive Behavior Review

### Goal

Assess whether core workflows are usable, accessible, and robust across viewport sizes.

### Scope

- `pipane/src/client/app.css`
- `pipane/src/client/main.ts`
- `pipane/src/client/session-picker.ts`
- `pipane/src/client/theme-selector.ts`
- `pipane/src/client/canvas-panel.ts`
- `pipane/e2e/ui-screenshots.e2e.ts`
- `pipane/e2e/wide-layout.e2e.ts`
- `pipane/e2e/input-clear.e2e.ts`
- `pipane/e2e/focus-new-session.e2e.ts`

### Review Tasks

- Test keyboard navigation for session picker, message input, model picker, settings, JSONL panel, and canvas panel.
- Check focus management in modals and after session changes.
- Audit color contrast across built-in themes.
- Review mobile sidebar and responsive layout behavior.
- Validate screenshot goldens still cover the main visual states.

### Acceptance Criteria

- Accessibility issues are logged with severity and affected workflow.
- Keyboard-only smoke tests exist for the most important workflows.
- Any visual regressions are captured through screenshot tests or documented manual checks.

## Ticket 10: Packaging, CLI, Publish, and Production Runtime Review

### Goal

Audit whether pipane installs, builds, starts, and publishes reliably as an npm package.

### Scope

- `pipane/bin/pipane.js`
- `pipane/package.json`
- `pipane/dev.sh`
- `pipane/prod.sh`
- `pipane/test.sh`
- `pipane/extensions/canvas.ts`
- `pipane/patches/*`
- `pipane/README.md`
- `docker/*`

### Review Tasks

- Verify `npm pack` contents match expected runtime files.
- Confirm the CLI bin resolves production server paths correctly after install.
- Test `npm run build`, `npm start`, `npm pack --dry-run`, and a local package install smoke test.
- Review postinstall patch behavior for fresh installs.
- Check Docker files and reverse-proxy examples against current runtime assumptions.

### Acceptance Criteria

- A release smoke-test checklist exists and passes locally.
- Package contents are intentional and minimal.
- Docker and README instructions match actual env vars and ports.

## Ticket 11: Test Strategy, Coverage, and CI Workflow Audit

### Goal

Evaluate whether the existing test suite gives enough confidence for core behavior and dependency upgrades.

### Scope

- `pipane/AGENTS.md`
- `pipane/package.json` scripts
- `pipane/vitest.config.ts`
- `pipane/playwright.config.ts`
- `pipane/e2e/*`
- Unit tests under `pipane/src/**/*test.ts`

### Review Tasks

- Run `npm run check`, `npm run test`, `npm run build`, and Playwright e2e.
- Compare test coverage to risk areas: auth, WebSocket protocol, process lifecycle, JSONL sync, settings, install flow, UI rendering.
- Identify flaky or slow tests and whether they can be split into smoke versus exhaustive suites.
- Decide whether CI should run screenshot tests by default or only on demand.
- Add missing test commands to documentation if current guidance is incomplete.

### Acceptance Criteria

- Test commands and expected runtime are documented.
- Known gaps are listed with recommended tests.
- CI recommendations distinguish required checks from optional/manual checks.

## Ticket 12: Documentation and Developer Experience Audit

### Goal

Review whether contributors and users can safely develop, run, configure, and troubleshoot pipane.

### Scope

- `pipane/README.md`
- `pipane/AGENTS.md`
- `docker/README.md`
- `pipane/package.json` scripts
- Environment variables referenced across `pipane/src/server/*`

### Review Tasks

- Inventory all env vars and document purpose, default, and security implications.
- Check quickstart instructions against current install/build behavior.
- Add troubleshooting notes for missing `pi`, auth URL, reverse proxy, failed patches, and stale sessions.
- Review whether docs accurately describe the test suite and e2e harness.
- Decide whether architecture notes should live in README or a separate `docs/` file.

### Acceptance Criteria

- Documentation reflects the current runtime and test behavior.
- Env vars are documented with defaults and warnings.
- Contributor setup has a clear path from clone to passing checks.

## Ticket 13: Upstream Patch and Fork Delta Review

### Goal

Understand and reduce the long-term maintenance risk from local patches against upstream packages.

### Scope

- `pipane/patches/@mariozechner+mini-lit+0.2.1.patch`
- `pipane/patches/@mariozechner+pi-web-ui+0.55.3.patch`
- `pipane/vite.config.ts` aliasing to `pi-web-ui/src/index.ts`
- Any imports from `@mariozechner/*`

### Review Tasks

- Summarize what each patch changes and why pipane needs it.
- Check whether newer upstream versions have absorbed the patch behavior.
- Identify patch hunks that are likely to break during `0.55.3` to `0.73.1` upgrades.
- Decide whether each patch should remain, be upstreamed, or be replaced by local extension code.

### Acceptance Criteria

- Each patch has a written owner/rationale/status.
- Upgrade blockers caused by patches are known before dependency updates.
- A preferred path exists for removing or reducing patch-package reliance.

## Ticket 14: Performance and Large Session Scalability Review

### Goal

Measure and improve behavior for large sessions, long tool outputs, screenshots, JSONL view, and render-heavy histories.

### Scope

- `pipane/scripts/bench-sessions.ts`
- `pipane/e2e/render-perf.e2e.ts`
- `pipane/e2e/fixtures/generate-large-session.ts`
- `pipane/src/client/pi-message-list.ts`
- `pipane/src/client/auto-collapse.ts`
- `pipane/src/client/jsonl-panel.ts`
- `pipane/src/server/session-jsonl.ts`

### Review Tasks

- Run existing session benchmark and render performance e2e.
- Measure initial load, session switch, scroll, auto-collapse, and JSONL panel open times.
- Check memory growth while streaming long outputs.
- Identify virtualization, chunking, or incremental parsing opportunities if needed.

### Acceptance Criteria

- Baseline metrics are captured with hardware/browser notes.
- Any performance regression threshold is proposed for future tests.
- Recommended optimizations are split into small follow-up tickets.

