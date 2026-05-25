# W-0001: Spike Pi package family upgrade compatibility

## Status

Backlog

## Context

Pipane currently pins the local Pi package family to `@mariozechner/*@0.55.3`:

- `@mariozechner/pi-agent-core`
- `@mariozechner/pi-ai`
- `@mariozechner/pi-coding-agent`
- `@mariozechner/pi-web-ui`

Pipane may already launch a newer global `pi` executable in RPC mode, but the app still compiles and tests against the older local package APIs. The riskiest dependency is `@mariozechner/pi-web-ui`, because Pipane carries a large local `patch-package` patch that appears to provide product-specific behavior:

- steering/send behavior while streaming;
- custom message editor key handling;
- extra message editor toolbar controls;
- fallback tool rendering;
- stable DOM hooks such as `data-tool-call-id` and `data-message-index`;
- LM Studio model-discovery type/build adjustments;
- generated `dist` and source-map changes.

The goal of this ticket is to learn what breaks during an upgrade attempt, not to redesign Pipane or inline upstream UI code. Inlining or replacing `pi-web-ui` components should be handled by separate follow-up tickets only if the spike proves it is necessary.

## Goal

Run a disposable compatibility spike that upgrades the Pi package family and records the exact compatibility failures, patch failures, runtime risks, and likely follow-up work.

The spike should answer:

- Can Pipane install with the upgraded Pi package family?
- Does `patch-package` apply cleanly, partially, or fail immediately?
- Which patched `pi-web-ui` behaviors are still required after the upgrade?
- Which current Pipane imports fail at type-check/build time?
- Does the source alias to `@mariozechner/pi-web-ui/src/index.ts` still work?
- Are there type identity problems if only part of the Pi family moves?
- Are session parsing and RPC assumptions still compatible with sessions/processes produced by the newer `pi` CLI?
- Does upgrading the package family reduce or remove the known transitive npm audit findings?
- Is the old `@mariozechner/*@0.73.1` line a useful stopping point, or should Pipane plan directly for the `@earendil-works/*` scope?

## Non-Goals

- Do not inline `pi-web-ui` code as part of this ticket.
- Do not rewrite the message editor, message renderers, or tool renderers as part of this ticket.
- Do not silently delete or weaken the existing `pi-web-ui` patch.
- Do not attempt a full visual redesign.
- Do not merge the spike branch unless a follow-up implementation ticket explicitly accepts the required changes.

## Recommended Approach

1. Create a disposable branch, for example `codex/pi-package-upgrade-spike`.
2. Capture the baseline before changing dependencies:
   - current `package.json` and `package-lock.json` Pi versions;
   - current patch files under `pipane/patches/`;
   - results from `npm run check`, `npm run test`, `npm run build`, and `npm audit --json` if feasible.
3. Attempt the old-scope upgrade first:
   - upgrade all four `@mariozechner/pi-*` packages together to `0.73.1`;
   - run `npm install`;
   - record whether `patch-package` applies, and save the exact failed hunks/errors.
4. Without fixing code, run:
   - `npm run check`;
   - `npm run test`;
   - `npm run build`;
   - `npm audit --json`;
   - `npm audit --omit=dev --json`.
5. Record all failures in a spike report under `docs/sessions/`.
6. If the old-scope result is understandable, optionally run a second disposable attempt for the new `@earendil-works/*` scope:
   - switch all four Pi packages to the matching new package names and same latest version family;
   - record install, patch, type-check, build, test, and audit results separately from the old-scope attempt.
7. Revert or discard the dependency changes after the report is written unless a separate implementation ticket is approved.

## What To Record

Create a short report with these sections:

### Package Attempted

- package scope and version family tested;
- exact dependency changes;
- whether all Pi packages were upgraded together;
- npm/node versions used.

### Install Result

- whether `npm install` completed;
- whether `patch-package` ran;
- each patch that applied, failed, or became obsolete;
- exact failure output for `@mariozechner/pi-web-ui` and `@mariozechner/mini-lit`.

### Patch Behavior Inventory

For each important patched behavior, record one of:

- still required and missing upstream;
- absorbed upstream;
- unclear, needs runtime/manual validation;
- no longer used by Pipane.

Behaviors to check:

- `MessageEditor.allowSendDuringStreaming`;
- `MessageEditor.onKeyDown`;
- `MessageEditor.extraToolbarButtons`;
- `setFallbackToolRenderer` / `FallbackToolRenderer`;
- `data-tool-call-id`;
- `data-message-index`;
- LM Studio model-discovery typing/runtime behavior;
- markdown strikethrough behavior from the `mini-lit` patch.

### Build And Type Failures

Record:

- missing exports;
- changed type names or module paths;
- duplicate or incompatible Pi type identities;
- source alias failures from `vite.config.ts`;
- generated declaration or `dist` assumptions that no longer hold.

### Runtime Compatibility Notes

If the app can run, smoke test and record:

- session picker loads;
- an existing session JSONL parses;
- prompt send works against a mock or real RPC process;
- steering while streaming still works or clearly regresses;
- tool messages render, including unknown tools;
- chat-to-JSONL jump and auto-collapse still work;
- model/provider picker still opens and saves settings;
- attachment handling still works at a basic level.

If the app cannot run, record the first blocker and stop there.

### Audit Delta

Record the before/after counts from:

- `npm audit --json`;
- `npm audit --omit=dev --json`.

Call out whether the upgrade resolves, reduces, or leaves the known Pi-family transitive findings:

- `protobufjs`;
- `undici`;
- `basic-ftp`;
- `fast-xml-parser`;
- `yaml`;
- `file-type`;
- `brace-expansion`;
- `ip-address`.

### Recommendation

End the report with one of these recommendations:

- upgrade is low-risk and can proceed directly;
- upgrade is possible after rebasing the existing patches;
- upgrade should wait until selected `pi-web-ui` behaviors are moved local;
- upgrade should target the new `@earendil-works/*` scope instead of old `@mariozechner/*`;
- upgrade is not currently worth pursuing.

Include the smallest set of follow-up tickets needed.

## Acceptance Criteria

- A disposable branch or equivalent local attempt has been used; the main working tree is not left with unreviewed upgrade changes.
- A spike report exists under `docs/sessions/` with exact command results and failure details.
- The report clearly distinguishes old-scope `@mariozechner/*@0.73.1` findings from any new-scope `@earendil-works/*` findings.
- The report includes a patch behavior inventory for the existing `pi-web-ui` patch.
- The report includes a clear recommendation and follow-up ticket list.
- No `pi-web-ui` code is inlined as part of this ticket.

## References

- `docs/sessions/2026-05-24-pipane-pi-web-ui-upgrade-handoff.md`
- `docs/sessions/2026-05-24-pipane-audit/01-dependency-freshness-and-upgrade-risk.md`
- `docs/sessions/2026-05-24-pipane-audit/02-npm-security-advisory-triage.md`
- `docs/sessions/2026-05-24-pipane-audit/13-upstream-patch-and-fork-delta.md`
