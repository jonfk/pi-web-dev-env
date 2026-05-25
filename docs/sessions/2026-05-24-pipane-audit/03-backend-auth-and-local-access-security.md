# Ticket 3: Backend Auth and Local Access Security Review

Date: 2026-05-24
Scope:
- `pipane/src/server/server.ts`
- `pipane/src/server/auth-guard.test.ts`
- `pipane/src/server/rest-api.ts`
- `pipane/src/server/ws-handler.ts`
- Env vars: `PIPANE_AUTH_TOKEN`, `PIPANE_AUTH_DISABLED`, `PIPANE_DISABLE_LOCAL_BYPASS`, `PIPANE_SECURE_COOKIE`, `PIPANE_PUBLIC_URL`, `PI_PUBLIC_HOSTNAME`

Research only. No code, config, or test changes were made.

## Threat Model Summary

`pipane` is a privileged local development UI. A successful remote client can:

- Read session metadata, prompts, model selections, raw JSONL session files, and debug traces.
- Browse directory names anywhere the backend process can access.
- Modify local pipane settings under `~/.piweb/settings.json`.
- Delete arbitrary existing `.jsonl` files by absolute path.
- Drive WebSocket commands that start or control `pi` sessions, steer/abort/kill turns, fork sessions, compact sessions, list models/commands, and reload backend `pi` processes.

Expected safe modes should therefore be explicit:

- Local-only: loopback clients may bypass auth for convenience.
- Remote built-in auth: remote clients must know the auth URL token, receive the `pipane_auth` cookie, and then use same-origin HTTP/WS with that cookie.
- Reverse-proxy auth: safe only if the proxy fully enforces access control for both HTTP and `/ws`, forwards WebSocket upgrades, terminates HTTPS if cookies are sent over a public network, and the backend is not directly reachable except through that proxy.

The current implementation is close to a single-user local tool with lightweight bearer-token access, not a hardened multi-user or internet-facing auth system.

## Auth Flow Inventory

### Token and public URL construction

- `AUTH_TOKEN` is `PIPANE_AUTH_TOKEN` or a random 24-byte base64url token generated on process start (`server.ts:78-83`).
- `PUBLIC_URL` comes from `PIPANE_PUBLIC_URL`, otherwise `http://${PI_PUBLIC_HOSTNAME || hostname()}:${PORT}` (`server.ts:81-83`).
- Startup prints `Remote: ${AUTH_URL}` unless `PIPANE_AUTH_DISABLED=1`, where it prints the bare remote URL (`server.ts:411-414`).
- When the token is random, startup logs that it changes on restart and recommends `PIPANE_AUTH_TOKEN` for a fixed token (`server.ts:415-417`).

Security notes:

- The auth token is embedded in `/auth?token=...`, so it can land in terminal scrollback, browser history, screenshots, and reverse-proxy access logs.
- `PIPANE_PUBLIC_URL` controls only printed URL generation; it is not used for origin, host, cookie domain, or proxy trust checks.
- `PI_PUBLIC_HOSTNAME` defaults to OS hostname. This can print an unreachable or unexpected `http://hostname:port` URL, but it does not alter authorization.

### HTTP auth

- `PIPANE_AUTH_DISABLED=1` bypasses all built-in HTTP auth (`server.ts:115-120`, `server.ts:172-175`).
- Local bypass is enabled unless `PIPANE_DISABLE_LOCAL_BYPASS=1`; local means direct socket remote address exactly `127.0.0.1`, `::1`, or `::ffff:127.0.0.1` (`server.ts:99-107`).
- `/auth` accepts either a local request or a matching query token, sets the auth cookie, and redirects to `/` (`server.ts:158-169`).
- All later Express routes, including static files, REST endpoints, and debug pages, pass through the auth middleware before registration (`server.ts:172-185`, `server.ts:205-217`, `server.ts:291-342`).
- Authorized local HTTP requests automatically receive the auth cookie (`server.ts:177-180`).

### Cookie behavior

Cookie set by `setAuthCookie`:

```text
pipane_auth=<AUTH_TOKEN>; Path=/; HttpOnly; SameSite=Lax; Max-Age=2592000[; Secure]
```

Source: `server.ts:109-112`.

Assessment:

