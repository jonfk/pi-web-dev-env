# W-0006: Plan pi-web-ui decoupling if upgrade requires it

## Status

Backlog

## Depends On

- `W-0001: Spike Pi package family upgrade compatibility`
- `W-0003: Preserve or rebase patched pi-web-ui behaviors`

## Context

Inlining or replacing `pi-web-ui` pieces should not be the first move. However, the spike may show that some patched behaviors cannot be preserved safely through package patches alone.

This ticket is a planning task for decoupling only if the upgrade evidence shows that patch rebasing is too fragile or blocks the accepted Pi package upgrade.

## Goal

Create a high-level implementation plan for reducing Pipane's dependence on patched `pi-web-ui` surfaces.

## Non-Goals

- Do not implement inlining in this ticket.
- Do not inline the whole `pi-web-ui` package.
- Do not duplicate upstream code unless the plan explains why a wrapper or upstream contribution is insufficient.

## Candidate Areas

- Local renderer registries and fallback tool renderer.
- Local message editor or wrapper.
- Local message leaf components for DOM hooks.
- Local `formatUsage` or small utility shims.
- Local storage type shims if upstream type identities become a blocker.
- Upstream PRs or issues for generic extension points.

## Acceptance Criteria

- The plan is based on concrete spike/upgrade findings.
- Each candidate area has a recommended approach: keep upstream, patch upstream, wrap locally, inline locally, or upstream contribution.
- Work is split into small follow-up implementation tickets.
- The plan identifies the lowest-risk first step if decoupling becomes necessary.
- The plan explicitly preserves the behaviors currently supplied by the `pi-web-ui` patch.
