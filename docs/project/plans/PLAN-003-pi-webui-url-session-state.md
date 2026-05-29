# PLAN-003: pi-webui URL Session State Implementation

## Source Material

- Final product decisions: `docs/project/prds/PRD-003-pi-webui-url-session-state.md`
- Session context only: `docs/sessions/2026-05-27-pi-webui-url-session-state-handoff.md`
- Adjacent picker behavior: `docs/sessions/2026-05-25-pi-webui-resume-scope-handoff.md`
- Domain vocabulary: `pi-webui/CONTEXT.md`

Use the PRD when any handoff text conflicts with it.

## Prototype Blockers

None. The current code and vendored Pi code answer the important unknowns:

- `SessionManager.open(...)` can create or rewrite missing, empty, or corrupt files, so pi-webui must validate URL session files before calling it.
- Pi's CLI already creates cwd-bound runtime resources only after the target session cwd is known.
- The browser app can use the existing `command_result` ordering to promote a **Disposable New Session** only after a prompt command finishes, rather than from prompt preflight.

## Phase Split

Implement in two phases, the minimum split that keeps the riskiest seam isolated:

1. [Phase 1: Server URL State and Runtime Startup](PLAN-003-phase-1-server-url-state-runtime-startup.md)
2. [Phase 2: Browser URL State, Synchronization, and Recovery UI](PLAN-003-phase-2-browser-url-state-recovery-ui.md)

Phase 1 creates the server Modules that decide URL state before runtime creation. Phase 2 makes the browser URL the active session source of truth and consumes the new invalid-state packet. More phases would mainly split pure Modules from their wiring, which would add bookkeeping without reducing the implementation risk.

## Shared Invariants

- `localStorage["pi-webui:session-file"]` is removed. Input history and debug localStorage remain.
- `session` and `cwd` URL params are mutually exclusive.
- URL pointer values are decoded absolute paths.
- Unknown URL params are ignored when opening `/ws` and are dropped by canonical pi-webui URL writes.
- `/` means a **Disposable New Session**. The browser replaces it with `/?cwd=<resolved initial cwd>` only after the server reports the valid startup cwd.
- A **Disposable New Session** must not sync `session_state.sessionFile` from the initial bootstrap into the URL.
- First prompt promotion uses the post-prompt `command_result` plus the latest `session_state.sessionFile`, not `prompt_preflight`.
- Browser Back and Forward reload the page for v1.
- Invalid URL state never creates `createAgentSessionRuntime(...)`, never sends a normal bootstrap, and leaves the bad browser URL unchanged.
- The existing slash `/new` command also creates a **Disposable New Session**. Treat a successful `/new` or `new_session` command as a move to `/?cwd=<current cwd>` using `pushState`, so the URL does not continue to point at the previous durable session.

## Shared Packet Contract

Add this WebSocket packet:

```js
{
  type: "invalid_url_state",
  payload: {
    kind: "conflict" | "cwd" | "session" | "session_cwd",
    value: string | null,
    message: string,
    defaultCwd: string,
    sessions: {
      currentProject: SessionInfo[],
      allProjects: SessionInfo[]
    }
  }
}
```

Kind meanings:

- `conflict`: both `session` and `cwd` params were present.
- `cwd`: the URL Cwd Pointer was missing, relative, nonexistent, not a directory, or disallowed by cwd policy.
- `session`: the URL Session Pointer was missing, relative, nonexistent, not a file, empty, corrupt, headerless, or missing header cwd.
- `session_cwd`: the session file header was readable, but its stored cwd failed the same cwd policy as `/cwd`.

Suggested message starts:

- `conflict`: `URL cannot include both session and cwd.`
- `cwd`: `Could not open URL working directory: <reason>`
- `session`: `Could not open URL session: <reason>`
- `session_cwd`: `Could not open URL session working directory: <reason>`

## Deep Modules

Create these Modules and keep callers thin:

- `pi-webui/src/server/cwd.ts`: cwd policy and directory listing Interface.
- `pi-webui/src/server/url-state.ts`: server URL grammar and invalid grammar states.
- `pi-webui/src/server/url-session-startup.ts`: URL state to initial Pi `SessionManager` plus cwd, or invalid packet payload.
- `pi-webui/src/server/session-info.ts`: shared `SessionInfo` serialization for normal and invalid session lists.
- `pi-webui/public/url-state.mjs`: browser URL grammar, WebSocket URL creation, canonicalization, navigation, history operation rules, and Back/Forward reload wiring.
- `pi-webui/public/invalid-url-state.mjs`: Invalid Session Message model and recovery action decisions.

These Modules pass the deletion test: without them, URL grammar, cwd policy, history rules, and invalid recovery spread across `index.ts` and `app.js`.

## TDD Strategy

Use vertical red-green-refactor slices inside each phase. Do not write all tests first.

Testing stance:

- Test behavior through the public Interface of each new Module.
- Prefer real temp directories and real session JSONL files for server tests.
- Use fake `location`, `history`, and `reload` objects for browser URL tests.
- Do not mock Pi internals when a real `SessionManager` with a temp file is enough.
- Keep controller-level tests focused on externally visible startup outcomes: runtime config chosen, invalid packet emitted, no normal bootstrap emitted.

Run after each phase:

```bash
npm test --prefix pi-webui
```

## Acceptance Checklist

- Opening `/` becomes `/?cwd=<resolved initial cwd>` without encoding an unprompted session file.
- Opening `/?cwd=<absolute path>` creates a fresh disposable runtime in that cwd.
- Opening `/?session=<absolute jsonl path>` opens the session with the stored cwd before runtime resources are created.
- First accepted prompt from `/` or `/?cwd=...` replaces the URL with `/?session=...`.
- Switching durable sessions uses `pushState`; repeated state for the same session is a no-op.
- `/cwd`, `/workspace`, `/new`, and `new_session` move the URL into cwd mode.
- Invalid cwd/session/conflict URLs render an Invalid Session Message, disable composer submission, retain the bad URL, and offer New session and Choose session.
- Choosing a session from any session picker navigates to `/?session=...`.
- Browser Back and Forward reload the page.
- The active-session localStorage helper and tests are gone.
