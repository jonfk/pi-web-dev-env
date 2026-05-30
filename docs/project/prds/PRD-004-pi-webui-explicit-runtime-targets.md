# PRD-004: pi-webui Explicit Runtime Targets

## Problem Statement

pi-webui currently manages working directory and session state through a mix of Pi runtime state, URL state, persisted workspace state, and runtime-adjacent helper functions. This makes some user flows depend on having an initialized runtime even when the user is trying to recover from a state where no runtime should exist, such as an invalid URL Session Pointer, invalid URL Cwd Pointer, or missing initial cwd.

The most problematic behavior is that pi-webui can fall back to a process working directory when no explicit cwd is known. That makes the server launch location act like a hidden project selection. In a multi-session, multi-project web UI, there should be no special default cwd from process state or environment variables. The user, URL, trusted session header, saved workspace, or prior explicit selection should provide the cwd.

The current design also risks cwd drift. When cwd is embedded in the runtime and other code also needs cwd before a runtime exists, pi-webui is pulled toward maintaining separate cwd state. The product needs one source of truth for the selected cwd or session target, with the runtime derived from that target.

## Solution

pi-webui will introduce an explicit selected target model. The selected target is the single source of truth for the cwd/session that the current browser tab intends to use. A Pi runtime may exist only as a derivation of a selected cwd target or selected session target. When no valid target is selected, pi-webui enters a no-runtime state.

The no-runtime state is intentional and usable. It supports only runtime-free commands and recovery actions, such as choosing a cwd, choosing a session from all projects, listing recent cwds, and browsing directories. Runtime-required commands, prompts, bash execution, model selection, compaction, and prompt-routed Pi commands stay unavailable until a valid target creates a runtime.

Valid `lastCwd` remains an acceptable startup source because it was written by a prior explicit user or session selection. Invalid or missing `lastCwd` does not fall back to `process.cwd()` or any cwd environment variable. It produces a cwd-required state with an explanation.

Invalid URL state remains blocking, but it no longer needs eager recovery data in the error packet. The client should use reusable runtime-free requests to fetch sessions or cwd choices on demand.

## User Stories

