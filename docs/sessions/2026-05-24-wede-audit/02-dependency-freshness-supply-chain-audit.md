# Ticket 2: Dependency Freshness and Supply-Chain Audit

## Scope

Audited dependency freshness, vulnerability status, lockfile reproducibility, and supply-chain risk for:

- Frontend: `wede/package.json`, `wede/package-lock.json`, `wede/vite.config.js`, `wede/eslint.config.js`
- Backend Go module: `wede/go.mod`, `wede/go.sum`, packages under `wede/backend/`
- Database tooling Go module: `wede/database/go.mod`, `wede/database/go.sum`, `wede/database/migrate.go`

No source code changes were made. This report is the only file created for this ticket.

## Commands Run

Environment:

| Command | Result |
| --- | --- |
| `node --version` | `v23.11.1` |
| `npm --version` | `10.9.2` |
| `go version` | `go version go1.25.6 darwin/arm64` |

Frontend:

| Command | Result |
| --- | --- |
| `npm ci` | First sandboxed run failed with `npm error Exit handler never called!` and could not write logs under `/Users/jfokkan/.npm/_logs`; rerun with cache/registry access succeeded: `added 213 packages, and audited 214 packages in 4s`; reported `3 vulnerabilities (2 moderate, 1 high)`. |
| `npm outdated` | Exit 1 because packages are outdated; details in frontend table. |
| `npm outdated --json` | Exit 1 because packages are outdated; used for exact current/wanted/latest data. |
| `npm audit` | Exit 1; 3 vulnerabilities: `brace-expansion`, `postcss`, `vite`. |
| `npm audit --omit=dev` | Exit 1; 2 vulnerabilities remain when dev dependencies are omitted: `postcss`, `vite`. |
| `npm run lint` | Exit 1; 36 problems: 32 errors, 4 warnings. Failures are mostly existing React Hooks lint rules plus `no-empty`, `no-unused-vars`, `no-self-assign`, and `react-refresh/only-export-components`. |
| `npm run build` | Exit 0; Vite build succeeds. Warning: generated JS chunk is `1,584.22 kB` / `508.89 kB gzip`, above 500 kB warning threshold. |
| `npm ls --depth=0` | Exit 0, but several packages are marked `extraneous` even after `npm ci`: `@emnapi/core`, `@emnapi/runtime`, `@emnapi/wasi-threads`, `@napi-rs/wasm-runtime`, `@tybys/wasm-util`, `tslib`. These packages do exist in `package-lock.json`, so this appears to be npm tree/reporting oddity around optional/native dependencies, not necessarily an untracked install. |
| `npm ls vite postcss brace-expansion --all` | Exit 0; `vite@8.0.3` depends on `postcss@8.5.8`; `eslint@9.39.4 -> minimatch@3.1.5 -> brace-expansion@1.1.12`. |
| `npm view ... version deprecated` for all direct npm dependencies | No direct dependency returned deprecation metadata. Registry latest versions confirmed; `eslint` and `@eslint/js` have major latest versions but npm does not mark them outdated under current install constraints. |

Backend Go:

| Command | Result |
| --- | --- |
| `go list -m -u all` from `wede/` | Exit 0; no upgrades reported for `github.com/creack/pty v1.1.24` or `github.com/gorilla/websocket v1.5.3`. |
| `go list -m -json all` from `wede/` | Exit 0; confirmed root module `wede`, Go `1.25.6`, `creack/pty v1.1.24`, `gorilla/websocket v1.5.3`. |
| `go test ./...` from `wede/` | First sandboxed run failed on Go build cache permission; rerun with cache access passed. It also discovered `wede/node_modules/flatted/golang/pkg/flatted`, which is supply-chain noise caused by `node_modules` living inside the Go module root. |
| `govulncheck` | Not installed: `govulncheck not found`. Go vulnerability database checks remain a followup. |

Database Go:

| Command | Result |
| --- | --- |
| `go list -m -u all` from `wede/database` | Exit 0; module has no required dependencies, so no upgrades reported. |
| `go list -m -versions github.com/jackc/pgx/v5` | Exit 0; latest listed version is `v5.9.2`. |
| `go test ./...` from `wede/database` | First sandboxed run failed on Go build cache permission. Rerun with cache access failed for real module reason: `migrate.go:27:2: no required module provides package github.com/jackc/pgx/v5; to add it: go get github.com/jackc/pgx/v5`. |

