# Ticket 1: Dependency Freshness and Upgrade Risk Audit

Date: 2026-05-24  
Project: `pipane/`  
Scope reviewed: `package.json`, `package-lock.json`, `patches/*`, `vite.config.ts`, `vitest.config.ts`, `playwright.config.ts`

## Executive Summary

The smallest safe upgrade batch is a security-focused patch/minor refresh of direct tooling and runtime dependencies that does not touch the pinned `@mariozechner/pi-*` family: upgrade `vite` to `7.3.3`, `ws` to `8.21.0`, `happy-dom` to `20.9.0`, and include low-risk freshness companions `@tailwindcss/vite` to `4.3.0`, `lit` to `3.3.3`, and `tsx` to `4.22.3` if the lockfile refresh permits. This batch removes direct high/moderate audit findings in `vite`, `ws`, and `happy-dom` while avoiding the much larger upstream UI/API and patch rebase risk.

The `@mariozechner/pi-agent-core`, `pi-ai`, `pi-coding-agent`, and `pi-web-ui` packages are all pinned to `0.55.3`; npm reports latest `0.73.1`. Because these packages depend on each other in the same version family and because `pi-web-ui` carries a large local `patch-package` patch, the pi package upgrade should be handled as a coordinated branch with explicit patch revalidation, not mixed into the urgent direct-security batch.

Defer Vite 8 and TypeScript 6. Vite 7.3.3 addresses current Vite advisories with much lower config/build risk, while the installed `@tailwindcss/vite@4.2.1` advertises Vite peer support only through `^7` in the current lockfile graph. TypeScript 6 is a major compiler upgrade and should be trialed separately after dependency security cleanup.

## Evidence and Commands Run

- `sed -n '1,240p' pipane/package.json`
- `sed -n '1,220p' pipane/vite.config.ts`
- `sed -n '1,220p' pipane/vitest.config.ts`
- `sed -n '1,240p' pipane/playwright.config.ts`
- `sed -n '1,260p' pipane/patches/@mariozechner+pi-web-ui+0.55.3.patch`
- `sed -n '1,220p' pipane/patches/@mariozechner+mini-lit+0.2.1.patch`
- `wc -l pipane/patches/@mariozechner+pi-web-ui+0.55.3.patch pipane/patches/@mariozechner+mini-lit+0.2.1.patch`
- `rg '^diff --git|^@@|^[+-]{3} ' pipane/patches/@mariozechner+pi-web-ui+0.55.3.patch`
- `rg 'allowSendDuringStreaming|setShowJsonMode|customRenderer|showJson|steering|discoverLMStudioModels|textarea|rows' pipane/patches/@mariozechner+pi-web-ui+0.55.3.patch`
- `npm ls @mariozechner/pi-agent-core @mariozechner/pi-ai @mariozechner/pi-coding-agent @mariozechner/pi-web-ui @mariozechner/mini-lit vite vitest typescript @playwright/test happy-dom lucide ws --all --depth=4`
- `npm outdated --json`
  - First sandboxed run failed with `ENOTFOUND registry.npmjs.org`.
  - Escalated read-only registry run succeeded.
- `npm audit --json`
  - First sandboxed run failed with `ENOTFOUND registry.npmjs.org`.
  - Escalated read-only audit run succeeded.
- `npm why protobufjs`
- `npm why basic-ftp`
- `npm why undici`
- `npm why fast-xml-parser`
- `npm why path-to-regexp`
- `npm why qs`
- `npm why file-type`
- `npm why picomatch`

Blocked validation:

- I attempted to validate `patch-package` portability by downloading `@mariozechner/pi-web-ui@0.73.1` into `/private/tmp` and checking the existing patch against it. That was rejected because this ticket explicitly limits file creation/editing to this report file. No workaround was attempted. Treat patch applicability against `0.73.1` as unvalidated until a dedicated upgrade branch permits temporary package extraction or install.

