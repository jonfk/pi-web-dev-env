# Backend Security Boundary Audit

## Scope

Ticket 1 from `docs/sessions/2026-05-21-wede-codebase-health-audit.md`.

Reviewed Go backend security boundaries for filesystem, workspace selection, terminal/WebSocket, Git operations, auth/session handling, config, and browser-facing API route exposure.

Primary files reviewed:

- `wede/backend/cmd/wede/main.go`
- `wede/backend/internal/auth/auth.go`
- `wede/backend/internal/files/files.go`
- `wede/backend/internal/workspace/workspace.go`
- `wede/backend/internal/terminal/terminal.go`
- `wede/backend/internal/git/git.go`
- `wede/backend/internal/config/config.go`
- Browser-facing frontend call sites were spot-checked for token and terminal behavior: `wede/src/hooks/useAuth.js`, `wede/src/components/Terminal.jsx`, `wede/src/components/TerminalPanel.jsx`.

No source code changes were made.

## Commands Run

```bash
pwd
sed -n '1,240p' docs/sessions/2026-05-21-wede-codebase-health-audit.md
rg --files wede/backend
nl -ba wede/backend/cmd/wede/main.go
nl -ba wede/backend/internal/auth/auth.go
nl -ba wede/backend/internal/files/files.go
nl -ba wede/backend/internal/workspace/workspace.go
nl -ba wede/backend/internal/terminal/terminal.go
nl -ba wede/backend/internal/git/git.go
nl -ba wede/backend/internal/config/config.go
rg -n "HandleFunc|/api/|websocket|Upgrade|Authorization|token|exec.Command|os\.|filepath|RemoveAll|Rename|WriteFile|ReadFile|ReadDir|MkdirAll" wede/backend
find wede/backend -name '*_test.go' -print
go test ./...
go test -race ./...
rg -n "api/terminal|api/files|api/workspace|api/git|Authorization|token=|authDisabled|localStorage|WebSocket" wede/src wede/backend/cmd/wede/frontend_dev.go wede/backend/cmd/wede/frontend_embed.go wede/README.md wede/wede.config.json
nl -ba wede/backend/cmd/wede/frontend_dev.go
nl -ba wede/backend/cmd/wede/frontend_embed.go
find wede -maxdepth 2 -name 'wede.config.json' -print -exec nl -ba {} \;
nl -ba wede/src/components/Terminal.jsx | sed -n '60,80p'
nl -ba wede/src/hooks/useAuth.js | sed -n '1,110p'
nl -ba wede/README.md | sed -n '112,124p'
nl -ba wede/src/components/TerminalPanel.jsx | sed -n '1,90p'
nl -ba wede/src/components/TerminalPanel.jsx | sed -n '145,170p'
test -d docs/sessions/2026-05-24-wede-audit
git status --short
ls -la docs/sessions/2026-05-24-wede-audit
```

Test results:

- `go test ./...` passed after rerun with normal Go build-cache access. Initial sandboxed run reached package checks but failed while trimming `/Users/jfokkan/Library/Caches/go-build/trim.txt`.
- `go test -race ./...` passed after rerun with normal Go build-cache access. Initial sandboxed run failed for the same cache permission reason.
- `find wede/backend -name '*_test.go' -print` returned no files, so these commands did not exercise backend behavior beyond compilation/package loading.

## Route Coverage

