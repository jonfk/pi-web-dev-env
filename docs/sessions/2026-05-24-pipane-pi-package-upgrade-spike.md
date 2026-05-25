# Pipane Pi Package Upgrade Spike

Date: 2026-05-24

Branch: `codex/pi-package-upgrade-spike`

## Baseline

- Workspace: `pipane/`
- Node: `v23.11.1`
- npm: `10.9.2`
- `packageManager` in `package.json`: `npm@11.3.0`
- Local Pi package family before the spike:
  - `@mariozechner/pi-agent-core`: `0.55.3`
  - `@mariozechner/pi-ai`: `0.55.3`
  - `@mariozechner/pi-coding-agent`: `0.55.3`
  - `@mariozechner/pi-web-ui`: `0.55.3`
  - `@mariozechner/mini-lit`: declared `^0.2.0`, locked to `0.2.1`
- Patch files before the spike:
  - `pipane/patches/@mariozechner+pi-web-ui+0.55.3.patch`
  - `pipane/patches/@mariozechner+mini-lit+0.2.1.patch`

Baseline command results:

- `npm run check`: passed.
- `npm run test`: passed, `21` files and `301` tests. The run emits expected test stderr such as `ECONNREFUSED` from mocked browser fetch paths.
- `npm run build`: passed. Vite emitted existing KaTeX font resolution warnings and chunk-size warnings.
- `npm audit --json`: failed with audit findings: `18` total, `9` moderate, `8` high, `1` critical.
- `npm audit --omit=dev --json`: failed with audit findings: `17` total, `9` moderate, `7` high, `1` critical.

Baseline known Pi-family transitive findings present:

- `protobufjs`
- `undici`
- `basic-ftp`
- `fast-xml-parser`
- `yaml`
- `file-type`
- `brace-expansion`
- `ip-address`

## Old-Scope Attempt: `@mariozechner/*@0.73.1`

### Package Attempted

- Scope/version family: `@mariozechner/*@0.73.1`
- Exact dependency change attempted:
  - `@mariozechner/pi-agent-core`: `0.55.3` -> `0.73.1`
  - `@mariozechner/pi-ai`: `0.55.3` -> `0.73.1`
  - `@mariozechner/pi-coding-agent`: `0.55.3` -> `0.73.1`
  - `@mariozechner/pi-web-ui`: `0.55.3` -> `0.73.1`
- All four Pi packages were upgraded together.
- Registry check: `0.73.1` is the latest published old-scope version for all four packages.

### Install Result

`npm install @mariozechner/pi-agent-core@0.73.1 @mariozechner/pi-ai@0.73.1 @mariozechner/pi-coding-agent@0.73.1 @mariozechner/pi-web-ui@0.73.1` completed.

Install output included deprecation warnings for all upgraded old-scope packages:

```text
npm warn deprecated @mariozechner/pi-agent-core@0.73.1: please use @earendil-works/pi-agent-core instead going forward
npm warn deprecated @mariozechner/pi-tui@0.73.1: please use @earendil-works/pi-tui instead going forward
npm warn deprecated @mariozechner/pi-ai@0.73.1: please use @earendil-works/pi-ai instead going forward
npm warn deprecated @mariozechner/pi-web-ui@0.73.1: please use @earendil-works/pi-web-ui instead going forward
npm warn deprecated @mariozechner/pi-coding-agent@0.73.1: please use @earendil-works/pi-coding-agent instead going forward
```

The project `postinstall` script did not appear in the `npm install` output, so `npm run postinstall` was run explicitly. `patch-package` result:

```text
@mariozechner/mini-lit@0.2.1 ✔

**ERROR** Failed to apply patch for package @mariozechner/pi-web-ui at path

    node_modules/@mariozechner/pi-web-ui

Info:
    Patch file: patches/@mariozechner+pi-web-ui+0.55.3.patch
    Patch was made for version: 0.55.3
    Installed version: 0.73.1

patch-package finished with 1 error(s).
```

### Patch Behavior Inventory