## Findings

### High: direct security exposure in Vite, ws, and happy-dom

`npm audit --json` reports direct vulnerabilities in:

- `vite@7.3.1`: high severity, three advisories affecting `7.0.0 - 7.3.1`, fix available.
- `ws@8.19.0`: moderate severity uninitialized memory disclosure affecting `8.0.0 - 8.20.0`, fix available.
- `happy-dom@20.7.0`: high severity advisories affecting `<=20.8.8`, fix available.

These are the best candidates for the smallest urgent upgrade batch because they are direct dependencies with nearby patch/minor targets.

### High: pi package family is stale and security-relevant, but high upgrade risk

`npm outdated --json` reports all four direct pi packages at `0.55.3` with latest `0.73.1`:

- `@mariozechner/pi-agent-core`
- `@mariozechner/pi-ai`
- `@mariozechner/pi-coding-agent`
- `@mariozechner/pi-web-ui`

`npm ls` shows these packages depend on each other at the `0.55.3` family. `npm why` traces several high/critical transitive advisories through this family:

- `protobufjs@7.5.4` via `@google/genai@1.43.0` via `@mariozechner/pi-ai@0.55.3`; audit reports critical/high/moderate advisories.
- `undici@7.22.0` via `@mariozechner/pi-ai@0.55.3`; audit reports high/moderate advisories for `<7.24.0`.
- `basic-ftp@5.2.0` via `proxy-agent` via `@mariozechner/pi-ai@0.55.3`; audit reports high advisories for `<=5.3.0`.
- `fast-xml-parser@5.3.6` via AWS SDK dependencies pulled by `@mariozechner/pi-ai@0.55.3`; audit reports high/moderate advisories for current ranges.
- `file-type@21.3.0` via `@mariozechner/pi-coding-agent@0.55.3`; audit reports moderate advisories.

Because the pi packages are pre-1.0 packages, the `0.55.3` to `0.73.1` move is semver-minor by number but should be treated as potentially breaking.

### High: `@mariozechner/pi-web-ui` local patch is large and upgrade-fragile

The `pi-web-ui` patch is 3,437 lines and touches both `src/` and `dist/` output plus source maps. Key patched behaviors include:

- steering support with `allowSendDuringStreaming` in `AgentInterface` and `MessageEditor`;
- message editor behavior changes around textarea/input handling;
- fallback tool renderer export via `setFallbackToolRenderer`;
- JSON/tool rendering behavior;
- LM Studio model discovery URL adjustments;
- UI/rendering changes across message, artifact, sandbox, attachment, and i18n files.

The Vite config aliases `@mariozechner/pi-web-ui` to `node_modules/@mariozechner/pi-web-ui/src/index.ts`, explicitly so the app consumes patched TypeScript source. This makes `pi-web-ui` upgrades particularly sensitive: a successful package install is not enough; patched source symbols and runtime behavior must still match Pipane expectations.

### Medium: `@mariozechner/mini-lit` patch is small but behavioral

The `mini-lit` patch is 17 lines and changes markdown rendering so strikethrough tokens render tildes literally. It is narrow, but user-visible. There is no newer `mini-lit` version reported by `npm outdated`; keep the patch as-is unless a future pi-web-ui version removes the need.

### Medium: direct Express is current but transitives still audit vulnerable

`npm outdated` did not report `express`, but `npm audit` reports transitive advisories under the current Express graph:

- `path-to-regexp@8.3.0` via `router@2.2.0` via `express@5.2.1`.
- `qs@6.15.0` via `body-parser@2.2.2` and `express@5.2.1`.

These may be resolvable by lockfile transitive updates if compatible versions are available. They should be checked after the smallest direct-security batch.

### Medium: Vite 8 should be separated

