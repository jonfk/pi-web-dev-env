# Ticket 3: Test Coverage and Quality Gates Audit

## Scope

Audit only. No source changes were made.

Primary files reviewed:
- `wede/package.json`
- `wede/eslint.config.js`
- `wede/AGENTS.md`
- `wede/.github/workflows/ci.yml`
- `wede/.github/workflows/release.yml`
- `wede/backend/internal/auth/auth.go`
- `wede/backend/internal/files/files.go`
- `wede/backend/internal/git/git.go`
- `wede/backend/internal/terminal/terminal.go`
- `wede/backend/internal/workspace/workspace.go`
- `wede/src/hooks/useAuth.js`
- `wede/src/hooks/useTheme.jsx`
- `wede/src/hooks/useMobile.js`
- `wede/src/components/App.jsx`
- `wede/src/components/IDE.jsx`
- `wede/src/components/FileExplorer.jsx`
- `wede/src/components/FolderPicker.jsx`
- `wede/src/components/GitPanel.jsx`
- `wede/src/components/Terminal.jsx`
- `wede/src/components/TerminalPanel.jsx`
- `wede/src/components/Editor.jsx`

## Commands Run

From repository root:

- `pwd`
- `rg --files wede`
- `git status --short`
- `find wede -path 'wede/node_modules' -prune -o -path 'wede/dist' -prune -o -name '*test*' -print -o -name '*spec*' -print`
- `find . -path './wede/node_modules' -prune -o -path './.git' -prune -o -path './wede/dist' -prune -o -name '*.yml' -print -o -name '*.yaml' -print -o -name 'justfile' -print -o -name 'Makefile' -print`
- `rg -n "vitest|jest|playwright|testing-library|cypress|test" wede/package.json wede/package-lock.json wede/vite.config.js wede/eslint.config.js wede/.github/workflows -g '!node_modules'`
- `rg -n "TODO|FIXME|eslint-disable|dangerouslySetInnerHTML|eval\\(|new Function|innerHTML|CheckOrigin|os.RemoveAll|exec.Command|LimitReader|HasPrefix" wede/src wede/backend -g '!node_modules'`

From `wede/`:

- `npm run lint`
  - Failed before linting: `sh: eslint: command not found`.
- `npm run build`
  - Failed before building: `sh: vite: command not found`.
- `npm ls --depth=0`
  - Failed with `ELSPROBLEMS`; local `node_modules` is incomplete/inconsistent and has no `node_modules/.bin`.

From `wede/backend/`:

- `go test ./...`
  - Passed compile checks, but every package reports `[no test files]`.
- `go test -race ./...`
  - Passed compile/race instrumentation checks, but every package reports `[no test files]`.

## Current Quality Gates

Local documented gates in `wede/AGENTS.md`:
- `npm ci`
- `npm run build`
- `npm run build:all`
- `go test ./...` from `wede/backend/`
- `gofmt -w ...` for changed Go files
- `bash -n ../docker/entrypoint.sh` only when Docker startup behavior changes

Package scripts in `wede/package.json`:
- `npm run lint` runs `eslint .`
- `npm run build` runs `vite build`
- No frontend test script exists.
- No backend wrapper script exists for `go test ./...` or `go test -race ./...`.

ESLint configuration:
- Uses `@eslint/js` recommended rules, `eslint-plugin-react-hooks` recommended rules, and `eslint-plugin-react-refresh`.
- `no-unused-vars` is an error, with uppercase variable ignores.
- Browser globals are enabled.
- The config does not include TypeScript, import validation, security-oriented rules, promise rules, accessibility rules, or test environment overrides.
- React hooks coverage is mostly good for stale closures because `react-hooks` recommended is enabled, but there is one explicit `react-hooks/exhaustive-deps` disable in `wede/src/components/IDE.jsx` around restored-tab content loading. That should be justified by a test or refactored later.

CI:
- `wede/.github/workflows/ci.yml` exists for pushes and pull requests to `main`.
- CI runs `npm ci`, `npm run build`, an embedded frontend Go build, and `./wede --help || true`.
- CI does not run `npm run lint`.
- CI does not run `go test ./...`.
- CI does not run `go test -race ./...`.
- CI does not run frontend unit/component/E2E tests.
- Release workflow builds binaries for Linux, macOS, and Windows, but also does not lint or test.

