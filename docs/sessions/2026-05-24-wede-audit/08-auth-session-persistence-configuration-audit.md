# Ticket 8: Auth, Session Persistence, and Configuration Audit

## Scope

Audited authentication, lockout behavior, persistent sessions, frontend token storage, WebSocket auth, config discovery, runtime options, install/docs credential handling, and config/session file permission posture.

Primary files reviewed:

- `wede/backend/internal/auth/auth.go`
- `wede/backend/internal/config/config.go`
- `wede/backend/cmd/wede/main.go`
- `wede/src/hooks/useAuth.js`
- `wede/src/components/Login.jsx`
- `wede/src/components/Settings.jsx`
- `wede/wede.config.json`
- `wede/README.md`

Supporting files reviewed:

- `wede/src/components/Terminal.jsx`
- `wede/backend/internal/terminal/terminal.go`
- `wede/install.sh`
- `wede/AGENTS.md`
- prior session report `docs/sessions/2026-05-24-wede-audit/06-terminal-websocket-lifecycle-audit.md`

No source changes were made.

## Commands Run

- `pwd && rg --files wede | sed -n '1,140p'`
- `git status --short`
- `sed -n ...` / `nl -ba ...` for audited source files
- `rg -n "token|Authorization|auth|password|WEDE_AUTH|wede.config|sessions|WebSocket|ws://|wss://" wede -S`
- `rg --files wede | rg '_test\.go$|\.test\.|__tests__'`
- `find docs/sessions/2026-05-24-wede-audit -maxdepth 1 -type f -print`
- `find wede -name AGENTS.md -print`
- `cd wede/backend && go test ./...`
- `stat -f '%Sp %N' wede/wede.config.json docs/sessions/2026-05-24-wede-audit || stat -c '%A %n' ...`
- `git status --short --untracked-files=all | sed -n '1,220p'`

Result: `cd wede/backend && go test ./...` passed. All backend packages currently report `[no test files]`.

## Threat Model

Assumptions for this audit:

- wede is primarily a self-hosted development tool run on localhost, a private machine, a NAS/Raspberry Pi, or a trusted local network.
- Authenticated access is powerful: the app exposes filesystem read/write, git mutation, and a browser terminal capable of running shell commands as the server user.
- The built-in password/token layer is suitable as a lightweight access gate for local/trusted deployments, not as a full Internet-facing identity system.
- Internet-facing use should require HTTPS, a reverse proxy or stronger auth layer, conservative origin policy, safer token handling, and explicit session expiry/revocation.
- `authDisabled` is acceptable only behind another trusted access-control layer or a loopback-only deployment. In local-network or public deployments it effectively exposes a remote shell and file manager.

Important tradeoff: the current implementation optimizes for simple single-user convenience. That is a reasonable product direction for local development, but the docs advertise server/NAS/Raspberry Pi deployment, so the security boundaries need to be explicit and the most dangerous credential exposures should be removed.

## Must-Fix Findings

### M1. Startup logs disclose the configured password

Evidence: `wede/backend/cmd/wede/main.go:82-87` logs `password: %s` whenever auth is enabled.

Impact: service managers, shell history captures, shared terminal sessions, cloud logs, screenshots, or support bundles can expose the reusable login secret. This is especially risky because sessions grant file write and terminal access.

Recommendation: do not log the configured password. For generated first-run credentials, print a one-time setup secret only when creating it, then require users to read/change the config file. Runtime logs should say auth is enabled and where config was loaded, without printing secret values.

### M2. Sessions persist indefinitely and logout does not revoke server-side tokens

Evidence: tokens are loaded from `~/.wede/sessions.json` on startup at `wede/backend/internal/auth/auth.go:40-59`, saved on login at `auth.go:63-69` and `auth.go:126-132`, and represented as `map[string]bool` with no expiry metadata. Frontend logout only removes `localStorage` at `wede/src/hooks/useAuth.js:84-88`; no backend logout/revoke endpoint exists.

Impact: any stolen token remains valid across browser restarts and server restarts until the sessions file is manually removed or auth is disabled/reconfigured. This is awkward for shared machines, lost devices, accidental browser sync/extensions exposure, and incident recovery.

Recommendation: add server-side session records with `createdAt`, `lastSeen`, optional user agent/device label, idle TTL, absolute max age, and a logout/revoke endpoint. At minimum, make persistence configurable and document how to clear all sessions.

### M3. WebSocket authentication uses long-lived bearer tokens in the URL query string

