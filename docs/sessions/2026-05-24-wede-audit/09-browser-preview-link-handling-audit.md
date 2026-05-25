# Ticket 9: Browser Preview and Link Handling Audit

## Scope

Audited the embedded browser preview, iframe sandbox policy, URL handling, global link interception, cross-origin tolerance, and Vite development proxy behavior for `wede`.

Primary files reviewed:

- `wede/src/components/Browser.jsx`
- `wede/src/components/IDE.jsx`
- `wede/vite.config.js`

Supporting files reviewed:

- `wede/src/components/Terminal.jsx`
- `wede/backend/cmd/wede/main.go`
- `wede/backend/cmd/wede/frontend_dev.go`
- `wede/backend/cmd/wede/frontend_embed.go`
- `wede/package.json`

No source code changes were made.

## Commands Run

- `pwd && rg --files -g 'Browser.jsx' -g 'IDE.jsx' -g 'vite.config.js' -g 'package.json' -g '*test*' -g '*spec*'`
- `git status --short`
- `sed -n '1,240p' wede/src/components/Browser.jsx`
- `sed -n '1,280p' wede/src/components/IDE.jsx`
- `sed -n '280,620p' wede/src/components/IDE.jsx`
- `sed -n '1,220p' wede/vite.config.js`
- `cat wede/package.json`
- `rg -n "urlToName|openBrowser|Browser|sandbox|iframe|proxy|X-Frame|frame|navigate|href|target=|contentWindow|postMessage" wede/src wede/backend wede/vite.config.js`
- `rg -n "9090|5173|embed|dist|static|/api|websocket|proxy|Serve|FileServer|frontend" wede/backend wede -g '!node_modules' -g '!dist'`
- `find wede/backend -maxdepth 4 -type f | sort`
- `sed -n '1,130p' wede/backend/cmd/wede/frontend_dev.go`
- `sed -n '1,120p' wede/backend/cmd/wede/frontend_embed.go`
- `sed -n '1,130p' wede/backend/cmd/wede/main.go`
- `sed -n '1,110p' wede/src/components/Terminal.jsx`
- `npm run build` from `wede`
- `git status --short`
- `git status --short` from `wede`
- `git check-ignore -v dist || true` from `wede`
- `nl -ba wede/src/components/Browser.jsx | sed -n '1,120p'`
- `nl -ba wede/src/components/IDE.jsx | sed -n '108,154p'`
- `nl -ba wede/vite.config.js | sed -n '1,80p'`
- `nl -ba wede/src/components/Terminal.jsx | sed -n '60,76p'`

Build result: `npm run build` completed successfully. Vite emitted the existing large chunk warning for the main JavaScript bundle.

## Sandbox Permission Assessment

Current iframe sandbox:

```jsx
sandbox="allow-same-origin allow-scripts allow-forms allow-popups allow-modals allow-top-navigation-by-user-activation"
```

Location: `wede/src/components/Browser.jsx:59-76`.

Permission assessment:

- `allow-scripts`: Needed for realistic local app previews. Most React/Vite/browser apps require JavaScript, so removing this would make the preview unusable for the main workflow.
- `allow-same-origin`: Useful for realistic local app behavior, cookies, local storage, same-origin fetches, and avoiding opaque-origin breakage. However, combined with `allow-scripts`, this is the highest-risk pair because same-origin preview pages can run as their normal origin instead of an opaque sandbox origin.
- `allow-forms`: Reasonable for previewing login forms, demos, and local app workflows. It increases interaction capability but is expected in a browser preview.
- `allow-popups`: Not strictly necessary for an embedded preview. It allows previewed content to open popup windows. If retained, consider adding `allow-popups-to-escape-sandbox` only if external auth/docs flows must work exactly like a normal browser; otherwise keep popup behavior constrained or remove this permission.
- `allow-modals`: Usually not required for app preview. It allows previewed content to call modal APIs such as `alert`, `confirm`, and `prompt`, which can interrupt the IDE. Recommend removing unless a known preview workflow depends on modal dialogs.
- `allow-top-navigation-by-user-activation`: Risky for an IDE shell. It permits a user-click inside previewed content to navigate the top-level wede page away. This can surprise users and lose IDE context. Recommend removing by default and routing external/full-page navigations through the explicit external-open button instead.

Current missing permissions appear intentionally restrictive:

- No `allow-downloads`, so previewed content should not be able to trigger downloads through the sandbox permission.
- No `allow-pointer-lock`, `allow-orientation-lock`, `allow-presentation`, or similar specialized capabilities.

Security concern: when the preview loads the same origin as the IDE, especially `http://localhost:9090` in production or `http://localhost:5173` in frontend dev, `allow-scripts allow-same-origin` lets previewed content execute with that origin. A same-origin iframe may be able to interact with `window.parent` or reachable same-origin DOM/storage in ways a cross-origin preview cannot. This matters if users preview untrusted local content or accidentally point the preview at the wede app itself.