- Good: `HttpOnly` reduces script-readable token exposure.
- Good: `SameSite=Lax` is a reasonable default for normal navigation and same-site fetches.
- Risk: `Secure` is opt-in via `PIPANE_SECURE_COOKIE=1`, not inferred from `PIPANE_PUBLIC_URL=https://...` or proxy headers.
- Risk: cookie lifetime is 30 days and equals the server bearer token. There is no separate session identifier, expiry shorter than token lifetime, rotation endpoint, revocation, or logout.
- Risk/ambiguity: using `PIPANE_SECURE_COOKIE=1` with a TLS-terminating reverse proxy and plain HTTP backend is safe for browsers hitting the public HTTPS origin, but the backend has no awareness of `X-Forwarded-Proto`. Docs need to state that users must set this when the browser uses HTTPS.

### WebSocket auth

- `WsHandler` receives `isRequestAuthorized` from `server.ts`, so WS and HTTP use the same predicate (`server.ts:270-281`).
- On WS connection, unauthorized clients are accepted at the upgrade layer and then closed with code `1008` and reason `Unauthorized` (`ws-handler.ts:206-214`).
- Authorized WS clients receive an `init` message and can send commands (`ws-handler.ts:232-248`, `ws-handler.ts:297-345`).
- The browser client builds `ws://` or `wss://` from `window.location.protocol` and `window.location.host`, relying on the `pipane_auth` cookie for auth (`main.ts:579-586`).

HTTP vs WS match:

- Both HTTP and WS use `AUTH_DISABLED`, local bypass, and `pipane_auth` cookie checks.
- Neither accepts token auth directly on non-`/auth` HTTP routes or WS query parameters.
- WS has no Origin validation. With auth enabled, cookie `SameSite=Lax` should generally block cross-site WebSocket cookie attachment in modern browsers, but this should be validated in target browsers because WebSocket cookie/SameSite behavior has historically been a sharp edge. With auth disabled, any webpage that can reach the service may attempt a WS connection unless the proxy or network blocks it.

## Reverse Proxy Deployment Findings

Current README guidance is very thin:

- "Remote access is protected by an auth URL by default. Set `PIPANE_AUTH_TOKEN` to use a fixed token." (`README.md:40-44`)
- "If pipane is running behind a reverse proxy that handles authentication, set `PIPANE_AUTH_DISABLED=1`..." (`README.md:44`)

Missing guidance:

- Treat pipane as a privileged local file/session/agent-control service.
- Reverse proxy must protect both HTTP and `/ws`.
- Reverse proxy must support WebSocket upgrades for `/ws`.
- Backend should not be reachable directly when `PIPANE_AUTH_DISABLED=1`.
- For HTTPS public access, set `PIPANE_PUBLIC_URL=https://...` for correct printed URL and set `PIPANE_SECURE_COOKIE=1`.
- Consider `PIPANE_DISABLE_LOCAL_BYPASS=1` when a local reverse proxy fronts the service. Otherwise a proxy on the same host connecting to pipane over `127.0.0.1` causes every proxied request to look local to pipane and bypass built-in auth.
- Avoid logging query strings for `/auth?token=...` if using built-in auth through a proxy.

Important failure mode:

If a local reverse proxy connects to pipane over loopback and pipane's own auth is expected to protect remote users, the local bypass will authorize every proxied request because `req.socket.remoteAddress` is loopback (`server.ts:99-107`, `server.ts:115-120`). The safe combos are:

- Proxy handles auth: `PIPANE_AUTH_DISABLED=1`, backend bound/reachable only behind proxy.
- Pipane handles auth behind local proxy: set `PIPANE_DISABLE_LOCAL_BYPASS=1`.

## REST Exposure Findings

All REST endpoints are behind the global auth middleware unless auth is disabled or local bypass applies. After access is granted, guardrails are broad.

### Session listing and content

- `/api/sessions` returns absolute session paths, cwd, display cwd, first user prompt, timestamps, message count, and names (`rest-api.ts:110-116`; `session-index.ts:14-24`, `session-index.ts:219-230`).
- `/api/sessions/messages` reads any existing path ending in `.jsonl`, parses it, and returns messages/model/thinking level (`rest-api.ts:205-225`).
- `/api/sessions/fork-messages` reads any existing `.jsonl` and returns user message text plus entry IDs (`rest-api.ts:231-267`).
- `/api/sessions/raw` returns raw content from any existing `.jsonl` path (`rest-api.ts:273-286`).
- `/api/sessions` `DELETE` unlinks any existing path ending in `.jsonl` (`rest-api.ts:183-199`).

Finding: these endpoints are not constrained to `getAgentDir()/sessions`. An authorized client can read or delete arbitrary accessible `.jsonl` files anywhere on disk. This may be acceptable for a trusted local single-user tool, but it is a high-impact behavior if exposed remotely or if auth is disabled.

### Local settings