## Dependency Tables

### Frontend Runtime / Browser-App Dependencies

`npm outdated` uses `wanted` as the latest version allowed by the current semver range and `latest` as the registry latest compatible with current npm/engine constraints.

| Package | Current installed | Wanted | Latest checked | Scope | Status / risk |
| --- | ---: | ---: | ---: | --- | --- |
| `react` | `19.2.4` | `19.2.6` | `19.2.6` | runtime | Patch update available. React 19 line is current/supported. Low risk if paired with `react-dom`. |
| `react-dom` | `19.2.4` | `19.2.6` | `19.2.6` | runtime | Patch update available. Keep in lockstep with `react`. |
| `lucide-react` | `1.7.0` | `1.16.0` | `1.16.0` | runtime UI icons | Minor update available. Usually low risk, but icon exports can change. |
| `codemirror` | `6.0.2` | `6.0.2` | `6.0.2` | runtime editor | Current by registry check. |
| `@codemirror/lang-*` packages | installed versions match registry latest for all checked language packages | same | same | runtime editor | Current by registry check. Direct packages checked: cpp, css, go, html, java, javascript, json, markdown, php, python, rust, sql, xml. |
| `@codemirror/theme-one-dark` | `6.1.3` | `6.1.3` | `6.1.3` | runtime editor | Current by registry check. |
| `@xterm/xterm` | `6.0.0` | `6.0.0` | `6.0.0` | runtime terminal | Current by registry check. xterm.js 6 package name is current under `@xterm/xterm`. |
| `@xterm/addon-fit` | `0.11.0` | `0.11.0` | `0.11.0` | runtime terminal | Current by registry check. |
| `@xterm/addon-web-links` | `0.12.0` | `0.12.0` | `0.12.0` | runtime terminal | Current by registry check. |
| `tailwindcss` | `4.2.2` | `4.3.0` | `4.3.0` | styling/build-time dependency listed as production dependency | Minor update available. This is build tooling, not browser runtime; consider moving to dev dependency if not imported at runtime. |
| `@tailwindcss/vite` | `4.2.2` | `4.3.0` | `4.3.0` | Vite plugin listed as production dependency | Minor update available. This is build tooling; should likely be dev dependency unless deployment installs production deps only and still needs to build. |

### Frontend Dev / Tooling Dependencies

| Package | Current installed | Wanted | Latest checked | Scope | Status / risk |
| --- | ---: | ---: | ---: | --- | --- |
| `vite` | `8.0.3` | `8.0.14` | `8.0.14` | dev server/build | Patch update available and urgent: current version is covered by high-severity Vite advisories. |
| `@vitejs/plugin-react` | `6.0.1` | `6.0.2` | `6.0.2` | build tooling | Patch update available. Low risk. |
| `@eslint/js` | `9.39.4` | `9.39.4` | `10.0.1` via `npm view`; `maintenance` dist-tag is `9.39.4` | lint tooling | Current on ESLint 9 maintenance line. ESLint 10 is latest major but has engine `^20.19.0 || ^22.13.0 || >=24`; current Node `23.11.1` does not satisfy it. Treat as risky major/toolchain decision. |
| `eslint` | `9.39.4` | `9.39.4` | `10.4.0` via `npm view`; `maintenance` dist-tag is `9.39.4` | lint tooling | Current on ESLint 9 maintenance line. ESLint 10 major requires Node `^20.19.0 || ^22.13.0 || >=24`; current Node `23.11.1` does not satisfy it. |
| `eslint-plugin-react-hooks` | `7.0.1` | `7.1.1` | `7.1.1` | lint tooling | Minor update available. Lint currently fails under existing rules, so update should be paired with lint remediation or explicitly deferred. |
| `eslint-plugin-react-refresh` | `0.5.2` | `0.5.2` | `0.5.2` | lint tooling | Current by registry check. |
| `globals` | `17.4.0` | `17.6.0` | `17.6.0` | lint tooling | Minor update available. Low risk. |
| `@types/react` | `19.2.14` | `19.2.15` | `19.2.15` | typing/tooling | Patch update available. Low risk. |
| `@types/react-dom` | `19.2.3` | `19.2.3` | `19.2.3` | typing/tooling | Current by registry check. |

