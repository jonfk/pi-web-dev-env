# Ticket 8: Client State, Rendering, and Component Maintainability Review

Date: 2026-05-24
Scope:
- `pipane/src/client/main.ts`
- `pipane/src/client/ws-agent-adapter.ts`
- `pipane/src/client/session-picker.ts`
- `pipane/src/client/pi-message-list.ts`
- `pipane/src/client/message-renderers.ts`
- `pipane/src/client/tool-renderers.ts`
- `pipane/src/client/app.css`

Research only. No code or test changes were made.

## Summary

The client has a generally sound direction: server-authoritative flat message state, a small `pi-message-list` wrapper over upstream `pi-web-ui` leaf components, coalesced `session_sync`, sidebar truncation, message-list initial truncation, and auto-collapse for completed tools. The highest maintainability risk is not one broken component, but responsibility concentration in `main.ts`, `ws-agent-adapter.ts`, `session-picker.ts`, and `tool-renderers.ts`.

The most performance-sensitive path is large transcript rendering. It has a dedicated Playwright perf test, but that test currently feeds legacy `session_messages`, disables truncation, and requires generated/built artifacts before it can produce fresh numbers. Current runtime mitigations are useful (`messages.initialCount`, sidebar per-project truncation, tool auto-collapse, sync coalescing), but the render path still rebuilds maps/items and runs DOM scans after every content render. Add current-protocol measurements before doing heavier refactors such as virtualization.

## Module Responsibility Map

| Module | Primary responsibilities | Mixed concerns observed | Notes |
|---|---|---|---|
| `main.ts` | App bootstrap, storage shim setup, global render function, responsive shell, message-editor wiring, sending/forking, settings loading, canvas/JSONL panel orchestration, auto-scroll, install prompts, global event listeners | Transport event wiring, local UI state, DOM querying, modal side effects, settings fetches, render scheduling | Largest risk is central orchestration with many top-level mutable variables and no teardown path. |
| `ws-agent-adapter.ts` | WebSocket connection, reconnect, request/response RPCs, server event handling, session sync application, session lifecycle state, optimistic sessions, steering queues, slash commands, model/thinking selection | Transport, state store, protocol typing, command UI behavior, synthetic chat messages, `window.dispatchEvent` for `/fork` | Large but partly cohesive as an adapter; slash commands and protocol definitions are the easiest extractions. |
| `session-picker.ts` | Sidebar session list UI, grouping/sorting/filtering, pin persistence, fetching/debouncing sessions, folder picker, burger menu portal, theme/actions menu | Data fetching, session derived model, local storage persistence, global body portal, theme selector UI, folder browser | Strong unit coverage exists, but component size is inflated by CSS and multiple sub-features. |
| `pi-message-list.ts` | Flat render of `AgentMessage[]`, inline tool-result map, initial transcript truncation, upstream/custom message renderer dispatch | Minimal; render-time derivation and display count are colocated | Cohesive and small. Performance is sensitive because it processes the whole message array every render. |
| `message-renderers.ts` | Registers custom user and compaction-summary renderers | Fullscreen image overlay DOM side effects, duplicate toggle logic from tool renderers | Small, but shared collapse/toggle helpers should be central if compaction/tool UI evolves. |
| `tool-renderers.ts` | Registers Read/Write/Edit/Bash/Canvas/fallback renderers, highlighting, custom tool layout, streaming scroll pin, DOM toggle side effects | Rendering, DOM mutation, scroll observers, highlighting setup, diff algorithm, auto-collapse notification | Biggest rendering hotspot after message list. Observer lifecycle is not cleaned up when refs detach. |
| `app.css` | Global/light-DOM styles for upstream components, tool density, message/editor overrides, mobile shell, canvas, JSONL, modals, theme selector, show-earlier button | Styles for many component ownership domains in one file; selector coupling to upstream DOM | Useful as integration CSS, but fragile around upstream `pi-web-ui` structure. |

## Maintainability Findings

### High: `main.ts` is the orchestration bottleneck