Current test inventory:
- No first-party `*test*` or `*spec*` files were found under `wede/` outside `node_modules`.
- Go packages compile, but there are no Go tests.
- No frontend test framework is installed or configured.

## Coverage Gaps

### Backend: Files

Critical uncovered behavior:
- `files.safePath` is the highest priority gap. It joins cleaned request paths to the workspace and checks `strings.HasPrefix(full, ws)`. This needs table-driven tests for traversal and sibling-prefix cases, because a workspace like `/tmp/ws` can be a prefix of `/tmp/ws-evil`.
- `List` filters `.git`, `node_modules`, and `.DS_Store`, sorts directories before files, and returns relative paths. This affects user navigation and should be covered.
- `Read` enforces a 10 MB limit and returns `404` for missing files. This is user-facing data access behavior.
- `Write`, `Create`, `Delete`, and `Rename` mutate the filesystem. They need handler tests for malformed JSON, missing workspace, path escape attempts, nested directory creation, root delete rejection, and rename destination containment.

User/security risk:
- Path traversal or sibling-prefix mistakes can allow reading, writing, renaming, or deleting files outside the selected workspace.
- Delete uses `os.RemoveAll`, so boundary mistakes have high blast radius.

Recommended backend test style:
- Table-driven Go tests using `testing.T.TempDir`, `httptest.NewRecorder`, and small fake workspace providers.

### Backend: Auth

Critical uncovered behavior:
- Login success creates a token, persists sessions, and resets failed attempts.
- Wrong password returns `401` with remaining attempts.
- Third failure locks the handler and returns `403`.
- Locked state blocks subsequent correct password attempts.
- `Check` accepts token from either `Authorization` header or `token` query parameter.
- `Middleware` rejects missing/invalid tokens and passes valid tokens.
- Disabled auth bypasses login/check/middleware behavior.
- Session persistence reads/writes `~/.wede/sessions.json`; tests need a controlled home/data directory approach.

User/security risk:
- Lockout and middleware are the main local access controls. Regressions can either lock out legitimate users or permit unauthenticated API access.

Recommended backend test style:
- Handler-level tests with `httptest`.
- Prefer adding a test-only constructor or dependency seam later so tests can use `t.TempDir` for session storage without touching the real home directory.

### Backend: Workspace

Critical uncovered behavior:
- `SetWorkspace` rejects missing paths and files, accepts directories, normalizes to absolute paths, updates recents, caps recents at 20, and notifies listeners.
- `HandleOpen` expands `~`, validates request JSON, and returns the current workspace.
- `HandleBrowse` expands home paths, filters hidden directories, sorts visible directories, returns parent and valid roots.
- Recents persistence currently writes under `~/.wede/recent.json`, which needs controlled storage for deterministic tests.

User/security risk:
- Workspace selection is the root of all file, git, and terminal behavior. A wrong current workspace can cause operations in the wrong project.

Recommended backend test style:
- Unit tests for `SetWorkspace` and handler tests for `HandleOpen`/`HandleBrowse`.
- Add controlled data-dir injection before testing persistence-heavy cases.

### Backend: Git

Critical uncovered behavior:
- `Status` parses `git status --porcelain` into staged/unstaged/untracked entries.
- Rename parsing maps `old -> new` to the new path.
- Mixed staged and unstaged states can produce two entries for one path.
- Non-git workspace returns `{ isRepo: false }`.
- `Stage`, `Unstage`, `Commit`, and `Checkout` decode request bodies loosely and call git commands at the handler boundary.
- `Diff` scopes file paths with `--`, which should remain covered.

User/security risk:
- Git status drives user decisions about what to stage and commit. Bad parsing can hide changes, stage wrong files, or mislead users before a commit.

Recommended backend test style:
- First extract or test parsing via table-driven cases.
- Handler-boundary tests can use a temporary git repo where needed, but keep the initial suite focused on parser behavior and no-workspace/non-repo responses.

### Backend: Terminal

