# Ticket 12: Documentation and Developer Experience Audit

Date: 2026-05-24
Scope: `pipane/README.md`, `pipane/AGENTS.md`, `docker/README.md`, `pipane/package.json` scripts, and environment variables referenced across `pipane/src/server/*`.

## Executive Summary

The current docs do not yet meet the acceptance bar for contributor setup, runtime configuration, or troubleshooting. `pipane/README.md` gives a publish/install quickstart but not a local contributor path from clone to build, run, and checks. `pipane/AGENTS.md` documents the testing strategy, but its counts and e2e file inventory are stale. `docker/README.md` is more operationally useful than the app README, but it omits several security implications and has a default/auth mismatch that could confuse users.

Recommendation: keep `README.md` as the user-facing entry point with install, local development, config, auth, and troubleshooting basics. Move deeper runtime architecture, process-pool/session lifecycle notes, and e2e harness internals into a separate `docs/architecture.md` or `docs/development.md`, linked from the README and AGENTS file.

## Environment Variable Inventory

### Runtime server variables

| Variable | Referenced in | Purpose | Default/current behavior | Security or DX implication |
| --- | --- | --- | --- | --- |
| `NODE_ENV` | `src/server/server.ts`, `src/server/process-pool.ts`, `bin/pipane.js`, package scripts | Chooses default server port and production mode. Stripped from child pi processes before spawning tools. | `bin/pipane.js` sets `NODE_ENV=production` unless already set. Server defaults to port `8222` in production and `18111` otherwise. | Docs should explain why child tools do not inherit `NODE_ENV`; otherwise contributors may wonder why spawned commands differ from server env. |
| `PORT` | `src/server/server.ts`, `package.json`, `dev.sh`, `prod.sh`, Docker | HTTP/WebSocket server listen port. | `8222` when `NODE_ENV=production`, otherwise `18111`; Docker sets `8222`; dev script sets backend to `18111`. | Needed for reverse proxy setup and local port conflict troubleshooting. |
| `PI_CWD` | `src/server/server.ts`, `dev.sh`, `prod.sh`, Docker, e2e harness | Default working directory for new sessions and prewarmed pi processes. | `process.cwd()` in server; dev/prod scripts default to pipane project root; Docker defaults to `/workspace`; e2e uses a temp project dir. | High-impact behavior: tools execute relative to this directory. README should warn users to launch pipane from the intended workspace or set `PI_CWD`. |
| `PIPANE_VERBOSE` | `src/server/server.ts` | Enables normal console output when set to `1`; equivalent to `--verbose`. | Quiet mode by default, only important URLs/version/update messages are printed. | Troubleshooting docs should tell users to use `--verbose` or `PIPANE_VERBOSE=1` for server/pi diagnostics. |
| `PI_CLI` | `src/server/server.ts`, `src/server/pi-runtime.ts`, `src/server/ws-handler.ts` | Overrides pi executable/path used by pipane. | Unset means `pi`. If command is path-like, availability is checked with `existsSync`; otherwise via `which`. | Needed when global `pi` is missing, multiple versions exist, or automatic install is unsupported. |
| `PI_MAX_PROCESSES` | `src/server/server.ts` | Global cap for CWD-aware pi RPC process pool. | Server default `24`; Docker Compose default `4`. | Resource-control knob. Docs should warn that high values can increase memory/process load. |
| `PI_PREWARM_COUNT` | `src/server/server.ts` | Number of pi RPC processes to prewarm for default cwd. | Server default `2`; Docker Compose default `1`. | Startup/perceived-latency tradeoff. Higher values consume resources before any prompt. |
| `PIPANE_AUTH_DISABLED` | `src/server/server.ts`, Docker | Disables built-in HTTP and WebSocket auth checks when set to `1`. | Server default disabled=false. Dockerfile default `0`, but `docker-compose.yml` default is `${PIPANE_AUTH_DISABLED:-1}`. | Major security footgun: `docker/README.md` says open `/auth?token=change-me`, but Compose disables pipane auth by default unless overridden, making that URL unnecessary and potentially misleading. Docs should only recommend this behind a trusted auth proxy/network. |
| `PIPANE_AUTH_TOKEN` | `src/server/server.ts`, Docker | Fixed auth token for `/auth?token=...` and cookie validation. | Random 24-byte base64url token each server start when unset. Docker Compose defaults to `change-me`. | Fixed token is useful for reverse proxies/bookmarks, but `change-me` is insecure if auth is enabled. Docs should say the token grants remote access and should be secret. |
| `PI_PUBLIC_HOSTNAME` | `src/server/server.ts` | Hostname used to construct the printed auth URL when `PIPANE_PUBLIC_URL` is unset. | OS hostname from `hostname()`. | Name prefix is inconsistent with `PIPANE_PUBLIC_URL`; docs should either document it as legacy/compat or standardize later. |
| `PIPANE_PUBLIC_URL` | `src/server/server.ts`, Docker | External origin used for printed remote/auth URL. Trailing slashes are stripped. | `http://${PI_PUBLIC_HOSTNAME || hostname()}:${PORT}`. Docker Compose sets `http://${PIPANE_HOSTNAME}:${APP_PORT}`. | Essential behind reverse proxies, HTTPS, or non-default hostnames. If wrong, the printed auth URL is wrong even though server may work. |
| `PIPANE_DISABLE_LOCAL_BYPASS` | `src/server/server.ts`, auth tests | Disables localhost auth bypass when set to `1`. | Local requests from `127.0.0.1`, `::1`, or `::ffff:127.0.0.1` bypass auth by default and receive the auth cookie. | Important security behavior missing from docs. Users exposing local ports through tunnels/proxies should know how local bypass behaves. |
| `PIPANE_SECURE_COOKIE` | `src/server/server.ts` | Adds `Secure` to the auth cookie when set to `1`. | Not set by default; cookie uses `HttpOnly; SameSite=Lax; Max-Age=30 days`. | Required for HTTPS-only deployments that want secure cookies. Must not be set for plain HTTP local use or cookie may not be sent. |
| `HOME` | `src/server/rest-api.ts` | Default and `~` expansion for `/api/browse`. | Falls back to `/` when unset. | Low risk, but docs should mention folder picker starts at home by default and can browse visible directories. |

