# Ticket 13: Upstream Patch and Fork Delta Review

Date: 2026-05-24
Workspace: `/Users/jfokkan/Developer/jonfk_code/pi-web-dev-env`
Project root: `pipane/`

## Executive Summary

Pipane currently relies on two `patch-package` patches:

- `@mariozechner/mini-lit@0.2.1`: one small markdown rendering behavior change.
- `@mariozechner/pi-web-ui@0.55.3`: a broad patch with a small set of real source-level API/DOM changes plus large generated `dist` and source-map churn.

The main long-term maintenance risk is the `pi-web-ui` patch. Pipane imports patched APIs directly (`setFallbackToolRenderer`, `FallbackToolRenderer`) and depends on patched `message-editor` properties (`allowSendDuringStreaming`, `onKeyDown`, `extraToolbarButtons`) and patched DOM hooks (`data-tool-call-id`, `data-message-index`). A dependency update from `0.55.3` to `0.73.1` will not absorb those behaviors: inspection of the published `@mariozechner/pi-web-ui@0.73.1` tarball found none of the core patch symbols except unrelated upstream exports such as `registerMessageRenderer`, `renderMessage`, storage exports, and `formatUsage`.

Recommended path: keep `mini-lit` patch unless/until markdown rendering is moved local; replace most `pi-web-ui` patch-package reliance with local extension/wrapper code where possible, and upstream only generic extension points (`setFallbackToolRenderer`, `extraToolbarButtons`, streaming send support, stable DOM data attributes).

## Evidence Gathered

- Current dependencies in `pipane/package.json` pin the Pi packages to `0.55.3`; `@mariozechner/mini-lit` resolves to `0.2.1` in `package-lock.json`.
- `pipane/vite.config.ts:47-53` aliases bare `@mariozechner/pi-web-ui` imports to `node_modules/@mariozechner/pi-web-ui/src/index.ts`, so the client builds against patched source files, not just patched `dist`.
- `pipane/src/client/main.ts:91-103` imperatively sets `message-editor.allowSendDuringStreaming` and `message-editor.onKeyDown`.
- `pipane/src/client/main.ts:446-458` renders `<message-editor>` with `.allowSendDuringStreaming=${true}` and `.extraToolbarButtons=${() => renderToolbarExtras()}`.
- `pipane/src/client/tool-renderers.ts:8-9` imports `setFallbackToolRenderer` and `FallbackToolRenderer` from `@mariozechner/pi-web-ui`; `pipane/src/client/tool-renderers.ts:576-662` installs a generic fallback renderer.
- `pipane/src/client/main.ts:195-205` and `pipane/src/client/auto-collapse.ts` depend on `data-message-index` and `data-tool-call-id` hooks for chat-to-JSONL jumps and auto-collapse.
- Network check: sandboxed `npm view` initially failed with `ENOTFOUND`; rerun with approved network access succeeded.
- Upstream package facts checked via npm:
  - `@mariozechner/mini-lit` versions end at `0.2.1`; no newer version exists under that scope.
  - `@mariozechner/pi-web-ui@0.73.1` exists and is the relevant old-scope upgrade target.
  - `@earendil-works/pi-web-ui` exists at `0.75.3`; Pi release notes state `0.73.1` is the final old `@mariozechner/*` release and later releases move to `@earendil-works/*`.

## Patch-by-Patch Summary

### `patches/@mariozechner+mini-lit+0.2.1.patch`

Owner: Pipane UI / message rendering.

Rationale: Prevent LLM approximations such as `~500` from rendering as strikethrough text. The patch overrides marked's `renderer.del` in `dist/MarkdownBlock.js` to render delimiters literally as `~...~`.

Status: Keep for now. It is small, understandable, and isolated, but it patches compiled `dist` because `mini-lit` does not ship the relevant TypeScript source. There is no newer `@mariozechner/mini-lit` release to test against.