- `MessageEditor.allowSendDuringStreaming`: still required and missing upstream. `AgentInterface.sendMessage()` still returns early when `session.state.isStreaming` is true, and `MessageEditor` blocks Enter send while `isStreaming`.
- `MessageEditor.onKeyDown`: still required and missing upstream on `MessageEditor`. Upstream has an `Input` component with `onKeyDown`, but `MessageEditor` uses a private `handleKeyDown` and exposes no property override.
- `MessageEditor.extraToolbarButtons`: still required and missing upstream. Upstream `MessageEditor` has no extension point for Pipane's toolbar controls.
- `setFallbackToolRenderer` / `FallbackToolRenderer`: old patch behavior is missing as an API, but upstream now has a built-in `DefaultRenderer` fallback through `renderTool()`. Pipane's custom generic fallback renderer remains incompatible unless moved local or reintroduced through a rebased patch.
- `data-tool-call-id`: still required by Pipane auto-collapse and chat-to-JSONL jump behavior; missing upstream on `<tool-message>`.
- `data-message-index`: still required by Pipane chat-to-JSONL jump behavior; missing upstream message rendering. Pipane currently adds this through local `pi-message-list.ts`.
- LM Studio model-discovery typing/runtime behavior: partially absorbed upstream. Upstream `model-discovery.ts` imports `LMStudioClient`, maps downloaded LLM models, supports `vision`, `trainedForToolUse`, `maxContextLength`, and `lmstudio` provider type. Runtime validation is still needed against a real LM Studio server.
- Markdown strikethrough behavior from the `mini-lit` patch: still required locally. The `@mariozechner/mini-lit@0.2.1` patch applies cleanly and installs a `renderer.del` override. The upgraded old-scope package family did not remove or obsolete this patch.

### Build And Type Failures

`npm run check` failed with these main categories:

- `AgentState.error` no longer exists; upstream now documents `errorMessage?: string`.
- `AgentState.streamMessage` was renamed to `streamingMessage`.
- Several `AgentState` fields are now readonly, including `isStreaming` and `pendingToolCalls`.
- `setFallbackToolRenderer` is not exported by `@mariozechner/pi-web-ui`.
- `FallbackToolRenderer` is not exported by `@mariozechner/pi-web-ui`.

Representative exact errors:

```text
src/client/main.ts(406,15): error TS2339: Property 'error' does not exist on type 'AgentState'.
src/client/rerun-duplicate.test.ts(138,24): error TS2551: Property 'streamMessage' does not exist on type 'AgentState'. Did you mean 'streamingMessage'?
src/client/tool-renderers.ts(8,32): error TS2305: Module '"@mariozechner/pi-web-ui"' has no exported member 'setFallbackToolRenderer'.
src/client/tool-renderers.ts(9,47): error TS2305: Module '"@mariozechner/pi-web-ui"' has no exported member 'FallbackToolRenderer'.
src/client/ws-agent-adapter.ts(414,16): error TS2540: Cannot assign to 'isStreaming' because it is a read-only property.
src/client/ws-agent-adapter.ts(416,16): error TS2540: Cannot assign to 'pendingToolCalls' because it is a read-only property.
```

`npm run test` failed:

- `20` files passed.
- `1` suite failed: `src/client/tool-renderers.test.ts`.
- `288` tests passed before the failing suite stopped collection.

Exact first runtime failure:

```text
TypeError: (0 , setFallbackToolRenderer) is not a function
 ❯ registerCodingAgentRenderers src/client/tool-renderers.ts:662:2
```

`npm run build` failed during client build:

```text
src/client/tool-renderers.ts (8:31): "setFallbackToolRenderer" is not exported by "node_modules/@mariozechner/pi-web-ui/src/index.ts", imported by "src/client/tool-renderers.ts".
```

The source alias in `vite.config.ts` still resolves to `node_modules/@mariozechner/pi-web-ui/src/index.ts` for the old-scope package, but that source entrypoint no longer exports the fallback renderer API Pipane imports.

No generated declaration or `dist` assumptions were validated beyond this because the build stops at the missing export.

