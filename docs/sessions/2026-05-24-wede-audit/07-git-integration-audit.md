# Ticket 7: Git Integration Audit

## Scope

Audit-only review of Git behavior in:

- `wede/backend/internal/git/git.go`
- `wede/src/components/GitPanel.jsx`
- `wede/src/components/FileExplorer.jsx`
- `wede/src/components/IDE.jsx`

Focus areas: `git status --porcelain` parsing, command argument safety, branch/checkout/commit workflow UX, repo state handling, and graph correctness. No source files were modified.

## Commands Run

- `git status --short`
- `rg --files | rg '(^|/)(git.go|GitPanel.jsx|FileExplorer.jsx|IDE.jsx|go.mod|package.json)$|docs/sessions'`
- `sed -n ...` / `nl -ba ...` on the primary files
- `rg -n "git/(status|log|stage|unstage|commit|branches|checkout)|New\\(.*git|internal/git" wede/backend wede/src`
- `rg -n "exec\\.Command|CombinedOutput|/api/git|checkout|branch|status --porcelain|git status" wede/backend wede/src`
- `cd wede/backend && go test ./...`

Result:

```text
?   	wede/backend/cmd/wede	[no test files]
?   	wede/backend/internal/auth	[no test files]
?   	wede/backend/internal/config	[no test files]
?   	wede/backend/internal/files	[no test files]
?   	wede/backend/internal/git	[no test files]
?   	wede/backend/internal/terminal	[no test files]
?   	wede/backend/internal/workspace	[no test files]
```

Temporary fixture repos were created only under `/private/tmp`:

- `/private/tmp/wede-git-audit.oMy0od`
- `/private/tmp/wede-git-audit2.jhzhJt`
- `/private/tmp/wede-git-copy.MaNWvx`
- `/private/tmp/wede-git-nonrepo.X3c3QK`
- `/private/tmp/wede-git-unborn-stage.aK8ZnF`

## Scenario Coverage

Covered with real Git repos or direct Git output:

- Non-Git workspace
- Empty unborn repo
- Unborn repo with staged file
- Modified, staged modified, untracked, renamed, deleted files
- Paths containing spaces, quotes, leading dash, and newline
- Merge conflict
- Dirty checkout blocked by Git
- Detached HEAD
- Dirty submodule
- Merge history, branches, tags, and delimiter-bearing commit subject
- Backend test suite

Not fully covered:

- Frontend visual graph rendered in browser; audit is code/fixture-output based.
- Large histories performance; only algorithmic/code-path risks were reviewed.
- Real remote repository behavior; remote branch behavior is inferred from `git branch -a` and `git checkout <remote/ref>` semantics.

## Parser Findings

### P1: `status --porcelain` parsing is incorrect for quoted paths, including ordinary spaces

Code: `wede/backend/internal/git/git.go:54-75`

The handler runs `git status --porcelain` and slices each line with `line[3:]`, then trims and optionally splits on `" -> "`. This parses the human-quoted porcelain text, not the actual path.

Fixture output:

```text
 D deleted.txt
R  "old name.txt" -> "new name.txt"
M  normal.txt
 M "quote\"name.txt"
 M "space name.txt"
?? --dash.txt
?? "line\nbreak.txt"
?? "untracked file.txt"
```

Current parser would return paths such as:

- `"new name.txt"` including quotes
- `"space name.txt"` including quotes
- `"quote\"name.txt"` including quotes and escapes
- `"line\nbreak.txt"` as escaped text rather than the real newline-containing path

Impact:

- GitPanel stage/unstage actions send the parsed path back to the backend.
- `git add "\"space name.txt\""` does not target `space name.txt`.
- FileExplorer Git coloring keys will not match actual file paths for quoted output.

Recommended fix direction:

- Use `git status --porcelain=v1 -z` or porcelain v2 with `-z`.
- Parse NUL-delimited records, including the special rename/copy two-path form.
- Preserve raw paths as actual strings; add separate display fields if quoting is desired in the UI.

