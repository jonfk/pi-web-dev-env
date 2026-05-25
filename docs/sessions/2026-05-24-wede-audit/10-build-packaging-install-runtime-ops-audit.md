# Ticket 10: Build, Packaging, Install, and Runtime Ops Audit

## Scope

Audited Wede production build flow, frontend embedding behavior, install script, release artifact handling, README accuracy, and the root Docker integration. This was research/exploration only; no source files were changed. The only file created for this ticket is this report.

Primary files reviewed:

- `wede/package.json`
- `wede/vite.config.js`
- `wede/backend/cmd/wede/frontend_dev.go`
- `wede/backend/cmd/wede/frontend_embed.go`
- `wede/backend/cmd/wede/main.go`
- `wede/backend/internal/config/config.go`
- `wede/install.sh`
- `wede/README.md`
- `wede/.github/workflows/ci.yml`
- `wede/.github/workflows/release.yml`
- `docker/Dockerfile`
- `docker/docker-compose.yml`
- `docker/entrypoint.sh`
- `docker/Caddyfile`
- `docker/README.md`

## Commands Run

From `/Users/jfokkan/Developer/jonfk_code/pi-web-dev-env` unless noted:

- `pwd && rg --files`
- `git status --short`
- `sed -n ...` / `nl -ba ...` inspections of the files listed above
- `find docs/sessions/2026-05-24-wede-audit -maxdepth 1 -type f -print`
- `git ls-files ...`
- `git status --short --untracked-files=all`
- `git check-ignore -v ...`
- `docker compose -f docker/docker-compose.yml config`

From `wede/`:

- `test -d node_modules && echo node_modules-present || echo node_modules-missing`
- `bash -n install.sh`
- `bash -n ../docker/entrypoint.sh`
- `bash -n ../docker/bootstrap.sh`
- `npm run build`
- `npm run build:all`
- `ls -lh wede`
- `test -d backend/cmd/wede/dist && echo embed-dist-present || echo embed-dist-removed`
- `./wede --help`
- `git status --short --untracked-files=all`
- `git rev-parse --show-toplevel && git rev-parse HEAD && git remote -v`

Clean-checkout simulation:

- Created a temporary archive copy from `wede` HEAD under `/private/tmp/wede-audit-clean.7pAv6O`
- `npm ci`
- `npm run build:all`
- `ls -lh wede`
- `test -d backend/cmd/wede/dist && echo embed-dist-present || echo embed-dist-removed`
- `./wede --help`

Note: the first clean-copy `npm run build:all` attempt failed because the sandbox blocked writes to the normal Go build cache at `~/Library/Caches/go-build`. Re-running the same command with normal cache access succeeded. This was an environment permission issue, not a Wede build failure.

## Build Findings

`npm run build` succeeds locally. It produces `dist/index.html`, CSS, and one large JS bundle. Vite reports a non-fatal warning that the JS chunk is larger than 500 kB after minification.

`npm run build:all` succeeds locally and in a temporary clean archive copy after `npm ci`. It produces an executable `./wede` of about 10 MB, and `./wede --help` prints the expected `-port` and `-p` flags. The temporary embed directory `backend/cmd/wede/dist` is removed after successful builds.

Acceptance check: `build:all` works from a clean checkout once dependencies are installed with `npm ci`. The script itself does not install dependencies; a truly fresh checkout with no `node_modules` must run `npm ci` first.

Reliability risk: `build:all` uses a single shell chain:

```json
"build:all": "vite build && cp -r dist backend/cmd/wede/dist && cd backend && go build -tags embed_frontend -o ../wede ./cmd/wede && rm -rf cmd/wede/dist"
```

Because cleanup only runs after a successful Go build, a failure after the copy step can leave `backend/cmd/wede/dist` behind. A later run with that directory already present can change `cp -r` behavior and may create a nested `dist/dist` layout instead of the intended embed root. The release workflow avoids this exact shape by creating the directory and copying `dist/*`, but the package script is more fragile.

The CI workflow builds the embedded binary manually and then runs `./wede --help || true`. The `|| true` means CI would not fail if the binary smoke test failed.

The release workflow passes `-ldflags "-s -w -X main.Version=${VERSION}"`, but no `Version` variable was found in `main`. This does not currently break the build, but it makes the version injection ineffective.