Recommended default sandbox:

```text
allow-scripts allow-forms allow-same-origin
```

Optionally add `allow-popups` if the product intentionally supports popup-based flows from the preview. Avoid `allow-modals` and `allow-top-navigation-by-user-activation` unless there is a documented user story that requires them.

## Navigation and Link Interception Findings

### Address bar URL handling

Location: `wede/src/components/Browser.jsx:16-25`.

The address bar trims input and prepends `http://` unless the value starts with lowercase `http://` or `https://`.

Findings:

- `localhost:3000`, `127.0.0.1:5173`, and `0.0.0.0:8080` become HTTP URLs and should work for typical local preview.
- `example.com` becomes `http://example.com`, not HTTPS. That is convenient for localhost but surprising for public sites in 2026, where HTTPS is usually expected.
- Uppercase schemes such as `HTTPS://example.com` are incorrectly rewritten to `http://HTTPS://example.com`.
- Invalid strings are accepted and passed directly to the iframe. The user gets browser-native failure behavior, but no IDE-level validation or feedback.
- Non-HTTP schemes are not intentionally supported. `file:`, `about:`, `data:`, `javascript:`, and custom protocols are rewritten into malformed HTTP URLs rather than explicitly rejected or handled.
- The external-open anchor uses `loadedUrl` directly at `Browser.jsx:52`; if `loadedUrl` is malformed, the external button inherits that malformed target.

Recommendation: centralize URL parsing with the `URL` constructor, normalize schemes case-insensitively, and explicitly allow only `http:` and `https:`. For bare hosts, prefer:

- `http://` for localhost, loopback, and private development hosts.
- `https://` for public-looking domains.

If that heuristic feels too magical, a conservative alternative is to keep the current `http://` default but show validation errors for malformed URLs and reject unsupported schemes explicitly.

### Iframe navigation state

Location: `wede/src/components/Browser.jsx:65-75`.

The iframe `onLoad` attempts to read `contentWindow.location.href` and updates the tab URL if readable. Cross-origin access errors are swallowed.

Findings:

- This is tolerant of cross-origin pages and avoids crashing the IDE.
- Cross-origin in-frame navigations will not update the address bar because the parent cannot read `location.href`.
- Same-origin preview navigation can update the address bar.
- There is no visible load error state for frame-blocked HTTPS sites, DNS failures, CSP/X-Frame-Options denial, mixed content blocking, or invalid URLs. The iframe may show browser-native blank/error content, but the IDE does not explain what happened.

Recommendation: keep the cross-origin try/catch, but add explicit user-facing preview states for common failures where feasible: invalid URL, unsupported scheme, and sites that refuse iframe embedding. Some frame-blocking cases are difficult to detect perfectly from the parent, so the UI should avoid overpromising.

### Global anchor interception

Location: `wede/src/components/IDE.jsx:132-153`.

The IDE installs capture-phase handlers for `click` and `auxclick` on `document`. Any anchor whose raw `href` attribute starts with lowercase `http://` or `https://` is prevented and opened in the single browser preview tab.

Findings:

- This will intercept normal links in the IDE chrome, such as Settings footer credits.
- It overrides expected browser behavior for Cmd/Ctrl-click, Shift-click, target `_blank`, and middle-click. The comment explicitly notes capture is used before browser ctrl-click behavior.
- It does not check `event.defaultPrevented`, mouse button, modifier keys, `download`, `target`, same-page anchors, or whether the link lives in an area that opted into interception.
- It only matches lowercase absolute HTTP(S) attributes. Browser-normalized `a.href` might be HTTP(S), but the raw attribute `HTTPS://...` or protocol-relative `//example.com` will not be intercepted.
- Because there is only one browser tab, clicking a link anywhere in the IDE silently navigates the existing preview tab rather than opening a new tab/window. That can be surprising and can replace a user’s active local preview.
- Links inside cross-origin iframe content are not intercepted by this handler, because the listener is on the parent document. Those links follow iframe sandbox behavior instead.

Recommendation: narrow interception to intentional surfaces. Good options:

1. Remove global interception and let normal links behave normally. Add explicit "open in preview" actions where useful.
2. Intercept only plain left-clicks without modifier keys, and only from specific IDE-rendered content that wants preview behavior.
3. Respect `target="_blank"`, `download`, `event.defaultPrevented`, non-left clicks, and Cmd/Ctrl/Shift/Alt modifiers.

For an IDE, option 2 is the best balance: predictable default browser behavior, plus preview convenience in selected contexts.

## Manual Scenario Notes