### Runtime Compatibility Notes

The app could not be smoke tested in the old-scope attempt because `npm run build` fails on the missing `setFallbackToolRenderer` export. Runtime validation should stop at this blocker.

Session parsing and RPC assumptions could not be fully runtime-tested. Static failures show the local WebSocket adapter is incompatible with the newer `AgentState` shape. Server-side JSONL/session utilities still reference Pipane's local `streamMessage` model and need a separate compatibility pass against newer sessions/processes.

### Audit Delta

- Baseline `npm audit --json`: `18` total, `9` moderate, `8` high, `1` critical.
- Old-scope `npm audit --json`: `15` total, `8` moderate, `6` high, `1` critical.
- Baseline `npm audit --omit=dev --json`: `17` total, `9` moderate, `7` high, `1` critical.
- Old-scope `npm audit --omit=dev --json`: `14` total, `8` moderate, `5` high, `1` critical.

Known Pi-family transitive findings after old-scope upgrade:

- Still present: `protobufjs`, `undici`, `basic-ftp`, `yaml`, `file-type`, `brace-expansion`, `ip-address`.
- Removed from audit output: `fast-xml-parser` and its `@aws-sdk/xml-builder` effect.

## New-Scope Attempt: `@earendil-works/*@0.75.x`

### Package Attempted

- Scope/version family: `@earendil-works/*@0.75.x`
- Exact dependency change attempted:
  - removed `@mariozechner/pi-agent-core`
  - removed `@mariozechner/pi-ai`
  - removed `@mariozechner/pi-coding-agent`
  - removed `@mariozechner/pi-web-ui`
  - added `@earendil-works/pi-agent-core@0.75.5`
  - added `@earendil-works/pi-ai@0.75.5`
  - added `@earendil-works/pi-coding-agent@0.75.5`
  - added `@earendil-works/pi-web-ui@0.75.3`
- All four Pi packages were moved together to the new scope.
- Registry note: the latest published `0.75.x` versions are not identical. Core, AI, and coding-agent publish `0.75.5`; web-ui publishes `0.75.3`.

Installed tree:

```text
@earendil-works/pi-agent-core@0.75.5
@earendil-works/pi-ai@0.75.5
@earendil-works/pi-coding-agent@0.75.5
@earendil-works/pi-web-ui@0.75.3
@mariozechner/mini-lit@0.2.1
```

### Install Result

`npm uninstall` of the old-scope family completed, then `npm install` of the new-scope family completed.

`npm run postinstall` result:

```text
@mariozechner/mini-lit@0.2.1 ✔
Error: Patch file found for package pi-web-ui which is not present at node_modules/@mariozechner/pi-web-ui
---
patch-package finished with 1 error(s).
```

The old `pi-web-ui` patch cannot even target a package after the scope rename. It must be renamed/rebased or intentionally removed as part of a scoped migration.

### Patch Behavior Inventory

The new-scope `@earendil-works/pi-web-ui@0.75.3` source has the same broad behavior gaps observed in old-scope `0.73.1`:

- `MessageEditor.allowSendDuringStreaming`: still missing.
- `MessageEditor.onKeyDown`: still missing on `MessageEditor`; only the separate `Input` component exposes `onKeyDown`.
- `MessageEditor.extraToolbarButtons`: still missing.
- `setFallbackToolRenderer` / `FallbackToolRenderer`: still missing.
- `data-tool-call-id`: still missing.
- `data-message-index`: still missing.
- LM Studio model discovery: present through `LMStudioClient`.
- Markdown strikethrough behavior: still covered by the separate `@mariozechner/mini-lit@0.2.1` patch.

### Build And Type Failures

`npm run check` failed immediately because Pipane still imports the old scope:

```text
src/client/main.ts(17,8): error TS2307: Cannot find module '@mariozechner/pi-web-ui' or its corresponding type declarations.
src/client/message-renderers.ts(10,67): error TS2307: Cannot find module '@mariozechner/pi-ai' or its corresponding type declarations.
src/server/session-index.ts(12,50): error TS2307: Cannot find module '@mariozechner/pi-coding-agent' or its corresponding type declarations.
src/server/session-jsonl.ts(20,47): error TS2307: Cannot find module '@mariozechner/pi-agent-core' or its corresponding type declarations.
```

