# wede Codebase Health Audit Tickets

Date: 2026-05-21

## High-Level Assessment

`wede` is a compact self-hosted web IDE with three main surfaces:

- React/Vite frontend in `wede/src`
- Go HTTP/WebSocket backend in `wede/backend`
- Operational/install/database-adjacent assets in `wede/install.sh`, `wede/wede.config.json`, `wede/database`, and shared Docker files at repository root

The codebase is small enough for a thorough audit, but the product surface is high-risk because it exposes filesystem access, terminal PTYs, Git commands, folder browsing, browser previews, authentication, persisted sessions, and install scripts. The healthiest review strategy is to split the audit by risk boundary and user workflow rather than by language alone.

Recommended order:

1. Security boundary and backend safety
2. Dependency freshness and supply-chain posture
3. Test strategy and quality gates
4. Frontend state/UI maintainability
5. Feature-specific workflows: files, terminal, Git, browser, workspace
6. Build, packaging, install, and docs alignment
7. Optional database/migration scope decision

Known initial observations to validate during tickets:

- No project test files were found outside `node_modules`.
- The backend currently has no visible Go tests.
- `package.json` and Go modules contain modern dependency versions, but freshness must be verified with live registry/module checks before making claims.
- Several backend APIs operate directly on user-provided paths, shell sessions, Git commands, and persisted auth tokens; these deserve dedicated security review.
- The `database/` folder appears separate from the README's "no database" product framing and should be explicitly classified as active, legacy, or unrelated before spending deep audit time there.

## Ticket 1: Backend Security Boundary Audit

Goal: Assess whether the Go backend safely protects filesystem, workspace, terminal, Git, auth, and browser-facing API boundaries.

Primary files:

- `wede/backend/cmd/wede/main.go`
- `wede/backend/internal/auth/auth.go`
- `wede/backend/internal/files/files.go`
- `wede/backend/internal/workspace/workspace.go`
- `wede/backend/internal/terminal/terminal.go`
- `wede/backend/internal/git/git.go`
- `wede/backend/internal/config/config.go`

Review questions:

- Can authenticated users access, modify, rename, or delete files outside the selected workspace?
- Are path traversal, symlink traversal, absolute path handling, prefix collisions, and workspace-root edge cases handled correctly?
- Are WebSocket origin checks, token-in-query usage, terminal session IDs, and reconnect behavior acceptable for a self-hosted IDE?
- Are session tokens stored, rotated, revoked, and scoped appropriately?
- Are Git command arguments safely passed, validated, and constrained?
- Are sensitive values logged, especially passwords, session tokens, paths, or command output?
- Does `authDisabled` have clear and safe behavior when enabled?

Suggested commands:

```bash
cd wede/backend
go test ./...
go test -race ./...
gofmt -w <changed-files-if-any>
```

Deliverable:

- Findings list with severity, affected file/line, exploitability, and recommended fix.
- A short set of backend security tests to add first.

Acceptance criteria:

- Every externally reachable backend route is accounted for.
- High-risk filesystem and terminal behaviors are backed by concrete repro cases or cleared with evidence.

## Ticket 2: Dependency Freshness and Supply-Chain Audit

Goal: Determine whether frontend and backend dependencies are current, supported, vulnerable, and appropriate for the app.

Primary files:

- `wede/package.json`
- `wede/package-lock.json`
- `wede/go.mod`
- `wede/go.sum`
- `wede/database/go.mod`
- `wede/database/go.sum`
- `wede/vite.config.js`
- `wede/eslint.config.js`

Review questions:

- Which npm packages are outdated, deprecated, or vulnerable?
- Which Go modules have available upgrades or security advisories?
- Are React, Vite, Tailwind, CodeMirror, xterm.js, gorilla/websocket, and creack/pty versions compatible and actively supported?
- Is the lockfile clean and reproducible?
- Are any transitive dependencies introducing unnecessary risk for a single-binary app?
- Should `database/` dependencies be audited as production scope, tooling scope, or removed from the main audit if inactive?

Suggested commands:

```bash
cd wede
npm ci
npm outdated
npm audit
npm run lint
npm run build
cd backend
go list -m -u all
go list -m -json all
go test ./...
cd ../database
go list -m -u all
go test ./...
```

Notes:

- `npm outdated`, `npm audit`, and Go module update checks require network access.
- Do not mark dependencies as "up to date" without running registry/module checks.

Deliverable:

- Dependency table grouped by frontend, backend, and database/tooling.
- Recommended upgrade plan: safe patch/minor upgrades first, risky major upgrades separately.
- Any advisories or unsupported packages linked to exact remediation.

Acceptance criteria:

- Current installed versions, latest compatible versions, and upgrade risk are documented.
- The audit distinguishes between production runtime dependencies and development/tooling dependencies.

## Ticket 3: Test Coverage and Quality Gates Audit

Goal: Identify the minimum useful test strategy and CI-quality checks needed for confidence.

Primary files:

- `wede/package.json`
- `wede/eslint.config.js`
- `wede/backend/internal/*`
- `wede/src/components/*`
- `wede/src/hooks/*`
- `wede/AGENTS.md`

Review questions:

- What critical behavior currently has no tests?
- Which backend handlers should get table-driven unit tests?
- Which frontend workflows need component or end-to-end coverage?
- Is linting strict enough for React hooks, unused code, unsafe globals, and accidental stale closures?
- Is there a CI workflow outside this local checkout that should be reviewed separately?
- What is the smallest first test suite that would catch meaningful regressions?

Suggested commands:

```bash
cd wede
npm run lint
npm run build
cd backend
go test ./...
go test -race ./...
```

Recommended first test areas:

- `files.safePath` and file handler behavior.
- Auth login/check/middleware and lockout behavior.
- Workspace open/browse/recents behavior.
- Git status parsing with porcelain edge cases.
- Terminal session lifecycle at the handler boundary where feasible.
- Frontend save/open-tab/authFetch state behavior.

Deliverable:

- Coverage gap report.
- Proposed test pyramid for this repo.
- Prioritized first 5-10 tests to implement.

Acceptance criteria:

- Each proposed test maps to a meaningful user or security risk.
- The output recommends exact test tooling if frontend tests are added.

## Ticket 4: Frontend Architecture and State Management Audit

Goal: Review React component organization, state ownership, persistence, data fetching, and maintainability.

Primary files:

- `wede/src/App.jsx`
- `wede/src/components/IDE.jsx`
- `wede/src/components/FileExplorer.jsx`
- `wede/src/components/Editor.jsx`
- `wede/src/components/EditorTabs.jsx`
- `wede/src/components/TerminalPanel.jsx`
- `wede/src/components/Terminal.jsx`
- `wede/src/components/GitPanel.jsx`
- `wede/src/components/Browser.jsx`
- `wede/src/hooks/useAuth.js`
- `wede/src/hooks/useTheme.jsx`
- `wede/src/hooks/useMobile.js`

Review questions:

- Is application state owned at the right level, or is `IDE.jsx` carrying too many unrelated responsibilities?
- Are persisted tabs, terminal sessions, auth tokens, theme, and workspace state resilient across workspace changes and reloads?
- Are async fetches cancellable or guarded against stale updates?
- Are errors surfaced to users consistently?
- Are localStorage keys scoped enough to avoid cross-workspace confusion?
- Are hooks following dependency best practices without suppressed issues hiding real bugs?
- Are mobile and desktop flows sharing behavior cleanly?

Suggested commands:

```bash
cd wede
npm run lint
npm run build
```

Deliverable:

- Component responsibility map.
- List of state-management risks and suggested refactors.
- "Quick wins" versus "larger refactor" recommendations.

Acceptance criteria:

- The audit identifies specific places where state can become stale, inconsistent, or difficult to test.
- Recommendations preserve the small-app nature of the codebase and avoid unnecessary framework churn.

## Ticket 5: Filesystem Workflow Audit

Goal: Thoroughly review file explorer, editor, and file API behavior from UI to backend.

Primary files:

- `wede/backend/internal/files/files.go`
- `wede/src/components/FileExplorer.jsx`
- `wede/src/components/Editor.jsx`
- `wede/src/components/EditorTabs.jsx`
- `wede/src/components/IDE.jsx`

Review questions:

- Are create, read, write, rename, delete, and copy/paste behaviors correct for files, folders, nested paths, hidden files, symlinks, and binary files?
- Does the UI handle backend errors, large files, unreadable files, and conflicts?
- Can unsaved changes be lost through tab close, workspace switch, reload, file delete, or rename?
- Are file size limits and content assumptions appropriate?
- Is the explorer refresh model reliable after nested changes?
- Are destructive actions confirmed or recoverable enough for the product?

Suggested commands:

```bash
cd wede
npm run build
cd backend
go test ./...
```

Deliverable:

- Workflow matrix covering create/read/update/delete/rename/copy.
- Risk list with repro steps.
- Recommended backend tests and frontend UX improvements.