1. As a pi-webui user, I want pi-webui to avoid using the server process directory as my project, so that I do not accidentally work in an install directory or launch directory.
2. As a pi-webui user, I want pi-webui to avoid using a cwd environment variable as a special default project, so that the app remains naturally multi-project.
3. As a pi-webui user, I want `/` to reopen my last explicitly selected cwd when it is still valid, so that the app remains convenient across launches.
4. As a pi-webui user, I want `/` to ask me to choose a cwd when no valid prior cwd exists, so that I choose the project intentionally.
5. As a pi-webui user, I want an invalid or deleted saved cwd to show a clear explanation, so that I understand why startup is blocked.
6. As a pi-webui user, I want an invalid saved cwd to avoid falling back to another cwd, so that I do not type into the wrong project.
7. As a pi-webui user, I want a URL Cwd Pointer to remain the explicit way to start a new session in a cwd, so that direct project links still work.
8. As a pi-webui user, I want a URL Session Pointer to open the session using its stored cwd, so that the conversation resumes in the intended project.
9. As a pi-webui user, I want a session whose stored cwd is invalid to fail loudly, so that the old conversation is not attached to an unrelated project.
10. As a pi-webui user, I want invalid URL state to keep the bad URL visible, so that I can inspect or fix it.
11. As a pi-webui user, I want invalid URL state to avoid creating an agent runtime, so that no hidden fallback session is created.
12. As a pi-webui user, I want cwd-required state to avoid creating an agent runtime, so that no project is selected until I choose one.
13. As a pi-webui user, I want to choose a cwd from a no-runtime state, so that I can recover without restarting the server.
14. As a pi-webui user, I want to browse directories from a no-runtime state, so that choosing a cwd has the same ergonomics as the normal cwd picker.
15. As a pi-webui user, I want to see recent cwds from a no-runtime state, so that I can quickly select a project I used before.
16. As a pi-webui user, I want to choose an existing session from a no-runtime state, so that invalid startup does not trap me.
17. As a pi-webui user, I want no-runtime "Choose session" to show all sessions, so that the picker does not imply a current project before one exists.
18. As a pi-webui user, I want resuming a session to remember that session's cwd as the last cwd, so that future startup can return to that project.
19. As a pi-webui user, I want switching cwd to update the selected target before runtime creation, so that the UI and runtime cannot disagree about cwd.
20. As a pi-webui user, I want switching workspace to behave like selecting that workspace's cwd, so that workspaces are just saved cwd targets.
21. As a pi-webui user, I want starting a new session to keep the current selected cwd target, so that new work starts in the project I selected.
22. As a pi-webui user, I want browser URL state to continue representing selected session or cwd, so that tabs remain independent.
23. As a pi-webui user, I want the composer disabled when no runtime exists, so that I cannot send prompts before selecting a project or session.
24. As a pi-webui user, I want slash command autocomplete in no-runtime state to show only commands that can work there, so that unavailable commands are not misleading.
25. As a pi-webui user, I want runtime-required slash commands to fail clearly if invoked without a runtime, so that command behavior is predictable.
26. As a pi-webui user, I want invalid URL recovery to reuse the same cwd/session pickers as normal workflows, so that recovery feels consistent.
27. As a maintainer, I want one selected target to be the source of truth, so that cwd does not drift between controller state, runtime state, URL state, and persisted state.
28. As a maintainer, I want runtime creation to assert that the runtime cwd matches the selected target, so that source-of-truth bugs fail loudly.
29. As a maintainer, I want target resolution to happen before runtime creation, so that Pi services are never built for the wrong cwd.
30. As a maintainer, I want target resolution to be testable without a runtime, so that startup, invalid URL, and cwd-required behavior can be verified in isolation.
31. As a maintainer, I want runtime-free operations to have their own clear interface, so that no-runtime recovery does not depend on runtime objects.
32. As a maintainer, I want lastCwd persistence to happen only after explicit target transitions, so that incidental commands do not rewrite project selection.
33. As a maintainer, I want URL invalid packets to avoid carrying eager cwd/session lists, so that errors stay explanatory and recovery data has one reusable retrieval path.
34. As a maintainer, I want existing URL Session Pointer behavior to stay compatible, so that PRD-003 remains true except where it depended on a default cwd.
35. As a maintainer, I want the implementation to be split into coherent phases, so that each phase can land with a stable product model.

## Implementation Decisions

- The selected target is the source of truth for cwd/session selection.
- A runtime may exist only for a selected cwd target or selected session target.
- Runtime cwd is not the authority for pi-webui's selected cwd. Runtime cwd is an implementation fact that must match the selected target.
- Runtime creation must fail loudly if the created runtime cwd does not match the selected target cwd.
- The selected target model includes these states:
  - cwd required, with a user-facing reason;
  - invalid URL, with invalid kind, value, and message;
  - cwd target, with resolved cwd and selection source;
  - session target, with session path, resolved session header cwd, and selection source.
- Missing `lastCwd` produces cwd-required state.
- Invalid or deleted `lastCwd` produces cwd-required state with an explanation.
- Valid `lastCwd` remains a startup target source.
- `process.cwd()` is never a fallback cwd.
- cwd environment variables are not supported as pi-webui default cwd configuration.
- `PI_WEBUI_CWD` or equivalent cwd env configuration is intentionally out of architecture because pi-webui should not have a special default project.
- URL Cwd Pointers still create cwd targets when valid.
- URL Session Pointers still create session targets when valid.
- URL Session Pointers must still be prevalidated before opening through Pi session management, because missing, corrupt, or headerless files must not be created or repaired as a side effect of URL validation.
- A valid session target reads cwd from the session header before runtime creation.
- A session resume counts as explicit target selection and persists the session header cwd as `lastCwd`.
- Workspaces remain saved cwd shortcuts. Selecting a workspace resolves to a cwd target.
- New sessions run in the current selected cwd target.
- Invalid URL state does not include eager session lists or default cwd recovery.
- Cwd-required state is not invalid URL state. It is app state caused by no selected target.
- No-runtime state supports runtime-free commands and requests only.
- Runtime-free recovery includes listing all sessions, listing recent cwds, listing directories, selecting cwd, and selecting session.
- No-runtime "Choose session" shows all sessions only. There is no current-project scope until a cwd target exists.
- Runtime-free cwd selection creates a cwd target, persists `lastCwd`, creates the runtime, and transitions to normal connected state.
- Runtime-free session selection creates a session target, persists the session header cwd as `lastCwd`, creates the runtime, and transitions to normal connected state.
- Runtime-required commands include prompts, bash execution, compaction, model switching, session naming, prompt template commands, extension commands, and runtime-bound Pi slash commands.
- Slash command availability should be generated from the current controller mode so no-runtime state does not advertise runtime-required commands as available.
- Generic command success must not persist `lastCwd`. Persistence belongs to explicit target transitions.
- Existing New Session Cwd Mode remains the URL representation for selected cwd with no durable session identity yet.
- Existing URL Session Pointer behavior remains the representation for durable selected sessions.

