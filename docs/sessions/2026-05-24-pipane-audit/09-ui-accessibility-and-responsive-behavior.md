# Ticket 9: UI, Accessibility, and Responsive Behavior Review

Date: 2026-05-24
Scope inspected:

- `pipane/src/client/app.css`
- `pipane/src/client/main.ts`
- `pipane/src/client/session-picker.ts`
- `pipane/src/client/theme-selector.ts`
- `pipane/src/client/canvas-panel.ts`
- Related UI surfaces needed for scoped workflows: `jsonl-panel.ts`, `model-picker-dialog.ts`, `local-settings-modal.ts`
- `pipane/e2e/ui-screenshots.e2e.ts`
- `pipane/e2e/wide-layout.e2e.ts`
- `pipane/e2e/input-clear.e2e.ts`
- `pipane/e2e/focus-new-session.e2e.ts`

Validation note: this was a research-only static/code/test coverage audit. I did not run screenshot tests because `ui-screenshots.e2e.ts` deletes and rewrites `pipane/e2e/latest/*.png` on startup.

## Workflow Coverage Matrix

| Workflow | Current behavior observed | Existing automated coverage | Gaps / follow-ups |
| --- | --- | --- | --- |
| Session picker list | Main sessions are native `<button>` controls; search is a native input. Session switch clears search and focuses the message textarea via `main.ts` session-change handler. | `focus-new-session.e2e.ts` verifies the group `+` new-session path returns focus to textarea. `ui-screenshots.e2e.ts` captures the desktop session list. | No keyboard-only smoke for tab order through search, session items, show-more, pin/delete controls, burger menu, or folder picker. Pin/delete are rendered as nested non-focusable spans inside a session button. |
| Message input | `message-editor` receives `onSend`, `onAbort`, model selector, attachment button, and extra toolbar buttons. Enter and Meta/Ctrl+Enter paths are handled. | `input-clear.e2e.ts` verifies the textarea clears after Enter send. `focus-new-session.e2e.ts` verifies focus after creating a new session. `ui-screenshots.e2e.ts` captures empty and filled input. | No keyboard smoke for model picker opening/selection, abort/stop, attachment controls, thinking toggle, or toolbar tab order. Upstream `message-editor` internals were not audited here. |
| Model picker | Opens as a document-body overlay, focuses the search input, supports Escape and backdrop/cancel close. Model rows are native buttons. | No scoped e2e coverage found. | Missing `role="dialog"`, accessible name association, `aria-modal`, focus trap, focus restore to opener, and keyboard test for search/filter/select/cancel. |
| Settings modal | Opens as document-body overlay, focuses textarea after loading, supports Escape/backdrop/cancel close when not busy. Buttons are native. | No scoped e2e coverage found. | Missing `role="dialog"`, accessible name, `aria-modal`, focus trap, focus restore to opener, status live region, and small-screen footer/wrapping validation. |
| JSONL panel | Togglable from burger menu; header action buttons are native buttons with titles; line expansion headers are clickable divs. | `real-stack.e2e.ts` has functional JSONL jump coverage, outside the named e2e scope. No screenshot golden in scoped screenshot suite. | Line expand/collapse is mouse-only; panel lacks landmarks/region labelling; no keyboard smoke for open, close, collapse all, expand all, or per-line expansion. |
| Canvas panel | Opens/restores on canvas tool results when enabled; close button is native button with title; body scrolls. | `canvas-panel.test.ts` covers restore behavior. `ui-screenshots.e2e.ts` captures a `tool-canvas.png` tool renderer but not the side panel because mocked settings disable canvas. | No keyboard smoke or visual golden for the actual side panel. On mobile it becomes a full-screen fixed panel without dialog semantics, Escape close, focus management, or focus restore. |
| Mobile sidebar | Desktop sidebar is removed under 768px and replaced by an absolute hamburger plus fixed overlay/backdrop; session selection closes overlay. | No scoped e2e mobile viewport coverage found. | No mobile keyboard/focus validation. Overlay lacks Escape close, role/label, focus trap, focus restore, and likely allows tabbing behind the overlay. |

## Accessibility Findings

### High: Portal overlays do not implement dialog semantics or focus containment