`main.ts` owns many independent state cells (`mobileSidebarOpen`, `steeringQueue`, `prefetchedSessions`, `autoScroll`, `canvasFeatureEnabled`, `messagesInitialCount`, hard-kill prompt state) and drives the whole UI through one top-level `renderApp()` (`main.ts:43-70`, `main.ts:346-497`). It also configures `message-editor` by querying the DOM after render (`main.ts:87-122`, `main.ts:489-497`), installs document/window listeners (`main.ts:51-58`, `main.ts:182-208`, `main.ts:741`), fetches local settings twice (`main.ts:560-574`, `main.ts:641-656`), and wires adapter events to canvas/JSONL/sidebar/editor side effects (`main.ts:612-706`).

This is functional for a single-page app, but every new panel or setting now increases the chance of accidental render loops, stale DOM queries, and untested teardown behavior. The best extraction is not a broad rewrite. Split a few stable seams:
- `local-settings-client.ts`: load/refresh typed local settings once and expose `{ canvasFeatureEnabled, sessionsPerProject, messagesInitialCount }`.
- `chat-shell-state.ts` or a small `PiAppShell` component: own responsive sidebar state, auto-scroll state, and `pi-message-list` reset/focus effects.
- `panel-orchestrator.ts`: centralize canvas/JSONL init/refresh hooks currently spread across `renderApp()` and adapter listeners.

Benefit: lower blast radius for UI changes and easier tests for settings and shell behavior. Risk: moving too much at once could destabilize startup; extract one concern per ticket.

### High: `ws-agent-adapter.ts` combines adapter state with command/UI policy

The adapter is the right place for WebSocket reconnect, request IDs, pending requests, session sync, and server-authoritative state (`ws-agent-adapter.ts:43-145`, `ws-agent-adapter.ts:273-372`, `ws-agent-adapter.ts:621-742`). It also implements slash commands, help markdown, model/thinking UI policy, optimistic session display records, and emits a browser event for `/fork` (`ws-agent-adapter.ts:1029-1194`, `ws-agent-adapter.ts:1205-1237`, `ws-agent-adapter.ts:1308-1351`).

Concrete extraction candidates:
- Move slash command parsing and help-message construction to `slash-commands.ts`, injected with adapter methods. Keep adapter as executor.
- Move model/thinking support inference to a shared helper; it is duplicated with `main.ts` (`main.ts:231-241`, `ws-agent-adapter.ts:852-866`).
- Align `WsCommand` with the protocol ticket: the local union omits commands the adapter sends, including `get_default_model`, `get_session_statuses`, `remove_steering`, `fork_prompt`, and `cwd` on new prompts.

Benefit: improves protocol clarity and enables focused tests without instantiating the full adapter. Risk: slash commands mutate chat state today; preserve exact emitted messages and events.

### Medium: `session-picker.ts` is a component plus a small application

The sidebar has good behavior-focused tests for sorting, statuses, search, truncation, and active highlighting. The risk is size and ownership: `session-picker.ts` includes about 600 lines of CSS, session fetching/debounce/single-flight logic, derived grouping/sorting, pin persistence, folder browsing, and a portalled burger menu (`session-picker.ts:54-627`, `session-picker.ts:638-843`, `session-picker.ts:859-941`, `session-picker.ts:1129-1217`).

Focused extractions:
- `session-list-model.ts`: pure `filter/group/sort/truncate` functions. Existing tests can move from DOM-heavy assertions toward pure model assertions plus a small rendering smoke test.
- `session-picker-menu.ts`: burger menu portal and theme actions. This isolates document-body rendering and removes theme UI from session list logic.
- `folder-picker.ts`: folder browser subcomponent, once folder creation behavior stabilizes.

Benefit: keeps the well-tested behavior but makes changes easier to review. Risk: Lit state ownership and portal positioning can regress; keep the first ticket pure-model only.

### Medium: DOM side effects and listener cleanup are uneven

Positive examples:
- `session-picker` unsubscribes adapter listeners, clears timers, and removes its portal in `disconnectedCallback()` (`session-picker.ts:729-747`).
- `installChatJsonlJumpListener()` is guarded so it installs once (`main.ts:182-208`).

