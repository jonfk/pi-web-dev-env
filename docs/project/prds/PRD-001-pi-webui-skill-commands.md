# PRD-001: pi-webui Skill Commands

## Problem Statement

Users can invoke pi skills from the TUI with `/skill:{name}`, but pi-webui does not surface Skill Commands in its Slash Command Catalog and rejects manual `/skill:{name}` invocations as unsupported. This makes pi-webui feel inconsistent with the TUI and prevents users from using their existing skill workflow from the browser.

## Solution

pi-webui will support Skill Commands using the same model as the TUI. Skills will appear in the Slash Command Catalog as `/skill:{name}` when pi skill commands are enabled, and manual `skill:*` slash invocations will be submitted through the existing session prompt path so pi owns skill expansion. pi-webui will not read, parse, or expand skill files itself.

The implementation will introduce a Slash Command Module that centralizes catalog construction and command dispatch classification. The browser will receive Slash Command Refresh messages whenever session resources may have changed.

## User Stories

1. As a pi-webui user, I want to see available Skill Commands in slash autocomplete, so that I can discover the same skills I use in the TUI.
2. As a pi-webui user, I want Skill Commands to use the `/skill:{name}` form, so that the browser matches the TUI command vocabulary.
3. As a pi-webui user, I want selecting a Skill Command to insert the slash command into the composer, so that I can add arguments before sending.
4. As a pi-webui user, I want `/skill:{name} {request}` to invoke the skill, so that the agent receives the skill instructions and my request together.
5. As a pi-webui user, I want pi to own skill expansion, so that Skill Commands behave consistently across the TUI and browser.
6. As a pi-webui user, I want prompt templates to keep working after Skill Commands are added, so that existing prompt workflows do not regress.
7. As a pi-webui user, I want extension slash commands to keep working after Skill Commands are added, so that installed extensions remain usable.
8. As a pi-webui user, I want built-in commands that are known but unsupported in the browser to remain visible as unsupported, so that I understand pi-webui knows about them.
9. As a pi-webui user, I want unsupported slash commands to produce a clear web UI error, so that I am not confused by silent failures.
10. As a pi-webui user, I want Skill Commands to disappear from autocomplete when pi skill commands are disabled, so that the catalog respects my pi settings.
11. As a pi-webui user, I want manual `skill:*` invocations to pass through to pi, so that pi decides whether a skill can be expanded.
12. As a pi-webui user, I want Skill Commands to refresh after `/reload`, so that newly added or removed skills are reflected without restarting pi-webui.
13. As a pi-webui user, I want Skill Commands to refresh after switching workspaces or cwd, so that project-local skills match the active workspace.
14. As a pi-webui user, I want Skill Commands to refresh after switching sessions, so that the catalog matches the active session resources.
15. As a pi-webui user, I want Skill Commands to use the same descriptions as pi, so that I can choose the right skill from autocomplete.
16. As a maintainer, I want slash command catalog construction centralized, so that new command sources do not require editing several unrelated paths.
17. As a maintainer, I want slash command dispatch classification centralized, so that supported, prompt-routed, and unsupported commands are easy to reason about.
18. As a maintainer, I want pi-webui tests to verify behavior through the Slash Command Module interface, so that command behavior is protected while implementation details can change.
19. As a maintainer, I want prompt templates labeled as source `prompt`, so that pi-webui uses pi's command vocabulary instead of a web-only `template` label.
20. As a maintainer, I want Skill Command support isolated from running-input behavior, so that steering and follow-up behavior can be implemented separately.

## Implementation Decisions

- Build a Slash Command Module that owns Slash Command Catalog construction and dispatch classification.
- Keep command execution in the session controller. The Slash Command Module classifies commands, but the session controller still invokes handlers, calls `session.prompt`, sends state, and reports command results.
- Include built-in pi slash commands in the catalog and preserve the existing `supported: false` behavior for Unsupported Slash Commands.
- Include webui-specific slash commands in the catalog with source `webui`.
- Include extension commands in the catalog with source `extension`.
- Include prompt templates as Prompt Commands with source `prompt`, replacing the current web-only `template` source label.
- Include Skill Commands with source `skill` and command names in the form `skill:{name}`.
- Only include Skill Commands in the Slash Command Catalog when pi's `enableSkillCommands` setting is enabled.
- Classify any `skill:*` invocation as prompt-routed, even if it is not present in the current catalog. This matches the TUI-style behavior where pi owns expansion and fallback.
- Reconstruct prompt-routed slash invocations as exact slash text and call `session.prompt(...)`.
- Do not read `SKILL.md` files, parse skill frontmatter, or build skill prompt text in pi-webui.
- Add a `slash_commands` server-to-client message that replaces the browser's Slash Command Catalog.
- Send a Slash Command Refresh on initial connection and after session-resource changes, including reloads, cwd/workspace switches, session switches, new sessions, imports, and other bootstrap paths where resources may have changed.
- Preserve current composer behavior while the agent is running. TUI-style steering and follow-up are a separate PRD and should not be bundled into this implementation.

## Testing Decisions

- Good tests should verify observable command behavior through public interfaces, not private helper details or implementation shape.
- Add focused tests for the Slash Command Module because it is the new deep module for catalog and classification behavior.
- Test that Skill Commands are included in the Slash Command Catalog when enabled.
- Test that Skill Commands are omitted from the Slash Command Catalog when disabled.
- Test that prompt templates are labeled as source `prompt`.
- Test that Unsupported Slash Commands remain visible with `supported: false`.
- Test that known handler commands classify as handler-routed.
- Test that extension commands, Prompt Commands, and Skill Commands classify as prompt-routed.
- Test that unknown non-skill commands classify as unsupported.
- Test that manual `skill:*` commands classify as prompt-routed even when absent from the catalog.
- Add controller-level coverage that a Skill Command invocation calls `session.prompt(...)` with slash text.
- Add controller-level coverage that `/reload` sends a Slash Command Refresh after resources reload.
- Use existing node test patterns in pi-webui as prior art for narrow module tests and server bridge tests.

## Out of Scope

- Changing Enter while running from abort to steer.
- Adding Alt+Enter follow-up behavior.
- Splitting the composer send and stop controls.
- Changing image attachment behavior while the agent is running.
- Implementing a visual skill launcher beyond slash autocomplete.
- Editing pi's skill loading, validation, or expansion behavior.
- Supporting skill installation or skill management from pi-webui.

## Notes

- This PRD intentionally keeps Skill Command support independent from TUI-style steering and follow-up support.
- Skill Commands should work for normal idle-session submission as part of this PRD.
- Running-session slash behavior may remain limited until the separate steering/follow-up PRD is implemented.
- The glossary in `CONTEXT.md` defines Skill Command, Slash Command Catalog, Slash Command Refresh, and Slash Command Module.

## Later / Follow-ups

- Implement TUI-style steering and follow-up behavior for pi-webui.
- Add a richer skill browser or launcher if slash autocomplete is not enough.
- Consider exposing command source grouping or filtering in the slash menu.
- Consider documenting Skill Command behavior in the pi-webui README after implementation lands.
