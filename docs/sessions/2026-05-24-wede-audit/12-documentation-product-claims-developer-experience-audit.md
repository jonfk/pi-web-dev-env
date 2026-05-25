# Ticket 12: Documentation, Product Claims, and Developer Experience Audit

## Scope

Audited documentation, examples, commands, screenshots, configuration, and product claims against the current `wede/` implementation.

Primary files reviewed:

- `wede/README.md`
- `wede/AGENTS.md`
- `wede/package.json`
- `wede/wede.config.json`
- `wede/docs/screenshots/*`
- `wede/public/manifest.json`
- `wede/landing/index.html`

Related implementation files inspected to verify claims:

- `wede/backend/cmd/wede/main.go`
- `wede/backend/cmd/wede/frontend_embed.go`
- `wede/backend/cmd/wede/frontend_dev.go`
- `wede/backend/internal/auth/auth.go`
- `wede/backend/internal/config/config.go`
- `wede/backend/internal/git/git.go`
- `wede/backend/internal/terminal/terminal.go`
- `wede/backend/internal/workspace/workspace.go`
- `wede/src/components/Editor.jsx`
- `wede/src/components/Browser.jsx`
- `wede/src/hooks/useAuth.js`
- `wede/install.sh`
- `wede/go.mod`

## Commands Run

From `wede/` unless noted:

| Command | Result | Notes |
|---|---:|---|
| `npm run build` | Pass | Built frontend into `dist/`. Vite emitted a large chunk warning for `index-BlRV_5q9.js` at 1,584.22 kB / 508.89 kB gzip. |
| `npm run build:all` | Pass | Built frontend, copied `dist` into backend embed path, compiled embedded binary at `./wede`, then removed `backend/cmd/wede/dist`. |
| `go test ./...` from `wede/backend/` | Pass | Compile-tested backend packages; all packages report `[no test files]`. |
| `bash -n ../docker/entrypoint.sh` from `wede/` | Pass | AGENTS command is valid. |
| `npm ci --dry-run` | Pass | Lockfile is internally installable in this environment without mutating `node_modules`. |
| `npm run dev -- --help` | Pass | Vite dev command is present. |
| `./wede --help` | Pass | Shows `-port` and `-p`; no long `--port` alias in help text because Go `flag` prints single-dash form. |
| `go run ./cmd/wede --help` from `wede/backend/` | Pass | Backend command compiles enough to print usage. |
| `npm run lint` | Fail | 32 errors and 4 warnings. This is not documented as required in AGENTS, but the script exists and is broken. |
| `du -h wede/wede && file wede/wede` from repo root | Pass | Built binary is 10M, Mach-O arm64 on this machine. |
| `sips -g pixelWidth -g pixelHeight wede/docs/screenshots/*.png` | Pass | Screenshot files are readable; dimensions recorded below. |
| `npm view vite@8.0.1 engines --json` | Fail | Network blocked by sandbox: `ENOTFOUND registry.npmjs.org`; package-lock was used instead. |
| `npm view @vitejs/plugin-react@6.0.1 engines --json` | Fail | Network blocked by sandbox: `ENOTFOUND registry.npmjs.org`; package-lock was used instead. |

## README Claim Verification Table

