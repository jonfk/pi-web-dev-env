# PLAN-004: pi-webui Explicit Runtime Targets

## Source Material

- Product requirements: `docs/project/prds/PRD-004-pi-webui-explicit-runtime-targets.md`
- Existing URL session state PRD: `docs/project/prds/PRD-003-pi-webui-url-session-state.md`
- Existing explicit cwd investigation: `docs/sessions/2026-05-29-explicit-cwd-selection-handoff.md`
- Domain vocabulary: `pi-webui/CONTEXT.md`

When this plan conflicts with PRD-003, prefer PRD-004. PRD-003 remains the baseline for URL Session Pointer and URL Cwd Pointer behavior, but PRD-004 removes default cwd fallback behavior.

## Goal

Make pi-webui own one selected runtime target as the source of truth for cwd/session selection. The Pi runtime becomes a derived execution adapter for that target. When no target exists, pi-webui enters an intentional no-runtime state with only runtime-free recovery operations available.

## Shared Invariants

- There is exactly one selected target, or no selected target.
- A runtime may exist only for a cwd target or session target.
- Runtime cwd must match the selected target cwd.
- `process.cwd()` is never used as a cwd fallback.
- No cwd environment variable is used as a pi-webui default cwd.
- Valid `lastCwd` is a target source because it came from prior explicit selection.
- Missing, invalid, or deleted `lastCwd` creates cwd-required state.
- Invalid URL state creates no runtime and does not compute fallback cwd recovery.
- Cwd-required state creates no runtime and is not invalid URL state.
- No-runtime "Choose session" lists all sessions only.
- Resuming or selecting a session persists the session header cwd as `lastCwd`.
- Generic command success does not persist `lastCwd`.
- Runtime-free recovery data is requested through reusable operations instead of embedded in error packets.

## Phase Split

1. [Phase 1: Target Startup](PLAN-004-phase-1-target-startup.md)
2. [Phase 2: Runtime-Free Recovery](PLAN-004-phase-2-runtime-free-recovery.md)
3. [Phase 3: Target-Based Transitions](PLAN-004-phase-3-target-based-transitions.md)

This is the minimal coherent split:

- Phase 1 establishes target resolution and removes fallback cwd at startup.
- Phase 2 makes no-runtime states usable through runtime-free recovery.
- Phase 3 migrates runtime-changing commands so cwd/session transitions also flow through selected targets.

## Deep Modules

- Target Resolver: converts URL state plus persisted workspace state into a selected target or no-runtime target state.
- Runtime Target Host: owns the selected target, creates/disposes runtime from it, and asserts runtime cwd agreement.
- Runtime-Free Recovery Module: lists sessions, recent cwds, and directories without needing a runtime.
- Slash Command Availability Module: builds catalogs based on controller mode and command capability.
- Target Transition Module: resolves slash/protocol transitions into new targets and persists `lastCwd` only when appropriate.

These modules pass the deletion test: without them, target resolution, cwd persistence, no-runtime recovery, and command capability decisions would spread across the WebSocket controller and browser app.

## Shared Packet Shape Sketch

The exact names can be refined during implementation, but the wire model should separate explanatory state from recovery data:

```js
{ type: "cwd_required", payload: { message, value? } }
{ type: "invalid_url_state", payload: { kind, value, message } }
{ type: "runtime_ready", payload: { cwd, agentDir, diagnostics, slashCommands } }
{ type: "recovery_result", payload: { request, data } }
```

Existing `connected` may remain if keeping the packet name reduces churn. The important decision is that invalid and cwd-required packets do not carry fallback cwd/session lists.

## Implementation Guidelines

- Prefer changing behavior through deep modules before editing large controller branches.
- Keep target state explicit and serializable enough for tests.
- Do not let runtime-free operations call `this.session` or `this.runtime`.
- Do not add a cwd env var as a convenience during implementation.
- Do not preserve old fallback behavior behind a compatibility option.
- Use existing cwd validation policy for URL cwd, selected cwd, workspace cwd, and `lastCwd`.
- Keep invalid URL and cwd-required copy separate even if they share rendering code.
- Keep plans test-first at the module level where possible.

## Verification Strategy

Run after each phase:

```bash
npm test --prefix pi-webui
```

Testing should prioritize integration and e2e-style coverage. Module tests are still valuable for target parsing, session prevalidation, and cwd policy edge cases, but each phase should be accepted primarily through browser-visible or WebSocket-visible scenarios.

## Integration/E2E Validation Matrix

- Start with no `lastCwd` and no URL params. Confirm no runtime is created and cwd selection is required.
- Start with invalid/deleted `lastCwd`. Confirm no runtime is created and no process cwd fallback occurs.
- Start with valid `lastCwd`. Confirm runtime starts in that cwd.
- Open valid `?cwd=<path>`. Confirm runtime starts in that cwd.
- Open valid `?session=<path>`. Confirm runtime starts from the session header cwd.
- Open missing/corrupt/headerless session URL. Confirm invalid URL state and no fallback.
- Use no-runtime "Choose session". Confirm all sessions are shown and selecting one creates a runtime.
- Use no-runtime cwd picker. Confirm selecting a cwd creates a runtime and persists `lastCwd`.
- Use `/resume`. Confirm the resumed session header cwd persists as `lastCwd`.
- Use normal runtime-required commands after target selection. Confirm behavior remains unchanged.
- Use browser reload after target selection. Confirm the selected URL/session/cwd state reopens correctly.
- Use two browser tabs with different selected targets. Confirm one tab's target does not affect the other.

## Acceptance Checklist

- `process.cwd()` is absent from pi-webui cwd target selection.
- No cwd environment variable is documented or honored as a default cwd.
- `lastCwd` is the only no-param startup source, and only when valid.
- Missing/invalid `lastCwd` creates cwd-required state.
- Invalid URL state does not include `defaultCwd` or eager session lists.
- Runtime-free recovery works in invalid URL and cwd-required states.
- No-runtime session picker shows all sessions only.
- Runtime cwd is asserted against selected target cwd.
- `lastCwd` is persisted only by explicit target transitions.
- Session resume persists the session header cwd.
- Existing URL Session Pointer and URL Cwd Pointer flows continue to work.
