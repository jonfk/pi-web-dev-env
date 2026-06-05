# Add Typed Command Effects For URL State

## Summary

Replace browser-side command-name inference for pi-webui URL updates with typed semantic command effects returned by successful command responses.

## Context

`pi-webui/public/url-state.mjs` currently decides URL behavior from command names such as `new_session`, `switch_session`, `slash:cwd`, and `select_session`. This makes URL updates depend on browser-maintained knowledge of which commands change the selected runtime target.

`docs/project/plans/PLAN-007-pi-webui-workspace-sidebar.md` may add new sidebar-driven navigation actions. If those actions keep using command-name inference, every new command shape must be mirrored in URL-state policy and can drift from the server-side target transition result.

The cleaner boundary is:

- server owns whether a runtime target transition actually succeeded and what target it selected;
- browser owns how that semantic outcome maps to URL history behavior.

## Desired Outcome

Successful runtime-target-changing command responses include typed semantic effects, and browser URL state updates consume those effects instead of inferring behavior from command names.

Example effect shape:

```js
{
  type: "runtime_target_changed",
  target: {
    kind: "cwd",
    cwd: "/abs/workspace"
  }
}
```

```js
{
  type: "runtime_target_changed",
  target: {
    kind: "session",
    sessionPath: "/abs/session.jsonl",
    cwd: "/abs/workspace"
  }
}
```

The final wire shape can differ, but it should stay semantic. Do not have the server instruct the browser to call `pushState`, `replaceState`, or navigate to a literal browser URL.

## Notes

- Start with target-changing commands already covered by URL transition intent: `new_session`, `switch_session`, `select_cwd`, `select_session`, `slash:new`, `slash:cwd`, `slash:workspace`, `slash:import`, `slash:clone`, and `slash:fork`.
- Keep command acknowledgement and command-specific display data intact; add effects alongside existing `data` rather than replacing useful command results.
- Preserve current URL behavior unless this ticket explicitly discovers a mismatch with the domain vocabulary in `pi-webui/CONTEXT.md`.
- Add focused tests for `url-state.mjs` showing that typed effects update URL state without relying on command names.
- Add server-side tests or websocket-level tests that target-changing command results include the expected semantic effect after successful transition and do not include it on failure or cancellation.
- This ticket should compose with, but does not require, a future navigation-state/sidebar refactor.