- `/api/settings/local` returns settings path, existence flag, validation errors, settings object, and formatted JSON (`rest-api.ts:118-124`; `local-settings.ts:139-146`).
- Validation, patch, and put endpoints accept and write local settings (`rest-api.ts:126-181`; `local-settings.ts:222-250`).

Finding: settings data is not currently secret, but it exposes the local settings path and lets any authorized client change UI/runtime-affecting local settings, including canvas enablement. This is expected for a trusted owner but should be documented as privileged.

### Directory browse

- `/api/browse` resolves `path` or `~` and returns non-hidden directory names and absolute paths for any accessible directory (`rest-api.ts:292-311`).

Finding: this is a filesystem enumeration endpoint. It does not read file contents, but it can disclose project and directory structure beyond pi sessions. It should be considered privileged.

### Debug traces and pool state

- `/api/debug/load-trace/event` lets clients write frontend events into trace storage by trace ID (`rest-api.ts:59-87`).
- `/api/debug/load-trace/latest` and `/:traceId` return recorded trace data (`rest-api.ts:89-107`).
- `/api/debug/pool` and `/debug/pool` expose process IDs, cwd, attached session paths, session statuses, pending request counts, and open WS count (`server.ts:291-342`; `ws-handler.ts:190-203`).

Finding: debug data can include sensitive local paths, session state, timing, and client-provided trace attrs. It is correctly behind the global guard, but should be included in the privileged surface docs.

## Test Coverage Matrix

| Scenario | Covered? | Evidence | Notes |
| --- | --- | --- | --- |
| Protected HTTP blocks unauthenticated when local bypass disabled | Yes | `auth-guard.test.ts:93-114` | Covers `/`, `/api/sessions`, `/debug/pool`. |
| Bad `/auth` token rejected | Yes | `auth-guard.test.ts:116-118` | Only HTTP status checked. |
| Good `/auth` token sets cookie and allows HTTP | Yes | `auth-guard.test.ts:120-128` | Does not assert cookie flags. |
| Unauthorized WS blocked when local bypass disabled | Yes | `auth-guard.test.ts:131-145` | Expects close code `1008`. |
| Cookie-authenticated WS allowed | Yes | `auth-guard.test.ts:147-166` | Checks `init` message. |
| Localhost bypass authorizes HTTP and sets cookie | Yes | `auth-guard.test.ts:170-186` | Does not cover localhost WS bypass. |
| Auth disabled allows HTTP | Yes | `auth-guard.test.ts:189-213` | Covers `/`, `/api/sessions`, `/debug/pool`. |
| Auth disabled allows WS | Yes | `auth-guard.test.ts:215-231` | Checks `init` message. |
| Remote unauthorized HTTP with actual non-loopback socket | Partial/No | Tests simulate by disabling local bypass, but still connect to `127.0.0.1` | Good unit coverage for predicate outcome, but not deployment-realistic remote address behavior. |
| Remote unauthorized WS with actual non-loopback socket | Partial/No | Same as above | Needs a non-loopback or injectable remote address test if feasible. |
| Reverse proxy over loopback with pipane auth enabled | No | Not covered | Important failure mode: local proxy makes remote clients look local unless `PIPANE_DISABLE_LOCAL_BYPASS=1`. |
| `PIPANE_SECURE_COOKIE=1` cookie flag | No | Not covered | Should assert `Secure`, `HttpOnly`, `SameSite=Lax`, `Max-Age`, `Path`. |
| HTTPS `PIPANE_PUBLIC_URL` without `PIPANE_SECURE_COOKIE` | No | Not covered | Should be documented or tested as warning behavior if warnings are added. |
| `PIPANE_PUBLIC_URL`/`PI_PUBLIC_HOSTNAME` startup URL generation | No | Not covered | Could be unit-tested if URL construction is extracted. |
| REST path confinement to agent sessions | No | Not covered | Current behavior is unconstrained; tests should pin intended behavior once decided. |
| WS Origin policy | No | Not covered | No origin check exists. Need decision before test. |

## Severity-Ranked Risks

### High: Local reverse proxy can accidentally bypass pipane built-in auth

Evidence: local bypass trusts `req.socket.remoteAddress` when not disabled (`server.ts:99-107`), and auth accepts local requests before checking cookies (`server.ts:115-120`). A reverse proxy on the same host commonly connects to the backend over `127.0.0.1`, making all proxied users appear local to pipane.

Impact: if operators expect pipane's built-in auth URL to protect a public reverse-proxied deployment but forget `PIPANE_DISABLE_LOCAL_BYPASS=1`, remote users may be fully authorized without the token.