| README / Product Claim | Status | Evidence / Risk |
|---|---|---|
| “A lightweight, open-source, self-hosted web IDE.” | Verified | Implementation serves local React app plus Go backend. License is MIT. |
| “Code editor, terminal, git, and file explorer — all in your browser.” | Verified with caveats | All components and API handlers exist. Terminal and git capabilities depend on host shell/git availability and permissions. |
| “One ~10MB binary.” | Verified locally | `npm run build:all` produced `wede/wede`; `du -h` reports `10M`. Size is platform/build dependent, so docs should say approximate. |
| “No cloud.” / “No cloud dependency.” | Needs qualification | Runtime app does not appear to upload code to a cloud service, but `wede/index.html` loads Google Fonts and README/landing link external assets. The landing page also loads `https://webcrft.io/crft.js`. Air-gapped/runtime docs should clarify whether external fonts are optional and whether the shipped app is fully offline-capable. |
| “Your code never leaves your machine.” | Needs qualification | No upload path found by inspection, but terminal/browser preview can make arbitrary network requests initiated by user commands or iframes. Browser loads external font assets. Phrase should be scoped to “wede does not send project files to a hosted service.” |
| “No Docker.” | Verified for runtime | App runs as a Go binary. Docker may still be runnable from the web terminal if installed. |
| “No Node.js runtime.” | Verified for built binary, not development | `build:all` embeds frontend. Development requires Node/npm. README already separates development, but product claim should say “for the released/built binary.” |
| “No database.” | Needs qualification | Running IDE uses config plus `~/.wede/sessions.json` and `~/.wede/recent.json`, not a DB. However the repo contains `wede/database/` with Postgres migrations and a `database` Go module, which conflicts with the product claim unless documented as unused/legacy/unrelated. |
| “Run anywhere: Linux servers, macOS, Raspberry Pi, NAS devices, air-gapped networks, CI runners.” | Needs verification | Local macOS arm64 build works. Install script supports `linux/darwin/windows` and `amd64/arm64`, but Windows terminal behavior is likely risky because terminal uses `github.com/creack/pty`, which is Unix-focused. Air-gapped is questionable due external font references and release install needing network. |
| “Access from any device through any modern browser.” | Needs browser matrix | UI is responsive by code and screenshots include mobile. No README browser support matrix. Terminal WebSocket, iframe sandbox, localStorage auth, and PWA behavior should list tested Chrome/Edge/Firefox/Safari/iOS Safari. |
| “File Explorer: VS Code-style project tree with git status colors. Context menu for copy, paste, rename, delete.” | Verified by implementation | `FileExplorer.jsx` implements tree UI and context actions; git status is mapped. |
| “CodeMirror 6 with syntax highlighting for JavaScript, TypeScript, Go, Python, Rust, and 10+ languages.” | Mostly verified | `Editor.jsx` maps JS/JSX/TS/TSX, HTML, CSS, JSON, Python, Go, Markdown, XML/SVG, SQL, Rust, C/C++/H, Java, PHP. Claim is accurate. |
| Landing claim “20+ languages.” | Mismatch | Implementation maps about 18 extensions/language modes depending how counted. README says “10+”; landing says “20+”. Align landing to README or add more language modes. |
| “Web Terminal: Full PTY terminal emulator via xterm.js and WebSocket. Multiple tabs. Run shell commands, SSH, Docker — anything.” | Verified with caveats | Terminal uses xterm.js, WebSocket, `creack/pty`, and host shell. “Anything” should be softened; depends on host installed binaries and server permissions. |
| “Git Client: Built-in visual commit graph, staging area, branch management, and checkout.” | Partially verified | Status, log graph, stage, unstage, commit, branch list, and checkout exist. “Branch management” overstates implementation if readers expect create/delete/rename/merge/pull/push; only listing and checkout are implemented. |
| “Built-in Browser: Preview your running web app in an embedded browser tab.” | Verified with caveats | `Browser.jsx` uses an iframe. It cannot preview sites that block framing via `X-Frame-Options`/CSP and may hit mixed-content limitations under HTTPS. |
| “Mobile Friendly: Fully responsive UI for tablets and phones.” | Needs verification | Mobile UI exists and screenshot exists. “Fully” is broad; should list tested viewport/browser set. |
| “Secure Access: Password authentication with 3-attempt lockout. Deploy behind HTTPS reverse proxy for production.” | Partially verified, high-risk wording | 3-attempt lockout exists and unlocks only by restart. Security claim needs caveats: server binds to `:port` on all interfaces; startup logs password; raw session tokens persist in `~/.wede/sessions.json`; logout only clears localStorage and does not revoke server token; terminal WebSocket sends token in query string; WebSocket upgrader allows all origins after auth middleware. |
| Quick install `curl -fsSL ... | bash` | Not executed | Destructive/network install was not run. Script inspection shows it downloads latest release to `~/.local/bin`, creates `~/.config/wede/wede.config.json` with random password, and prints password. |
| “Or download binary directly from GitHub Releases.” | Needs verification | Not tested due network/scope. |
| Getting Started config example | Works but incomplete | Config loader requires `wede.config.json` unless auth disabled. README does not mention install script creates global config, search order includes `~/.config/wede/` and executable directory, or that the server listens on all interfaces. |
| CLI `wede [flags] [path]`; `path` optional shows folder picker | Verified | `workspace.New("")` leaves no workspace and UI folder picker is used. However config is still required before folder picker can load. |
| `--port` override | Verified in code | Go flag supports `--port` and `-port`; help displays `-port`. Shorthand `-p` exists but README omits it. |
| “wede looks for `wede.config.json` in current directory or parent directories.” | Incomplete | Code also searches `~/.config/wede/wede.config.json` and next to executable. README should document full search order. |
| `authDisabled` and `WEDE_AUTH_DISABLED=1` | Verified | Config and env override exist. Docs should emphasize this removes app auth entirely and must only be used behind a real access-control layer. |
| Development frontend commands `npm install`, `npm run dev` | Mostly verified | `npm run dev -- --help` works. For clean checkout, prefer `npm ci` because lockfile exists and AGENTS says `npm ci`. |
| Development backend commands `cd backend && go run ./cmd/wede .` | Compile-verified | `go run ./cmd/wede --help` works from backend. Actual server start was not kept running. |
| “Vite dev server proxies API and WebSocket requests to Go backend.” | Partially verified | `vite.config.js` proxies `/api` with `ws: true`. Terminal client special-cases Vite ports `5173` and `5174` to connect directly to `:9090`, so the docs should mention backend must be on 9090 in dev unless code/config is changed. |
| “Build a single binary: npm run build:all.” | Verified | Command completed and produced `./wede`; temporary embedded dist was removed. |
| Go badge “1.22+” | Mismatch | `wede/go.mod` says `go 1.25.6`; local Go is `go1.25.6`. Update badge/docs or lower `go.mod` after compatibility testing. |
| Tech stack “React 19 + Vite” / “Tailwind CSS 4” | Verified | `package.json` uses React 19.2.4, Vite 8.0.1 range resolved to 8.0.3 locally, Tailwind 4.2.2. |