Acceptance criteria:

- The audit includes at least one manual or automated scenario for each file operation.
- Any data-loss risks are explicitly called out.

## Ticket 6: Terminal and WebSocket Lifecycle Audit

Goal: Review PTY session management, reconnect behavior, auth, resource cleanup, and UI ergonomics for terminal tabs.

Primary files:

- `wede/backend/internal/terminal/terminal.go`
- `wede/src/components/Terminal.jsx`
- `wede/src/components/TerminalPanel.jsx`
- `wede/src/components/TerminalToolbar.jsx`
- `wede/src/components/IDE.jsx`

Review questions:

- Are terminal sessions created, listed, reattached, and cleaned up predictably?
- Can users create orphaned PTYs or unbounded server resources?
- Does closing a terminal tab kill or detach the PTY, and is that behavior intentional?
- Are WebSocket token handling and origin policy appropriate?
- Does workspace switching terminate sessions reliably?
- Is reconnect backoff correct and bounded?
- Does mobile input behavior remain usable?

Suggested commands:

```bash
cd wede/backend
go test -race ./...
```

Deliverable:

- Lifecycle diagram for terminal sessions.
- Resource-leak and security findings.
- Recommended behavior contract for close, reconnect, and workspace switch.

Acceptance criteria:

- The audit clearly distinguishes intended persistence from accidental orphaning.
- Any suggested changes include user-visible behavior expectations.

## Ticket 7: Git Integration Audit

Goal: Review Git command behavior, parsing, UX correctness, and safety.

Primary files:

- `wede/backend/internal/git/git.go`
- `wede/src/components/GitPanel.jsx`
- `wede/src/components/FileExplorer.jsx`
- `wede/src/components/IDE.jsx`

Review questions:

- Is `git status --porcelain` parsing correct for spaces, renames, copies, conflicts, quoted paths, deleted files, and submodules?
- Are stage/unstage/commit/checkout commands correctly separated from user-controlled shell execution risk?
- Are detached HEAD, unborn branch, no repo, merge conflicts, and worktree states handled?
- Does checkout warn about uncommitted changes?
- Are commit failures and Git errors shown clearly to users?
- Is the visual graph correct for merges, branches, tags, remotes, and long histories?

Suggested commands:

```bash
cd wede/backend
go test ./...
```

Manual scenario ideas:

- Non-Git workspace.
- Empty Git repo with unborn branch.
- Modified, staged, untracked, renamed, copied, deleted, conflicted files.
- Branch checkout with dirty working tree.
- Merge commit history.

Deliverable:

- Git workflow findings with repro setup.
- Parsing test cases to add.
- UX recommendations for risky Git actions.

Acceptance criteria:

- Edge cases are tested against real Git repositories or explicit fixture outputs.
- Findings separate parser bugs from missing UX safeguards.

## Ticket 8: Auth, Session Persistence, and Configuration Audit

Goal: Review authentication, lockout, persistent sessions, config discovery, and runtime options.

Primary files:

- `wede/backend/internal/auth/auth.go`
- `wede/backend/internal/config/config.go`
- `wede/backend/cmd/wede/main.go`
- `wede/src/hooks/useAuth.js`
- `wede/src/components/Login.jsx`
- `wede/src/components/Settings.jsx`
- `wede/wede.config.json`
- `wede/README.md`

Review questions:

- Are passwords or generated credentials exposed through logs, docs, install output, or config examples in ways that match product expectations?
- Should sessions persist indefinitely, or should there be expiry/revocation?
- Are auth tokens safe in localStorage for this threat model?
- Is token-in-query acceptable for WebSocket auth, and is it documented?
- Does lockout behavior protect users without making recovery awkward?
- Is config lookup order documented and safe?
- Are config file permissions enforced or checked?

Suggested commands:

```bash
cd wede/backend
go test ./...
```

Deliverable:

- Threat-model summary for the current auth design.
- Recommended changes grouped as must-fix, should-fix, and documentation-only.
- Tests to add for login, check, middleware, config loading, and disabled-auth mode.

Acceptance criteria:

- The audit explicitly states assumptions about self-hosted/local-network deployment.
- Any security tradeoff is tied to product documentation.

## Ticket 9: Browser Preview and Link Handling Audit

Goal: Review the embedded browser preview, iframe sandbox, URL handling, and global link interception.

Primary files:

- `wede/src/components/Browser.jsx`
- `wede/src/components/IDE.jsx`
- `wede/vite.config.js`