Recommendation: document this loudly and consider startup warnings when `PIPANE_PUBLIC_URL` is non-local and local bypass remains enabled. Longer term, add explicit bind/proxy mode or disable local bypass automatically when a public URL is configured.

### High: Auth-disabled mode is a full privileged exposure unless the proxy is perfect

Evidence: `PIPANE_AUTH_DISABLED=1` returns true for all HTTP and WS authorization (`server.ts:115-117`, `server.ts:172-175`, `ws-handler.ts:210-214`). README recommends it behind a reverse proxy but does not state direct-backend reachability requirements (`README.md:40-44`).

Impact: if backend port is reachable from LAN/public internet, any client can read sessions, browse directories, mutate settings, delete `.jsonl` files, and control agent sessions.

Recommendation: document `PIPANE_AUTH_DISABLED=1` as safe only when another layer authenticates all HTTP and WS traffic and the backend is inaccessible except through that layer. Consider a startup warning that names the risk.

### Medium: Cookie `Secure` is opt-in and not tied to HTTPS public URL

Evidence: `Secure` is set only when `PIPANE_SECURE_COOKIE=1` (`server.ts:109-112`). `PIPANE_PUBLIC_URL` may be HTTPS, but cookie flags do not infer that (`server.ts:81-83`).

Impact: public HTTPS deployments can accidentally send a long-lived bearer cookie without `Secure` if any HTTP access path exists for the same host.

Recommendation: document required env combo for HTTPS reverse proxy: `PIPANE_PUBLIC_URL=https://...` plus `PIPANE_SECURE_COOKIE=1`. Consider warning when public URL starts with `https://` and secure cookie is not set.

### Medium: Long-lived bearer token appears in URL and cookie

Evidence: printed auth URL is `/auth?token=<AUTH_TOKEN>` (`server.ts:80-83`, `server.ts:411-417`); cookie stores the same token for 30 days (`server.ts:109-112`).

Impact: query-token leakage through browser/proxy logs or screenshots grants durable access until token rotation or restart for random tokens. Fixed `PIPANE_AUTH_TOKEN` increases durability across restarts.

Recommendation: document log hygiene. Longer term, make `/auth?token=` exchange the token for a distinct session cookie, preferably revocable and shorter-lived.

### Medium: REST session file endpoints accept arbitrary `.jsonl` paths

Evidence: read/delete endpoints only require `endsWith(".jsonl")` and `existsSync(sessionPath)` (`rest-api.ts:183-199`, `rest-api.ts:205-225`, `rest-api.ts:231-267`, `rest-api.ts:273-286`).

Impact: any authorized or bypassed client can read or delete non-session `.jsonl` files accessible to the backend user.

Recommendation: decide whether this is intended. If not, constrain paths to the agent sessions directory and add tests. If intended, document it as owner-level filesystem access.

### Medium: WebSocket has no Origin policy

Evidence: WS auth checks only the shared request predicate; no `Origin` handling appears in `ws-handler.ts:210-214` or `server.ts:115-120`.

Impact: with auth disabled, any reachable browser origin can attempt a WS connection. With auth enabled, risk depends on cookie SameSite behavior and browser/proxy conditions; this needs validation.

Recommendation: define trusted-origin expectations. Consider rejecting cross-origin WS requests unless explicitly configured.

### Low: Remote URL env vars are presentation-only

Evidence: `PIPANE_PUBLIC_URL` and `PI_PUBLIC_HOSTNAME` only build printed URLs (`server.ts:81-84`, `server.ts:411-412`).

Impact: operators may assume these configure host binding, allowed host, cookie scope, or proxy trust. They do not.

Recommendation: document what these vars do and do not do.

## Follow-Ups

1. Decide whether pipane is strictly single-user local software or supports remote multi-user/shared deployments. Current behavior fits trusted single-user best.
2. Decide if local bypass should remain enabled by default when `PIPANE_PUBLIC_URL` is non-loopback or when running behind a reverse proxy.
3. Decide whether REST session path parameters should be restricted to `getAgentDir()/sessions`.
4. Add tests for cookie attributes, including `PIPANE_SECURE_COOKIE=1`.
5. Add deployment tests or integration fixtures for reverse-proxy-over-loopback behavior.
6. Add documentation for secure reverse proxy configuration: HTTPS, `/ws` upgrade, `PIPANE_DISABLE_LOCAL_BYPASS=1` when relying on pipane auth, backend not directly reachable when `PIPANE_AUTH_DISABLED=1`, and query-string log hygiene.
7. Validate WebSocket SameSite/cross-origin behavior in target browsers, then add or intentionally skip an Origin policy based on the threat model.