| Route | Handler | Auth | Boundary notes |
|---|---|---:|---|
| `POST /api/auth/login` | `auth.Handler.Login` | Public | Password check, lockout after 3 failures, creates persistent bearer token in `~/.wede/sessions.json`. |
| `GET /api/auth/check` | `auth.Handler.Check` | Public | Accepts bearer token from `Authorization` header or `token` query parameter. |
| `GET /api/workspace` | `workspace.Manager.HandleGet` | Protected unless auth disabled | Returns current workspace and recent absolute paths. |
| `POST /api/workspace/open` | `workspace.Manager.HandleOpen` | Protected unless auth disabled | Authenticated user may select any existing local directory visible to the backend process. |
| `GET /api/workspace/browse` | `workspace.Manager.HandleBrowse` | Protected unless auth disabled | Authenticated user may browse directories from home or `/`; returns absolute directory paths. |
| `GET /api/files` | `files.Handler.List` | Protected unless auth disabled | Uses `safePath`; vulnerable to prefix and symlink boundary issues. |
| `GET /api/files/read` | `files.Handler.Read` | Protected unless auth disabled | Uses `safePath`; follows symlinks; 10 MB size check uses `os.Stat`, which follows symlinks. |
| `PUT /api/files/write` | `files.Handler.Write` | Protected unless auth disabled | Uses `safePath`; follows symlink targets; creates parent directories. |
| `POST /api/files/create` | `files.Handler.Create` | Protected unless auth disabled | Uses `safePath`; follows symlink parent directories. |
| `DELETE /api/files/delete` | `files.Handler.Delete` | Protected unless auth disabled | Uses `safePath`; blocks exact workspace root string; `os.RemoveAll` on symlink path removes the symlink itself, but prefix/root checks are weak. |
| `POST /api/files/rename` | `files.Handler.Rename` | Protected unless auth disabled | Uses `safePath` for both paths; follows symlink parent dirs for destination. |
| `GET /api/git/status` | `git.Handler.Status` | Protected unless auth disabled | Runs fixed Git arguments in workspace. |
| `GET /api/git/log` | `git.Handler.Log` | Protected unless auth disabled | User-controlled `count` is passed to `git log -n` without validation. |
| `GET /api/git/diff` | `git.Handler.Diff` | Protected unless auth disabled | Uses `--` before user-controlled file path. |
| `POST /api/git/stage` | `git.Handler.Stage` | Protected unless auth disabled | User-controlled path passed to `git add` without `--` or path validation. |
| `POST /api/git/unstage` | `git.Handler.Unstage` | Protected unless auth disabled | Uses `--` before user-controlled path. |
| `POST /api/git/commit` | `git.Handler.Commit` | Protected unless auth disabled | Message passed as one argv element; no shell injection observed. |
| `GET /api/git/branches` | `git.Handler.Branches` | Protected unless auth disabled | Fixed Git arguments. |
| `POST /api/git/checkout` | `git.Handler.Checkout` | Protected unless auth disabled | User-controlled ref passed to `git checkout` without validation or option terminator. |
| `GET /api/terminal/sessions` | `terminal.Handler.ListSessions` | Protected unless auth disabled | Reveals active terminal session IDs. |
| `GET /api/terminal` | `terminal.Handler.HandleWS` | Protected unless auth disabled | WebSocket terminal. Accepts token in query via middleware, accepts all origins, predictable/reusable session IDs. |
| `/` and other non-API paths | frontend handler | Public | Serves app shell/static frontend. |

## Findings Table