### Server-adjacent variables used by harness/CLI/Docker

| Variable | Referenced in | Purpose | Default/current behavior | Security or DX implication |
| --- | --- | --- | --- | --- |
| `PIPANE_PRINT_ENTRY` | `bin/pipane.js`, `src/server/global-cli.test.ts` | Prints resolved built server entry path and exits. | Off by default. | Packaging/test helper; not user-facing unless documenting CLI diagnostics. |
| `PI_CODING_AGENT_DIR` | e2e harness, video walkthrough | Points pi at an alternate agent config/session directory. | Not set by app server directly; e2e creates a temp dir with mock `models.json`, `auth.json`, and `settings.json`. | Useful for isolated testing. Should be mentioned in contributor/e2e docs, not necessarily user README. |
| `PI_MODEL` | e2e harness | Forces pi model for real-stack tests. | E2E sets `mock/mock-model`. | Contributor-only. Helps prevent real provider use in tests. |
| `RUN_WALKTHROUGH` | `e2e/video-walkthrough.e2e.ts` | Enables skipped walkthrough/video test. | Skipped unless set. | AGENTS should list this as optional/manual, because `npx playwright test` discovers it but skips by default. |
| `AWS_*`, `ANTHROPIC_*`, `OPENAI_*`, `GOOGLE_*`, `AZURE_*`, `XAI_*`, `GROQ_*`, `MISTRAL_*`, `GITHUB_TOKEN` | e2e harness | Ambient credentials stripped from real-stack test child env. | Removed from spawned e2e pipane process. | Good security practice worth documenting in e2e harness notes. |
| `DEV_PORT`, `BACKEND_PORT` | `dev.sh` | Dev frontend/backend ports. | `8111` and `18111`. | README should document local dev URL and how to avoid conflicts. |
| `APP_PORT`, `PIPANE_HOSTNAME`, `WEDE_HOSTNAME`, `WORKSPACE_DIR`, `PI_SSH_KEY_PATH`, `WEDE_*` | Docker files/README | Docker proxy hostnames/port, mounted workspace, SSH key, wede auth. | Compose defaults include `APP_PORT=8080`, `PIPANE_HOSTNAME=pipane.localhost`, `WORKSPACE_DIR=..`, SSH key path from `${HOME}/.ssh/id_ed25519`, and auth disabled for pipane/wede unless overridden. | Docker README should present these in a configuration table with clear trust-boundary warnings. |

