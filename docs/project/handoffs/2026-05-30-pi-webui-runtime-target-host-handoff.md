# pi-webui Runtime Target Host Handoff

Date: 2026-05-30

## Goal

Continue the current `pi-webui` Phase 3 work by fixing runtime target transitions without weakening the explicit selected-target design from `PLAN-004`.

The immediate implementation problem is that the current `pi-webui` changes centralize target transitions, but runtime-present session transitions now recreate/dispose the Pi runtime directly. That breaks Pi session replacement lifecycle semantics. The fix should deepen the target-transition design rather than revert to scattered controller logic.

Use this handoff together with:

- `docs/project/prds/PRD-004-pi-webui-explicit-runtime-targets.md`
- `docs/project/plans/PLAN-004-pi-webui-explicit-runtime-targets.md`
- `docs/project/plans/PLAN-004-phase-3-target-based-transitions.md`
- `docs/project/handoffs/2026-05-30-pi-webui-pre-phase-3-recovery-fixes-handoff.md`
- `pi-webui/CONTEXT.md`

Do not redesign the selected-target model. The decisions below are the agreed continuation of the review conversation.

## Current Worktree Context

The relevant in-progress changes are in the nested `pi-webui` repo:

- Modified: `pi-webui/src/server/index.ts`
- Modified: `pi-webui/public/app.js`
- Added: `pi-webui/src/server/target-transitions.ts`
- Added: `pi-webui/test/server-target-transitions.test.mjs`

At review time, `npm test` from `pi-webui` passed with 221 tests. That does not cover the lifecycle regression described below.

## Architecture Direction

Follow the vocabulary and guidance from `improve-codebase-architecture`:

- A **Runtime Target Host** Module should be deep: callers submit target intent; lifecycle ordering, selected target mutation, persistence, runtime creation/replacement, and assertions stay local to the Module.
- The **Target Transition Module** should stay focused on pure target intent: resolve cwd/workspace/session/new transitions, classify source, and answer persistence policy. It should not mutate runtime.
- Use a real **Adapter** seam for applying transitions, because there are at least two real Adapters:
  - no-runtime creation;
  - runtime-present Pi SDK session replacement/direct cwd recreation.

Before or during implementation, update `pi-webui/CONTEXT.md` with the domain terms that become load-bearing. Suggested terms:

- **Selected Runtime Target**: the cwd or session target owned by pi-webui for one browser tab.
- **Runtime Target Host**: the server Module that applies selected target transitions and derives a Pi runtime from them.
- **Target Transition Module**: the server Module that resolves command/recovery input into selected target transitions and persistence policy.
- **Session Replacement Adapter**: an Adapter used by the Runtime Target Host when an existing Pi runtime can apply a transition through SDK lifecycle methods.

No ADRs were found in this area during review.

## Issue 1: Preserve Pi Lifecycle In Target Transitions

### Problem

The current Phase 3 implementation in `pi-webui/src/server/index.ts` applies all target transitions by:

1. stopping file watch;
2. unsubscribing;
3. disposing the old runtime;
4. creating a new runtime from the target;
5. binding/bootstraping.

This is correct for no-runtime recovery and probably necessary for cwd/workspace switching, but it is wrong for runtime-present session/new-session transitions.

Pi runtime methods such as `runtime.switchSession(...)` and `runtime.newSession(...)` provide lifecycle behavior that direct dispose/recreate bypasses:

- `session_before_switch` / cancellation;
- `session_shutdown` with the intended reason;
- `session_start` with `resume` or `new`;
- replaced-session context handling.

`PLAN-004-phase-3-target-based-transitions.md` already says to keep cancellation semantics where runtime hooks still apply. The current code violates that part of the plan.

### Agreed Solution

Keep pi-webui as the owner of the **Selected Runtime Target**, but choose the runtime mutation path based on controller state and transition kind.

The Runtime Target Host should apply transitions like this:

1. **No runtime exists**
   - Create the runtime directly from the target.
   - Assert runtime cwd matches target cwd.
   - Persist `lastCwd` if the transition policy says so.
   - Update selected target, bind, and bootstrap.

2. **Runtime exists + session transition**
   - Resolve/prevalidate the session target before changing runtime.
   - Call `runtime.switchSession(transition.sessionPath)`.
   - If cancelled, do not update selected target and do not persist `lastCwd`.
   - If successful, assert `runtime.cwd === transition.cwd`.
   - Update selected target, persist if appropriate, bind, and bootstrap.

3. **Runtime exists + new-session transition**
   - Resolve the transition from the current selected cwd target, not from `runtime.cwd` as authority.
   - Call `runtime.newSession()`.
   - If cancelled, do not update selected target and do not persist `lastCwd`.
   - If successful, selected target is cwd mode for the transition cwd.
   - Assert runtime cwd matches transition cwd, then persist/bind/bootstrap.

4. **Runtime exists + cwd/workspace transition**
   - Direct recreate remains acceptable because Pi does not expose a runtime `switchCwd` method.
   - This path should still use the Runtime Target Host for ordering, selected target update, persistence, assertion, bind, and bootstrap.

The important coherence rule: target resolution happens before runtime mutation, but selected target and `lastCwd` are committed only after the runtime mutation succeeds.

### Deep Module Shape

Prefer adding a new `pi-webui/src/server/runtime-target-host.ts` rather than growing `index.ts`.

The exact names can vary, but keep the Interface small. A caller should not need to know watcher cleanup, Pi lifecycle method details, persistence ordering, or bind/bootstrap ordering.

