# Ticket 10: Packaging, CLI, Publish, and Production Runtime Review

Date: 2026-05-24
Workspace: `/Users/jfokkan/Developer/jonfk_code/pi-web-dev-env`
Project: `pipane/`

## Summary

`pipane` can build, pack, and start from built output in a temp-copy smoke test, and the CLI wrapper resolves the expected production server entry from a packed tarball. The npm package contents are mostly intentional and small: `dist/`, `bin/`, `extensions/`, `patches/`, `LICENSE`, `README.md`, and npm's automatically included `package.json`.

The main release risks are:

- Built CSS references KaTeX font files in `node_modules/@mariozechner/pi-web-ui/dist/fonts/...`, but the tarball does not include those font files. An installed package will likely 404 math fonts.
- `postinstall` runs `patch-package` for consumers/global installs. That makes install reliability depend on patch-package successfully finding and patching transitive dependency layouts after install.
- `@mariozechner/mini-lit` is semver-ranged as `^0.2.0`, but the included patch is version-specific to `0.2.1`.
- Local package install smoke hung under this environment before producing output; it was stopped and documented below.
- No `docker/` directory exists in this checkout, and README does not document ports, `npm start`, Docker, or reverse-proxy settings beyond auth variables.

## Commands And Evidence

All mutating smoke commands were run against a temp copy under `/private/tmp/pipane-audit-nrtBGv`, not the workspace project. The temp copy symlinked `node_modules` from the workspace to avoid dependency installation and kept generated `dist/`, tarballs, and install attempts outside the repo.

| Command | Location | Result |
| --- | --- | --- |
| `rg --files pipane` | workspace | Inspected project file set. No `pipane/docker/` directory found. |
| `git status --short` | workspace | Only `?? docs/sessions/2026-05-24-pipane-audit/` was shown before report creation; no project files modified. |
| `npm run build` | temp copy | Passed. Vite emitted unresolved KaTeX font URL warnings and large chunk warnings. |
| `npm pack --dry-run` | temp copy | First run built successfully but failed after build because `/Users/jfokkan/.npm` had root-owned cache files. Re-run with `npm_config_cache=/private/tmp/pipane-audit-nrtBGv/npm-cache` passed. |
| `npm start` with `PORT=18222 PI_CLI=definitely-not-an-installed-pi-binary PIPANE_AUTH_TOKEN=audit-token` | temp copy | Initially blocked by sandbox listen `EPERM`; with approval, server started and printed `Local: http://localhost:18222`. |
| `curl -i --max-time 5 http://127.0.0.1:18222/` | against temp server | Returned `HTTP/1.1 200 OK`, `Set-Cookie: pipane_auth=audit-token`, and built `index.html`. |
| `npm pack --pack-destination /private/tmp/pipane-audit-nrtBGv` | temp copy | Passed and created `pipane-0.1.6.tgz`. |
| `tar -tzf /private/tmp/pipane-audit-nrtBGv/pipane-0.1.6.tgz` | temp tarball | Confirmed 37 package files matching dry-run contents. |
| `PIPANE_PRINT_ENTRY=1 node .../extract/package/bin/pipane.js` | extracted tarball | Printed `/private/tmp/pipane-audit-nrtBGv/extract/package/dist/server/server/server.js`. |
| `npm install --no-audit --no-fund /private/tmp/pipane-audit-nrtBGv/pipane-0.1.6.tgz` | temp install dir | Hung with no output for about one minute; process `npm install /private/tmp/.../pipane-0.1.6.tgz` was stopped. No installed files were produced. |
| `npm ls @mariozechner/mini-lit @mariozechner/pi-web-ui patch-package --depth=0` | workspace | Installed versions: `@mariozechner/mini-lit@0.2.1`, `@mariozechner/pi-web-ui@0.55.3`, `patch-package@8.0.1`. |

## Package Contents Findings

`package.json` packaging shape:

- `private: false`
- `bin.pipane: bin/pipane.js`
- `files`: `dist/`, `bin/`, `extensions/`, `patches/`, `LICENSE`, `README.md`
- `prepack: npm run build`
- `postinstall: patch-package`