Evidence: frontend builds `/api/terminal?session=...&token=...` at `wede/src/components/Terminal.jsx:70-72`; auth middleware accepts query tokens at `wede/backend/internal/auth/auth.go:173-176`; terminal logs the session ID at `wede/backend/internal/terminal/terminal.go:206-212`.

Impact: query parameters are more likely than headers to appear in browser history, proxy/access logs, debug tooling, error telemetry, or screenshots. The token is long-lived, so accidental disclosure gives durable access.

Recommendation: prefer a short-lived WebSocket ticket minted over an authenticated HTTP request, then consumed once during upgrade. If query-token auth remains for compatibility, document the risk clearly, avoid logging request URLs, and make ticket TTL/replay behavior explicit.

### M4. Config and example credential handling are unsafe by default

Evidence: workspace `wede/wede.config.json` contains `"password": "admin"` and is mode `-rw-r--r--`; README examples use inline password values at `wede/README.md:72-82` and `README.md:107-122`; install creates `${HOME}/.config/wede/wede.config.json` at `wede/install.sh:117-122` without `chmod 600` or `umask 077`; config loader reads secrets without checking owner/mode at `wede/backend/internal/config/config.go:23-61`.

Impact: users may copy or deploy a weak default password, leave credentials world-readable on multi-user systems, or unknowingly run with a checked-in/project-local secret. Since authenticated users get shell/file access, config secrecy matters.

Recommendation: remove weak real-looking defaults from shipped config examples, generate strong credentials only during install/setup, write config files with `0600`, and have `config.Load` warn or fail when password-bearing config files are group/world-readable on platforms where mode checks are meaningful.

## Should-Fix Findings

### S1. Lockout is protective but recovery is coarse and easy to self-deny

Evidence: after three failed attempts, `locked` is set process-wide at `wede/backend/internal/auth/auth.go:106-115`; the UI says restart the server at `wede/src/components/Login.jsx:25-33`.

Impact: this slows brute force, but one client can lock out the only user until restart. If sessions persist indefinitely, existing tokens may still work while new logins are blocked. There is no cooldown, source-based tracking, or admin recovery command.

Recommendation: replace permanent process-wide lockout with a rate limiter or timed backoff, ideally by source IP/subnet plus global guardrail. Provide a documented recovery path such as delete lockout state, wait for cooldown, or use a local CLI reset.

### S2. Tokens in `localStorage` are convenient but should be an explicit threat-model choice

Evidence: `wede/src/hooks/useAuth.js:7`, `useAuth.js:19-33`, and `useAuth.js:71-73` store and reload `wede_token` in `localStorage`.

Impact: `localStorage` makes sessions survive reloads and browser restarts, but it is readable by any script running in the app origin. A future XSS bug, malicious browser extension, shared browser profile, or same-origin asset compromise can extract the bearer token.

Recommendation: decide and document the intended posture. For local-only single-user convenience, `localStorage` can be acceptable if docs say tokens are long-lived local secrets. For stronger deployments, prefer `HttpOnly`, `Secure`, `SameSite` cookies, shorter session lifetimes, and CSRF/origin protections.

### S3. Config lookup order is convenient but can surprise users in arbitrary project directories

Evidence: loader walks from current working directory up through parent dirs first at `wede/backend/internal/config/config.go:23-39`, then `~/.config/wede`, then executable directory at `config.go:41-61`; README only says it looks in current/parent dirs at `wede/README.md:103`.

Impact: running `wede` inside an unfamiliar repository can load a project-local `wede.config.json` before the user-level config. That file can set a weak password or `authDisabled`. This may be intended for per-project config, but the precedence and risk are not clearly documented.

Recommendation: document exact lookup order and precedence. Consider adding `--config`, `WEDE_CONFIG`, and a startup log that includes config path but never secrets. Consider requiring explicit confirmation or refusing `authDisabled` from project-local config unless opted in.

### S4. Config/session file errors and permissions are mostly ignored

Evidence: `os.UserHomeDir`, `os.MkdirAll`, `json.Marshal`, and `os.WriteFile` errors are ignored in `wede/backend/internal/auth/auth.go:28-69`; config loader reads files but does not inspect permissions at `wede/backend/internal/config/config.go:23-61`.

Impact: session persistence can silently fail, insecure permissions can go unnoticed, and users may believe they are protected by persisted sessions or config secrecy when they are not.

Recommendation: log non-secret operational errors, check directory/file modes where supported, fail closed for obviously unsafe password config files, and write session/config files atomically with restrictive modes.

### S5. Auth-disabled mode is a runtime option but not tightly constrained