Critical uncovered behavior:
- Websocket origin policy is currently `CheckOrigin: true`; this should be an explicit reviewed decision and covered by tests if narrowed later.
- Session creation defaults to current workspace or home directory.
- Reconnect reuses existing sessions and replays ring buffer contents.
- Workspace changes close connections, kill processes, mark sessions closed, and clear the session map.
- `ListSessions` returns only non-closed sessions.
- Resize messages call PTY resize and non-resize messages are written to PTY.

User/security risk:
- Terminal sessions expose shell access. Session identity, origin policy, workspace directory, reconnect behavior, and cleanup are all security/stability-sensitive.

Recommended backend test style:
- Unit-test `ringBuffer` immediately.
- Handler-boundary tests should be introduced carefully because PTY/websocket tests can be slower and platform-sensitive.
- Prefer isolating session management from PTY spawning before broad terminal tests.

### Frontend: Auth and API State

Critical uncovered behavior:
- `useAuth` initial check reads `localStorage`, calls `/api/auth/check`, handles disabled auth, invalid stored tokens, locked state, and server connection failure.
- `login` handles success, disabled auth, wrong password with remaining count, lockout, unknown response, and network failure.
- `authFetch` adds `Authorization`, logs out on `401`, and avoids auth headers when auth is disabled.

User/security risk:
- Incorrect auth state can expose protected UI, cause token loss, or hide lockout/server errors.

Recommended frontend test tooling:
- Vitest + React Testing Library + `@testing-library/user-event` + jsdom for hooks/components.
- Mock `fetch` and `localStorage` directly for `useAuth`.

### Frontend: Workspace and File Workflows

Critical uncovered behavior:
- `FolderPicker` browse/open/manual path/recents flows.
- `FileExplorer` root load, git status mapping, create, copy/paste, delete, rename, and refresh behavior.
- `IDE` restored tabs re-fetch content on mount, open-file de-duplication, modified state, save behavior, tab persistence, workspace switching clearing tabs and terminal key.
- `IDE` has an explicit hooks dependency lint suppression for restored tabs. A component test should pin intended behavior so future stale closure fixes are safer.

User/security risk:
- These workflows directly affect user files. Regressions can lose edits, open stale content, delete wrong files, or show misleading modified state.

Recommended frontend test tooling:
- Component tests with Vitest + React Testing Library for `FolderPicker`, `FileExplorer`, and `IDE` behavior.
- MSW is optional; for the smallest first suite, direct `authFetch` mocks are enough. Add MSW once more integrated UI flows appear.

### Frontend: Terminal and Git UI

Critical uncovered behavior:
- `Terminal.jsx` opens websocket URLs with `session` and `token` query params, reconnects, sends resize, writes terminal data, and cleans up websocket/xterm resources.
- `TerminalPanel` reconciles saved local terminal tabs with server sessions and persists active terminal IDs.
- `GitPanel` refreshes status/log/branches, stages/unstages, commits, checks out branches/commits, and exposes copy actions.

User/security risk:
- Terminal regressions can leak tokens in unexpected contexts, create orphan sessions, or break shell access.
- Git UI regressions can stage, unstage, or commit unexpected files.

Recommended frontend test tooling:
- Component tests with mocked xterm/websocket for terminal lifecycle basics.
- Component tests for GitPanel actions with mocked `authFetch`.
- E2E tests should cover the full auth -> workspace -> open/edit/save -> git status happy path after unit/component tests exist.

## Test Pyramid

Recommended smallest useful pyramid:

1. Backend Go unit/handler tests, highest volume
   - Fast, deterministic table-driven tests for path safety, auth, workspace, git parsing, and selected file handlers.
   - These catch the highest security and data-loss risks with the lowest maintenance cost.

2. Frontend component/hook tests, medium volume
   - Vitest + React Testing Library + jsdom.
   - Focus on auth state, file open/save state, folder picker, file explorer mutations, and GitPanel action wiring.

3. Thin E2E smoke tests, low volume
   - Playwright.
   - One or two full-browser flows once the app can be started reliably in CI.
   - Recommended first E2E: login, open temp workspace, open file, edit, save, reload, verify content.
   - Recommended second E2E: auth lockout or invalid token redirect, depending on desired CI speed and determinism.

