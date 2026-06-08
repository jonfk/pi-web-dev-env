# ADR-0001: Incremental React TypeScript Frontend Migration

Status: Accepted

Date: 2026-06-07

## Context

pi-webui currently serves a mostly plain JavaScript browser frontend from `pi-webui/public`. The server is already TypeScript, but the browser UI does not have the same type-safety guarantees or component boundaries.

The current frontend also owns several tightly-coupled workflows: active runtime websocket state, streamed chat rendering, composer behavior, modal pickers, slash command discovery, file completion, URL state, and keyboard routing. Rewriting all of that at once would create a large behavioral migration with a high regression risk.

New UI areas such as the workspace/session sidebar have different interaction and data-read patterns than the existing chat stream. They are good candidates for a typed component model without requiring a full frontend rewrite.

## Decision

pi-webui will migrate the frontend toward TypeScript and React incrementally.

New frontend surfaces may be built as React and TypeScript islands mounted inside the existing browser shell. Existing plain JavaScript modules remain valid until there is a concrete reason to migrate them.

The first React TypeScript island will be the workspace/session sidebar. It will coexist with the existing `public/app.js` controller through a narrow bridge rather than taking ownership of the whole frontend application.

The migration goal is better type safety, clearer component boundaries, and an eventual unified frontend architecture. The migration is not a mandate to rewrite unrelated existing workflows before their boundaries are understood.

## Consequences

- pi-webui will add a real client build step for React and TypeScript.
- New islands should have explicit integration boundaries with the existing JavaScript controller.
- Shared behavior should move to typed modules when it is touched by a React island or when doing so reduces real coupling.
- The existing chat, composer, modal, websocket, and URL-state flows can continue to run in plain JavaScript while the migration proceeds.
- The codebase will temporarily contain two frontend styles. That is acceptable when the boundary is explicit and the migration remains component-by-component.

## Guardrails

- Do not start a broad React rewrite as part of adding a single island.
- Do not duplicate runtime authority inside React components.
- Do not introduce abstractions solely to prepare for a hypothetical future migration.
- Prefer typed request and response shapes at the server/client boundary over loose client-side aliases.
- Keep each migration step small enough to verify against existing websocket, URL, keyboard, modal, and composer behavior.