Evidence: `WEDE_AUTH_DISABLED` overrides config at `wede/backend/internal/config/config.go:73-75`; disabled auth bypasses middleware at `wede/backend/internal/auth/auth.go:167-170`; README says only to use it behind another access-control layer at `wede/README.md:118-122`.

Impact: a misplaced environment variable or project config can expose all APIs, including terminal and file write, to anyone who can reach the port.

Recommendation: make disabled-auth startup logs loud and specific, document the exact risk, and consider refusing non-loopback binds when auth is disabled unless an explicit `--i-understand`-style option is supplied. Current server binds `":" + port` at `wede/backend/cmd/wede/main.go:81`, which listens on all interfaces.

## Docs-Only Findings

### D1. Deployment security boundary is underspecified

README says “self-hosted” and “deploy behind HTTPS reverse proxy for production” at `wede/README.md:43`, but it does not clearly define local-only, trusted-LAN, and Internet-facing modes.

Recommendation: add a short security model section:

- Localhost: built-in auth and persistent `localStorage` token are convenience features.
- Trusted LAN: use a strong password, understand bearer tokens, avoid shared browsers, protect config files.
- Internet-facing: require HTTPS, reverse proxy auth or stronger session settings, no auth-disabled mode, restrictive file permissions, and short-lived/revocable sessions.

### D2. Session lifecycle is undocumented

The docs do not say that sessions survive browser restart and server restart via `~/.wede/sessions.json`, or how to revoke them.

Recommendation: document where session tokens live, whether they expire, what logout means, and how to clear all sessions until a proper revoke API exists.

### D3. WebSocket query-token tradeoff is undocumented

The terminal uses WebSocket auth via query token because browser WebSocket APIs cannot set arbitrary headers. That tradeoff is not currently called out.

Recommendation: document that terminal access uses a bearer credential in the WebSocket URL today, advise HTTPS/reverse proxy log hygiene, and point to the planned short-lived-ticket approach if adopted.

### D4. Config lookup and file permission expectations need exact docs

README mentions current/parent directory lookup but not the full order, env override behavior, or recommended permissions.

Recommendation: document exact precedence: current/parents, `~/.config/wede/wede.config.json`, executable directory, then fatal. Include recommended `chmod 600 ~/.config/wede/wede.config.json` and warn against committing real passwords.

## Tests To Add

- `auth.Login`: correct password returns 64-hex-character token; wrong password returns remaining attempts; third failure locks; successful login resets failed attempts.
- `auth.Check`: valid header token authenticates; missing/invalid token does not; locked state is reported; query token behavior is covered while it exists.
- `auth.Middleware`: rejects missing/invalid token, accepts header token, accepts query token only if intentionally supported, and bypasses when auth is disabled.
- `auth` persistence: saved sessions reload after handler recreation; corrupt session file is handled safely; save/load errors are observable; expiry/revocation works after added.
- `auth` disabled mode: login/check responses include `authDisabled`, middleware bypasses, no session file is loaded/saved.
- `auth` lockout recovery/rate limit: timed cooldown or reset path, per-source behavior if implemented, and no permanent accidental denial.
- `config.Load`: exact lookup precedence, default port, missing password fatal when auth enabled, password optional when disabled, `WEDE_AUTH_DISABLED` override parsing, malformed JSON fatal.
- `config` permissions: group/world-readable password config warns/fails as chosen; install-created config uses `0600`; session file uses `0600`; directory creation uses `0700`.
- WebSocket auth integration: terminal route rejects unauthenticated upgrades, accepts intended auth path, rejects expired/replayed WS tickets after implemented.

## Followups / Ambiguities

- Is wede intended to be safe when bound to all interfaces on a trusted LAN by default, or should it default to loopback and require an explicit host/bind option for remote access? Recommendation: default loopback unless remote access is an explicit product goal.
- Should sessions be “remember me forever” by design? Recommendation: no. Use a bounded default, for example 12-24 hour absolute lifetime or 7-30 day optional remember-me, plus server-side revoke.
- Should logout terminate terminal sessions and revoke the token? Recommendation: yes for the simple model; detached terminal persistence should be an explicit advanced feature.
- Should project-local config be first priority? Recommendation: only if per-project config is a core workflow. Otherwise prefer user config first, or require `--config` for project-local auth settings.
- Is `authDisabled` intended for development only, reverse-proxy production, or both? Recommendation: support both only with explicit docs and a loud startup warning because the blast radius includes remote shell execution.
- Should generated credentials be shown after install? Recommendation: yes, once, if generated locally; do not log them on every server start, and write the config with restrictive permissions.
