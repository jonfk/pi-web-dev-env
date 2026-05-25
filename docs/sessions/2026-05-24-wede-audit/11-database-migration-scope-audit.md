# Ticket 11: Database and Migration Scope Audit

## Scope

Audit-only review of `wede/database` to decide whether it is active product code, legacy code, or unrelated repository residue. No source files were modified.

Primary files reviewed:

- `wede/database/migrate.go`
- `wede/database/go.mod`
- `wede/database/go.sum`
- `wede/database/migrations/20260327000024_initial_setup.sql`
- `wede/database/seed.sql`
- `wede/README.md`
- `wede/package.json`
- `wede/.github/workflows/ci.yml`
- `wede/.github/workflows/release.yml`
- `wede/landing/index.html`

## Commands Run

From repository root `/Users/jfokkan/Developer/jonfk_code/pi-web-dev-env`:

```bash
pwd
rg --files
git status --short
sed -n '1,220p' wede/AGENTS.md
sed -n '1,260p' wede/README.md
sed -n '1,260p' wede/database/migrate.go
sed -n '261,520p' wede/database/migrate.go
sed -n '1,220p' wede/database/go.mod
sed -n '1,260p' wede/database/migrations/20260327000024_initial_setup.sql
sed -n '1,260p' wede/database/seed.sql
rg -n "database|DATABASE_URL|migrate|migration|_migrations|seed.sql|postgres|pgx|supabase|CREATE TABLE|users|projects|payments|credits" wede docker docs TODO.md justfile
find . -maxdepth 4 -type f \( -name '*ci*' -o -name '*.yml' -o -name '*.yaml' -o -name 'Makefile' -o -name 'justfile' -o -name 'package.json' -o -name 'go.mod' \) -print
find wede -maxdepth 3 -name .git -type d -print
find wede -maxdepth 2 -type f -name '.env*' -print
```

From `/Users/jfokkan/Developer/jonfk_code/pi-web-dev-env/wede/database`:

```bash
go test ./...
go list -m -u all
```

From nested repo `/Users/jfokkan/Developer/jonfk_code/pi-web-dev-env/wede`:

```bash
git status --short --untracked-files=all
git ls-files database README.md .github/workflows package.json go.mod
git log --oneline --decorate -- database README.md .github/workflows package.json go.mod
git log --follow --format='%h %ad %s' --date=short -- database/migrate.go
git log --follow --format='%h %ad %s' --date=short -- database/migrations/20260327000024_initial_setup.sql
git show --stat --summary 710ed3f
git show 710ed3f:README.md | sed -n '1,180p'
rg -n "database|DATABASE_URL|go run ./database|migrate|postgres|pgx|users|_migrations" . --glob '!node_modules/**' --glob '!.git/**'
sed 's/=.*$/=<redacted>/' .env.dev
sed 's/=.*$/=<redacted>/' .env.main
nl -ba database/migrate.go | sed -n '1,280p'
nl -ba README.md | sed -n '45,140p'
nl -ba .github/workflows/ci.yml | sed -n '1,120p'
nl -ba package.json | sed -n '1,80p'
nl -ba database/migrations/20260327000024_initial_setup.sql
nl -ba database/seed.sql
```

Verification results:

- `go test ./...` failed before test execution because `database/migrate.go` imports `github.com/jackc/pgx/v5`, but `wede/database/go.mod` has no `require` entry for it.
- `go list -m -u all` returned only `wede/database`, because the database module declares no dependencies.

## Usage Evidence

Evidence against active product use:

- The product README says the packaged product has "No Docker, no Node.js runtime, no database" at `wede/README.md:57`.
- The landing page repeats "No Docker, no Node runtime, no database" in `wede/landing/index.html`.
- The documented dev/build flow uses frontend scripts and the backend command under `wede/backend`; no README path asks users to run migrations.
- `wede/package.json:6-13` has no database or migration script.
- `wede/.github/workflows/ci.yml:25-33` runs `npm ci`, `npm run build`, and builds `./backend/cmd/wede`; it does not run `go test` or `go build` in `database`.
- `wede/.github/workflows/release.yml` follows the same frontend plus backend binary path and does not package or run database migrations.
- Search outside `wede/database` found no application imports, command invocations, docs, CI, Docker, or install script references that use the migration runner.
- The SQL schema is generic example data: `database/migrations/20260327000024_initial_setup.sql:5` labels the table as "Example: users table", and `database/seed.sql:2-4` inserts `admin@example.com`.
- Git history shows `database/` was added in the initial commit on 2026-03-27 and has not been touched since. Later product/auth changes updated README/backend/frontend files but not the database folder.