### P1: Rename parsing loses old path and breaks on quoted rename output

Code: `wede/backend/internal/git/git.go:73-75`

For a rename, default porcelain emits:

```text
R  "old name.txt" -> "new name.txt"
```

The code returns only the post-arrow string and keeps quotes. That is enough to show one row, but not enough for robust diff/display semantics. With `-z`, Git emits rename records differently:

```text
b'R  new name.txt\x00old name.txt\x00...'
```

Recommended fix direction:

- Represent status records with `path` and optional `oldPath`.
- Add explicit parser tests for rename records from `--porcelain=v1 -z`.

### P1: Conflict states are collapsed to generic modified/deleted rows

Code: `wede/backend/internal/git/git.go:84-111`

Fixture output for a content conflict:

```text
UU conflict.txt
```

The current code treats `x='U'` as a staged `modified` row and `y='U'` as an unstaged `modified` row because `U` falls through to the default status. Other unmerged combinations (`AA`, `DD`, `AU`, `UD`, `DU`, `UA`) would also be misrepresented.

Impact:

- A conflicted file appears as normal modified work.
- The commit button can become enabled based on staged rows even though Git will reject unresolved conflicts.
- Users do not get a clear conflict state or resolution workflow.

Recommended fix direction:

- Add `conflicted` / `unmerged` status with raw XY state.
- Disable commit while any unmerged entries exist.
- Surface a clear merge-conflict message in GitPanel.

### P2: Submodule state is too coarse

Fixture output for a dirty submodule:

```text
 M vendor/sub
```

Current parser maps this to a normal unstaged modified file. Porcelain can encode richer submodule states (`M`, `m`, `?` in submodule-aware formats). The UI does not distinguish "submodule commit changed" from "submodule has dirty content/untracked content."

Recommended fix direction:

- Use porcelain v2 if submodule detail matters, or explicitly document/coarsen submodules as modified directories.
- Add fixture tests for dirty submodule, changed submodule HEAD, and untracked content inside submodule.

### P2: Log parser uses `|` as an unsafe field delimiter

Code: `wede/backend/internal/git/git.go:144-169`

Fixture command:

```text
git log --format='%H|%h|%s|%an|%ar|%D|%P' -n 10 --all
```

Fixture output included a subject with a pipe:

```text
5c83edc...|5c83edc|root | pipe subject|Audit|0 seconds ago|tag: v1.0|
```

The handler uses `strings.SplitN(line, "|", 7)`, so delimiter-bearing subjects shift fields. That can corrupt message, author, date, refs, and parents.

Recommended fix direction:

- Use NUL or ASCII unit/record separators in the `git log --format`.
- Or request JSON-like safe fields is not available from Git directly; custom separators are the usual route.

### P2: Log order is not topological, which can make graph lanes wrong

Code: `wede/backend/internal/git/git.go:144`; `wede/src/components/GitPanel.jsx:55-93`

The handler calls:

```text
git log --format=... -n 50 --all
```

In the merge fixture, output order was:

```text
feature
merge-feature
root | pipe subject
main
```

Because `--topo-order` is not used, parents can appear before children when timestamps are close or histories interleave. `buildGraph` assumes it can maintain active lanes while walking entries; non-topological ordering risks visually incorrect branch/merge lines.

Recommended fix direction:

- Use `git log --topo-order --date-order --decorate=short ... --all`.
- Add pure unit tests for `buildGraph` with merge commits and criss-cross/interleaved branch histories.

## Workflow/UX Findings

### P1: Stage is protected from shell injection but not Git option injection for leading-dash paths

Code: `wede/backend/internal/git/git.go:27`, `wede/backend/internal/git/git.go:212`

Good: Git commands are executed with `exec.Command("git", args...)`, so commit messages and paths are not evaluated by a shell.

Problem: `Stage` runs:

```go
h.run("add", path)
```

For a real file named `--dash.txt`, Git treats the path as an option:

```text
git add --dash.txt
error: unknown option `dash.txt'
```

The safe form works:

```text
git add -- --dash.txt
```

`Diff` and `Unstage` already use `--` before paths. `Stage` should do the same for non-empty file paths. For stage-all, keep intentional `.` behavior.

### P1: Checkout accepts user-controlled option-like strings

Code: `wede/backend/internal/git/git.go:305`

`Checkout` runs:

```go
h.run("checkout", body.Branch)
```

This is not shell injection, but it allows Git to interpret leading-dash input as checkout options. The frontend mostly supplies branch names or hashes, but the backend endpoint is still directly callable.

Recommended fix direction:

- Validate that checkout target is an existing branch/ref/hash returned by trusted Git queries, or use a safer endpoint split: checkout branch, checkout commit, create branch.
- Reject empty strings and leading-dash targets unless intentionally supported.
- Prefer `git switch` for branches and `git checkout --detach <hash>` for commit checkout.

### P1: Checkout/commit/stage errors are swallowed in the frontend

Code: `wede/src/components/GitPanel.jsx:280-310`

The frontend awaits `authFetch` but never checks `res.ok` or reads/display errors for:

- stage
- unstage
- stage all
- unstage all
- commit
- checkout branch
- checkout commit

Impact:

- Dirty checkout correctly fails in Git:

```text
error: Your local changes to the following files would be overwritten by checkout:
	file.txt
Please commit your changes or stash them before you switch branches.
Aborting
```

But GitPanel just refreshes, with no warning or explanation.

- Commit failures from missing user identity, unresolved conflicts, hooks, empty commit, or no staged changes are invisible.

Recommended fix direction:

- Add a visible error/toast/inline message path for failed Git actions.
- Preserve backend output but normalize common cases into friendlier messages.

### P1: Checkout does not warn before risky branch/commit changes

Code: `wede/src/components/GitPanel.jsx:303-310`, `wede/src/components/GitPanel.jsx:426-428`

Branch rows immediately call checkout on click. Commit context menu immediately checks out a commit. There is no confirmation, dirty-worktree preflight, or detached HEAD explanation.

Observed Git behavior for dirty checkout: Git blocks when the target would overwrite local edits, but cleanly switching branches with unrelated uncommitted changes can still carry changes across branches. Checking out a commit detaches HEAD.

Recommended fix direction:

- Before checkout, inspect status and warn if there are uncommitted changes.
- For commit checkout, explicitly confirm detached HEAD.
- Consider separate actions: "Switch branch", "Create branch from commit", "Detach at commit".

### P2: Detached HEAD is not represented correctly

Fixture output:

```text
git branch --show-current

git branch -a --format='%(refname:short)|%(HEAD)'
(HEAD detached at bb76934)|*
main|
```

Code:

- Status branch uses `git branch --show-current`, which returns empty in detached HEAD.
- Branch list marks current by comparing branch name to `current`, so `(HEAD detached at ...)` is not marked current.
- GitPanel can render `(HEAD detached at ...)` as a clickable branch row; clicking it attempts checkout of that literal display string.

Recommended fix direction:

- Return structured state: `branch`, `head`, `detached`, `headLabel`.
- Do not treat the detached pseudo-ref as a checkoutable branch.

### P2: Unborn branch UX is ambiguous

Fixture output:

```text
git status --porcelain

git branch --show-current
main

git branch -a --format='%(refname:short)|%(HEAD)'