`npm pack --dry-run` produced a 37-file package:

- `bin/pipane.js`
- `dist/client/index.html`, favicon, JS/CSS assets, PDF worker
- `dist/server/server/*.js` and `dist/server/shared/jsonl-sync.js`
- `extensions/canvas.ts`
- `patches/@mariozechner+mini-lit+0.2.1.patch`
- `patches/@mariozechner+pi-web-ui+0.55.3.patch`
- `LICENSE`, `README.md`, `package.json`

Intentional/minimal:

- Source files, tests, e2e fixtures, screenshots, scripts, `dev.sh`, `prod.sh`, `test.sh`, TS configs, Vite config, lockfile, and `node_modules` are not packed.
- Runtime server path assumptions line up with packed contents: `dist/server/server/server.js`, `dist/client`, root `package.json`, and `extensions/canvas.ts` are present.

Not minimal dependency surface:

- Several build/client-time packages are in `dependencies`, not `devDependencies`: `@tailwindcss/vite`, `lit`, `lucide`, and `patch-package`. Because `prepack` builds the client, consumers should not need most build tooling at runtime. `patch-package` is only needed because of `postinstall`.

Font packaging issue:

- Build output CSS contains `@font-face` URLs like `../../../../../../Users/jfokkan/Developer/jonfk_code/pi-web-dev-env/pipane/node_modules/@mariozechner/pi-web-ui/dist/fonts/KaTeX_AMS-Regular.woff2`.
- `npm pack --dry-run` did not include any `node_modules/@mariozechner/pi-web-ui/dist/fonts/*` files.
- Vite warned that the same KaTeX font files "didn't resolve at build time" and would remain unchanged for runtime resolution.
- Expected impact: installed package serves `dist/client` only, so these font URLs are outside the package static root and likely fail in browser. The app still serves HTML, but math rendering fonts are unreliable.

## CLI And Runtime Findings

`bin/pipane.js`:

- Resolves server entry as `path.resolve(__dirname, "../dist/server/server/server.js")`.
- `PIPANE_PRINT_ENTRY=1` works both from the source tree and from an extracted packed tarball.
- Spawns `process.execPath` with the server entry and forwards CLI args.
- Sets `NODE_ENV` to `production` unless already set.

Production server:

- Default production port is `8222`; development default is `18111`.
- `PORT` overrides the server listen port.
- `PI_CWD` defaults to `process.cwd()`.
- `PI_CLI` can override the `pi` command, with `.js/.mjs/.cjs` values launched through `node`.
- Static files are served from `dist/client` relative to `dist/server/server/server.js`.
- Version is read from root `package.json` using `../../../package.json`, which is packed automatically by npm.
- Canvas extension path is `../../../extensions/canvas.ts`, which is packed.

Smoke result:

- `npm start` from the temp built copy started and served `/` successfully after local port binding was allowed.
- Starting without approval failed with `listen EPERM: operation not permitted 0.0.0.0:18222`, which appears to be this execution sandbox rather than app behavior.
- The server performs a non-blocking npm registry update check at startup. In restricted or offline production networks this should not block startup, but it is another runtime network assumption.

## Postinstall Patch Behavior

Current behavior:

- `postinstall` always runs `patch-package`.
- Included patches target `@mariozechner/mini-lit@0.2.1` and `@mariozechner/pi-web-ui@0.55.3`.
- Installed local versions match the patch filenames today.

Risks:

- `@mariozechner/mini-lit` is declared as `^0.2.0`; a fresh install may resolve a newer `0.2.x` version while the patch filename remains `0.2.1`.
- `patch-package` help says local runs can exit `0` even after failing to apply patches unless configured otherwise; on CI `--error-on-fail` is enabled by default. That split can hide broken installs locally and fail automated installs.
- As a dependency installed inside another project or globally, npm's dependency layout may differ from the source tree layout. The hung tarball install prevented confirmation that postinstall patches apply cleanly in a consumer install.
- The `pi-web-ui` patch is very large and touches both `dist` and `src`; this increases the chance of patch drift.

Recommendation:

