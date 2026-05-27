# PRD-002: pi-webui TUI-Style Steering And Follow-up

## Problem Statement

The pi TUI lets users steer a running agent with Enter and queue follow-up messages with a separate follow-up action. pi-webui currently treats composer submission while the agent is running as an abort action. This prevents users from steering or queuing follow-up work from the browser and makes pi-webui behave differently from the TUI.

## Solution

pi-webui will adopt the TUI running-input behavior. When the agent is running, Enter submits the current composer contents as steering input, Alt+Enter submits the current composer contents as follow-up input, and Shift+Enter continues to insert a newline. Abort will move to an explicit stop control and remain available through Escape.

This feature should build on the existing session prompt path and use `session.prompt(...)` with the appropriate streaming behavior. It should apply to regular prompts, prompt-routed slash commands, and image attachments.

## User Stories

1. As a pi-webui user, I want pressing Enter while the agent is running to steer the agent, so that I can correct or redirect work without aborting.
2. As a pi-webui user, I want pressing Alt+Enter while the agent is running to queue a follow-up, so that I can add the next instruction without interrupting the current turn.
3. As a pi-webui user, I want Shift+Enter to continue inserting a newline, so that multiline prompts remain easy to write.
4. As a pi-webui user, I want Escape to abort a running agent, so that I still have a fast keyboard cancellation path.
5. As a pi-webui user, I want a visible stop control while the agent is running, so that mouse and touch users can abort explicitly.
6. As a pi-webui user, I want a visible send control while the agent is running, so that mouse and touch users can submit steering input.
7. As a pi-webui user, I want the browser to avoid overloading one button as both send and stop, so that I do not accidentally abort when I meant to steer.
8. As a pi-webui user, I want regular text submitted during a run to use steering behavior by default, so that pi-webui matches the TUI Enter behavior.
9. As a pi-webui user, I want follow-up submission to wait until the current agent work finishes, so that I can queue the next request safely.
10. As a pi-webui user, I want prompt templates submitted during a run to steer or follow up according to my keypress, so that templates behave like normal prompt text.
11. As a pi-webui user, I want Skill Commands submitted during a run to steer or follow up according to my keypress, so that skills behave like normal prompt text.
12. As a pi-webui user, I want extension commands submitted during a run to continue executing immediately when pi handles them that way, so that extension command behavior remains consistent with pi.
13. As a pi-webui user, I want image attachments submitted during a run to follow the same Enter and Alt+Enter behavior, so that multimodal steering and follow-up are possible.
14. As a pi-webui user, I want bash command routing to remain separate from prompt steering, so that `!` commands continue to run as bash commands.
15. As a pi-webui user, I want slash command routing to remain unavailable when image attachments are present, so that attachments continue through the normal prompt path.
16. As a pi-webui user, I want pending image attachments cleared only after a successful send path is chosen, so that failed submissions do not lose my attachments.
17. As a pi-webui user, I want optimistic user messages to remain sensible for steering and follow-up submissions, so that the chat log reflects what I submitted.
18. As a pi-webui user, I want the status and queue display to reflect steering and follow-up messages, so that I understand what is pending.
19. As a maintainer, I want running-input routing to be explicit in client code, so that abort, steer, and follow-up are not hidden behind the same submit branch.
20. As a maintainer, I want server prompt handling to require an explicit streaming behavior while streaming, so that running input does not silently fall back to web-only behavior.
21. As a maintainer, I want tests around keyboard behavior, so that future UI edits do not regress TUI parity.
22. As a maintainer, I want steering and follow-up support to be separate from Skill Command support, so that the two features can ship and be reviewed independently.

## Implementation Decisions

- Change composer submission while the session is running from abort to steering submission.
- Add Alt+Enter handling for follow-up submission while the session is running.
- Keep Shift+Enter as newline insertion.
- Keep Escape as the keyboard abort path while the session is running.
- Split visible running controls so users have both a send/steer control and a stop/abort control.
- Send `streamingBehavior: "steer"` for Enter-submitted prompts and prompt-routed slash commands while streaming.
- Send `streamingBehavior: "followUp"` for Alt+Enter-submitted prompts and prompt-routed slash commands while streaming.
- Apply the same streaming behavior to image attachment submissions.
- Preserve bash routing for messages routed as bash commands.
- Preserve the current rule that slash and bash routing only apply when there are no image attachments.
- Do not reinterpret pi's `steeringMode` and `followUpMode` settings. Those settings control queue drain behavior, not whether Enter chooses steer or follow-up.
- Preserve extension command semantics by continuing to route extension slash commands through `session.prompt(...)`, where pi can execute them immediately.
- Remove the server-side default that silently converts missing streaming behavior to follow-up. Running submissions should send an explicit streaming behavior.

## Testing Decisions

- Good tests should describe external behavior: what the browser sends and what the server passes to the session, not private DOM or helper implementation details.
- Add client-side behavior tests for Enter while running sending steering input instead of abort.
- Add client-side behavior tests for Alt+Enter while running sending follow-up input.
- Add client-side behavior tests for Escape and the stop control sending abort.
- Add client-side behavior tests that Shift+Enter remains newline.
- Add client-side behavior tests that image attachments are sent with the selected streaming behavior while running.
- Add server-side tests that prompt requests while streaming pass explicit `streamingBehavior` through to `session.prompt(...)`.
- Add server-side tests that prompt-routed slash commands receive the selected streaming behavior.
- Use existing pi-webui route-input, chat-state, and browser-app test patterns as prior art.

## Out of Scope

- Adding Skill Commands to the Slash Command Catalog.
- Extracting the Slash Command Module.
- Adding Slash Command Refresh.
- Changing pi's queue drain modes.
- Adding a full keyboard shortcut settings UI.
- Changing model, settings, workspace, or session command behavior except where running submission routing touches them.

## Notes

- This PRD should be implemented after, or independently from, Skill Command support.
- The intended behavior is TUI parity: Enter steers; Alt+Enter queues follow-up.
- Existing pi settings named `steeringMode` and `followUpMode` should not be mistaken for the input routing choice.
- Running input should be explicit. Missing streaming behavior should be treated as a caller bug rather than silently choosing follow-up.

## Later / Follow-ups

- Add visible queue management controls if users need to inspect or remove queued steering/follow-up messages.
- Add help text or keyboard shortcut documentation for Enter, Alt+Enter, Shift+Enter, and Escape.
- Consider a touch-friendly follow-up control if Alt+Enter is not discoverable enough.
- Consider aligning additional TUI input behaviors after this feature lands.