## Docs Mismatch List

1. README Go badge says `Go 1.22+`, but `wede/go.mod` requires `go 1.25.6`. This is the most direct clean-checkout mismatch for contributors.

2. README development docs say `npm install`, while `wede/AGENTS.md` says `npm ci`. For reproducible onboarding from a clean checkout, README should use `npm ci`.

3. README CLI/config section says config lookup is current directory or parent directories, but implementation searches:
   - current working directory and parents
   - `~/.config/wede/wede.config.json`
   - next to executable

4. README suggests default port is `9090`, but the program still hard-fails if no config file is found. The “path none shows folder picker” claim is true only after config is present.

5. README omits `-p` shorthand even though it is implemented.

6. README says “Secure Access” without warning that startup logs the password and that sessions are long-lived persisted bearer tokens in `~/.wede/sessions.json`.

7. README says deploy behind HTTPS reverse proxy, but does not provide required reverse-proxy guidance for WebSocket upgrade, `Host`/scheme forwarding expectations, mixed content, or iframe preview limitations.

8. README says “No database,” while `wede/database/` contains Postgres migration code. Runtime claim is likely accurate, but repo structure creates product/documentation confusion.

9. Landing page says syntax highlighting for `20+ languages`; implementation and README support the safer `10+ languages` claim.

10. Landing page hardcodes `v0.1.1`; package version is `0.0.0`, and no local release metadata was verified. This will drift unless release automation updates it.

11. Landing page uses remote CDN screenshots/icons and `https://webcrft.io/crft.js`, while README emphasizes no cloud dependency. Distinguish marketing site dependencies from app runtime.