### Backend Go Module

| Module | Current | Latest/upgrade check | Scope | Status / risk |
| --- | ---: | ---: | --- | --- |
| `github.com/creack/pty` | `v1.1.24` | `go list -m -u all` reported no upgrade | backend runtime terminal pty | Current by Go module proxy check. Required by `backend/internal/terminal/terminal.go`; should be direct, not `// indirect`, because source imports it directly. |
| `github.com/gorilla/websocket` | `v1.5.3` | `go list -m -u all` reported no upgrade | backend runtime websocket | Current by Go module proxy check. Required by `backend/internal/terminal/terminal.go`; should be direct, not `// indirect`, because source imports it directly. Gorilla websocket v1.5.3 is the current stable line from module check. |

Backend module notes:

- `wede/go.mod` declares `go 1.25.6`. That matches local Go, but it is very new; confirm CI/runtime images also use Go 1.25.6.
- `go test ./...` from module root includes `wede/node_modules/flatted/golang/pkg/flatted`. This is unnecessary supply-chain surface and can cause unrelated npm transitive files to affect Go test results.

### Database Tooling Module

| Module | Current | Latest/upgrade check | Scope | Status / risk |
| --- | ---: | ---: | --- | --- |
| `github.com/jackc/pgx/v5` | Missing from `database/go.mod` | `go list -m -versions` latest listed `v5.9.2` | database migration tooling runtime | Required by `database/migrate.go`, but not declared. `go test ./...` fails until this is added intentionally or the tool is removed/re-scoped. |

Database module notes:

- `wede/database/go.mod` has no `require` entries, but `database/migrate.go` imports `github.com/jackc/pgx/v5`.
- This dependency appears to be database tooling, not backend server runtime. It should be intentionally scoped as tooling/ops, or the migration tool should be folded into the backend module if it is part of application runtime operations.

## Advisories

### npm advisories

| Package | Installed path / reason | Severity | Advisory | Remediation |
| --- | --- | --- | --- | --- |
| `vite` `8.0.3` | Direct dev dependency; also used by `@tailwindcss/vite` and `@vitejs/plugin-react` | High | GHSA-4w7w-66w2-5vf9, GHSA-v2wj-q39q-566r, GHSA-p9ff-h696-f583 | Upgrade to `vite@8.0.14` or newer compatible version. Run `npm audit fix` or explicit package update, then rerun `npm ci`, `npm audit`, `npm run build`, `npm run lint`. |
| `postcss` `8.5.8` | Transitive under `vite@8.0.3` | Moderate | GHSA-qx2v-qp2m-jg93 | Upgrading Vite should move PostCSS to a fixed version (`>=8.5.10`). Verify with `npm ls postcss` and `npm audit --omit=dev`. |
| `brace-expansion` `1.1.12` | Transitive under `eslint@9.39.4 -> minimatch@3.1.5` | Moderate | GHSA-f886-m6hf-6m8v | `npm audit fix` should update the lockfile to a fixed transitive version if available. Verify with `npm ls brace-expansion`. Production audit omits this issue, so it is tooling-only. |

Production-vs-dev note:

- `npm audit --omit=dev` still reports Vite/PostCSS because `@tailwindcss/vite` and `tailwindcss` are in `dependencies`, and the dependency graph still includes Vite. These should likely be dev dependencies unless the production deployment installs dependencies and builds on the server.

### Go advisories

No Go vulnerability advisory scan was completed because `govulncheck` is not installed. `go list -m -u all` only checks versions, not known vulnerabilities. Follow up with `govulncheck ./...` for `wede/` and `wede/database/` after installing the tool.

## Lockfile / Reproducibility

