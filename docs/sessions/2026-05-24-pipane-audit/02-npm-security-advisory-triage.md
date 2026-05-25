# Ticket 2: npm Security Advisory Triage

Date: 2026-05-24  
Scope: `pipane/` npm dependency audit, runtime server dependencies, browser build dependencies, test/dev dependencies, and transitive dependencies pulled by `@mariozechner/*`, Vite, Playwright, and test tooling.

## Executive Summary

`npm audit --json` currently reports **18 vulnerabilities**: **1 critical, 8 high, 9 moderate**. `npm audit --omit=dev --json` reports **17 vulnerabilities**: **1 critical, 7 high, 9 moderate**. The single dev-only finding is direct `happy-dom`.

The highest-priority runtime issue is `ws` because pipane directly exposes a production WebSocket server at `/ws` and uses `ws@8.19.0`, affected by `GHSA-58qx-3vcg-4xpx`. The advisory is moderate and requires high privileges, but the package is directly reachable by authenticated WebSocket clients and should be patched urgently.

The critical `protobufjs` advisory is present in production through `@mariozechner/pi-ai -> @google/genai -> protobufjs`. It is high impact but lower exposure in pipane's own server: pipane does not parse protobuf descriptors directly, and reachability appears limited to Google GenAI provider code inside the child `pi` RPC process when that provider is used. It still needs coordinated upstream/lockfile remediation because the affected package is installed in production dependencies.

Most remaining high/critical advisories are production-installed but provider/proxy/build-tool scoped rather than directly exposed by pipane REST/WebSocket request handling. `vite`, `postcss`, and `picomatch` are dev/build exposure; `happy-dom` is test-only; `basic-ftp`, `fast-uri`, `fast-xml-parser`, `undici`, `yaml`, `file-type`, `brace-expansion`, and `ip-address` are transitive runtime packages whose exploitability depends on provider/model/tool code paths in `@mariozechner/*` or SDK internals.

`npm audit fix --dry-run --json` was run with a temporary cache and registry access. It proposed patched versions for every audited vulnerable package, including `ws@8.21.0`, `protobufjs@7.6.1`, `vite@7.3.3`, `happy-dom@20.9.0`, `undici@7.25.0`, `fast-xml-parser@5.7.3`, `basic-ftp@5.3.1`, and other transitive fixes. Since this was a research-only task, the lockfile was not changed and no post-fix audit was executed against a modified tree.

## Evidence / Commands

Commands run from `pipane/` unless noted:

- `npm audit --json`
  - Result: 18 total vulnerabilities: 1 critical, 8 high, 9 moderate.
- `npm audit --omit=dev --json`
  - Result: 17 total vulnerabilities: 1 critical, 7 high, 9 moderate.
  - Difference from full audit: `happy-dom` drops out, confirming it is dev/test-only.
- `npm ls protobufjs vite happy-dom ws basic-ftp fast-uri fast-xml-parser path-to-regexp picomatch undici postcss yaml @mariozechner/pi-agent-core @mariozechner/pi-ai @mariozechner/pi-coding-agent @mariozechner/pi-web-ui --all`
  - Used to map primary chains.
- `npm ls brace-expansion file-type ip-address qs @aws-sdk/xml-builder @protobufjs/utf8 --all`
  - Used to map additional live findings not listed in the ticket prompt.
- `npm --cache /private/tmp/pipane-npm-audit-cache audit fix --dry-run --json`
  - Initial sandboxed run failed with registry DNS; escalated run succeeded.
  - Proposed 27 changed packages and 92 added optional/platform packages.
- `rg` import scans across `src`, `e2e`, `scripts`, `bin`, Vite/Vitest/Playwright configs, and `node_modules/@mariozechner`.
  - Used to identify direct usage and reachable runtime paths.

Relevant code observations:

- Production dependencies include direct `express`, `ws`, `@mariozechner/pi-*`, `@tailwindcss/vite`, `patch-package`; dev dependencies include direct `vite`, `vitest`, `happy-dom`, `@playwright/test` ([`pipane/package.json:57`](../../../pipane/package.json#L57), [`pipane/package.json:70`](../../../pipane/package.json#L70)).
- Production server imports `express`, `ws`, and `@mariozechner/pi-coding-agent`; Vite is not imported by the server ([`pipane/src/server/server.ts:18`](../../../pipane/src/server/server.ts#L18)).
- Auth middleware runs before static files and REST API registration; WebSocket authorization is checked in `WsHandler.handleConnection` ([`pipane/src/server/server.ts:172`](../../../pipane/src/server/server.ts#L172), [`pipane/src/server/ws-handler.ts:210`](../../../pipane/src/server/ws-handler.ts#L210)).
- WebSocket command input is JSON parsed and routes to prompt/session/process commands; prompt text and optional image payloads are forwarded to the child `pi` RPC process ([`pipane/src/server/ws-handler.ts:266`](../../../pipane/src/server/ws-handler.ts#L266), [`pipane/src/server/ws-handler.ts:461`](../../../pipane/src/server/ws-handler.ts#L461)).
- REST endpoints parse JSON, read user-selected `.jsonl` session paths, list arbitrary directories for browse, and parse session JSONL through `@mariozechner/pi-coding-agent` ([`pipane/src/server/rest-api.ts:44`](../../../pipane/src/server/rest-api.ts#L44), [`pipane/src/server/rest-api.ts:205`](../../../pipane/src/server/rest-api.ts#L205), [`pipane/src/server/rest-api.ts:292`](../../../pipane/src/server/rest-api.ts#L292)).
- Vite dev server is configured only for local dev/build with `/ws` and `/api` proxying to the backend; its own filesystem advisories are not part of `npm start` production runtime ([`pipane/vite.config.ts:75`](../../../pipane/vite.config.ts#L75)).
- Browser attachments are handled client-side by turning images into base64 image payloads and document text into prompt text before sending to the server; no direct server-side `file-type` parsing was found in pipane source ([`pipane/src/client/main.ts:146`](../../../pipane/src/client/main.ts#L146)).

## Advisory Table

| Package | Severity | Advisory IDs / titles | Chain | Exposure | Fix / blocker |
| --- | --- | --- | --- | --- | --- |
| `protobufjs@7.5.4` | Critical | `GHSA-xq3m-2v4x-88gg` ACRE; plus `GHSA-66ff-xgx4-vchm`, `GHSA-2pr8-phx7-x9h3`, `GHSA-fx83-v9x8-x52w`, `GHSA-75px-5xx7-5xc7`, `GHSA-jvwf-75h9-cwgg`, `GHSA-685m-2w69-288q`, `GHSA-q6x5-8v7m-xcrf`, `GHSA-jggg-4jg4-v7c6` | `@mariozechner/pi-ai -> @google/genai -> protobufjs` | Runtime installed; not directly reachable in pipane request parsing. Potentially reachable only when Google GenAI provider code processes protobuf descriptors/messages inside the `pi` child process. | Dry-run proposes `protobufjs@7.6.1` and protobufjs helper updates. Coordinate through `@mariozechner/pi-ai`/lockfile update; validate Google provider tests. |
| `@protobufjs/utf8@1.1.0` | Moderate | `GHSA-q6x5-8v7m-xcrf` overlong UTF-8 decoding | `@mariozechner/pi-ai -> @google/genai -> protobufjs -> @protobufjs/utf8` | Same as `protobufjs`; low direct pipane exposure. | Dry-run proposes `@protobufjs/utf8@1.1.1`. |
| `ws@8.19.0` | Moderate | `GHSA-58qx-3vcg-4xpx` uninitialized memory disclosure | Direct production dependency; also deduped under `@google/genai`, `openai`, `happy-dom`, `@lmstudio/sdk` | Runtime reachable. pipane exposes a production `WebSocketServer` at `/ws`; auth limits access, but authenticated clients send arbitrary frames. | Urgent direct patch. Dry-run proposes `ws@8.21.0`. |
| `vite@7.3.1` | High | `GHSA-4w7w-66w2-5vf9`, `GHSA-v2wj-q39q-566r`, `GHSA-p9ff-h696-f583` | Direct dev dependency and transitive via `@tailwindcss/vite`, `vitest`, `vite-node` | Dev/build-only. Affects Vite dev server file access/HMR WebSocket, not production `npm start`. Exposure if `npm run dev:client` is bound to non-local/trusted network. | Direct patch. Dry-run proposes `vite@7.3.3`. |
| `happy-dom@20.7.0` | High | `GHSA-w4gp-fjgq-3q4g`, `GHSA-6q6h-j7hj-3r64` | Direct dev dependency; also used by `vitest` environment | Test-only/dev-only. Dropped from `npm audit --omit=dev`. | Direct dev patch. Dry-run proposes `happy-dom@20.9.0`. |
| `basic-ftp@5.2.0` | High | `GHSA-6v7q-wjvx-w8wg`, `GHSA-chqc-8p9q-pq6q`, `GHSA-rp42-5vxx-qpwr`, `GHSA-rpmf-866q-6p89` | `@mariozechner/pi-ai -> proxy-agent -> pac-proxy-agent -> get-uri -> basic-ftp` | Runtime installed, low exposure unless proxy auto-config resolves FTP URLs or attacker controls FTP credentials/server. No direct pipane FTP path found. | Dry-run proposes `basic-ftp@5.3.1`. Prefer upstream/lockfile coordinated patch. |
| `fast-uri@3.1.0` | High | `GHSA-q3j6-qgpj-74h6`, `GHSA-v39h-62p7-jpjc` | `@mariozechner/pi-ai -> ajv -> fast-uri` | Runtime installed; low direct exposure. Pipane does not expose AJV schema validation on user URLs; provider/tool schemas may use AJV internally. | Dry-run proposes `fast-uri@3.1.2`. |
| `fast-xml-parser@5.3.6` | High | `GHSA-8gc5-j5rx-235r`, `GHSA-jp2q-39xq-3w4g`, `GHSA-gh4j-gqv2-49f6`, `GHSA-fj3w-jwp8-x2g3` | `@mariozechner/pi-ai -> @aws-sdk/client-bedrock-runtime -> @aws-sdk/core -> @aws-sdk/xml-builder -> fast-xml-parser` | Runtime installed; provider-scoped to AWS/Bedrock XML handling. No direct pipane XML endpoint. Exposure if Bedrock provider parses or builds attacker-influenced XML. | Dry-run proposes `fast-xml-parser@5.7.3` and `@aws-sdk/xml-builder@3.972.25`. Coordinate with `@mariozechner/pi-ai`/AWS SDK compatibility. |
| `@aws-sdk/xml-builder@3.972.8` | Moderate | Via `fast-xml-parser` | `@mariozechner/pi-ai -> @aws-sdk/client-bedrock-runtime -> @aws-sdk/core -> @aws-sdk/xml-builder` | Same as `fast-xml-parser`. | Dry-run proposes `@aws-sdk/xml-builder@3.972.25`. |
| `path-to-regexp@8.3.0` | High | `GHSA-j3q9-mxjg-w52f`, `GHSA-27v5-c462-wpq7` | `express -> router -> path-to-regexp` | Runtime installed through Express. Low exposure because pipane routes are static/simple (`/api/...`, `/auth`) and do not include attacker-controlled route patterns, sequential optional groups, or multiple wildcards. | Dry-run proposes `path-to-regexp@8.4.2`. Patch with Express/router lockfile update. |
| `picomatch@4.0.3` and `picomatch@2.3.1` | High | `GHSA-3v7f-55p6-f55p`, `GHSA-c2c7-rcm5-vvqj` | `vite -> picomatch`; `patch-package -> find-yarn-workspace-root -> micromatch -> picomatch`; `vitest` also dedupes Vite/picomatch | Dev/build and postinstall/workspace detection. No production request handling path found. | Dry-run proposes `picomatch@4.0.4` and `2.3.2`. |
| `undici@7.22.0` | High | `GHSA-f269-vfmq-vjvj`, `GHSA-2mjp-6q6p-2qxm`, `GHSA-vrm6-8vpv-qv8q`, `GHSA-v9p9-hfj2-hcw8`, `GHSA-4992-7rv2-5pvq`, `GHSA-phc3-fgpg-7m6h` | `@mariozechner/pi-ai -> undici` | Runtime installed; provider/network-client scoped. Pipane server uses browser/client `fetch` and Node HTTP, but no direct `undici` import found in pipane source. Could be reachable through provider HTTP/WebSocket calls in child `pi` process. | Dry-run proposes `undici@7.25.0`. Coordinate with `@mariozechner/pi-ai`. |
| `postcss@8.5.6` | Moderate | `GHSA-qx2v-qp2m-jg93` | `vite -> postcss` | Browser build/dev-only. No server runtime exposure. | Dry-run proposes `postcss@8.5.15`. |
| `yaml@2.8.2` | Moderate | `GHSA-48c2-rrv3-qjmp` | `@mariozechner/pi-coding-agent -> yaml`; also deduped under `vite`/`patch-package` | Runtime installed. Potentially reachable if `@mariozechner/pi-coding-agent` parses user-editable YAML configs/extensions. Pipane local settings are JSON-only and do not call `yaml` directly. | Dry-run proposes `yaml@2.9.0`. Coordinate with `@mariozechner/pi-coding-agent`; validate config/extension parsing. |
| `file-type@21.3.0` | Moderate | `GHSA-5v7r-6r5c-r473`, `GHSA-j47w-4g3g-c36v` | `@mariozechner/pi-coding-agent -> file-type` | Runtime installed. No direct pipane server import; client-side attachments are converted to text/images before prompt. Potential exposure if child `pi` process or extensions inspect user-provided files/attachments using `file-type`. | Dry-run proposes `file-type@21.3.4`. Coordinate upstream. |
| `brace-expansion@2.0.2` and `5.0.4` | Moderate | `GHSA-f886-m6hf-6m8v`, `GHSA-jxxr-4gwj-5jf2` | `@mariozechner/pi-ai -> @google/genai -> google-auth-library -> gaxios -> rimraf -> glob -> minimatch -> brace-expansion`; `@mariozechner/pi-coding-agent -> minimatch -> brace-expansion` | Runtime installed; low direct exposure unless attacker controls glob/brace patterns in provider/tooling or coding-agent file matching. No direct pipane user glob endpoint found. | Dry-run proposes `brace-expansion@2.1.0` and `5.0.6`. |
| `ip-address@10.1.0` | Moderate | `GHSA-v2v4-37r5-5v8g` | `@mariozechner/pi-ai -> proxy-agent -> socks-proxy-agent -> socks -> ip-address` | Runtime installed; low exposure. Advisory affects HTML-emitting methods; no direct pipane use found. | Dry-run proposes `ip-address@10.2.0`. |
| `qs@6.15.0` | Moderate | `GHSA-q8mj-m7cp-5q26` | `express -> qs`; `express -> body-parser -> qs` | Runtime installed. Advisory is in `qs.stringify` with specific options; pipane does not call `qs` directly and Express request parsing is not using vulnerable stringify flow in app code. | Dry-run proposes `qs@6.15.2`. |

## Exposure Classification

### Runtime, Directly Reachable

- `ws`: production server creates `new WebSocketServer({ server, path: "/ws" })` and accepts authenticated clients. Patch first despite moderate severity because this is the clearest actual runtime exposure.
- `path-to-regexp`: production Express route matcher dependency. Current route definitions are simple static paths, so the vulnerable route-pattern shapes are not user-controlled or currently present. Patch with Express/router lockfile update but treat as lower practical exposure than `ws`.
- `qs`: production Express/body-parser dependency. No direct vulnerable `qs.stringify` call found in pipane. Low practical exposure, patch with lockfile update.

### Runtime Installed, Provider / Child Process / SDK Scoped

- `protobufjs`, `@protobufjs/utf8`: installed through Google GenAI SDK. Not directly touched by pipane REST/WebSocket parsing; potential exposure is Google provider use inside the child `pi` RPC process.
- `undici`: installed through `@mariozechner/pi-ai`; likely provider network-client exposure rather than direct pipane server exposure.
- `fast-xml-parser`, `@aws-sdk/xml-builder`: installed through AWS Bedrock runtime SDK; relevant when Bedrock provider code handles XML.
- `basic-ftp`, `fast-uri`, `ip-address`: installed through proxy/provider stacks; low exposure unless user/provider configuration routes through vulnerable proxy/PAC/FTP/IP helper paths.
- `yaml`, `file-type`, `brace-expansion`: installed through `@mariozechner/pi-coding-agent`; possible exposure through config, extension, file matching, or attachment/file inspection in the child process, but no direct pipane server usage found.

These packages are not safe to ignore because they are in production dependency closure, but most require coordinated `@mariozechner/*` validation rather than isolated pipane source changes.

### Dev / Build / Test Only

- `vite`: dev server and production build exposure. Not served by `npm start`. Patch before using dev server on shared networks; otherwise low production exposure.
- `postcss`: build pipeline only.
- `picomatch`: mostly Vite/Vitest/patch-package glob matching. No production route/input path found.
- `happy-dom`: test-only. Confirmed absent from `npm audit --omit=dev`.

## User-Provided Input Path Checks

- **Attachments:** Browser-side `message-editor` attachments are converted to image payloads or extracted document text in `src/client/main.ts`; no direct server-side `file-type` import was found in pipane. Residual risk is in `@mariozechner/pi-coding-agent` or `pi-web-ui` attachment/artifact utilities, not pipane server request handling.
- **JSONL parsing:** REST `/api/sessions/messages`, `/api/sessions/fork-messages`, and `/api/sessions/raw` accept a user-provided `.jsonl` path and read it if it exists. They use `parseSessionEntries`/`buildSessionContext` from `@mariozechner/pi-coding-agent`, not the vulnerable npm packages directly. This is relevant for `yaml`, `file-type`, and `brace-expansion` only if those are used by the upstream parser or session context builder; no direct evidence found in pipane source.
- **WebSocket data:** WebSocket frames are parsed as JSON and forwarded to server handlers. Prompt text/images, model provider/model ID, `cwd`, `sessionPath`, and steering text are user-controlled after auth. Direct `ws` advisory is reachable here. Provider-scoped advisories may become reachable after prompt/model selection causes the child `pi` process to call provider SDKs.
- **REST endpoints:** Authenticated REST endpoints parse JSON bodies, read arbitrary existing `.jsonl` paths, list arbitrary directories, and validate/save JSON settings. No direct XML/YAML/protobuf/file-type parsing was found in pipane REST handlers.
- **Dev server file access:** Vite advisories affect `npm run dev:client`, particularly dev-server filesystem/HMR WebSocket behavior. Production static serving uses Express from `dist/client`, not Vite.

## Remediation Order

1. **Urgent direct runtime patch**
   - Update direct `ws` resolution to a patched version (`8.21.0` per dry-run).
   - Validate with `npm audit --json`, `npm audit --omit=dev --json`, unit tests, and WebSocket/auth e2e coverage.

2. **Coordinated production transitive upgrade**
   - Update lockfile/transitives for `@mariozechner/pi-ai` and `@mariozechner/pi-coding-agent` dependency closure, or upgrade the upstream `@mariozechner/*` packages if newer releases already incorporate these fixes.
   - Target dry-run versions:
     - `protobufjs@7.6.1`, `@protobufjs/utf8@1.1.1`
     - `undici@7.25.0`
     - `fast-xml-parser@5.7.3`, `@aws-sdk/xml-builder@3.972.25`
     - `basic-ftp@5.3.1`
     - `fast-uri@3.1.2`
     - `yaml@2.9.0`
     - `file-type@21.3.4`
     - `brace-expansion@2.1.0` and `5.0.6`
     - `ip-address@10.2.0`
     - `qs@6.15.2`
     - `path-to-regexp@8.4.2`
   - Validate model provider flows: OpenAI, Google GenAI, Bedrock, proxy/PAC settings, YAML/config loading, attachments/file inspection, and session JSONL parsing.

3. **Dev/build/test patch**
   - Update `vite` to `7.3.3`, `postcss` to `8.5.15`, `picomatch` to patched `2.3.2`/`4.0.4`, and `happy-dom` to `20.9.0`.
   - Keep Vite dev server bound to localhost/trusted interfaces until patched.
   - Validate `npm run build`, `npm run test`, and Playwright tests.

4. **Defer with rationale only after patch attempt**
   - If upstream `@mariozechner/*` packages pin or break on newer transitives, defer provider-scoped findings with explicit notes:
     - Not directly reachable from pipane server request parsing.
     - Requires specific provider/proxy/config/file-inspection code path.
     - Track upstream release or use package manager overrides only after compatibility testing.

## Blocked Validations / Follow-Ups

- This task was research-only, so no lockfile/source changes were made and no true post-fix `npm audit --json` could be captured against an updated dependency tree.
- `npm audit fix --dry-run --json` succeeded and captured proposed patched versions, but its embedded `audit` object still reflects the current vulnerable tree. A follow-up implementation ticket should apply the chosen upgrade strategy and then capture fresh `npm audit --json` and `npm audit --omit=dev --json`.
- Need upstream compatibility check for `@mariozechner/pi-ai@0.55.3` and `@mariozechner/pi-coding-agent@0.55.3` with patched transitive versions. Prefer upgrading upstream packages if newer releases exist; use npm overrides only with provider regression tests.
- Need provider-specific validation for Google GenAI (`protobufjs`), Bedrock (`fast-xml-parser`), proxy/PAC/FTP (`basic-ftp`, `ip-address`), and YAML/config/file inspection (`yaml`, `file-type`, `brace-expansion`).
- The live audit now reports 18 findings, while the ticket prompt mentioned 17. The production-only audit reports 17; the full audit adds dev-only `happy-dom`.