## Documentation Gap Findings

1. `pipane/README.md` quickstart is incomplete for both users and contributors.
   - It only shows `npm install -g pipane` and optional global pi install.
   - It does not say to run `pipane`, what URL/port to open, how auth URL/cookie works, how to choose a workspace, or how to run from a clone.
   - It omits Node/npm requirements despite `package.json` requiring Node `>=20.0.0` and declaring `packageManager: npm@11.3.0`.

2. `pipane/AGENTS.md` test documentation is stale.
   - It claims `136 tests across 13 files`; verified `npm run test -- --reporter dot` reports `301 passed` across `21` files.
   - It claims `10 tests across 3 files`; verified `npx playwright test --list` reports `21 tests in 10 files`.
   - It only details `real-stack`, `ui-screenshots`, and `rerun-duplicate`; current e2e also includes focus, input clear, render performance, session cwd, steering, video walkthrough, and wide layout.

3. Docker auth docs conflict with Compose defaults.
   - `docker/README.md` tells users to open `http://pipane.localhost:8080/auth?token=change-me`.
   - `docker/docker-compose.yml` defaults `PIPANE_AUTH_DISABLED` to `1`, so the auth URL is bypassed by default. The Dockerfile default is `0`, but Compose overrides it.
   - This needs an explicit default-mode explanation: "Compose is intended for trusted local use with built-in auth disabled by default" or change the default in a future code/config ticket.

4. Runtime configuration is mostly undocumented.
   - README only mentions `PIPANE_AUTH_TOKEN` and `PIPANE_AUTH_DISABLED`.
   - Missing high-value vars: `PORT`, `PI_CWD`, `PI_CLI`, `PIPANE_PUBLIC_URL`, `PIPANE_DISABLE_LOCAL_BYPASS`, `PIPANE_SECURE_COOKIE`, `PIPANE_VERBOSE`, `PI_MAX_PROCESSES`, `PI_PREWARM_COUNT`.

5. Troubleshooting coverage is absent.
   - There are no notes for missing `pi`, broken auth URL, proxy/cookie issues, patch-package failures, failed/stale sessions, pool reload, or verbose logs.
   - The UI can emit `pi_install_required` and has automatic install support only when command is exactly `pi` with no base args; if `PI_CLI` points elsewhere, the user must install manually.

6. Patch-package behavior is not documented.
   - `postinstall` always runs `patch-package`, and the package ships `patches/@mariozechner+mini-lit+0.2.1.patch` plus `patches/@mariozechner+pi-web-ui+0.55.3.patch`.
   - If dependency versions drift or patches fail, contributors need a doc path: reinstall locked deps, verify package versions, inspect patch-package output, and avoid silently deleting patches.

7. Architecture content should not expand the README much further.
   - `src/server/server.ts` has useful architecture comments about detached/attached sessions, process pool, lifecycle, and WebSocket routing.
   - This belongs in a separate development/architecture doc. README should summarize the model in a short "How it works" section and link to the deeper file.

## Quickstart Assessment

Recommended README quickstart shape:

```bash
git clone <repo>
cd pipane
npm install
npm run build
npm run test
npx playwright test --list
npx playwright test --timeout 60000
```

For local dev:

```bash
cd pipane
npm run dev
# open http://localhost:8111
```

Important nuance: `npm run dev` uses tmux and starts Vite on `DEV_PORT=8111` with backend on `BACKEND_PORT=18111`; docs should either call out the tmux requirement or provide a non-tmux alternative using `npm run dev:server` and `npm run dev:client` in separate terminals.

For local production smoke:

```bash
cd pipane
npm run build
PI_CWD=/path/to/project npm start
# open the Local URL or printed Remote auth URL
```

Current build behavior verified:

- `npm run check` passes.
- `npm run build` passes.
- Build prints repeated unresolved KaTeX font URL warnings from `@mariozechner/pi-web-ui`; docs should clarify whether these are expected/benign or should become a follow-up fix.
- Build prints large chunk warnings; likely expected for now, but worth documenting as non-fatal if no immediate optimization is planned.

