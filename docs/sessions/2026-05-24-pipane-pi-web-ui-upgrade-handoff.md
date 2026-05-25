# Pipane Pi Package / pi-web-ui Handoff

Date: 2026-05-24
Workspace: `/Users/jfokkan/Developer/jonfk_code/pi-web-dev-env`
Project root: `pipane/`

## Purpose

This handoff captures the exploration from the current conversation so a fresh agent can continue planning. No implementation was performed.

The user asked about:

- how Pipane uses the pinned `@mariozechner/pi-*` packages at `0.55.3`;
- how those packages interact with a globally launched `pi` in RPC mode at `0.73.1`;
- whether `@mariozechner/pi-web-ui` can be upgraded separately;
- whether `pi-web-ui` could be inlined, and whether that could happen one component at a time;
- the exact current dependency surface on `pi-web-ui`.

Do not duplicate the deeper dependency/security/patch analysis already captured in:

- [`docs/sessions/2026-05-24-pipane-audit/01-dependency-freshness-and-upgrade-risk.md`](./2026-05-24-pipane-audit/01-dependency-freshness-and-upgrade-risk.md)
- [`docs/sessions/2026-05-24-pipane-audit/02-npm-security-advisory-triage.md`](./2026-05-24-pipane-audit/02-npm-security-advisory-triage.md)
- [`docs/sessions/2026-05-24-pipane-audit/13-upstream-patch-and-fork-delta.md`](./2026-05-24-pipane-audit/13-upstream-patch-and-fork-delta.md)

## Key Conclusions

Pipane has two separate relationships to Pi:

- It links `@mariozechner/pi-agent-core`, `pi-ai`, `pi-coding-agent`, and `pi-web-ui` at `0.55.3` for local types, session parsing, UI components, storage shells, renderer registries, and CSS.
- It launches whatever `pi` executable resolves from `PI_CLI` or `PATH` with `--mode rpc`; that executable may already be `0.73.1`.

That means Pipane can already run in a mixed-version shape: local `0.55.3` library code talking JSONL RPC to a newer child `pi` process. The RPC command set Pipane uses appears broadly compatible with the latest published Pi RPC docs, but mixed-version risk remains around JSONL framing, ignored newer events, session format parsing, queue updates, and extension UI requests.

`pi-web-ui` can technically be upgraded separately, but it is not a low-risk standalone bump. The package is part of the same pre-1.0 Pi family, and Pipane depends on local `patch-package` behavior that upstream `0.73.1` does not appear to provide. Treat a separate `pi-web-ui` upgrade as a compatibility spike, not a normal dependency update.

Inlining `pi-web-ui` selectively is plausible and likely cleaner long term than carrying a broad patch. Do not inline the whole package by default. Inline the parts Pipane actually uses, in dependency order.

## Exact Current `pi-web-ui` Dependency Surface

Direct imports and types:

- `AppStorage`, `CustomProvidersStore`, `ProviderKeysStore`, `SessionsStore`, `SettingsStore`, `setAppStorage` from `@mariozechner/pi-web-ui` in `pipane/src/client/main.ts`.
- `formatUsage` from `@mariozechner/pi-web-ui` in `pipane/src/client/main.ts`.
- `registerToolRenderer`, `setFallbackToolRenderer`, `ToolRenderer`, `ToolRenderResult`, `FallbackToolRenderer` in `pipane/src/client/tool-renderers.ts`.
- `registerMessageRenderer` in `pipane/src/client/message-renderers.ts`.
- `renderMessage` in `pipane/src/client/pi-message-list.ts`.
- `StorageBackend`, `StorageTransaction` types in `pipane/src/client/dummy-storage.ts`.
- `getToolRenderer` and `getMessageRenderer` in client tests.

Custom elements Pipane uses directly or indirectly:

- `<message-editor>` in `pipane/src/client/main.ts`.
- `<user-message>` and `<assistant-message>` in `pipane/src/client/pi-message-list.ts`.
- `<tool-message>` indirectly through upstream `<assistant-message>`.
- `<thinking-block>` via upstream rendering, then monkey-patched by `pipane/src/client/thinking-block-patch.ts`.
- `<markdown-block>` in multiple Pipane components; this is from `@mariozechner/mini-lit`, but Pipane relies on the current upstream component stack to register/use it consistently.

Build/package coupling:

- `pipane/src/client/app.css` imports `@mariozechner/pi-web-ui/app.css`.
- `pipane/vite.config.ts` aliases bare `@mariozechner/pi-web-ui` imports to `node_modules/@mariozechner/pi-web-ui/src/index.ts`.
- `pipane/prod.sh` rebuilds `pi-web-ui` from source before building Pipane.

## Inlining Strategy Recommended

Inline one piece at a time. Suggested order:

1. Local renderer registries:
   - `registerMessageRenderer`, `getMessageRenderer`, `renderMessage`.
   - `registerToolRenderer`, `getToolRenderer`, `renderTool`, fallback renderer support.
   - This removes the most obvious patched API blocker: `setFallbackToolRenderer`.

2. Local `message-editor`:
   - Pipane depends on patched `allowSendDuringStreaming`, `onKeyDown`, and `extraToolbarButtons`.
   - This is high-value because it isolates steering input, fork prompt shortcut behavior, toolbar extras, attachment handling, and stop/send controls.

3. Local message leaf components:
   - `assistant-message`, `tool-message`, `user-message`, and possibly `thinking-block`.
   - Pipane already owns `pi-message-list`; it only borrows these leaves.
   - This is also where `data-tool-call-id` and `data-message-index` behavior should become locally owned.

4. Local tiny utilities/types:
   - `formatUsage`.
   - Storage type shims or local minimal store interfaces.
   - Attachment loading only if still needed after editor inlining.

5. Reassess whether `pi-web-ui` remains needed:
   - At that point it may only provide CSS and attachment/document/artifact helpers.

## Upgrade/Compatibility Risks To Validate

For mixed local `0.55.3` packages with `pi@0.73.1` RPC:

- Pipane uses Node `readline` to split RPC stdout, while latest Pi RPC docs warn that generic line readers are not strictly JSONL-compliant because they can split on Unicode separators.
- Pipane ignores newer events such as `agent_end`, `turn_start`, `queue_update`, `compaction_start`, `compaction_end`, `auto_retry_start`, `auto_retry_end`, and `extension_error`.
- Pipane tracks steering queue state locally instead of consuming `queue_update`.
- Pipane does not handle `extension_ui_request`; simple tools like the current canvas extension should be fine, but dialog-capable extensions could hang or degrade.
- Pipane parses session files using local `0.55.3` `parseSessionEntries` / `buildSessionContext`; this must be tested against sessions generated by `0.73.1`.

For separate `@mariozechner/pi-web-ui@0.73.1` upgrade:

- Expect build failures around removed/unavailable patched exports and properties.
- Expect possible duplicate or mismatched `@mariozechner/pi-ai` / `pi-agent-core` type identities if only `pi-web-ui` is moved.
- Existing patch-package patch is known high risk; see the referenced upstream patch/fork delta audit rather than re-copying details here.

## Suggested Next Work

Recommended next non-implementation spike:

1. Create a disposable compatibility branch.
2. Upgrade only `@mariozechner/pi-web-ui` to `0.73.1`.
3. Run `npm install`, `npm run check`, and `npm run build`.
4. Record exact failures in a short doc or issue.
5. Do not fix them in the same spike unless the user explicitly asks.

Recommended next implementation path, if approved later:

1. Add local renderer registries and switch Pipane imports to them.
2. Inline or rewrite `message-editor`.
3. Run unit tests and screenshot tests after each step.
4. Only after the UI surface is local, revisit coordinated Pi package upgrades.

## External References Used

- Latest Pi RPC docs: <https://pi.dev/docs/latest/rpc>
- Pi `0.73.1` release notes: <https://pi.dev/news/releases/0.73.1>
- Pi package scope migration note: <https://pi.dev/news/2026/5/7/pi-has-a-new-home>