| Severity | Finding | Affected file/line | Exploitability | Recommended fix |
|---|---|---|---|---|
| Critical | File boundary can be bypassed through prefix collision in `safePath`. `strings.HasPrefix(full, ws)` treats sibling paths such as `/tmp/workspace2/file` as inside `/tmp/workspace` when reached through `../workspace2/file`. | `wede/backend/internal/files/files.go:45-58` | Any authenticated user, or anyone when `authDisabled` is true, can read/write/create/delete/rename outside the selected workspace if a sibling path shares the workspace string prefix. | Resolve workspace and requested path to canonical absolute paths, then enforce containment with `filepath.Rel` and reject `rel == ".."` or `strings.HasPrefix(rel, "../")`. Add path-separator-aware checks and tests for `/tmp/ws` vs `/tmp/ws2`. |
| Critical | File APIs follow symlinks out of the workspace. `os.Stat`, `os.ReadFile`, `os.WriteFile`, `os.MkdirAll`, and `os.Rename` are reached after lexical path checks only. | `wede/backend/internal/files/files.go:75`, `125`, `138`, `174-177`, `202-215`, `247`, `280-283` | Any authenticated user can read or overwrite files outside the workspace by creating or using a symlink inside the workspace, for example `link -> /etc` or `link -> $HOME/.ssh`. With auth disabled this is unauthenticated local-network/browser-origin reachable. | Decide symlink policy explicitly. For a strict workspace boundary, evaluate each path component with `Lstat`/`EvalSymlinks`, reject symlink escapes, and use canonical containment checks on the final target and parent directory before writes/renames. |
| High | WebSocket terminal accepts all origins and becomes drive-by reachable when auth is disabled. | `wede/backend/internal/terminal/terminal.go:18-20`, `wede/backend/internal/auth/auth.go:167-170`, `wede/README.md:118-122` | If `authDisabled` is enabled, any webpage loaded in the user's browser can open `ws://localhost:9090/api/terminal?session=...` and send shell input because browsers do not apply CORS to WebSockets the same way as fetch. With auth enabled, the same origin weakness magnifies any query-token leak. | Enforce an origin allowlist for configured host/localhost or require a CSRF-style WebSocket nonce issued to the frontend. When `authDisabled` is true, require explicit host binding/reverse-proxy mode or disable terminal unless a trusted-origin setting is configured. |
| High | Terminal sessions are predictable and hijackable by session ID once a caller is authorized. Session IDs are frontend-generated as `term-1`, `term-2`, etc.; `/api/terminal/sessions` lists them; reconnecting replaces the old connection and replays scrollback. | `wede/src/components/TerminalPanel.jsx:25-29`, `49-63`, `157-164`; `wede/backend/internal/terminal/terminal.go:116-124`, `184-197`, `206-237` | Any authenticated caller can list session IDs, connect to another active terminal session, detach the legitimate UI, read scrollback, and send commands. This is most serious if multiple people share one backend or a token leaks. | Generate high-entropy server-side terminal IDs, bind each terminal session to the authenticated session token that created it, and require ownership on reconnect/list. Avoid using bearer tokens as fallback terminal session IDs. |
| High | Session tokens are persistent bearer secrets with no expiry, rotation, revocation endpoint, or scope. Logout only removes localStorage; server-side tokens remain valid in `~/.wede/sessions.json` across restarts. | `wede/backend/internal/auth/auth.go:50-69`, `128-135`; `wede/src/hooks/useAuth.js:84-88` | Anyone who obtains a token keeps full filesystem/Git/terminal access until `sessions.json` is manually deleted or the password/config/auth implementation changes. | Store session metadata with creation/last-used timestamps, add logout/revoke-all endpoints, expire old tokens, rotate on login if appropriate, and scope tokens to terminal session ownership where applicable. |
| Medium | Token-in-query support exposes bearer tokens to URLs. Auth middleware and check accept `?token=...`; terminal frontend sends token in the WebSocket URL. | `wede/backend/internal/auth/auth.go:150-153`, `172-176`; `wede/src/components/Terminal.jsx:70-72` | Query tokens can appear in browser tooling, proxy logs, crash reports, or referrers in some deployments. The current server does not log full URLs, but reverse proxies commonly do. | Prefer cookie auth with `SameSite` or a short-lived WebSocket ticket minted over authenticated fetch. If query support remains, restrict it to WebSocket upgrade only and make tickets single-use/short-lived. |
| Medium | Password is printed to logs on startup, and the checked-in example config uses `admin`. | `wede/backend/cmd/wede/main.go:81-87`; `wede/wede.config.json:1-4` | Anyone with process logs can authenticate. The committed default password makes accidental exposed deployments especially risky. | Do not log configured passwords. On first run, generate a random password once or require explicit setup. Replace the checked-in example with a non-secret template or documentation-only sample. |
| Medium | Workspace browse/open intentionally allow authenticated users to enumerate and select any local directory, not a preconfigured root. | `wede/backend/internal/workspace/workspace.go:143-170`, `173-252` | An authenticated user can switch the selected workspace to `$HOME`, `/`, or any readable directory, then use file/Git/terminal APIs from there. This may be acceptable for a single-user local IDE, but it is not a workspace sandbox. | Document this as the trust model or add an optional allowed-root setting. If a selected workspace is meant to be a boundary, enforce it in workspace open/browse as well as file APIs. |
| Medium | Git user inputs are not consistently separated from options or validated. `git add` receives the user path without `--`; `git checkout` receives a user-controlled ref as a possible option/ref; log `count` is unbounded. | `wede/backend/internal/git/git.go:139-145`, `197-218`, `295-311` | No shell injection was found because `exec.Command` passes argv directly. However, crafted paths/refs beginning with `-` can be interpreted as Git options, checkout can perform unintended destructive modes, and large counts can cause resource use. | Use `git add -- <path>`, validate checkout targets against known branch/hash entries or use explicit modes, and parse/clamp log count to a small integer range. Reject malformed JSON instead of silently decoding zero values. |
| Low | Auth lockout is global, permanent until restart, and not time-based. | `wede/backend/internal/auth/auth.go:82-123` | A remote attacker can deny login after 3 wrong attempts if the server is reachable. Existing sessions continue to work. | Add IP/session-aware rate limiting or timed lockout; provide an admin-safe unlock path. |
| Low | Error responses disclose local absolute paths and command output in several places. | `wede/backend/internal/workspace/workspace.go:70-75`, `160-163`; `wede/backend/internal/files/files.go:75-79`, `177-180`, `247-250`, `283-286`; `wede/backend/internal/git/git.go:212-216`, `236-240`, `259-263` | Authenticated users already have broad local access, but these messages increase path and environment disclosure, especially with auth disabled or shared deployments. | Return generic client errors and log detailed errors locally with redaction. |
| Low | Session token generation ignores `rand.Read` errors. | `wede/backend/internal/auth/auth.go:128-130` | Rare on normal systems, but crypto failures should not silently produce weak/empty material. | Check the error from `rand.Read` and fail login with a server error if randomness is unavailable. |

## Evidence/Repro Notes

### Filesystem prefix collision

Current containment check:

```go
cleaned := filepath.Clean(reqPath)
full := filepath.Join(ws, cleaned)
if !strings.HasPrefix(full, ws) {
    return "", false
}
```