Risks:
- `WsAgentAdapter.connect()` installs a `document.visibilitychange` listener every time `connect()` is called and exposes no `disconnect()` teardown (`ws-agent-adapter.ts:289-299`).
- `main.ts` installs `window.resize`, `document.click`, and `window.pi-fork-request` listeners without teardown. For the current one-shot app this is acceptable, but it makes component tests/hot reload/reinitialization brittle (`main.ts:51-58`, `main.ts:182-208`, `main.ts:741`).
- `createScrollPin()` installs `scroll` listeners and `MutationObserver`s on tool body elements, but the Lit ref callback ignores `undefined` detach and never removes the listener from the previous element (`tool-renderers.ts:72-135`). If renderer instances are long-lived while many tool bodies are replaced, old elements can retain observer/listener closures until garbage collection. The observer is disconnected only when a new element is assigned.
- `message-renderers.ts` adds an Escape key listener for image fullscreen and removes it only on Escape, not on click-close (`message-renderers.ts:15-31`).

Recommended ticket: add teardown-aware helpers for global listeners and scroll pins. This is low feature risk and directly improves maintainability.

### Medium: `tool-renderers.ts` has duplicated render structure and hidden performance costs

Read/Write/Edit/Bash/Fallback renderers duplicate the same gutter/header/body/collapse structure (`tool-renderers.ts:260-655`). They also parse params, compute highlighted HTML, and sometimes run `simpleDiff()` inside render (`tool-renderers.ts:376-402`, `tool-renderers.ts:407-467`). Highlighting uses `unsafeHTML`, but its source is `highlight.js` output from text content; that is a common pattern, still worth keeping covered by renderer tests when adding languages.

Focused extraction:
- `tool-renderer-shell.ts`: one helper that takes icon/state/header/body and returns the shared gutter layout.
- `tool-renderer-utils.ts`: param parsing, result text, language detection, highlighting, collapse toggle.
- Keep each tool renderer class small and tool-specific.

Benefit: reduces inconsistent behavior across tool types and makes auto-collapse/collapse accessibility easier to fix once. Risk: visual regressions; pair with existing `ui-screenshots` tool-renderer snapshots.

### Low: `app.css` is an integration stylesheet with fragile upstream selectors

The CSS intentionally styles light-DOM/upstream components, but several selectors depend on upstream DOM class structure, for example token usage and editor overrides (`app.css:30-46`). It also owns unrelated domains in one file: burger dropdown, message density, mobile shell, canvas, model picker, local settings, JSONL viewer, theme selector, and show-earlier button (`app.css:57-1183`).

Recommended tickets:
- Split by domain into imported CSS files only if the build path supports it cleanly: `chat.css`, `tools.css`, `panels.css`, `modals.css`, `sidebar-menu.css`.
- Add comments naming upstream-coupled selectors and the expected DOM shape.

Benefit: safer edits and easier ownership. Risk: CSS import order regressions; do this only after screenshot coverage is green.

## Rendering and Performance Observations

### Current mitigations

- `pi-message-list` supports `initialCount` and defaults to showing the last configured messages, with "Show earlier messages" pagination (`pi-message-list.ts:31-111`). Local settings expose `messages.initialCount` and `main.ts` passes it through (`main.ts:68-70`, `main.ts:560-574`, `main.ts:431-438`).
- `session-picker` truncates visible sessions per project and ensures running sessions remain visible (`session-picker.ts:1301-1388`).
- `auto-collapse` scans completed tool messages and collapses older tool bodies after new completions, with tests covering disabled, keep-last-N, in-progress, user-reopened, and "only runs when new tools complete" behavior (`auto-collapse.ts:48-96`, `auto-collapse.test.ts:37-188`).
- `ws-agent-adapter` coalesces high-frequency `session_sync` to at most one queued payload per animation frame (`ws-agent-adapter.ts:621-692`).

### Hot paths to measure before refactoring