Review questions:

- Is the iframe sandbox permission set appropriate?
- Does global anchor interception surprise users or break expected browser behavior?
- Are local dev URLs, HTTPS URLs, ports, and invalid URLs handled well?
- Is cross-origin behavior understood and error-tolerant?
- Could previewed content interact with the IDE in unwanted ways?
- Does the Vite dev proxy match production behavior closely enough?

Suggested commands:

```bash
cd wede
npm run build
```

Deliverable:

- Sandbox and navigation risk assessment.
- UX findings for preview behavior.
- Recommended URL validation or permission adjustments.

Acceptance criteria:

- The audit documents why each iframe sandbox permission is needed or recommends removing it.
- Manual scenarios include local app preview and external HTTPS preview.

## Ticket 10: Build, Packaging, Install, and Runtime Ops Audit

Goal: Review production build flow, embedded frontend behavior, install script, docs, Docker integration, and operational reliability.

Primary files:

- `wede/package.json`
- `wede/vite.config.js`
- `wede/backend/cmd/wede/frontend_dev.go`
- `wede/backend/cmd/wede/frontend_embed.go`
- `wede/install.sh`
- `wede/README.md`
- `docker/Dockerfile`
- `docker/docker-compose.yml`
- `docker/entrypoint.sh`
- `docker/Caddyfile`

Review questions:

- Does `npm run build:all` reliably produce the intended single binary?
- Are embedded and dev frontend handlers behaviorally consistent?
- Is the install script robust across Linux, macOS, Windows shells, missing releases, checksum/signature needs, PATH handling, and config creation?
- Do Docker files align with the wede product or another repo component?
- Are generated passwords and config permissions handled safely?
- Is README guidance accurate for the current code?
- Are release artifacts verified, signed, or checksummed?

Suggested commands:

```bash
cd wede
npm run build
npm run build:all
bash -n install.sh
bash -n ../docker/entrypoint.sh
```

Deliverable:

- Build and install reliability report.
- Docs mismatches and recommended edits.
- Release hardening recommendations.

Acceptance criteria:

- The audit confirms whether `build:all` works from a clean checkout.
- Any Docker findings clearly state whether Docker is in scope for `wede` or the larger repo.

## Ticket 11: Database and Migration Scope Audit

Goal: Decide whether `wede/database` is active product code, legacy code, or unrelated repository residue, then audit accordingly.

Primary files:

- `wede/database/migrate.go`
- `wede/database/go.mod`
- `wede/database/migrations/20260327000024_initial_setup.sql`
- `wede/database/seed.sql`
- `wede/README.md`

Review questions:

- Why does `database/` exist when README says the product has no database?
- Is this used by production, docs, CI, another deployment mode, or old code?
- Does the migration runner safely parse env files and apply SQL?
- Is reset behavior intentionally destructive and adequately guarded?
- Are migration statements SQL-injection safe for filenames and seed tracking?
- Should this folder be removed, moved, documented, or included in regular checks?

Suggested commands:

```bash
cd wede/database
go test ./...
go list -m -u all
```

Deliverable:

- Scope decision: active, legacy, unrelated, or needs owner clarification.
- If active, a health/security review of migration behavior.
- If inactive, cleanup or documentation recommendation.

Acceptance criteria:

- The audit does not spend deep effort here until scope is resolved.
- The final recommendation reconciles this folder with README/product claims.

## Ticket 12: Documentation, Product Claims, and Developer Experience Audit

Goal: Check whether docs, examples, commands, screenshots, and product claims match the current implementation.

Primary files:

- `wede/README.md`
- `wede/AGENTS.md`
- `wede/package.json`
- `wede/wede.config.json`
- `wede/docs/screenshots/*`
- `wede/public/manifest.json`
- `wede/landing/index.html`

Review questions:

- Do README commands work as written?
- Are "single binary", "no database", "secure access", and deployment claims accurate?
- Are dev commands aligned with AGENTS instructions?
- Are screenshots current enough to represent the app?
- Are config examples safe and complete?
- Is missing troubleshooting guidance hurting maintainability?
- Are browser support and HTTPS/reverse-proxy requirements clear?

Suggested commands:

```bash
cd wede
npm run build
npm run build:all
```

Deliverable:

- Docs mismatch list.
- Suggested README/AGENTS updates.
- Product claim risk notes.

Acceptance criteria:

- Every major README claim is either verified, marked as needing verification, or corrected.
- The developer onboarding path is executable from a clean checkout.