4. CI gates
   - Pull request gate should run `npm ci`, `npm run lint`, `npm run test`, `npm run build`, `go test ./...`, and optionally `go test -race ./...`.
   - Race tests can be nightly or required only for backend-touching PRs if runtime becomes an issue.

Exact frontend tooling recommendation:
- Add Vitest as the unit/component runner.
- Add React Testing Library for component rendering.
- Add `@testing-library/user-event` for user interactions.
- Add `jsdom` as Vitest environment.
- Add Playwright for E2E after the first component suite is in place.
- Optional after first suite: MSW for route-level fetch mocking.

## Prioritized First Tests

1. `files.safePath` rejects traversal and sibling-prefix paths.
   - Risk: prevents read/write/delete/rename outside workspace.
   - Cases: `""`, `"."`, `"/"`, `"file.txt"`, `"dir/../file.txt"`, `"../outside.txt"`, absolute path outside workspace, and sibling prefix like workspace `/tmp/ws` with request resolving to `/tmp/ws-evil/file`.

2. `files.Delete` refuses workspace root and escaped paths.
   - Risk: prevents catastrophic project or filesystem deletion.
   - Cases: empty path/root path returns forbidden; traversal returns forbidden; normal child delete succeeds.

3. `files.Write`, `Create`, and `Rename` reject escaped paths and malformed JSON.
   - Risk: prevents unauthorized mutation and verifies useful client error behavior.
   - Cases: bad JSON `400`, path outside workspace `403`, nested create/write succeeds, rename destination outside workspace fails.

4. `auth.Login` lockout table.
   - Risk: protects local server access while avoiding accidental lockout regressions.
   - Cases: wrong password decrements remaining, third wrong password locks, correct password after lock still forbidden, correct password before lock resets attempts.

5. `auth.Check` and `auth.Middleware` token handling.
   - Risk: prevents protected API bypass.
   - Cases: valid header token, valid query token, missing token, invalid token, disabled auth bypass.

6. `workspace.SetWorkspace` and `HandleOpen` validation.
   - Risk: ensures file/git/terminal operations use the intended project root.
   - Cases: missing path, file path, directory path, `~` expansion, recents ordering/deduplication.

7. `git.Status` porcelain parsing.
   - Risk: prevents misleading source-control UI and wrong commit decisions.
   - Cases: untracked, staged add, unstaged modified, staged+unstaged same file, deleted, renamed, copied, malformed short line ignored.

8. `terminal.ringBuffer` and session list behavior.
   - Risk: reconnect stability and no stale closed sessions in UI.
   - Cases: buffer truncates to max bytes, `Bytes` returns a copy, `ListSessions` omits closed sessions.

9. `useAuth` hook tests.
   - Risk: protects login/check/lockout/client token state.
   - Cases: stored token accepted, stored token rejected and removed, disabled auth sentinel, wrong password remaining count, `authFetch` logout on `401`.

10. `IDE` open/save tab state component test.
    - Risk: prevents edit loss and stale tab content.
    - Cases: opening a file creates one tab, opening same file does not duplicate, editing marks modified, save calls `/api/files/write` with current content and clears modified state.

## Followups / Ambiguities

- Should frontend dependencies be reinstalled with `npm ci` before relying on local lint/build results? I did not run install because this audit was scoped to read-only verification plus one markdown report file.
- Should CI require lint and tests before a first test suite exists, or should the first change add tests and CI gates together? Recommendation: add the first backend tests and frontend test harness first, then update CI in the same ticket or immediately after.
- Should `go test -race ./...` be required on every PR? Recommendation: yes initially, because the backend has auth/session/terminal concurrency. Revisit only if runtime becomes painful.
- Should terminal websocket `CheckOrigin: true` be accepted for localhost-only usage? Recommendation: make the intended threat model explicit before changing it, then test the chosen behavior.
- Auth and workspace persistence currently use `~/.wede`. Recommendation: introduce controlled data-directory injection before persistence tests so tests never touch a developer's real Wede state.
- The frontend restored-tabs effect suppresses `react-hooks/exhaustive-deps`. Recommendation: add a component test for restored tab loading before refactoring or broadening lint strictness.