Current Vite config includes a custom `nodeStubPlugin`, Tailwind plugin integration, HMR path customization, dev-server proxying, and esbuild decorator/class-field settings. `@tailwindcss/vite@4.2.1` currently peers `vite` as `^5.2.0 || ^6 || ^7`; even if `@tailwindcss/vite@4.3.0` changes this, Vite 8 should be trialed separately because it can affect dev server security defaults, optimizeDeps, plugin behavior, and build output.

### Medium: TypeScript 6 should be separated

`typescript@5.9.3` has latest `6.0.3`, but wanted remains `5.9.3` under the current range. This is a major compiler upgrade. Given the project relies on decorators, Lit components, Vite esbuild overrides, and separate server/client TS configs, TypeScript 6 should be trialed behind its own branch after the Vite 7 security patch and pi package decision.

## Upgrade Matrix

| Dependency | Current | Candidate target | Change type | Risk | Notes |
|---|---:|---:|---|---|---|
| `vite` | `7.3.1` | `7.3.3` | patch | Low/Medium | Direct high audit findings affect `<=7.3.1`; prefer this before Vite 8. |
| `vite` | `7.3.1` | `8.0.14` | major | High | Defer to separate branch; plugin/peer/config risk. |
| `ws` | `8.19.0` | `8.21.0` | minor | Low/Medium | Direct moderate audit finding fixed above `8.20.0`; server WebSocket paths need regression coverage. |
| `happy-dom` | `20.7.0` | `20.9.0` | minor | Low/Medium | Direct high audit findings; test environment only, but can affect DOM/Lit tests. |
| `@tailwindcss/vite` | `4.2.1` | `4.3.0` | minor | Low/Medium | Freshness gap; coordinate with Vite 7 patch. Check peer range before Vite 8. |
| `lit` | `3.3.2` | `3.3.3` | patch | Low | Direct runtime UI dependency; likely safe but run Lit component tests. |
| `tsx` | `4.21.0` | `4.22.3` | minor | Low | Dev/server script runner; verify dev server and bench script if upgraded. |
| `@playwright/test` | `1.58.2` | `1.60.0` | minor | Medium | Can require browser binary updates and screenshot baseline review; defer until after urgent security batch unless needed by CI. |
| `typescript` | `5.9.3` | `6.0.3` | major | High | Defer; run separate compiler branch. |
| `lucide` | `0.544.0` | `1.16.0` | major | Medium/High | Icon API/package export risk; not urgent. Also used by `pi-web-ui` and `mini-lit`. |
| `@mariozechner/pi-agent-core` | `0.55.3` | `0.73.1` | pre-1.0 minor | High | Upgrade with all pi packages; transitive security benefit possible. |
| `@mariozechner/pi-ai` | `0.55.3` | `0.73.1` | pre-1.0 minor | High | Source of critical/high transitive advisories; must validate provider/model behavior. |
| `@mariozechner/pi-coding-agent` | `0.55.3` | `0.73.1` | pre-1.0 minor | High | Source of `file-type` advisory path; must validate session/process flows. |
| `@mariozechner/pi-web-ui` | `0.55.3` | `0.73.1` | pre-1.0 minor | Very High | Large local patch must be rebased or retired; patch clean-apply unvalidated. |
| `@mariozechner/mini-lit` | `0.2.1` | no newer reported | none | Medium if touched | Existing patch is small but user-visible. |
| `vitest` | `3.2.4` | no newer reported | none | Low | Current version participates in vulnerable `picomatch` path; transitive lock refresh may still be needed. |

## Recommended Upgrade Sequence

1. **Batch A: smallest urgent direct-security batch**
   - Target: `vite@7.3.3`, `ws@8.21.0`, `happy-dom@20.9.0`.
   - Include if compatible during the same lock refresh: `@tailwindcss/vite@4.3.0`, `lit@3.3.3`, `tsx@4.22.3`.
   - Rollback point: one commit containing only `package.json` and `package-lock.json` dependency refresh. Revert if build/dev/test regressions appear.

