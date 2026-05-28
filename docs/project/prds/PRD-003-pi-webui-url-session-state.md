# PRD-003: pi-webui URL Session State

## Problem Statement

pi-webui currently stores the active Pi session file in browser `localStorage`. This makes reload behavior depend on hidden browser state instead of the URL, makes tabs less naturally independent, and prevents users from opening a URL that directly selects the Pi session or working directory they want.

Users need pi-webui URLs to describe the active session state clearly. Durable sessions should be opened by URL, disposable new sessions should be tied to a working directory, and invalid URL state should fail loudly instead of silently bootstrapping the wrong session.

## Solution

pi-webui will replace active-session `localStorage` with URL state. A durable session URL will use a **URL Session Pointer** in the shape `/?session=<absolute-jsonl-path>`. A **Disposable New Session** URL will use a **URL Cwd Pointer** in the shape `/?cwd=<absolute-path>`.

`/` without URL params will start the disposable new-session flow. Empty sessions do not have identity worth preserving, so pi-webui will not encode an unprompted session file in the URL. Once Pi accepts the first prompt, the browser will replace the disposable URL with the durable session URL.

Invalid URL state will render an **Invalid Session Message** in the transcript, disable the composer, keep the URL unchanged, and offer explicit recovery actions.

## User Stories

1. As a pi-webui user, I want the active durable session to be represented in the URL, so that reloading the browser opens the same Pi session.
2. As a pi-webui user, I want to open a URL with a session file path, so that I can resume a specific Pi session directly.
3. As a pi-webui user, I want browser tabs to carry their own session state, so that using multiple sessions in multiple tabs does not fight over browser `localStorage`.
4. As a pi-webui user, I want `/` to start a new disposable session, so that opening the app gives me a clean place to start.
5. As a pi-webui user, I want disposable new sessions to encode cwd instead of session identity, so that the URL records where new work will happen without pretending an empty session is durable.
6. As a pi-webui user, I want an empty session to become a URL session only after my first prompt is accepted, so that unprompted sessions do not clutter URL history with meaningless identities.
7. As a pi-webui user, I want `/` without cwd to populate the URL with the resolved initial cwd, so that the disposable session URL becomes explicit.
8. As a pi-webui user, I want `?cwd=<path>` to create a disposable session in that cwd, so that I can start new work in a specific workspace from a URL.
9. As a pi-webui user, I want invalid cwd URLs to show a clear message, so that I know the path must be corrected instead of silently using another directory.
10. As a pi-webui user, I want invalid session URLs to show a clear message, so that I do not accidentally type into the wrong session.
11. As a pi-webui user, I want the bad URL to remain visible when it is invalid, so that I can inspect or manually correct it.
12. As a pi-webui user, I want the composer disabled while URL state is invalid, so that I cannot accidentally submit work into a fallback session.
13. As a pi-webui user, I want an invalid URL message to offer New session, so that I can recover without editing the URL by hand.
14. As a pi-webui user, I want an invalid URL message to offer Choose session, so that I can recover by selecting an existing session.
15. As a pi-webui user, I want browser Back and Forward to navigate between meaningful session or cwd states, so that browser history feels useful.
16. As a pi-webui user, I want Back and Forward to reload into the URL state for v1, so that the app reliably opens the intended session or cwd.
17. As a pi-webui user, I want `/cwd` and `/workspace` switches to update the URL to cwd mode, so that the URL matches the new disposable session flow.
18. As a pi-webui user, I want switching from one durable session to another to create a browser history entry, so that Back can return to the previous session.
19. As a pi-webui user, I want repeated state updates for the same session to avoid adding history entries, so that Back does not step through internal server state.
20. As a pi-webui user, I want URLs with both `session` and `cwd` to fail clearly, so that ambiguous hand-edited URLs are not guessed.
21. As a pi-webui user, I want sessions whose stored cwd no longer exists to fail clearly, so that pi-webui does not attach an old conversation to a surprising workspace.
22. As a maintainer, I want URL state parsed before runtime initialization, so that pi-webui does not construct a runtime in the wrong cwd and immediately replace it.
23. As a maintainer, I want session URLs to use Pi's session manager open pattern, so that cwd is resolved before runtime services are created.
24. As a maintainer, I want URL grammar centralized in testable modules, so that client and server behavior remain understandable as URL state evolves.
25. As a maintainer, I want active-session localStorage removed, so that there is one source of truth for active session selection.
26. As a maintainer, I want input history and debug localStorage to keep working, so that unrelated browser preferences do not regress.
27. As a maintainer, I want invalid URL state to use a dedicated protocol packet, so that the client does not have to infer blocking URL errors from generic server errors.
28. As a maintainer, I want URL-state tests to cover parse and synchronization behavior, so that future browser changes do not regress reload and history semantics.
29. As a maintainer, I want controller initialization tests around cwd and session URL modes, so that runtime construction stays aligned with Pi's cwd-sensitive services.