```

An empty unborn repo has `branch=main`, no branches, no log entries, and no files. GitPanel shows a normal clean state plus "No commits yet" / "No branches". That is technically plausible but misses useful guidance for the first commit.

Recommended fix direction:

- Detect unborn state with `git rev-parse --verify HEAD` failure.
- Show "No commits yet" in the changes panel and allow initial commit flow when staged files exist.

### P2: Non-Git status is handled, but related fetch failures are silently ignored

Code:

- Backend status returns `isRepo:false` for non-repo: `wede/backend/internal/git/git.go:54-58`
- GitPanel fetches status/log/branches concurrently and swallows errors: `wede/src/components/GitPanel.jsx:267-275`

The status endpoint supports the non-repo UI. However, because refresh uses `Promise.all`, if `/api/git/log` or `/api/git/branches` returns malformed/non-JSON output in a future change, the whole refresh path would be swallowed and stale state could remain.

Recommended fix direction:

- Treat status as primary; fetch log/branches only if `isRepo`.
- Clear stale state on refresh failures.

### P2: FileExplorer status map loses staged/unstaged distinctions and old paths

Code: `wede/src/components/FileExplorer.jsx:209-215`

The map stores only `map[f.path] = f.status`. If a file has both staged and unstaged changes, one overwrites the other. Renames have no `oldPath`, and quoted parser paths will not match real explorer entries.

Recommended fix direction:

- Key by actual path from a robust parser.
- Preserve aggregate status per path: staged, unstaged, conflicted, renamed old/new path.

### P3: Visual graph labels are useful but incomplete for remotes/tags

Code: `wede/src/components/GitPanel.jsx:130-152`

Refs are split by `", "` and colored with simple heuristics:

- includes `HEAD`: green
- starts with `origin/`: peach
- otherwise accent

This handles basic refs but does not distinguish local branches, tags, non-origin remotes, symbolic refs, or detached HEAD labels. Ref names containing comma-space are rare but possible and would split incorrectly because refs are parsed from Git's `%D` decoration string.

Recommended fix direction:

- Emit structured decoration fields from backend where possible.
- At minimum, use `--decorate=short` with safer parsing and support `tag:`, `HEAD ->`, and arbitrary remote names.

## Test Cases To Add

Backend parser tests:

- Clean repo returns `isRepo:true`, empty files, current branch.
- Non-repo returns `isRepo:false`.
- Unborn repo returns `isRepo:true`, branch name, empty log/branches state handled separately.
- `--porcelain=v1 -z` paths with spaces, quotes, newline, tab, leading dash.
- Staged/unstaged combinations: `M `, ` M`, `MM`, `A `, ` D`, `D `.
- Rename with spaces: `R  new path\0old path\0`.
- Deleted file staging and unstaged deletion.
- Untracked file with leading dash.
- Conflict XY states: `UU`, `AA`, `DD`, `AU`, `UD`, `DU`, `UA`.
- Dirty submodule and changed submodule HEAD.
- Log parsing with commit subject containing `|`, author containing punctuation, refs/tags/remotes, merge parents.

Backend command tests:

- `Stage("--dash.txt")` must call `git add -- --dash.txt`.
- `Diff("--dash.txt")` and `Unstage("--dash.txt")` remain safe.
- `Checkout("")` returns 400.
- `Checkout("--orphan")` / option-like target is rejected or intentionally handled.
- Commit with empty message returns 400; commit failure returns useful error body.

Frontend tests:

- GitPanel displays backend action errors.
- Dirty checkout warning appears before branch/commit checkout.
- Detached HEAD state is visible and not rendered as a normal branch.
- Conflict files show conflict styling and disable commit until resolved.
- FileExplorer shows correct status for quoted/space paths and combined staged+unstaged state.
- Graph unit tests for merge, branch, tag, remote, detached HEAD, and >50 commit truncation behavior.

## Followups / Ambiguities

- Should the Git panel support advanced operations such as checkout arbitrary commit, detached HEAD, remote branch checkout, and submodule detail, or should it intentionally stay small and safe?
- Should "Stage All" include untracked files (`git add .`) as it does today, or should it mirror VS Code's staged/unstaged grouping with clearer separate actions?
- Should checkout with dirty worktree be blocked by policy or allowed after confirmation when Git would permit it?
- Recommendation: prioritize a backend parser refactor to `--porcelain -z`, explicit conflict state, and frontend error display before expanding graph features.