Suggested responsibilities behind the Runtime Target Host Interface:

- own the selected target;
- own the in-flight target transition gate;
- choose the correct Adapter for applying a transition;
- commit selected target only after successful runtime application;
- persist `lastCwd` only after successful explicit transition;
- fail loudly if runtime cwd differs from selected target cwd;
- keep watcher/subscription cleanup local to runtime replacement paths;
- expose enough result data for command results and URL synchronization.

Keep `target-transitions.ts` as the resolution/policy Module. If the current `TargetTransitionApplicator` remains, it should either become internal to Runtime Target Host or become a small private helper for the Host. Avoid making command handlers coordinate transition ordering themselves.

### Tests To Add

Prefer tests at the Runtime Target Host Interface. Use fakes for runtime/session lifecycle rather than driving real Pi if that keeps the test focused.

Cover:

- runtime-present session transition calls `runtime.switchSession`, not direct dispose/recreate;
- cancelled `switchSession` leaves selected target and `lastCwd` unchanged;
- successful `switchSession` updates selected target and persists session header cwd;
- runtime-present new-session transition calls `runtime.newSession`;
- cancelled `newSession` leaves selected target and `lastCwd` unchanged;
- cwd/workspace transition still uses direct recreation and commits only after success;
- no-runtime recovery creates runtime directly;
- concurrent target transitions are rejected or serialized by one consistent Host policy;
- a runtime cwd mismatch throws and does not silently commit target/persistence.

Also keep the existing `server-target-transitions` tests for pure resolution/policy behavior.

## Issue 2: Import / Clone / Fork And `lastCwd`

### Decision

Do not let `lastCwd` persistence add large complexity to `import`, `clone`, or `fork`.

The product rule remains: generic command success does not persist `lastCwd`. Persistence belongs to explicit target transitions, as described in `PLAN-004`.

### Required Coherence Check

Even if these commands do not persist `lastCwd`, they must not leave pi-webui with runtime cwd and selected target cwd drifting apart.

Recommended policy:

- `clone` and `fork`: keep runtime-required and non-persisting. After success, assert runtime cwd still matches selected target cwd. If this fails, that command needs explicit redesign rather than silent drift.
- `import`: this can legitimately open a session with a different header cwd. Use one of these policies:
  - Recommended: successful import updates selected target to a non-persisting session target for the imported session path/header cwd, then asserts agreement. Do not write `lastCwd`.
  - Stricter alternative: reject imports whose session header cwd differs from the current selected target cwd until import is redesigned as a full target transition.

Do not make import a full persisting explicit target transition unless the product decision changes.

### Tests To Add

Add focused coverage for whichever import policy is chosen:

- import with same cwd leaves selected target coherent and does not persist `lastCwd`;
- import with different header cwd either updates selected target without persistence or rejects before drift;
- clone/fork success asserts selected target agreement and does not persist `lastCwd`.

If direct controller tests are hard, move enough behavior into Runtime Target Host or a small command-postcondition Module so the Interface is testable.

## Intentional Behavior: `/cwd` From Session Mode

The earlier review noted that `/cwd <same-cwd>` from a session target is no longer a no-op. This is intentional.

`PLAN-004-phase-3-target-based-transitions.md` says `/cwd <path>` from an active session should move the browser tab to cwd mode, restart runtime in that cwd, update URL state, and persist `lastCwd`. Do not “fix” this back to the old `runtime.cwd` comparison.

## Client URL Behavior

The current `public/app.js` change makes runtime session picker selection send `switch_session` instead of navigating directly to a URL Session Pointer. That aligns with Phase 3 if command success updates URL state through `URL Transition Intent`.

Do not switch this back unless choosing a URL-navigation-only strategy for session picker. The current strategy is coherent with applying target transitions in-process and updating URL state after success.

## Suggested Implementation Order

1. Update `pi-webui/CONTEXT.md` with the target-host vocabulary above.
2. Add/shape `runtime-target-host.ts` and tests around its Interface.
3. Move transition application out of `NativePiSessionController.applyTargetTransition`.
4. Keep `target-transitions.ts` pure: resolution, target conversion, persistence policy.
5. Wire `/resume`, `switch_session`, `/new`, `new_session`, cwd/workspace, and runtime-free recovery through Runtime Target Host.
6. Add import/clone/fork coherence checks without `lastCwd` persistence.
7. Run `npm test` from `pi-webui`.

## Verification

Run:

```bash
npm test --prefix pi-webui
```

Manual smoke checks:

- Start from no-runtime cwd-required state and select cwd; confirm one runtime starts and URL moves to cwd mode.
- Start from no-runtime invalid session URL and select a valid session; confirm runtime starts, URL moves to session mode, and `lastCwd` persists the session header cwd.
- From an active session, use session picker; confirm Pi lifecycle hooks can cancel switch and cancellation leaves current target unchanged.
- From an active session, use `/new`; confirm Pi lifecycle hooks can cancel and success moves to New Session Cwd Mode.
- From an active session, use `/cwd <same cwd>`; confirm it intentionally moves to cwd mode.
- Try import with a different session header cwd; confirm chosen policy prevents target/runtime drift and does not write `lastCwd`.

## Out Of Scope

- Do not reintroduce `process.cwd()` or cwd environment fallback.
- Do not persist `lastCwd` from generic command success.
- Do not redesign URL Session Pointer or URL Cwd Pointer behavior beyond Phase 3 needs.
- Do not rewrite Pi runtime internals or vendored Pi code.
- Do not make import/clone/fork full target transitions unless the product decision changes.