## Implementation Decisions

- Use absolute session JSONL file paths for **URL Session Pointer** values.
- Use absolute working directory paths for **URL Cwd Pointer** values.
- Treat absolute paths in URLs as acceptable for this local software. Deployments are assumed to use HTTPS.
- Define the URL grammar as mutually exclusive: `session` opens a durable existing Pi session, and `cwd` opens a **Disposable New Session**.
- Reject URLs containing both `session` and `cwd` with invalid URL state instead of choosing precedence.
- Treat `/` without params as the disposable new-session flow.
- Do not add a `/new` alias in v1. It would duplicate `/` without adding distinct behavior, and the canonical disposable URL is still `/?cwd=<absolute-path>`.
- Canonical disposable new-session URLs should be `/?cwd=<absolute-path>`.
- When no `cwd` param is present for a disposable new session, populate cwd from the server's resolved initial cwd.
- When `cwd` is present, validate it with the same constraints as cwd switching: absolute path, exists, is a directory, and inside `$HOME` unless the allow-any setting is enabled.
- Do not encode an unprompted session file in the URL.
- After Pi accepts the first prompt for a disposable session, replace the URL with `/?session=<absolute-jsonl-path>`.
- Browser history follows meaningful identity changes: no pointer to first real pointer uses `replaceState`; existing pointer to different pointer uses `pushState`; same pointer is a no-op; invalid URL state leaves the URL unchanged.
- `/cwd` and `/workspace` switches move the URL into cwd mode and drop any existing session param.
- `/cwd` and `/workspace` URL updates use `pushState` because they move away from the current runtime/session identity.
- Browser Back and Forward should reload the page for v1, allowing normal startup to reopen the URL state.
- Replace the browser active-session storage helper with a URL-state module.
- The browser URL-state module should own parsing browser URL state, canonicalizing disposable URLs, syncing durable session URLs, and applying push/replace/no-op history rules.
- Add a server-side URL-state helper module instead of parsing WebSocket URL state inline in the session controller.
- The server URL-state module should own server URL grammar and return a parsed state: session, cwd, new/disposable, or invalid.
- Pass URL state on the WebSocket URL before controller runtime initialization.
- Stop passing `sessionFile` in the `ready` packet. `ready` should keep replay cursor behavior, while session selection moves to controller initialization.
- For `cwd` URL state, create the initial runtime directly in that cwd and explicitly create a fresh disposable session.
- For missing URL state, use the server's resolved initial cwd for a disposable new session.
- For `session` URL state, create a Pi session manager with the session path first, read cwd from the session manager, then create the runtime with that cwd and session manager.
- Use Pi's existing session-open pattern instead of parsing session JSONL manually.
- Validate that a `session` URL path exists and is a file before calling `SessionManager.open(...)`. Pi's session manager can preserve an explicit missing path and start a fresh session there, which would violate fail-loud invalid URL behavior.
- A `session` URL path is valid only if it points to an existing file containing a readable Pi session header with a stored cwd. Missing, empty, corrupt, or headerless session files are invalid URL state.
- pi-webui must not let `SessionManager.open(...)` create or rewrite a session file while validating a **URL Session Pointer**.
- After `SessionManager.open(sessionPath, sessionDir)`, validate the session header cwd before runtime creation. The stored cwd must exist, be a directory, and satisfy the same cwd allow-any policy used for cwd switching.
- If a session URL points at a missing/deleted session file, send invalid URL state and do not bootstrap a fallback session.
- If a session URL points at a session whose stored cwd no longer exists, send invalid URL state and do not fall back to the current/default cwd.
- Use a dedicated `invalid_url_state` WebSocket packet instead of `server_error`.
- `invalid_url_state` should include the invalid kind, invalid value, message, default cwd, and session lists.
- The `defaultCwd` value powers the New session action in the **Invalid Session Message**.
- The session lists power the Choose session action without a follow-up request while the app is in invalid URL state.
- For invalid cwd, session lists may be based on the default cwd because the requested cwd cannot be used.
- Invalid URL state must not create `createAgentSessionRuntime(...)`. Recovery data should still be computed with Pi's static session APIs: `SessionManager.list(defaultCwd, sessionDir)` for current-project sessions and `SessionManager.listAll()` for all sessions.
- Render invalid URL state as an **Invalid Session Message** in the transcript, similar to the TUI's startup-style messaging.
- Disable the composer while invalid URL state is active.
- Keep the bad URL unchanged while invalid URL state is active.
- Offer New session and Choose session actions from the invalid URL message.
- In invalid URL state, Choose session opens the picker from the `invalid_url_state` packet's prefetched session lists. Selecting a session must navigate to `/?session=<encoded-session-path>` instead of sending `/resume`, because no valid runtime/controller may exist.
- Do not offer a vague "clear URL" action, because blank `/` means disposable session in initial cwd.
- For normal valid sessions, `/resume` may continue to exist as an in-place switch command. URL session selection should prefer navigation to `/?session=<encoded-session-path>` so history, reload, Back/Forward, and startup runtime creation all use the same path.
- Mental model: URL changes create runtimes; slash commands mutate the current valid runtime.
- Keep one runtime/controller per WebSocket. Shared controllers across tabs remain out of scope for this implementation.