- `pi-message-list.render()` builds a full `toolResultsById` map and calls `buildRenderItems()` over all messages before slicing to the visible window (`pi-message-list.ts:61-104`). This means `initialCount=50` limits DOM output, but not all CPU work for huge sessions.
- `buildRenderItems()` calls `isLastAssistantMessage()` for each assistant message, and that helper scans backward through `messages` (`pi-message-list.ts:114-171`). In assistant-heavy transcripts this can become quadratic-ish. A low-risk fix is to compute the last assistant message index once per render.
- `runAutoCollapse()` does a document-wide `querySelectorAll("tool-message[data-tool-call-id]")` after content renders (`auto-collapse.ts:48-96`, `main.ts:489-497`). Its "completed length" guard prevents repeated collapse work, but the scan still scales with rendered tools.
- Tool renderers highlight code and compute diffs during render. Because `truncate()` is currently a no-op, large read/write/bash outputs can render in full despite call sites passing `4000` (`tool-renderers.ts:65-68`, `tool-renderers.ts:282-304`, `tool-renderers.ts:340-364`, `tool-renderers.ts:376-467`, `tool-renderers.ts:497-516`).
- `createScrollPin()` creates a `MutationObserver` per rendered tool body for streaming pinning (`tool-renderers.ts:72-135`). Completed tools do not need an active observer after final scroll.

### Existing measurements and targeted tests

- There is a dedicated `e2e/render-perf.e2e.ts` that measures large-session render time, DOM size, tool-message count, and scroll frame times. It uses a synthetic fixture described as 1,940 messages at a 10x multiplier and has a 10 second render budget (`render-perf.e2e.ts:2-9`, `render-perf.e2e.ts:133-191`, `render-perf.e2e.ts:194-258`).
- The generator builds realistic mixed user/assistant/tool-result sessions with large read/bash outputs (`e2e/fixtures/generate-large-session.ts:1-8`, `e2e/fixtures/generate-large-session.ts:212-380`).
- Important limitation: the perf E2E currently drives the client with legacy `session_messages`, not current `session_sync` (`render-perf.e2e.ts:92-100`). Ticket 5 also flags current-protocol large-session coverage as a gap.
- I did not run the perf E2E during this research pass. The fixture and built `dist/client` were not present in the working tree check, and running the test could generate artifacts/build output outside the assigned report. Follow-up should run it intentionally after building, capture baseline numbers in the ticket, and then convert it to `session_sync`.

## Lit and `pi-web-ui` Consistency

- `pi-message-list` deliberately uses upstream leaf elements (`assistant-message`, `user-message`, `tool-message`, `markdown-block`, `thinking-block`) while avoiding upstream `AgentInterface` and `MessageList`. This is consistent with the flat server state design.
- Custom renderers register through `pi-web-ui` extension points (`registerMessageRenderer`, `registerToolRenderer`, `setFallbackToolRenderer`) and return `isCustom: true` to avoid outer wrappers.
- Light DOM is intentionally used in `pi-message-list` so global/upstream styles apply (`pi-message-list.ts:47-49`). `session-picker` uses shadow DOM with component-local styles, except for its body portal menu which is styled globally in `app.css`.
- A consistency issue remains: collapse/toggle logic is implemented separately in `tool-renderers.ts`, `message-renderers.ts`, `auto-collapse.ts`, and CSS. Centralize collapse state helpers before adding more collapsible message types.

## Refactor Ticket Proposals

1. **Extract pure session list model from `session-picker.ts`.**
   - Scope: filtering, grouping, sorting, running/pinned precedence, truncation counts.
   - Benefit: lower-risk changes to sidebar behavior; faster unit tests.
   - Risk: low; keep DOM rendering unchanged.
   - Acceptance: existing `session-picker.test.ts` behavior covered by pure model tests plus one render smoke test.

2. **Make `pi-message-list` render derivation linear and add focused tests.**
   - Scope: compute `lastAssistantIndex` once; build only visible render items if custom renderers allow it; preserve tool-result mapping.
   - Benefit: reduces large transcript CPU even when `initialCount` limits DOM.
   - Risk: medium; inline tool results require a full `toolResultsById` map unless assistant/tool-result pairing changes.
   - Acceptance: tests for session switch reset, show-earlier behavior, last-assistant streaming flag, tool result inline mapping, and a synthetic large-array timing assertion or benchmark.