| Check | Finding |
| --- | --- |
| `package-lock.json` format | Lockfile version 3 with 249 package entries. |
| Clean install | `npm ci` succeeds with registry/cache access. |
| Vulnerability state after clean install | Not clean: 3 npm audit findings remain. |
| `node_modules` state | `npm ls --depth=0` reports several `extraneous` optional/native helper packages even after `npm ci`; they are present in `package-lock.json`, so this likely reflects npm reporting/tree metadata rather than local drift, but should be watched. |
| Go sums | Backend `go.sum` is small and matches the two declared modules. Database `go.sum` is empty because `database/go.mod` declares no dependencies, but source imports `pgx/v5`; database lock state is incomplete. |
| Cross-ecosystem contamination | Go module root includes `node_modules`, causing `go list ./...` and `go test ./...` to traverse an npm transitive Go package. This is unnecessary risk and noise. |

## Upgrade Plan

### Safe patch/minor first

1. Frontend security patch:
   - Update `vite` from `8.0.3` to `8.0.14`.
   - Ensure `postcss` resolves to `>=8.5.10`.
   - Ensure `brace-expansion` resolves to a fixed version.
   - Recommended command shape: `npm audit fix`, then inspect the lockfile diff. If the diff is broader than expected, use explicit `npm install vite@8.0.14` plus targeted transitive remediation.

2. Frontend low-risk freshness:
   - Update `react` and `react-dom` together from `19.2.4` to `19.2.6`.
   - Update `@types/react` to `19.2.15`.
   - Update `@vitejs/plugin-react` to `6.0.2`.
   - Update `tailwindcss` and `@tailwindcss/vite` to `4.3.0`.
   - Update `lucide-react` to `1.16.0`.
   - Update `eslint-plugin-react-hooks` to `7.1.1` and `globals` to `17.6.0`.

3. Dependency scoping:
   - Move `tailwindcss` and `@tailwindcss/vite` from `dependencies` to `devDependencies` unless production runtime truly imports them.
   - Keep React, CodeMirror, xterm, and lucide as runtime dependencies.

4. Go module hygiene:
   - In `wede/go.mod`, remove `// indirect` markers from `github.com/creack/pty` and `github.com/gorilla/websocket`, because backend source imports both directly.
   - Add an exclusion strategy so Go commands from `wede/` do not include `node_modules`; options include moving the Go module root to `wede/backend`, running backend checks with explicit package patterns, or keeping frontend dependencies outside the Go module tree.

5. Database tooling:
   - Decide whether `database/` is active tooling. If yes, add `github.com/jackc/pgx/v5` deliberately, likely current `v5.9.2`, then run `go test ./...`.
   - If the database tool is obsolete, remove or archive it rather than leaving a broken module.

### Risky majors / explicit decisions

1. ESLint 10:
   - Registry latest is `eslint@10.4.0` and `@eslint/js@10.0.1`.
   - Current Node is `v23.11.1`, but ESLint 10 declares engines `^20.19.0 || ^22.13.0 || >=24`.
   - Recommendation: do not upgrade ESLint major until the project standardizes on Node 24+ or an approved supported Node line. Stay on ESLint 9 maintenance for now.

2. Node runtime:
   - Node `23.11.1` is a non-LTS line. For reproducible frontend tooling, choose a supported LTS/current baseline and encode it in project docs/tooling, for example `.nvmrc`, `.node-version`, or `package.json` `engines`.

3. Go 1.25.6:
   - Local Go and `go.mod` match, but CI/container compatibility should be confirmed. If deployment images lag behind, this can break builds.

## Followups / Ambiguities

- Confirm intended production install/build model. If production installs only runtime dependencies, Tailwind/Vite plugin placement in `dependencies` is too broad. If production builds from source, this may be intentional but should be documented.
- Install and run `govulncheck` for both Go modules. Version freshness is checked; Go vulnerability advisories are not.
- Decide whether `database/` is production migration tooling, local-only tooling, or stale code. Current state fails compilation because `pgx/v5` is missing from `database/go.mod`.
- Decide how to prevent Go commands from traversing `node_modules`. This is the largest supply-chain hygiene issue outside the npm advisories.
- Lint currently fails before any dependency upgrade. Upgrading `eslint-plugin-react-hooks` may add or change React Compiler-era rules, so schedule dependency updates and lint remediation together.
- The build succeeds, but the single JS bundle is large. Consider code-splitting CodeMirror language packages and terminal/editor surfaces if initial load size matters.