Preferred long-term path: upstream a markdown option such as `disableStrikethrough` or replace usage with a local Pipane markdown component/renderer wrapper. Upstreaming is preferable if Pipane expects to keep using `markdown-block` broadly.

Upgrade risk: Low. It is only 17 lines and touches one hunk, but any upstream rewrite of `MarkdownBlock.js` or a marked major behavior change can make the patch fail or subtly re-enable strikethrough.

### `patches/@mariozechner+pi-web-ui+0.55.3.patch`

Owner: Pipane client shell, custom tool/message rendering, steering UX.

Rationale: Pipane uses upstream `pi-web-ui` as a component library but needs extra integration hooks:

- steering while the agent is streaming (`allowSendDuringStreaming`);
- custom editor keyboard handling (`onKeyDown`) for fork/send shortcuts;
- extra toolbar buttons in the input row (`extraToolbarButtons`);
- fallback rendering for unknown Pi tools with access to the tool name (`setFallbackToolRenderer`, `FallbackToolRenderer`);
- stable DOM attributes to connect rendered chat back to JSONL/tool state (`data-message-index`, `data-tool-call-id`);
- a narrow LM Studio typing workaround in `model-discovery.ts`;
- generated `dist`/`.map` changes so package consumers and TypeScript declarations line up.

Status: Keep until replaced; do not update Pi dependencies without first planning replacements for these hooks. `@mariozechner/pi-web-ui@0.73.1` does not absorb the core Pipane-specific behavior:

- no `allowSendDuringStreaming` in `AgentInterface` or `MessageEditor`;
- no `MessageEditor.onKeyDown` callback;
- no `MessageEditor.extraToolbarButtons`;
- no `setFallbackToolRenderer` or `FallbackToolRenderer`;
- no `data-message-index` or `data-tool-call-id`;
- `model-discovery.ts` still accesses `model.trainedForToolUse` and `model.vision` directly.

Upstream `0.73.1` does include some APIs that appear to have been local-patch-adjacent or later added upstream: `registerMessageRenderer`, `renderMessage`, `AppStorage`, `setAppStorage`, storage classes, and `formatUsage` are exported from `src/index.ts`.

Preferred long-term path: split this patch into three tracks:

1. Upstream generic extension points: fallback renderer with tool name, editor toolbar slot, optional streaming-send mode, and stable data attributes.
2. Move Pipane-specific composition local: keep using `pi-message-list` and custom renderer registration in Pipane, and avoid patching upstream `MessageList` if local rendering already covers the use case.
3. Remove generated churn: if patch-package remains, patch only upstream source files where Vite aliases to source; avoid broad generated `dist`/source-map patches unless Pipane publishes a package that must work after install without source aliasing.

## Upgrade-Risk Table

| Area | Current dependency | Why Pipane needs it | `0.73.1` absorbed? | Upgrade risk | Recommended status |
| --- | --- | --- | --- | --- | --- |
| `mini-lit` markdown `renderer.del` | `markdown-block` rendering | Prevent approximate values like `~500` becoming `<del>` | No newer `@mariozechner/mini-lit` exists | Low | Keep or upstream option |
| `MessageEditor.allowSendDuringStreaming` | `main.ts` sets and renders it | Steering messages while agent is running | No | High | Upstream generic prop or create local editor wrapper |
| `AgentInterface.allowSendDuringStreaming` | Indirect upstream parity | Same steering behavior if `AgentInterface` is used | No | Medium | Lower priority because Pipane renders local shell, but keep if using `AgentInterface` elsewhere |
| `MessageEditor.onKeyDown` | `main.ts` custom Cmd/Ctrl+Enter fork prompt | Custom keyboard shortcut before default send | No | High | Local wrapper or upstream callback |
| `MessageEditor.extraToolbarButtons` | `main.ts` inserts local toolbar controls | Pipane-specific controls without forking editor markup | No | High | Upstream slot/callback or own editor component |
| `setFallbackToolRenderer` / `FallbackToolRenderer` | `tool-renderers.ts` generic unknown-tool renderer | Unknown tools need tool name in renderer | No | High | Best upstream candidate; otherwise own `renderTool` dispatch locally |
| `data-message-index` | chat-to-JSONL jump code | Map UI message to original message index | No | Medium | Local `pi-message-list` already duplicates this; avoid upstream patch if not using upstream `MessageList` |
| `data-tool-call-id` | auto-collapse and JSONL jump code | Locate rendered tool messages by call id | No | High | Upstream stable DOM attr or local `assistant-message`/tool-message wrapper |
| `model-discovery.ts` casts | TypeScript compatibility around LM Studio model shape | Build stability with model metadata fields | No | Medium | Re-check with `0.73.1` type errors; upstream has same direct accesses |
| Generated `dist` and source maps | Published package / type declarations | Makes patched package work outside Vite source alias | N/A | High churn | Avoid carrying generated files if Pipane can rely on source alias; otherwise regenerate from a clean fork |