2. **Batch B: transitive audit cleanup without pi major movement**
   - After Batch A, rerun `npm audit --json`.
   - Try a lockfile-only compatible transitive refresh for remaining non-pi paths such as Express `path-to-regexp`/`qs`, Vite/Vitest `picomatch`, `postcss`, `yaml`, and `brace-expansion`.
   - Rollback point: separate commit from Batch A so direct security fixes are not entangled with broader lock churn.

3. **Batch C: coordinated pi package branch**
   - Upgrade all four `@mariozechner/pi-*` packages together to the same latest family, currently `0.73.1`.
   - Validate whether the `pi-web-ui` patch still applies, whether upstream now includes some patched behavior, and whether the Vite source alias is still necessary.
   - Rebase or retire the `pi-web-ui` patch explicitly; do not carry forward generated `dist/*.map` churn unless still required by package consumption.
   - Rollback point: branch-level rollback; do not merge until all app behavior, provider behavior, and UI screenshots pass.

4. **Batch D: Playwright**
   - Upgrade `@playwright/test` to `1.60.0`.
   - Rollback point: separate commit because browser binary and screenshot behavior can shift.

5. **Batch E: majors**
   - Trial Vite 8 in one branch.
   - Trial TypeScript 6 in another branch.
   - Trial `lucide@1.16.0` either with pi-web-ui or after pi-web-ui stabilizes, because icons are used both directly and through upstream UI packages.

## Tests Required by Batch

Batch A:

- `npm run check`
- `npm run test`
- `npm run build`
- WebSocket/server focused tests: `src/client/ws-agent-adapter.test.ts`, `src/server/ws-handler.ts` coverage through existing test suite, and any available attached-session/session lifecycle tests.
- Vite dev smoke: run `npm run dev:client` against the backend proxy settings and confirm HMR path `/__hmr` still works.
- `npm audit --json` to confirm direct `vite`, `ws`, and `happy-dom` advisories are removed.

Batch B:

- `npm audit --json`
- `npm run test`
- `npm run build`
- Express/API smoke tests covering routes, auth guard, local settings, session index, and REST API.

Batch C:

- `npm install`/patch-package validation on the branch.
- `npm run check`
- `npm run test`
- `npm run build`
- `npm run test:screenshots`
- E2E coverage for session picker, input send/rerun, steering while streaming, tool rendering, attachments, artifacts/canvas, model picker/provider discovery, LM Studio discovery, WebSocket agent adapter, server session lifecycle, and process pool.
- Manual smoke with at least one real or mock agent session because the pi packages own core runtime/provider behavior.

Batch D:

- `npm run test:screenshots`
- Existing Playwright E2E suite.
- Review screenshot diffs before accepting snapshot changes.

Batch E:

- For Vite 8: `npm run build`, `npm run dev:client`, HMR smoke, proxy smoke, browser load with node stub plugin paths, and full unit tests.
- For TypeScript 6: `npm run check`, `npm run build`, and focused Lit/decorator tests.
- For Lucide 1: build plus visual/screenshot tests for icon rendering.

## Follow-Up Questions and Blocked Validations

- Should the next implementation ticket allow temporary package extraction or a disposable branch install so `patch-package` clean-apply checks can be performed against `@mariozechner/pi-web-ui@0.73.1`?
- Should Batch A include freshness-only `@tailwindcss/vite`, `lit`, and `tsx`, or keep the smallest security batch strictly to `vite`, `ws`, and `happy-dom`?
- Are upstream `@mariozechner/pi-*` changelogs/release notes available or should the pi upgrade branch infer changes from package diffs and tests?
- Should direct transitive overrides be considered if the pi package family cannot be upgraded quickly but audit findings remain in `protobufjs`, `undici`, `basic-ftp`, or `fast-xml-parser`?
- Patch portability against candidate pi upgrades is blocked by the current report-only write constraint and remains unvalidated.