## Frontend Embed And Dev Findings

The embedded and non-embedded frontend handlers are broadly consistent:

- Both serve `/` as `index.html`.
- Both fall back to `/` for missing frontend paths, supporting SPA routing.
- The embedded build uses `//go:embed dist` and `fs.Sub(frontendFS, "dist")`.
- The dev build searches upward from cwd for `dist/` and serves it if present.

Development mode has an intentional split behavior: if no `dist/` exists, the Go backend returns a static HTML page telling the user to open the Vite dev server on `localhost:5173`. It does not reverse proxy Vite. This is consistent with `vite.config.js`, where Vite proxies `/api` and WebSocket traffic to the Go backend on `localhost:9090`.

Operational nuance: because the dev backend searches upward for any `dist/`, running from a nested directory under a repo that happens to contain a stale `dist/` can serve old frontend assets instead of showing the Vite instruction page. That is acceptable for a convenience dev path, but it is implicit and could confuse troubleshooting.

## Install And Runtime Findings

`bash -n install.sh` passes.

The installer targets `webcrft/wede`, reads the latest release via GitHub API, and downloads `wede-${os}-${arch}`. This aligns with Linux and macOS release artifact names, but not Windows: the release workflow publishes `wede-windows-amd64.exe`, while `install.sh` tries to download `wede-windows-amd64`.

The installer does not verify downloaded binaries. The release workflow creates `checksums.txt`, but `install.sh` never downloads or checks it. There is no signing or signature verification path.

The release-missing and API-error path is brittle. `LATEST=$(curl ... | grep ... | sed ...)` runs under `set -euo pipefail`, so a 404, rate limit response, or JSON shape change can exit before the later `if [ -z "$LATEST" ]` message. Parsing JSON with `grep` is also fragile.

PATH handling is Unix-centric. Linux/macOS install to `$HOME/.local/bin`, then check `$PATH` by splitting on `:`. That check is right for Unix shells but not Windows, where PATH separators are `;`. The Windows branch also assumes a Bash/MSYS-like environment with `uname`, `mktemp`, `tr`, `/dev/urandom`, `mv`, and `chmod`, so it is not a general Windows installer.

Config creation works functionally, but permissions are not hardened. The installer creates `~/.config/wede/wede.config.json` with the process umask, commonly `0644`, even though it contains the generated admin password. The Docker entrypoint similarly writes `/home/ubuntu/.config/wede/wede.config.json` via shell redirection without setting file mode. Runtime also logs the active password when auth is enabled.

Config lookup order is important: Wede searches cwd and parent directories before `~/.config/wede/`. The installer creates only `~/.config/wede/wede.config.json`, so a project-local `wede.config.json` will override the installed config. The README mentions cwd/parent lookup but does not document the full order, including `~/.config/wede` and next-to-executable fallback.

## Docker Scope Findings

Docker is in scope for the larger `pi-web-dev-env` repository, not as a standalone Wede-only deployment. The root Docker image builds and packages both `pipane` and `wede`:

- `docker/Dockerfile` has a `pipane-builder` stage and a `wede-builder` stage.
- The runtime image includes `/opt/pipane`, `/usr/local/bin/pipane`, and `/usr/local/bin/wede`.
- `docker/docker-compose.yml` runs separate `pipane` and `wede` services from the same `pi-assistant:local` image and fronts them with Caddy.
- `docker/README.md` explicitly describes this as a "`pipane + wede` Docker image".

The Docker files do align with Wede as one component of the larger repo. They should not be treated as Wede's canonical standalone packaging unless that is made explicit.

`docker compose -f docker/docker-compose.yml config` succeeds, so the compose file is syntactically valid in this environment.

Important mismatch: compose defaults `WEDE_AUTH_DISABLED` to `1`, while `docker/README.md` says Wede opens with password `admin`. With the current default, Wede's built-in auth is disabled and the password is irrelevant. Caddy serves plain HTTP and does not add an auth layer, so the default compose setup exposes Wede without Wede authentication on the configured local hostname/port.

`docker/Dockerfile` defaults `WEDE_AUTH_DISABLED=0`, but compose overrides it to `${WEDE_AUTH_DISABLED:-1}` for the Wede service. That makes image-default behavior and compose-default behavior differ.

