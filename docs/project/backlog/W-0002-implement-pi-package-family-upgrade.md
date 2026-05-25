# W-0002: Implement accepted Pi package family upgrade

## Status

Backlog

## Depends On

- `W-0001: Spike Pi package family upgrade compatibility`

## Context

The compatibility spike should identify whether Pipane can move from the pinned `@mariozechner/*@0.55.3` Pi package family to either:

- `@mariozechner/*@0.73.1`, the final old-scope release; or
- the newer `@earendil-works/*` package scope.

This ticket is the implementation follow-up after the spike selects a target. Keep this ticket focused on applying the accepted dependency upgrade and the minimum compatibility changes needed to make Pipane build, test, and run.

## Goal

Upgrade the Pi package family to the version/scope recommended by the spike report.

## Non-Goals

- Do not inline `pi-web-ui` components unless the spike proves it is required and a separate ticket explicitly approves that work.
- Do not redesign Pipane UI while upgrading packages.
- Do not combine unrelated dependency upgrades unless they are required by the chosen Pi package target.
- Do not remove patched behavior unless the spike report shows it is obsolete or covered upstream.

## Scope

- Update package names and versions for the Pi package family.
- Update imports if the selected target requires a scope migration.
- Rework or retire `patch-package` patches only where the spike report proves it is necessary.
- Keep the `mini-lit` behavior intact unless the selected target makes that package obsolete.
- Preserve existing Pipane behaviors around steering, editor controls, fallback tool rendering, message DOM hooks, session parsing, and model/provider settings.

## Acceptance Criteria

- The chosen Pi package family target is documented in the implementation notes.
- `npm install` completes cleanly.
- Existing patches either apply cleanly, are rebased intentionally, or are removed with documented justification.
- `npm run check` passes.
- `npm run test` passes.
- `npm run build` passes.
- `npm audit --json` and `npm audit --omit=dev --json` results are recorded.
- Any remaining Pi-family audit findings are documented with exposure notes and follow-up work.
- The implementation references the spike report and explains any deviations from its recommendation.