12. README feature claim “branch management” should be narrowed to “branch list and checkout” unless create/delete/rename/merge/push/pull are implemented.

13. AGENTS includes `npm run build` and `npm run build:all` but not `npm run lint`; since `lint` exists and currently fails, either fix lint later or document that lint is not currently a required gate.

14. README lacks troubleshooting for common startup failures:
   - missing `wede.config.json`
   - wrong password / locked after 3 failed attempts
   - port already in use
   - backend not running while using Vite dev server
   - terminal WebSocket failing behind reverse proxy
   - preview iframe blocked by target app CSP or `X-Frame-Options`
   - git panel empty because workspace is not a git repository

15. README lacks browser support details for desktop/mobile, PWA install behavior, WebSocket requirements, localStorage use, and known iframe limitations.

16. `wede/wede.config.json` in the repo uses `"password": "admin"`. This is convenient for local development but unsafe as example material. README should avoid implying that checked-in config is production-ready.

## Onboarding / DX Findings

- The production build path is executable from the current checkout: `npm run build` and `npm run build:all` both pass.

- Backend compile-test path is executable: `go test ./...` from `wede/backend/` passes, but there are no backend test files.

- Clean checkout prerequisites are under-documented:
  - Node version is not stated. `package-lock.json` shows Vite/Rolldown packages requiring `node "^20.19.0 || >=22.12.0"`.
  - Go version is not aligned between README and `go.mod`.
  - Git must be installed for git panel features.
  - A POSIX shell/PTY support is assumed for terminal features.

- `npm run lint` fails with 32 errors and 4 warnings. Even if lint is not a required acceptance gate today, its presence as a package script creates a DX trap for contributors.

- Development startup path needs clearer sequencing. The README says run frontend and backend separately, but backend needs a config file, and terminal dev WebSocket currently special-cases `localhost:9090` for Vite ports `5173`/`5174`.

- `npm run build:all` leaves generated artifacts ignored by git (`dist/`, `wede`) and removes `backend/cmd/wede/dist` as AGENTS says. This is good, but README could note the binary and frontend dist are ignored local build output.

- Install script inspection shows a better first-run path than README’s manual config step: it creates `~/.config/wede/wede.config.json` with a random password. README should tie Quick Install and Getting Started together so users know whether they need to create a local config manually.

## Screenshots

Local screenshot files exist and are readable:

| File | Dimensions | Modified |
|---|---:|---|
| `docs/screenshots/full_light.png` | 2832 x 1666 | 2026-05-21 10:58:14 EDT |
| `docs/screenshots/git.png` | 516 x 588 | 2026-05-21 10:58:14 EDT |
| `docs/screenshots/git_graph.png` | 514 x 290 | 2026-05-21 10:58:14 EDT |
| `docs/screenshots/mobile.png` | 632 x 1142 | 2026-05-21 10:58:14 EDT |
| `docs/screenshots/preview.png` | 1592 x 1026 | 2026-05-21 10:58:14 EDT |
| `docs/screenshots/settings.png` | 630 x 682 | 2026-05-21 10:58:14 EDT |

Findings:

- Screenshots are recent relative to the audit date.
- README only shows `full_light.png`, `git_graph.png`, and `preview.png`; other screenshots are unused in README.
- No screenshot capture script, browser matrix, app commit reference, or “last refreshed” note exists, so “current enough” cannot be mechanically verified.
- Landing page references remote CDN versions of screenshots instead of local `docs/screenshots/*`, so README and landing can drift independently.

## Product Claim Risk Notes

- **Security wording risk:** The current “Secure Access” phrasing is too strong. Password auth exists, but the implementation is closer to lightweight access control than hardened internet-facing auth. Production docs should explicitly require HTTPS, reverse proxy access control where appropriate, strong password, and trusted network exposure.

- **Network exposure risk:** `http.ListenAndServe(":"+port, mux)` binds all interfaces. README opens `http://localhost:9090`, but on a server/NAS this may expose wede to the LAN or public interface depending firewall/router setup.