- Pin `@mariozechner/mini-lit` exactly while patching it, or remove the patch by upstreaming/forking the change.
- Add a release smoke that installs the packed tarball into a clean temp prefix and verifies `postinstall`, `pipane` bin resolution, and a basic server start.

## Docker And README Findings

Docker:

- No `pipane/docker/` directory exists in this checkout.
- No Dockerfile, compose file, nginx example, or reverse-proxy config was available to audit.

README:

- Documents `npm install -g pipane`.
- Documents manual `pi` install via `npm install -g @mariozechner/pi-coding-agent`.
- Documents `PIPANE_AUTH_TOKEN` and `PIPANE_AUTH_DISABLED=1`.
- Does not document the `pipane` command after install.
- Does not document `PORT`, default production port `8222`, `PIPANE_PUBLIC_URL`, `PI_PUBLIC_HOSTNAME`, `PIPANE_SECURE_COOKIE`, `PIPANE_DISABLE_LOCAL_BYPASS`, `PI_CWD`, `PI_CLI`, `PI_MAX_PROCESSES`, or `PI_PREWARM_COUNT`.
- Mentions reverse proxy only for disabling built-in auth; it does not document WebSocket proxying for `/ws`, public URL/auth URL behavior, secure cookies behind TLS, or the default local bypass.

## Release Smoke-Test Checklist

Status legend: PASS, WARN, BLOCKED, TODO.

| Check | Status | Evidence / Notes |
| --- | --- | --- |
| Build from clean temp copy | PASS | `npm run build` completed. |
| Build warnings reviewed | WARN | Unresolved KaTeX font URLs and large chunk warnings. Font URLs are a packaging/runtime issue. |
| `npm pack --dry-run` | PASS | Passed with temp npm cache. Produced 37 files, 2.4 MB package, 8.3 MB unpacked. |
| Package contains runtime server | PASS | `dist/server/server/server.js` and server dependencies under `dist/server` included. |
| Package contains runtime client | PASS | `dist/client/index.html`, assets, favicon, PDF worker included. |
| Package contains package metadata | PASS | `package.json` included automatically by npm. |
| Package contains canvas extension | PASS | `extensions/canvas.ts` included. |
| Package contains patches | PASS | Both patch files included. |
| Package excludes tests/source/dev scripts | PASS | Expected files absent from tarball. |
| CLI bin resolves installed server entry | PASS | `PIPANE_PRINT_ENTRY=1` from extracted tarball points to `package/dist/server/server/server.js`. |
| `npm start` production server smoke | PASS | Temp copy served `/` with `HTTP/1.1 200 OK` after port-bind approval. |
| Local package install smoke | BLOCKED | `npm install` of packed tarball into temp dir hung with no output for about one minute; stopped. |
| Postinstall patches verified in fresh consumer install | BLOCKED | Blocked by hung install smoke. |
| Docker runtime assumptions verified | BLOCKED | No `docker/` directory exists. |
| README matches ports/env vars | TODO | README is missing most runtime env vars and command/port details. |

## Follow-Ups

1. Fix packaged CSS font URLs so KaTeX fonts are emitted into `dist/client/assets` or otherwise served by the production app. Re-run `npm pack --dry-run` and verify no CSS references to `node_modules` or local absolute paths remain.
2. Add a scripted release smoke that runs in `/tmp`: `npm pack`, clean `npm install` from tarball, `PIPANE_PRINT_ENTRY=1 pipane`, `PORT=<free> PI_CLI=<bogus> pipane`, and `curl /`.
3. Revisit `postinstall: patch-package`; either pin all patched package versions exactly and make install failures explicit, or remove install-time patching by upstreaming/forking patched packages.
4. Move build-only dependencies out of runtime dependencies where possible after confirming the global install still has everything needed at runtime.
5. Document production usage in README: `pipane`, default port `8222`, `PORT`, `PI_CWD`, `PI_CLI`, auth variables, reverse proxy `/ws`, `PIPANE_PUBLIC_URL`, secure cookie behavior, and local bypass behavior.
6. Add Docker files or remove Docker from the release scope. If Docker is desired, document exposed port `8222`, persisted agent/session directories, `PI_CLI` availability, and reverse-proxy/WebSocket configuration.