`docker/entrypoint.sh` writes Wede config on every `wede` service start, which keeps env changes reflected. However, because Wede's config loader checks cwd/parents before `~/.config/wede`, a mounted workspace containing `wede.config.json` can shadow the generated Docker config.

`wede` depends on `pipane` in compose even though the Wede service itself only needs the shared image and mounted workspace. That dependency may be intentional for the combined environment, but it is not required for Wede runtime.

## Docs Mismatches

`wede/README.md` says "No Docker" as a product value, while the larger repo has a Docker integration that packages Wede. This is not necessarily wrong for standalone Wede, but it should be worded carefully if users encounter both docs.

`wede/README.md` quick install pipes `install.sh` from `webcrft/wede/main`, but this local repo is `jonfk/wede` as a nested repo. If this fork is expected to be installable, the install command and release repo need clarification.

`wede/README.md` says Wede looks for `wede.config.json` in current/parent directories. The actual lookup order is cwd/parents, then `~/.config/wede/`, then next to the executable.

`wede/README.md` does not mention that the install script creates `~/.config/wede/wede.config.json` with a generated password. It starts Getting Started by asking users to create a project config manually, which conflicts with the quick-install path.

`docker/README.md` says Wede is available with password `admin`, but compose disables Wede auth by default. Either the compose default or the docs should change.

`docker/README.md` tells users to run `WEDE_AUTH_DISABLED=1` only behind another reverse proxy auth layer, but that is already the default in compose. This makes the default less safe than the surrounding text implies.

## Recommendations

1. Make `build:all` failure-safe. Use a temporary embed directory or add a cleanup trap so `backend/cmd/wede/dist` is removed on failure. Prefer copying `dist/.` or `dist/*` into a freshly-created embed directory to avoid nested `dist` behavior.

2. Update CI smoke verification to fail on binary startup/help failures. Remove `|| true` from `./wede --help || true`.

3. Fix Windows release installation. Either make the installer request `wede-windows-amd64.exe` and install an `.exe`, or publish a matching extensionless Windows artifact intentionally.

4. Verify release artifacts in `install.sh`. Download `checksums.txt`, check the selected artifact with `sha256sum` or platform equivalents, and fail closed on mismatch. Add signing, for example cosign or minisign, if releases are meant for unattended install.

5. Harden installer error handling. Use GitHub API parsing that can detect `message` errors and missing releases clearly. If staying POSIX-only, avoid assuming `grep` success under `pipefail`; otherwise use `jq` with an explicit dependency check.

6. Harden config permissions. Create config directories with `0700` and config files with `0600` in both `install.sh` and Docker entrypoint. Consider warning if an existing config file containing a password is group/world-readable.

7. Stop logging plaintext passwords at runtime. `main.go` logs the configured password when auth is enabled. That is convenient for development but unsafe for production logs, Docker logs, and service managers.

8. Align Docker auth defaults and docs. Recommended default: set `WEDE_AUTH_DISABLED` to `0` in compose and keep `WEDE_PASSWORD` default clearly documented as local-dev only, or keep auth disabled but put a strong warning at the top of Docker docs and add Caddy/auth guidance.

9. Document Docker scope explicitly. State that root Docker is a combined `pipane + wede` developer environment, not the standalone Wede distribution path.

10. Document full config lookup order and shadowing behavior. This matters for installed configs and Docker-generated configs because workspace-local configs take precedence.

## Followups And Ambiguities

- Should Wede standalone releases be owned by `webcrft/wede`, `jonfk/wede`, or both? The local nested repo remote is `jonfk/wede`, while install/docs target `webcrft/wede`.

- Is Docker meant to be secure-by-default for local-only use, or intentionally auth-disabled for convenience behind a developer's local network assumptions? This decides whether compose should default `WEDE_AUTH_DISABLED` to `0` or keep it at `1`.

- Should the installer support native Windows PowerShell, or only Git Bash/MSYS/Cygwin? Current behavior is only plausible for Unix-like Windows shells.

- Should `build:all` be the canonical release build path, or should CI/release keep their manual copy/build steps? Duplicating embed-copy logic already caused small differences between package script, CI, and release workflow.