3. **Update render perf E2E to current `session_sync` and record baseline.**
   - Scope: mock server sends full `session_sync` with `{ messages, isStreaming, pendingToolCalls, model, thinkingLevel }`; run with both `initialCount=50` and `initialCount=0`.
   - Benefit: turns existing perf harness into current-protocol validation.
   - Risk: low; test-only.
   - Acceptance: report render time, DOM elements, tool messages, scroll long frames; retain budget or set baseline threshold.

4. **Extract `main.ts` settings and panel orchestration.**
   - Scope: one helper for local settings load/refresh; one helper for canvas/JSONL event reactions.
   - Benefit: reduces duplicate settings fetch logic and isolates side-panel side effects.
   - Risk: medium; startup order and first render are sensitive.
   - Acceptance: unit tests for settings parsing/defaults; smoke/e2e confirms first session load, settings save refresh, canvas/JSONL toggles.

5. **Extract slash commands from `WsAgentAdapter`.**
   - Scope: parse/execute `/help`, `/new`, `/fork`, `/compact`, `/name`, `/reload` through an injected command context.
   - Benefit: smaller adapter, clearer protocol boundary, easier command tests.
   - Risk: medium; command side effects are user-visible chat messages and session changes.
   - Acceptance: port existing slash-command adapter tests; add `/compact` and `/name` state-message tests.

6. **Add teardown-aware DOM side-effect utilities.**
   - Scope: scroll pin cleanup on Lit ref detach, global listener cleanup pattern, image fullscreen Escape cleanup on click-close.
   - Benefit: prevents leaks in long-lived sessions and improves test isolation.
   - Risk: low to medium; streaming auto-scroll behavior must be preserved.
   - Acceptance: happy-dom tests for observer/listener cleanup and streaming pin behavior.

7. **Create a shared tool renderer shell.**
   - Scope: common gutter/header/body/collapse rendering and shared toggle helper.
   - Benefit: reduces duplication and makes collapse/auto-collapse behavior consistent.
   - Risk: medium; visual diffs likely.
   - Acceptance: existing `tool-renderers.test.ts`, auto-collapse tests, and screenshot tests pass.

8. **Split `app.css` by ownership after screenshot baseline.**
   - Scope: move panel/modal/tool/chat/sidebar-menu styles into domain files imported by `main.ts`.
   - Benefit: easier review and fewer accidental selector collisions.
   - Risk: medium; CSS order and upstream selector overrides can regress.
   - Acceptance: screenshot suite and mobile layout checks pass.

## Test Gaps

- No focused `pi-message-list` tests for `initialCount`, show-earlier behavior, session-switch reset, last assistant streaming flag, or full-array CPU cost.
- Existing render perf E2E uses legacy `session_messages`, not `session_sync`, and I did not capture a fresh baseline in this pass.
- No adapter-level teardown test for `visibilitychange` listener or reconnect cleanup.
- No test for `createScrollPin()` cleanup when a tool body is removed or replaced.
- Tool renderer tests mostly cover bash registration/formatting; they do not cover Read/Write/Edit/Fallback rendering, highlighting behavior, no-op `truncate()`, or large output cost.
- No tests around `main.ts` orchestration because it is not structured for direct unit tests. Settings load/refresh, auto-scroll, sidebar mobile state, and panel refresh are currently mostly e2e/smoke concerns.
- CSS upstream-coupled selectors are not protected except by screenshot/e2e coverage.

## Follow-Ups and Ambiguities

- Decide whether `truncate()` being a no-op in `tool-renderers.ts` is intentional product behavior or an unfinished performance compromise. The comment says full content is currently desired, but call sites still pass `4000`.
- Confirm the desired threshold for large-session UX: fast last-50 initial render, acceptable show-all render, smooth scrolling, or all three. The implementation choice differs: derivation optimization, virtualization, and content truncation solve different parts.
- Run and record `e2e/render-perf.e2e.ts` after an intentional build, then convert it to `session_sync`.
- Decide whether `WsAgentAdapter` should grow an explicit `disconnect()` method. It is not needed for the current one-shot app lifecycle, but it would make tests and hot reload safer.
- Coordinate with Ticket 5 protocol work before editing adapter command types; shared protocol extraction should not be duplicated.