- **Credential leakage risk:** The server logs `password: <password>` on startup. This undermines “secure access” and should be documented as a current caveat or fixed in implementation later.

- **Session persistence risk:** Auth sessions are raw random tokens stored in `~/.wede/sessions.json`. There is no documented token expiration or server-side logout/revocation. Browser logout removes only localStorage.

- **WebSocket token risk:** Terminal passes auth token in query string for WebSocket connections. Reverse proxies and access logs commonly record URLs, so HTTPS/reverse-proxy docs should warn about log hygiene or implementation should move to a safer token transport.

- **No cloud dependency risk:** App runtime is mostly local, but external Google font links in `index.html` and remote assets/scripts in landing page complicate broad “no cloud” wording.

- **No database risk:** Runtime appears database-free, but the checked-in `database/` module contradicts the simple product story.

## Suggested Doc Updates

1. Update prerequisites:

   ```md
   Requirements for development:
   - Node.js 20.19+ or 22.12+
   - npm 10+
   - Go 1.25+ (or lower go.mod after testing)
   - git
   ```

2. Change README development setup from `npm install` to:

   ```bash
   npm ci
   npm run dev
   ```

3. Add full config search order:

   ```md
   wede searches for `wede.config.json` in:
   1. the current directory and parent directories
   2. `~/.config/wede/wede.config.json`
   3. the directory containing the `wede` executable
   ```

4. Clarify first-run config:

   ```md
   The install script creates `~/.config/wede/wede.config.json` with a random password. If you build from source or download a binary manually, create this file yourself before starting wede.
   ```

5. Add binding/security warning:

   ```md
   wede listens on all network interfaces for the configured port. For local-only use, rely on your firewall or run behind a reverse proxy that restricts access. Do not expose wede directly to the public internet without HTTPS and an access-control layer.
   ```

6. Replace “Secure Access” with a more precise claim:

   ```md
   Password-gated access with a 3-attempt process lockout. For production, run behind HTTPS and a reverse proxy, and treat wede as a privileged shell/file access service.
   ```

7. Add reverse proxy notes:

   ```md
   Reverse proxies must support WebSocket upgrades for `/api/terminal`. If using HTTPS, proxy WebSocket traffic as `wss://` and avoid logging query strings because terminal auth currently uses a token query parameter.
   ```

8. Add browser/preview limitations:

   ```md
   The built-in browser preview is an iframe. Apps that set `X-Frame-Options` or restrictive `Content-Security-Policy frame-ancestors` headers may not render inside wede. HTTPS deployments may also block HTTP preview targets as mixed content.
   ```

9. Narrow git wording:

   ```md
   Built-in visual commit graph, staging area, commits, branch list, and checkout.
   ```

10. Align landing `20+ languages` to README `10+ languages`, or add enough CodeMirror language modes to make the higher claim true.

11. Add troubleshooting section covering:
    - config not found
    - missing/weak password
    - 3-attempt lockout and restart requirement
    - port already in use
    - Vite frontend cannot connect to backend
    - terminal WebSocket fails behind proxy
    - iframe preview blocked
    - git repo not detected

12. Add screenshot maintenance note:

    ```md
    Screenshots were last refreshed on YYYY-MM-DD from commit <sha>.
    ```

## Followups / Ambiguities

- Should `wede/database/` remain in this repository? If yes, document why it exists despite the “no database” claim. If no, remove it in a future implementation ticket.

- Is Windows intended to be supported by released binaries? The install script contains Windows detection, but terminal PTY support should be verified before docs claim Windows support.

- Should the app support fully air-gapped use? If yes, remove external font dependencies from the shipped app or document that fonts gracefully fall back.

- Is `npm run lint` intended to be a contributor quality gate? If yes, it needs a fix ticket. If no, consider removing the script or documenting that build/go test are the current gates.

- Should production deployments expose only via reverse proxy, or should wede grow a configurable bind host such as `127.0.0.1`? Docs can warn now, but implementation support would make safe deployment easier.

- Should sessions expire or be revocable? Current docs do not mention session duration, and current logout does not revoke server-side tokens.