## Testing Decisions

- Good tests should verify externally observable URL and protocol behavior, not private helper implementation details.
- Test the browser URL-state module as the primary client-side deep module.
- Browser URL-state tests should cover parsing `session`, parsing `cwd`, no-param disposable state, conflicting params, URL encoding of absolute paths, and history operation decisions.
- Browser URL-state tests should cover first accepted prompt replacing cwd mode with session mode.
- Browser URL-state tests should cover existing session pointer changes using push behavior.
- Browser URL-state tests should cover same-pointer updates as no-ops.
- Browser URL-state tests should cover invalid URL state leaving the URL unchanged.
- Replace the existing active-session storage tests with URL-state tests because active-session localStorage is removed.
- Test the server URL-state module as the primary server-side deep module.
- Server URL-state tests should cover mutually exclusive `session` and `cwd`, invalid conflict state, valid cwd state, invalid cwd state, missing state, and session state parsing.
- Add controller-level coverage that URL `cwd` creates the runtime in that cwd before a disposable session is created.
- Add controller-level coverage that URL `session` uses Pi's session manager cwd before runtime construction.
- Add controller-level coverage that missing `session` URL paths are invalid before `SessionManager.open(...)`, so they cannot create a new session at the missing path.
- Add controller-level coverage that empty, corrupt, or headerless `session` URL files send `invalid_url_state` and do not create, rewrite, or bootstrap a runtime.
- Add controller-level coverage that invalid session and invalid cwd send `invalid_url_state` and do not send a normal bootstrap.
- Add client behavior coverage that an invalid URL message disables composer submission.
- Add client behavior coverage that invalid URL message actions navigate to new-session cwd state or open the session picker, and that choosing a session from invalid state navigates to a session URL instead of sending `/resume`.
- Add client behavior coverage that first-prompt promotion happens from the post-prompt `session_state.sessionFile` for a disposable URL, not from prompt preflight alone.
- Add behavior coverage that `/cwd` and `/workspace` switches move the URL into cwd mode.
- Add behavior coverage that Back/Forward registers a reload handler.
- Use existing pi-webui node tests for pure modules and existing browser-app tests as prior art.

## Out of Scope

- Replacing absolute file paths with opaque session ids.
- Building a server-side session-id lookup table.
- Removing input-history or debug `localStorage`.
- Making empty, unprompted sessions durable or reload-preserving.
- In-place Back/Forward switching without page reload.
- Sharing one runtime/controller across multiple WebSocket connections.
- Remote-safe share links that hide local filesystem paths.
- A TUI-like recovery flow for choosing a replacement cwd when a session's stored cwd no longer exists.
- Changing Pi's session file format or session manager behavior.
- Implementing broader workspace management beyond URL cwd state.

## Notes

- pi-webui does not own durable conversation history. Pi owns durable sessions through session JSONL files and agent directory state.
- The active session URL state replaces only the active-session `localStorage` key. Composer input history and debug settings remain local browser preferences.
- `SessionManager.open(...)` already reads the session header cwd before runtime creation, matching the Pi CLI pattern.
- `SessionManager.open(...)` does not by itself prove that the requested session file exists. pi-webui owns that URL validation because a missing **URL Session Pointer** must be invalid, not a request to create a session at that path.
- URL validation must happen before any Pi session-manager operation that can repair, rewrite, or create a session file. Hand-edited session URLs are selection requests, not mutation requests.
- Invalid URL state is deliberately blocking. The goal is to avoid typing into the wrong session or cwd after opening a stale or hand-edited URL.
- A **Disposable New Session** becomes a **URL Session Pointer** after the first successful prompt flow yields a post-prompt `session_state.sessionFile`. Prompt preflight is not sufficient because it fires before the agent run.
- The glossary defines **URL Session Pointer**, **URL Cwd Pointer**, **Disposable New Session**, and **Invalid Session Message**.

## Later / Follow-ups

- Add a TUI-like recovery flow for sessions whose stored cwd no longer exists, allowing the user to choose a replacement cwd before opening the session.
- Consider opaque session ids or relative session keys if pi-webui needs remote-safe or less path-heavy URLs.
- Consider in-place Back/Forward handling once the startup URL-state path is stable.
- Consider documenting URL session behavior in the pi-webui README after implementation lands.
- Consider a dedicated "copy session URL" affordance if users start sharing links between windows or devices.
