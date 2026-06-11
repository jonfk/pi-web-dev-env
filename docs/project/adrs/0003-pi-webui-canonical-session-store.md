# ADR-0003: pi-webui Canonical Session Store

Status: Accepted

Date: 2026-06-08

## Context

pi-webui is a long-running web server for working across multiple workspaces and multiple Pi sessions. The workspace sidebar needs a coherent server-wide catalog of saved workspaces and their matching sessions.

Pi's CLI supports custom session directories for a single invocation. That behavior does not map cleanly to the sidebar catalog. `SessionManager.list(cwd, sessionDir)` can list sessions from a custom directory for one cwd, but `SessionManager.listAll()` lists from Pi's default agent session tree and does not accept `sessionDir`.

Leaving `PI_SESSION_DIR` or an equivalent `sessionDir` override in the sidebar path would make the source of truth ambiguous: current-workspace lists could read one directory while all-workspace or sidebar reads use another.

## Decision

pi-webui uses the Pi agent dir as its canonical session storage root.

Server-wide session catalog features, including the workspace sidebar, read persisted session metadata only from the canonical Pi agent session store under `PI_AGENT_DIR`. They do not honor `PI_SESSION_DIR`, `sessionDir`, or other CLI-style per-invocation session directory overrides.

`WorkspaceIndexService` may accept an injectable session lister for tests. That injection is a testability boundary, not a product configuration hook.

## Consequences

- Workspace/sidebar session grouping has one server-owned source of truth.
- Sidebar reads do not need to reconcile custom current-project listings with default all-project listings.
- pi-webui behavior intentionally diverges from Pi CLI session directory override behavior.
- Existing `PI_SESSION_DIR` support in pi-webui should be removed so runtime creation, session switching, recovery, and sidebar reads use the same canonical storage model.
- Tests should inject fake listers or use temporary agent dirs instead of setting `PI_SESSION_DIR`.

## Guardrails

- Do not thread `sessionDir` through new pi-webui sidebar services or tRPC procedures.
- Do not use `PI_SESSION_DIR` to load, list, recover, switch, create, fork, import, or clone pi-webui sessions.
- Do not loosely merge sessions from multiple storage roots.
- If a future server-managed storage override is needed, model it as an explicit replacement for the canonical Pi agent dir, not as a Pi CLI-compatible `sessionDir` override.
