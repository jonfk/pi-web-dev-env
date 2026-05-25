# W-0005: Review Pi package upgrade audit delta

## Status

Backlog

## Depends On

- `W-0001: Spike Pi package family upgrade compatibility`
- `W-0002: Implement accepted Pi package family upgrade`

## Context

The existing dependency audit identifies several production-installed vulnerabilities through the Pi package family, including provider and child-process scoped dependencies such as `protobufjs`, `undici`, `basic-ftp`, `fast-xml-parser`, `yaml`, `file-type`, `brace-expansion`, and `ip-address`.

The package upgrade may resolve some findings, but any remaining findings need fresh exposure notes based on the upgraded dependency graph.

## Goal

Compare npm audit results before and after the accepted Pi package upgrade and document remaining security work.

## Non-Goals

- Do not add npm overrides blindly.
- Do not upgrade unrelated major dependencies as part of this ticket.
- Do not treat provider-scoped findings as unreachable without evidence.

## Scope

- Run `npm audit --json`.
- Run `npm audit --omit=dev --json`.
- Compare findings against the pre-upgrade audit notes.
- Identify which findings were resolved by the Pi package upgrade.
- Identify which findings remain in production dependencies.
- For remaining findings, classify exposure as directly reachable, provider/child-process scoped, dev/build/test only, or unknown.
- Recommend follow-up work such as overrides, upstream issue tracking, provider-specific validation, or deferred risk acceptance.

## Acceptance Criteria

- Before/after audit counts are recorded.
- Remaining Pi-family findings are mapped to dependency chains.
- Each remaining production finding has an exposure classification.
- Recommended follow-up tickets are listed if action is still needed.
- No dependency overrides are added without explicit compatibility validation.