These notes are based on code inspection and build verification; no source changes were made.

### Local app preview

Scenario: user opens the browser tab and enters `localhost:3000`.

Expected current behavior:

- The input normalizes to `http://localhost:3000`.
- The iframe loads that URL with scripts, forms, same-origin behavior, popups, modals, and top navigation by user activation allowed.
- If the local app is cross-origin relative to wede, the parent cannot read in-frame navigation changes; the address bar may remain stale after app navigation.
- If the local app opens `_blank` or popup flows, sandbox popup permission allows popups.
- If the local app uses `alert`/`confirm`, modals are allowed and may interrupt the IDE.

Risk note: if the local preview points at the same origin as wede itself, the current `allow-scripts allow-same-origin` combination is much more permissive than a typical isolated preview. Avoid previewing untrusted same-origin content under this policy.

### External HTTPS preview

Scenario: user opens the browser tab and enters `https://example.com`.

Expected current behavior:

- The iframe attempts to load the HTTPS URL.
- Cross-origin URL reads throw and are swallowed, so the IDE remains stable.
- Sites that deny embedding through `X-Frame-Options` or CSP `frame-ancestors` will not render normally. The UI does not currently explain this.
- In-frame links are governed by the iframe sandbox, not by the parent document's global link handler.
- A user click in the previewed page may be able to trigger top-level navigation because `allow-top-navigation-by-user-activation` is present.

UX note: for many external HTTPS sites, the explicit external-open button may be the more reliable path than embedded preview because many production sites block framing.

## Vite Dev Proxy and Production Match

Location: `wede/vite.config.js:10-17`.

The Vite dev server proxies `/api` to `http://localhost:9090` with `changeOrigin: true` and `ws: true`.

Findings:

- HTTP API paths match production shape reasonably well: frontend code calls `/api/...`, Vite proxies in dev, and the Go backend serves `/api/...` directly in production.
- Terminal websocket behavior does not actually rely on the Vite proxy in dev. `Terminal.jsx:66-72` special-cases ports `5173` and `5174` to connect directly to `hostname:9090`.
- Because the websocket direct-connect logic only special-cases `5173` and `5174`, dev servers on other Vite ports would use the Vite host and may fail unless the proxy handles the websocket exactly as expected.
- `changeOrigin: true` differs from production, where requests naturally hit the backend origin. That is usually acceptable for local dev, but it can hide origin-sensitive behavior.
- The browser preview itself does not proxy arbitrary preview URLs. A previewed local app must be reachable directly from the user's browser.

Recommendation: either rely consistently on Vite proxy websocket support or document/centralize the direct backend websocket host rule so dev ports beyond `5173`/`5174` do not drift.

## Recommendations

Priority recommendations:

1. Remove `allow-top-navigation-by-user-activation` from the iframe sandbox by default. The preview should not be able to navigate the IDE shell away.
2. Remove `allow-modals` unless there is a known workflow that needs modal dialogs inside previewed content.
3. Document why `allow-scripts`, `allow-forms`, and `allow-same-origin` are retained. These are defensible for realistic app preview, but `allow-same-origin` should be treated as a conscious trust tradeoff.
4. Replace global link interception with scoped, modifier-aware interception. Preserve normal browser behavior for Cmd/Ctrl-click, Shift-click, middle-click, `_blank`, `download`, and already-prevented events.
5. Add URL validation/normalization before assigning iframe `src`. Accept only `http:` and `https:`; handle uppercase schemes; reject malformed URLs with visible feedback.
6. Prefer HTTPS for public-looking bare domains, or explicitly communicate that bare input defaults to HTTP.
7. Add lightweight preview error/help states for invalid URLs and likely frame-blocked external sites.
8. Clarify same-origin preview risk in code comments or docs: with `allow-scripts allow-same-origin`, previewing the IDE's own origin or untrusted same-origin content is not strongly isolated from the parent.

Lower-priority recommendations:

- Remove unused `ArrowLeft` and `ArrowRight` imports from `Browser.jsx`, or implement actual back/forward controls. Current icons are imported but unused.
- Consider supporting multiple browser preview tabs or prompting before a global link click replaces the single existing preview tab.
- Decide whether popup support is part of the product. If not, remove `allow-popups`.

## Followups and Ambiguities

- Should the embedded browser prioritize trusted local app preview over untrusted web browsing? The right sandbox depends on that product decision.
- Should external links in IDE chrome open the preview by default, or should they preserve native browser behavior?
- Should bare domains default to `http://` for developer convenience or `https://` for modern web expectations?
- Are popup-based auth flows expected inside the preview? This determines whether `allow-popups` should stay.
- Is previewing the wede app itself a supported scenario? If yes, the same-origin sandbox risk needs a specific mitigation strategy.
