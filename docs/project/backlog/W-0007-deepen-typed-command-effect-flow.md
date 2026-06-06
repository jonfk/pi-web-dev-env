# Deepen Typed Command Effect Flow

## Summary

Refactor the current `W-0004` typed command-effect pre-work so target-changing command handlers use one deep Module for successful runtime target command results, instead of manually wrapping command data with `runtime_target_changed` effects at each call site.

## Context

`docs/project/backlog/W-0004-add-typed-command-effects-for-url-state.md` replaces browser-side command-name inference with semantic command effects. The current staged implementation introduces the effect shape, but several handlers still repeat the same recipe:

- apply or adopt a **Selected Runtime Target**;
- build command-specific display data;
- wrap the result with `withCommandEffects(data, [runtimeTargetChangedEffect(target)])`;
- serialize it through `commandSuccessPayload`.

`docs/project/backlog/W-0005-support-new-session-cwd-payload.md` will add the target-changing `open_cwd` path for workspace sidebar actions. Before adding that path, concentrate the target-changing command result rules so new callers do not need to remember how URL effects are emitted.

This ticket covers the architectural cleanup identified while reviewing the `W-0004` staged changes against `docs/project/plans/PLAN-007-pi-webui-workspace-sidebar.md`. The future browser-side workspace index store remains part of `W-0006` and sidebar implementation work, not this ticket.

## Desired Outcome

Create a deeper server-side Module for target-changing command results. Its Interface should let callers say, in effect: "this command successfully selected this runtime target and has this display data." The Module owns the resulting `runtime_target_changed` effect and command-result serialization.

Tighten `pi-webui/public/url-state.mjs` so semantic effect application is explicit and testable without reintroducing command-name URL policy.

Share the same target-changing command result path for runtime-free recovery transitions such as `select_cwd`, `select_session`, `slash:cwd`, and `slash:workspace`.

## Scope

- Update `pi-webui/src/server/command-effects.ts` or a nearby server Module to own target-changing command result construction.
- Update `pi-webui/src/server/index.ts` target-changing handlers to use the deeper Module.
- Keep command-specific display data intact.
- Keep failure and cancellation results free of runtime target effects.
- Keep browser URL state driven by semantic effects, not command names.
- Keep `W-0005` explicit `open_cwd` behavior out of this ticket.
- Keep `W-0006` workspace index protocol and sidebar store behavior out of this ticket.

## Acceptance Criteria

- Runtime target command effects are emitted through one shared server-side path for normal target transitions.
- Runtime-free recovery target transitions use the same shared result/effect path.
- Handler call sites no longer repeat `withCommandEffects(data, [runtimeTargetChangedEffect(target)])`.
- `command_result` payloads still include existing command-specific `data`.
- Successful target-changing commands include a `runtime_target_changed` effect.
- Cancelled and failed target-changing commands do not include a `runtime_target_changed` effect.
- Browser URL state tests still prove that typed semantic effects update **URL Session Pointer** and **URL Cwd Pointer** state without command-name inference.
- `npm test --prefix pi-webui` passes.

## Notes

- This is a prerequisite cleanup for `PLAN-007`, but it does not implement sidebar UI.
- Use the existing domain vocabulary from `pi-webui/CONTEXT.md`: **Selected Runtime Target**, **Runtime Target Host**, **Target Transition Module**, **URL Session Pointer**, **URL Cwd Pointer**, and **New Session Cwd Mode**.
- Keep malformed command input validation at existing command boundaries. Do not add loose parsing or fallback behavior.