## Testing Decisions

- Prioritize integration and e2e-style tests over narrow unit tests. Good tests should exercise the same flows a browser tab or WebSocket client uses.
- Server integration tests should verify startup protocol behavior: valid target creates normal bootstrap, invalid URL creates invalid URL state, and missing/invalid `lastCwd` creates cwd-required state.
- Browser e2e or browser-like integration tests should verify user recovery flows: choose cwd, choose session, blocked prompt submission, and URL synchronization.
- Module tests remain useful for deep target-resolution rules where integration setup would obscure the cause of failure.
- Target resolution module tests should use real temporary directories and session files.
- Runtime creation integration tests should verify the seam where selected target becomes runtime configuration, including cwd match assertions.
- No-runtime recovery request tests should verify behavior without constructing an agent runtime.
- Invalid URL integration tests should verify that no normal connected/bootstrap packet is sent and that no runtime is created.
- Cwd-required integration tests should verify that missing, invalid, and deleted `lastCwd` do not fall back to process cwd.
- Persistence integration tests should verify that `lastCwd` is written only after explicit cwd/session target transitions.
- Session resume integration tests should verify that the session header cwd is persisted as `lastCwd`.
- Slash command integration tests should verify no-runtime catalog availability and runtime-required rejection behavior.
- Each implementation plan should end with validation scenarios that can become integration or e2e tests.
- Prior art includes existing server URL state tests, server cwd tests, URL session startup tests, browser URL state tests, invalid URL state tests, and workspace registry tests.

## Out of Scope

- Adding a pi-webui cwd environment variable or honoring a generic cwd environment variable.
- Using process cwd as a fallback under any name.
- Changing Pi's session file format.
- Editing session headers to repair missing cwd values.
- Adding opaque session ids or a server-side session lookup table.
- Making invalid session cwd recovery rewrite old sessions.
- Sharing one runtime across multiple browser tabs.
- In-place browser Back/Forward switching without reload.
- Changing input-history or debug browser storage.
- Reworking Pi's runtime internals or vendored Pi defaults.
- Replacing all slash command handling beyond the availability and target-transition work required here.

## Notes

- This PRD refines PRD-003. URL state remains the source for direct session and cwd links, but blank `/` no longer implies process cwd when no valid `lastCwd` exists.
- The main product shift is from "runtime owns cwd" to "selected target owns cwd and runtime derives from it."
- `lastCwd` is trusted only because pi-webui wrote it after prior explicit selection. It is not a default configured outside user/session behavior.
- The no-runtime state should feel like a narrow recovery mode, not a separate landing page.
- Invalid URL and cwd-required states may share UI pieces, but they represent different causes and should keep distinct copy.

## Later / Follow-ups

- Add explicit recovery for sessions whose stored cwd is missing by letting the user choose a replacement cwd override for that open operation.
- Consider a dedicated visual target selector for switching cwd/session without typing slash commands.
- Consider documenting selected target behavior in the README after implementation.
- Consider adding a lightweight diagnostics panel that shows selected target source for debugging.
- Consider moving prompt/template/extension command classification into a dedicated Slash Command Module if the catalog logic grows further.