Affected workflows: model picker, local settings, mobile sidebar overlay, mobile canvas/JSONL full-screen panels.

Evidence:

- `model-picker-dialog.ts` creates `.model-picker-overlay` / `.model-picker-panel` as plain divs, focuses search, and only handles Escape/backdrop/cancel close. There is no `role="dialog"`, `aria-modal`, accessible labelling, focus trap, inert background, or opener focus restoration.
- `local-settings-modal.ts` similarly creates plain div overlay/panel, focuses textarea after load, and closes via Escape/backdrop/cancel without dialog semantics, trapping, or focus restoration.
- `main.ts` renders the mobile sidebar overlay as plain divs. It closes on backdrop click or session switch, but has no Escape close and no focus management.
- `app.css` makes canvas and JSONL panels full-screen fixed overlays on mobile, but the underlying panel implementations remain plain side-panel structures.

Impact: keyboard and screen-reader users can lose context, tab behind overlays, miss modal boundaries, or fail to return to the invoking control. This is most severe on mobile-sized viewports where side panels become full-screen overlays.

Recommendation: centralize modal/overlay behavior: `role="dialog"`, `aria-modal="true"`, `aria-labelledby`, initial focus, focus trap, Escape handling, background inert/aria-hidden, and restore focus to the opener.

### Medium: JSONL per-line expand/collapse is mouse-only

Affected workflow: JSONL panel.

Evidence: each JSONL entry header is a clickable `<div class="jsonl-entry-header" @click=...>`, not a button and not keyboard-focusable.

Impact: keyboard-only users can reach header action buttons but cannot expand or collapse individual JSONL entries without a pointing device.

Recommendation: render line headers as `<button>` elements or add `tabindex="0"`, button role, `aria-expanded`, and Enter/Space key handling. Prefer a real button.

### Medium: Session pin/delete controls are nested non-focusable spans inside session buttons

Affected workflow: session picker.

Evidence: `renderGroup()` renders the main session row as a `<button class="session-item">`, then renders `.pin-btn` and `.delete-btn` as `<span>` elements inside it with click handlers.

Impact: pin/delete are not directly reachable by keyboard tabbing or announced as controls. Nesting interactive behavior inside a button also makes activation semantics ambiguous.

Recommendation: split each session row into a row container with separate buttons for session selection, pin, and delete, or expose row-level keyboard shortcuts with visible/announced controls.

### Medium: Folder picker lacks focus management and Escape close

Affected workflow: session picker `+ NEW` / open folder.

Evidence: `openFolderPicker()` toggles `showFolderPicker` and starts browsing, but no focus is moved to the path input. `renderFolderPicker()` contains a close button and path input but no Escape handler or focus restoration.

Impact: after opening the folder picker with keyboard, focus can remain on a control hidden under the overlay. Keyboard users may need extra tabbing to discover the path input and cannot dismiss with Escape.

Recommendation: focus the folder path input on open, support Escape, and restore focus to the opening `+ NEW` button on close.

### Low: Icon-only controls rely on `title`, not accessible labels

Affected workflows: burger menu, mobile sidebar button, JSONL header actions, canvas close, session pin/delete, thinking toggle.

Evidence: many icon buttons use only `title` for naming.

Impact: `title` is inconsistently exposed across assistive technology and is poor for touch users.

Recommendation: add explicit `aria-label` on icon-only buttons. Keep `title` only as a visual tooltip fallback.

## Responsive And Theme Findings

### Responsive behavior

- Wide desktop layout has a targeted e2e regression test: `wide-layout.e2e.ts` verifies the chat and input wrappers are not capped at `max-w-3xl` on a 1900px viewport.
- Mobile layout is implemented in CSS and render logic: the desktop sidebar is removed below 768px, a mobile sidebar button is shown, sidebar overlay is fixed, and canvas/JSONL side panels become full-screen fixed panels.
- No scoped mobile e2e/screenshot coverage exists for 375px/390px/768px widths, mobile sidebar open/close, mobile side panels, or input toolbar overflow.
- Settings and model picker panels use `96vw` widths and viewport-constrained heights, but footer/action wrapping is not validated. Settings footer uses horizontal flex rows and may overflow on narrow screens with all actions visible.

### Theme / contrast