Concrete repro shape:

1. Start with selected workspace `/tmp/wede-ws`.
2. Ensure sibling `/tmp/wede-ws2/secret.txt` exists.
3. Request `GET /api/files/read?path=../wede-ws2/secret.txt`.
4. `filepath.Join("/tmp/wede-ws", "../wede-ws2/secret.txt")` resolves lexically to `/tmp/wede-ws2/secret.txt`.
5. `strings.HasPrefix("/tmp/wede-ws2/secret.txt", "/tmp/wede-ws")` is true, so the file is treated as inside the workspace.

This affects read, write, create, delete, and rename because they all use `safePath`.

### Filesystem symlink escape

Concrete repro shape:

1. Selected workspace contains `outside -> /tmp/outside` symlink.
2. `GET /api/files/read?path=outside/secret.txt` passes lexical `safePath`.
3. `os.Stat` and `os.ReadFile` follow the symlink and read `/tmp/outside/secret.txt`.
4. `PUT /api/files/write` to the same path follows the symlink target and writes outside the workspace.

This is not cleared by the current code. `os.RemoveAll` on a symlink path generally removes the symlink rather than recursively deleting the target, but delete still inherits the prefix-collision problem.

### Workspace root edge cases

`Delete` blocks only `full == h.workspace()` at `wede/backend/internal/files/files.go:241`. With workspace `/`, `safePath` treats almost all absolute-looking results as prefixed by `/`; however, workspace selection itself can intentionally be `/` via `POST /api/workspace/open`, so the product currently allows root-as-workspace for authenticated users. If root workspaces should be disallowed, that belongs in workspace open validation.

### Terminal/WebSocket behavior

The terminal upgrader uses `CheckOrigin: func(...) bool { return true }`. The frontend sends terminal URLs like:

```js
const params = new URLSearchParams({ session: sid || 'default' })
if (token && !authDisabled) params.set('token', token)
const ws = new WebSocket(`${protocol}//${host}/api/terminal?${params.toString()}`)
```

Terminal session IDs are predictable (`term-${t.id}`), persisted in browser localStorage, listed by `/api/terminal/sessions`, and reconnecting attaches to the existing PTY while closing any old connection.

### Auth storage and disabled-auth behavior

Sessions are stored as raw tokens in `~/.wede/sessions.json` with mode `0600`. There is no server-side logout path, expiry, or revocation. `authDisabled` bypasses the middleware entirely for every `/api/` route. The README says to use it only behind another access-control layer, which is good documentation, but the terminal WebSocket origin behavior makes this especially sharp for browser-local threat models.

### Git argument handling

Git calls use `exec.Command`, so shell metacharacter injection was not observed. The remaining issue is Git option/ref interpretation and resource bounds:

- `git add <path>` lacks `--`.
- `git checkout <branch>` accepts one user-controlled argument that can be an option-like value or arbitrary ref.
- `git log ... -n <count> --all` accepts unparsed user input and has no upper bound.

## Followups/Ambiguities

- Is `wede` intended to be strictly single-user local software, or can multiple users share one backend through a reverse proxy? This decides whether terminal session ownership is critical or merely defense-in-depth.
- Should a selected workspace be a security sandbox, or is authenticated access equivalent to local user access to the entire machine? The current workspace browser/open API implements the latter.
- Should symlinks inside a workspace be editable as normal project files, blocked entirely, or allowed only when their canonical target remains inside the workspace?
- Is `authDisabled` meant for localhost-only development, production reverse-proxy deployments, or both? The safe defaults differ.
- Should terminal be available when `authDisabled` is true? It is the route most affected by cross-origin WebSocket behavior.

## Tests To Add First

1. `files.safePath` rejects sibling-prefix traversal: workspace `/tmp/ws`, request `../ws2/file`.
2. File read/write/create/rename reject symlink escapes where the final path or parent directory resolves outside the workspace.
3. File delete cannot delete outside the workspace via prefix collision and cannot delete the selected workspace root through cleaned path variants.
4. Workspace open/browse tests documenting whether `/`, `$HOME`, and arbitrary absolute paths are allowed or blocked by policy.
5. Terminal WebSocket rejects untrusted `Origin` values when auth is enabled and when auth is disabled.
6. Terminal session ownership test: token/session A cannot attach to or list token/session B's PTY after server-side ownership is added.
7. Auth session lifecycle tests for login, check, persisted reload, logout/revocation, expiry, and disabled-auth middleware behavior.
8. Git handler tests verifying `git add -- <path>`, checkout target validation, malformed JSON rejection, and log count clamping.
9. Config/startup test or integration check that configured passwords are never logged.

