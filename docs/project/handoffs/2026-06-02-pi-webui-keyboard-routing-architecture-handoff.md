# pi-webui Keyboard Routing Architecture Handoff

Date: 2026-06-02

## Goal

Continue from the frontend review of the `@` file completion feature into a small architecture improvement around keyboard priority and precedence in `pi-webui`.

Do not re-copy the full `@` file completion requirements. Use the existing artifacts below as the source of truth.

## References

- Domain vocabulary: `pi-webui/CONTEXT.md`
- `@` file completion plan and keyboard precedence requirements: `docs/project/plans/PLAN-005-pi-webui-at-file-completion.md`
- TUI steering and Escape abort behavior: `docs/project/prds/PRD-002-pi-webui-tui-steering-followup.md`
- Current browser integration point: `pi-webui/public/app.js`
- File completion UI module: `pi-webui/public/file-completion-controller.mjs`
- Existing modal commit/cancel ownership module: `pi-webui/public/modal-controller.mjs`
- Existing file completion tests: `pi-webui/test/file-completion-controller.test.mjs`

## Current Fix Applied

The review found that Escape consumed by the **File Completion UI Module** could still bubble to the document Escape handler and abort a running agent.

The small codebase-level fix has been applied in `pi-webui/public/app.js`: the document `keydown` handler now returns immediately when `event.defaultPrevented` is already true. This makes local handlers that call `preventDefault()` the higher-priority key owners before global document shortcuts run.

This also covers the same shape for slash-menu Escape and modal Escape paths, where local handlers prevent default before hiding their UI.

## Architecture Finding

Keyboard precedence is currently an implicit behavior spread across DOM listener order, event bubbling, `preventDefault()`, menu hidden state, and controller return values.

The bug is a symptom of that implicit **Interface**. A fresh agent should look for a deeper **Module** that gives keyboard routing better locality and a testable precedence contract.

## Deepening Candidates

1. **Keyboard Routing Module**

   Files involved: `pi-webui/public/app.js`, `pi-webui/public/file-completion-controller.mjs`

   Problem: file completion, slash completion, modal behavior, chat scrolling, composer submit, history navigation, and global abort compete through scattered handlers.

   Direction: concentrate the rule "higher-priority UI owns the key; global shortcuts only run on unhandled keys" behind one small browser-side Module.

   Test benefit: add direct precedence tests for file completion Escape, slash Escape, modal Escape, plain running Escape abort, PageUp/PageDown scrolling, and composer submit/history behavior.

2. **Modal Keyboard Module**

   Files involved: `pi-webui/public/app.js`, `pi-webui/public/modal-controller.mjs`

   Problem: `modal-controller.mjs` already centralizes commit-vs-cancel ordering, but modal key handling still lives in mode-specific listeners. `showConfirmModal()` appears to add a `modalDialog` keydown listener on each open without removing the previous listener.

   Direction: deepen the existing modal Module so it owns modal keyboard lifecycle as well as cancel callback ordering.

   Test benefit: modal Escape/Enter/Tab behavior can be tested through the modal Module instead of relying on full app event flow.

3. **Composer Key Arbitration Module**

   Files involved: `pi-webui/public/app.js`, `pi-webui/public/file-completion-controller.mjs`

   Problem: composer key ownership is encoded as a long ordered handler: file completion, slash menu, submit, history navigation, and running-session controls.

   Direction: extract the composer-specific key precedence rules into a Module while keeping the **File Completion UI Module** and slash menu state separate.

   Test benefit: tests can ask "given key plus composer state, which action wins?" without requiring the full DOM document handler.

## Recommended Next Step

Start with candidate 1 unless the confirm-modal listener accumulation needs immediate attention. Keep the first pass small: document the desired precedence contract, add focused tests that fail without the current `event.defaultPrevented` guard, then decide whether the routing Module should cover all document-level shortcuts or only composer-related keys.

Avoid introducing a new seam just for hypothetical adapters. The value is locality for the existing keyboard owners and leverage for tests, not abstraction for its own sake.

## Notes For The Next Agent

- The `pi-webui` working tree was already dirty when this handoff was written; do not revert unrelated staged or unstaged file-completion changes.
- The review discussion identified `preventDefault()` as the intended "handled" signal. `stopPropagation()` was considered too narrow for the codebase-level fix.
- `window.addEventListener("keydown", ...)` near the scroll-follow code still marks user input regardless of `defaultPrevented`; check whether that matters before changing it.
- The existing file-completion controller tests verify the controller consumes Escape, but they do not exercise bubbling into `app.js`. That is the gap the routing work should close.