Evidence that it may once have been intended as manual tooling:

- `database/migrate.go:6-14` includes manual usage comments for `go run ./database/`, `--env`, `--status`, and `--reset`.
- `database/migrate.go:36-40` maps `main`, `dev`, and `local` environments to `.env.main`, `.env.dev`, and `.env.local`.
- `.env.dev` and `.env.main` are tracked in the nested `wede` repo and contain `DATABASE_URL` keys. Values were intentionally redacted during inspection.

## Scope Decision

Decision: **legacy or template residue, not active product code**.

Confidence: high enough to avoid deeper active-code audit. The folder is tracked in the nested `wede` repository, but all product evidence points away from it: README/landing claims no database, build/release flows ignore it, app code has no references, and the standalone module does not currently compile because its declared dependencies are incomplete.

It is not clearly "unrelated repository residue" in the sense of an accidental untracked directory, because it was committed in the initial `wede` repo with env-file conventions. The most likely explanation is that this was scaffolded or planned early and then abandoned while the product became a single-binary, no-database IDE.

## Lightweight Health/Security Notes

These notes are intentionally shallow because the scope decision is inactive/legacy.

- **Does not compile as checked in:** `database/migrate.go:27` imports `github.com/jackc/pgx/v5`, but `database/go.mod` declares only `module wede/database` and `go 1.25.6`. Suggested `go test ./...` fails with "no required module provides package github.com/jackc/pgx/v5".
- **Env parsing is fragile:** `loadDatabaseURL` at `database/migrate.go:56-65` manually splits lines on `=` and trims whitespace. It does not handle quoted dotenv values, inline comments, `export DATABASE_URL=...`, escaped newlines, or spaces intentionally included in values.
- **Unknown env crashes before useful error:** `envFiles[*env]` is indexed without validation at `database/migrate.go:239-240`; an unsupported `--env` can produce misleading empty-path behavior and then call `filepath.Base("")`.
- **Migration tracking SQL is injection-prone for filenames:** `applyFile` builds one SQL string with `fmt.Sprintf` and embeds `name` directly into `INSERT INTO _migrations (filename) VALUES ('%s')` at `database/migrate.go:131-134`. Filenames come from local migration file names, not user input, but a malicious or accidental quote in a migration filename can break SQL or execute extra statements.
- **Seed tracking shares the migration table:** `seed.sql` is recorded as filename `seed.sql` via the same `applyFile` path at `database/migrate.go:174-177`. This works only as a convention and can collide with a migration named `seed.sql` if one is ever added.
- **Reset is intentionally destructive but not guarded:** `cmdReset` executes `DROP SCHEMA public CASCADE; CREATE SCHEMA public;` at `database/migrate.go:223-230`. There is no confirmation prompt, production/main refusal, hostname/db-name check, dry run, or separate force flag.
- **Connection string disclosure:** `main` prints the first 30 characters of `DATABASE_URL` at `database/migrate.go:242-249`. That can expose username, host, database name, or part of a password depending on URL shape.
- **No concurrency guard:** Multiple runner instances can race after reading `_migrations`, because migrations are not protected by advisory locks. The primary key may stop duplicate tracking inserts, but it does not make arbitrary migration SQL safe under concurrent execution.
- **SQL migration is placeholder quality:** The initial migration creates a generic `users` table and an update trigger; no active wede backend code reads or writes it.

## Recommendations

Recommended path: **remove `wede/database` from product scope unless an owner confirms an active near-term database plan.**

Specific cleanup/docs recommendations:

1. If wede is intentionally no-database, delete `wede/database` and remove tracked `DATABASE_URL` env entries from `.env.dev` / `.env.main` if they are not used elsewhere.
2. If the folder is kept as future or optional tooling, document that status explicitly in README or a local `database/README.md`, add it to normal checks, fix `go.mod`, and make CI run `cd database && go test ./...`.
3. If it is active for a private deployment mode, reconcile product claims: README and landing should not claim "no database" without qualifying the deployment mode.
4. Before any active use, replace the migration tracking insert with a parameterized query or at least `pgx` batch/transaction calls, add a force-confirm guard for reset, validate `--env`, avoid printing connection strings, and use a real dotenv parser.

## Followups/Ambiguities

- Is there an owner-confirmed private deployment that still depends on `.env.dev`, `.env.main`, or `wede/database`?
- Should the tracked `.env.dev` and `.env.main` files exist at all? They contain `DATABASE_URL` keys and possibly deploy-specific values; this audit redacted values and did not assess secret exposure.
- If `database/` is removed, should Ticket 02 dependency/supply-chain conclusions exclude `wede/database` entirely from product dependency scope?
