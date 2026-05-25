# W-0003: Preserve or rebase patched pi-web-ui behaviors

## Status

Backlog

## Depends On

- `W-0001: Spike Pi package family upgrade compatibility`

## Context

Pipane carries a large `@mariozechner/pi-web-ui@0.55.3` patch. The patch appears to provide intentional Pipane behavior rather than incidental local edits. Before the Pi package family upgrade can be trusted, each patched behavior needs an explicit decision.

This ticket should use the spike report's patch behavior inventory as input. The goal is to preserve product behavior, not to blindly make the patch apply.

## Goal

Decide and implement the minimum patch rebase, patch removal, or local compatibility shim needed to preserve existing Pipane behavior after the selected Pi package upgrade.

## Non-Goals

- Do not inline whole `pi-web-ui` components as part of this ticket.
- Do not rewrite the message editor or renderer system unless the spike identifies no smaller compatibility path.
- Do not remove user-visible behavior only because the upgraded upstream package lacks it.

## Behaviors To Preserve Or Decide

- Steering/send behavior while streaming.
- Custom message editor key handling.
- Extra message editor toolbar buttons.
- Fallback tool rendering for unknown tools.
- Stable tool/message DOM hooks such as `data-tool-call-id` and `data-message-index`.
- LM Studio model-discovery compatibility.
- Markdown strikethrough behavior from the `mini-lit` patch.
- Any generated `dist` or declaration behavior that is still required by Pipane's build.

## Acceptance Criteria

- Each patched behavior has an explicit outcome: preserved by upstream, preserved by rebased patch, preserved by local shim, intentionally removed, or deferred.
- Any removed behavior has product justification and user approval.
- The patch file is smaller or better explained where possible.
- `npm run check` passes.
- `npm run test` passes.
- `npm run build` passes.
- Focused manual or automated validation covers steering, editor controls, fallback tool rendering, and DOM-hook-dependent features.