`npm run test` failed:

- `15` files passed.
- `6` files failed.
- `221` tests passed and `6` were skipped before collection/startup failures.

Main failure categories:

- client tests cannot resolve `@mariozechner/pi-web-ui`;
- server tests cannot resolve `@mariozechner/pi-coding-agent`;
- auth guard server startup exits before startup because server imports cannot resolve.

Representative exact failures:

```text
Error: Failed to resolve import "@mariozechner/pi-web-ui" from "src/client/message-renderers.test.ts". Does the file exist?
Error: Cannot find package '@mariozechner/pi-coding-agent' imported from '/Users/jfokkan/Developer/jonfk_code/pi-web-dev-env/pipane/src/server/session-index.ts'
Error: Server exited before startup (code=1)
```

`npm run build` failed before TypeScript because CSS still imports old-scope web-ui assets:

```text
[@tailwindcss/vite:generate:build] Can't resolve '@mariozechner/pi-web-ui/app.css' in '/Users/jfokkan/Developer/jonfk_code/pi-web-dev-env/pipane/src/client'
file: /Users/jfokkan/Developer/jonfk_code/pi-web-dev-env/pipane/src/client/app.css
```

The current `vite.config.ts` source alias is old-scope-specific:

```ts
find: /^@mariozechner\/pi-web-ui$/,
replacement: path.resolve(__dirname, "node_modules/@mariozechner/pi-web-ui/src/index.ts")
```

That alias must be renamed if Pipane targets `@earendil-works/pi-web-ui`.

### Runtime Compatibility Notes

The app could not be smoke tested in the new-scope attempt because imports and CSS fail before a runnable build exists.

This attempt does not yet prove new-scope runtime compatibility; it proves that a scope migration is a separate source-level change, not a package-only upgrade.

### Audit Delta

- Baseline `npm audit --json`: `18` total, `9` moderate, `8` high, `1` critical.
- New-scope `npm audit --json`: `7` total, `3` moderate, `4` high, `0` critical.
- Baseline `npm audit --omit=dev --json`: `17` total, `9` moderate, `7` high, `1` critical.
- New-scope `npm audit --omit=dev --json`: `6` total, `3` moderate, `3` high, `0` critical.

Known Pi-family transitive findings after new-scope migration:

- Removed from audit output: `protobufjs`, `undici`, `basic-ftp`, `fast-xml-parser`, `yaml`, `file-type`, `brace-expansion`, `ip-address`.
- Remaining findings are outside the old Pi-family list: `happy-dom`, `path-to-regexp`, `picomatch`, `postcss`, `qs`, `vite`, `ws`.

## Recommendation

Recommendation: upgrade should target the new `@earendil-works/*` scope, but not as a package-only change. The old `@mariozechner/*@0.73.1` line is not a useful stopping point: it is deprecated, still fails the largest `pi-web-ui` patch, still leaves most known Pi-family audit findings, and still requires `AgentState` API migration work. The new scope removes the known Pi-family audit findings, but requires explicit import/CSS/alias migration and a patch strategy.

The smallest follow-up ticket set:

1. Rebase or replace the `pi-web-ui` patch behaviors against `@earendil-works/pi-web-ui`, with special attention to streaming steering, key handling, toolbar extension points, and DOM hooks.
2. Migrate Pipane imports, CSS imports, and Vite alias from `@mariozechner/*` to `@earendil-works/*`.
3. Update Pipane's adapter/session code for the newer `AgentState` API: `streamingMessage`, `errorMessage`, and readonly runtime fields.
4. Runtime-validate RPC/session compatibility against a newer `pi` CLI and existing JSONL sessions after the app can build.
5. Re-run audit triage after the new-scope migration, focusing on the remaining non-Pi findings.

Do not merge dependency changes from this spike as-is.