## Breakage Likely During `0.55.3` -> `0.73.1`

- Patch-package will almost certainly fail to apply cleanly. The `pi-web-ui` patch is 3,437 lines and touches many generated files; upstream `0.73.1` has significantly changed package contents and file sizes.
- The bare import alias to `src/index.ts` means source-level missing exports will become immediate build failures. `setFallbackToolRenderer` and `FallbackToolRenderer` are the most obvious blockers.
- Even if build errors are fixed, runtime behavior will regress unless `MessageEditor` replacement behavior exists: no steering send button during streaming, no custom keydown interception, and no extra toolbar insertion.
- Auto-collapse and JSONL jump behavior can silently break if rendered tool/message DOM lacks `data-tool-call-id` and `data-message-index`.
- The old package scope is at end of life. `0.73.1` is the final `@mariozechner/*` line; any upgrade beyond that requires `@earendil-works/*` package names and likely import/package-lock churn.

## Recommended Ownership and Status

| Patch / hunk family | Owner | Status | Decision |
| --- | --- | --- | --- |
| `mini-lit` markdown strikethrough override | Pipane UI | Keep | Small product choice; upstream option if feasible |
| `pi-web-ui` editor steering and toolbar hooks | Pipane client shell | Replace or upstream | High-value generic API; avoid long-term patch-package fork |
| `pi-web-ui` fallback tool renderer | Pipane tool rendering | Upstream first | Clean generic extension point with low upstream surface |
| `pi-web-ui` DOM data attributes | Pipane JSONL/auto-collapse | Replace locally or upstream | Needed for Pipane features; local wrapper may be safer |
| `pi-web-ui` `MessageList` data index | Pipane message list | Replace locally | Pipane already has `pi-message-list`; upstream hunk may be obsolete |
| `pi-web-ui` LM Studio casts | Model discovery/build | Re-test during upgrade | Keep only if compiler still fails |
| `pi-web-ui` generated `dist`/maps | Packaging/release | Reduce | High-maintenance noise; avoid unless publishing patched upstream package |

## Follow-ups

1. Before any dependency update, create a small compatibility branch that installs `@mariozechner/*@0.73.1` and records exact TypeScript/build failures.
2. Decide whether Pipane should keep building from `pi-web-ui/src/index.ts`. If yes, trim future patch-package files to source-only hunks. If no, local wrappers or an internal fork package are safer than patching generated tarball output.
3. Try upstream PRs/issues for:
   - `MessageEditor` toolbar slot/callback;
   - `MessageEditor` custom keydown hook;
   - streaming-send/steering mode;
   - fallback tool renderer receiving `toolName`;
   - stable `data-tool-call-id` on `tool-message`.
4. Move `mini-lit` markdown behavior into a local renderer only if upstream is unwilling to accept an option; otherwise the current patch is acceptable.
5. Plan the scope migration separately: old `@mariozechner/*` packages stop at `0.73.1`; newer Pi packages live under `@earendil-works/*`.