Built-in themes: default and gruvbox; dark mode can be light, dark, or system.

Likely contrast issues from declared gruvbox tokens and hard-coded CSS:

- `.local-settings-btn-primary` forces `color: white` on a theme-mixed primary background. With gruvbox light primary `#458588`, white-on-primary is about 4.23:1 before the 85% mix with white, below WCAG AA for normal text.
- Gruvbox light `--primary-foreground` on `--primary` is about 3.73:1 using the documented approximations, also below AA for normal text.
- Gruvbox light `--muted-foreground` on `--background` is about 4.29:1, slightly below AA for normal text. This affects small metadata labels throughout the sidebar and panels.
- Gruvbox light JSONL syntax colors are notably low contrast on the gruvbox light background: string green `#98971a` is about 2.73:1 and number yellow `#d79921` is about 2.19:1.
- Dark gruvbox core foreground/muted combinations look better by approximation, but JSONL syntax and active/hover states still need browser-computed verification because several colors use `color-mix()` and inherited tokens.

Recommendation: add browser-computed contrast checks for theme/mode combinations, especially gruvbox light JSONL syntax, muted metadata, primary buttons, active session state, and status/error banners.

## Screenshot Coverage Assessment

Current scoped goldens cover:

- Desktop session list (`session-list.png`)
- Full desktop tool-renderer page (`tool-renderers-full.png`)
- Individual tool renderer states for read/edit/write/bash success/bash error/canvas tool result
- Input empty and filled states
- Steering queue alone and in context
- Bash in-progress page state

Important visual states not captured in scoped goldens:

- Mobile sidebar closed/open states
- Mobile message input and toolbar wrapping
- Model picker dialog
- Local settings modal
- Folder picker overlay
- JSONL panel open/empty/populated/collapsed/long-string states
- Canvas side panel open on desktop and full-screen on mobile
- Theme matrix: default light/dark and gruvbox light/dark
- Reconnection/error banners
- Focus-visible states for keyboard navigation

The screenshot suite currently uses mocked local settings with `canvas.enabled: false`, so the actual canvas side panel is not visually protected by `ui-screenshots.e2e.ts`.

## Recommended Tests / Follow-ups

1. Add keyboard-only smoke tests for:
   - Session picker tab order: burger, `+ NEW`, search, session select, show more, group `+`, pin/delete after controls are made focusable.
   - Folder picker open/focus path input/Escape close/focus restore.
   - Model picker open/search/arrow or tab to model/select/Escape close/focus restore.
   - Settings modal open/focus textarea/Tab containment/Escape close/status announcement.
   - JSONL panel open/close/header actions/per-line expansion via keyboard.
   - Canvas panel close via keyboard and Escape behavior on mobile.

2. Add Playwright accessibility checks for modal invariants:
   - Exactly one active modal has `role="dialog"` and `aria-modal="true"`.
   - Focus remains within modal while open.
   - Invoker regains focus after close.

3. Add responsive screenshot tests at representative widths:
   - 390x844 mobile: main chat, sidebar open, input filled, model picker, settings modal, JSONL/canvas full-screen panels.
   - 768px breakpoint edge.
   - 1440 desktop with JSONL/canvas side panels.
   - 1900 wide layout is already covered functionally; consider a visual golden if visual regressions matter.

4. Add theme screenshot/contrast checks:
   - default light/dark and gruvbox light/dark.
   - Include JSONL syntax colors, muted sidebar metadata, active session, primary buttons, error/reconnect banners, and input toolbar.

5. Resolve design ambiguity: decide whether JSONL and canvas panels are side panels, modal overlays on mobile, or persistent application regions. Their accessibility model should follow that decision:
   - Side panel/region: labelled `aside`/`region`, normal tab order, no focus trap.
   - Modal overlay: dialog semantics, focus trap, Escape, background inert, focus restore.

## Acceptance Summary

- Accessibility issues are logged above with severity and affected workflow.
- Existing keyboard-only coverage is limited to input clearing on send and focusing the textarea after group-new-session creation; gaps are named.
- Responsive and theme risks are documented, with specific missing mobile and contrast validations.
- Screenshot goldens cover core desktop visual states and tool renderers but do not yet cover mobile, modals, side panels, theme matrix, or focus-visible states.