## Troubleshooting Notes to Add

- Missing `pi`: install `@mariozechner/pi-coding-agent`, restart pipane, or set `PI_CLI=/path/to/pi`. If the UI offers install, it only supports the plain `pi` command path.
- Wrong auth URL: set `PIPANE_PUBLIC_URL` to the externally reachable origin, including scheme and port. Use `PI_PUBLIC_HOSTNAME` only when the default URL pattern is otherwise correct.
- Local auth bypass surprises: localhost requests bypass auth unless `PIPANE_DISABLE_LOCAL_BYPASS=1`.
- HTTPS/reverse proxy cookies: set `PIPANE_PUBLIC_URL=https://...`; set `PIPANE_SECURE_COOKIE=1` only when serving over HTTPS.
- Reverse proxy auth: only set `PIPANE_AUTH_DISABLED=1` when another layer authenticates both HTTP and WebSocket traffic.
- Patch-package failures after install: run `npm install` from a clean lockfile state, inspect which patch failed, check exact dependency versions, and do not remove patch files without validating the patched behavior.
- Stale/bad sessions: use `/debug/pool` or `/api/debug/pool`, try the UI `/reload` command to reload pi processes, restart pipane if attached session state is stale, and check the pi sessions directory under the agent dir.
- E2E harness failures: run `npm run build` first; real-stack e2e needs the built server at `dist/server/server/server.js`; tests create temp `PI_CODING_AGENT_DIR` and strip ambient provider credentials.
- Port conflicts: set `PORT` for production server, `DEV_PORT` and `BACKEND_PORT` for dev, or Docker `APP_PORT`.

## Recommended Documentation Tickets

1. Rewrite `pipane/README.md` quickstart.
   - Include install/run URLs, global package flow, clone/contributor flow, Node/npm version, local dev, production smoke, auth URL behavior, and workspace selection via `PI_CWD`.

2. Add a runtime configuration table to `pipane/README.md`.
   - Include all server env vars above with defaults and security warnings.

3. Refresh `pipane/AGENTS.md`.
   - Replace stale test counts and file inventory with either current counts or a count-free description plus `npx playwright test --list`.
   - Document `npm run check`, `npm run build`, required build before e2e, screenshot update command, render-perf fixture generation, and optional `RUN_WALKTHROUGH=1`.

4. Add troubleshooting section.
   - Cover missing pi, auth URL, reverse proxy, patch-package, stale sessions/process pool, e2e build precondition, and expected build warnings.

5. Clarify Docker trust/auth model.
   - Decide whether Compose should default `PIPANE_AUTH_DISABLED=1` or `0`; then align `docker/README.md` open URL and examples.
   - Add Docker env var table and warnings for `change-me`, mounted SSH key, `WORKSPACE_DIR`, and hostnames.

6. Create `docs/architecture.md` or `docs/development.md`.
   - Recommended home for attached vs detached sessions, JSONL sync, process pool, auth guard, REST/WS split, and e2e harness design.
   - README should link to it rather than carrying detailed internals.

## Follow-ups and Blocked Validation

- I did not run the full Playwright e2e suite because this was a research-only docs audit and it can be longer-running/destructive to snapshots. I did run discovery with `npx playwright test --list` and verified current e2e count/file coverage.
- Initial sandboxed `npm run test` and Playwright discovery failed because localhost/IPC listens were blocked; rerunning with approved elevated permissions succeeded for Vitest and e2e discovery.
- Confirm with maintainers whether Docker Compose intentionally disables pipane and wede auth by default. This is the largest ambiguity because the README text and Compose defaults currently imply different operating modes.
- Confirm whether KaTeX font unresolved warnings and large bundle warnings are expected known noise; if yes, document them as benign, otherwise create a build hygiene ticket.

## Commands Run

- `npm run check` — passed.
- `npm run build` — passed with non-fatal KaTeX font URL warnings and large chunk warnings.
- `npm run test -- --reporter dot` — passed with `301` tests across `21` files after rerun with permissions for localhost sockets.
- `npx playwright test --list` — listed `21` tests across `10` files after rerun with permissions for local IPC/listeners.
