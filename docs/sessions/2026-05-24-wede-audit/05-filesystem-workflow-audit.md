# Ticket 5: Filesystem Workflow Audit

## Scope

Audited file explorer, editor tab state, and backend file API behavior from UI to backend.

Primary files reviewed:

- `wede/backend/internal/files/files.go`
- `wede/src/components/FileExplorer.jsx`
- `wede/src/components/Editor.jsx`
- `wede/src/components/EditorTabs.jsx`
- `wede/src/components/IDE.jsx`
- Supporting context: `wede/src/App.jsx`, `wede/backend/internal/workspace/workspace.go`, `wede/backend/cmd/wede/main.go`

No source changes were made. This report is the only file created.

## Commands Run

- `pwd`
  - Confirmed workspace: `/Users/jfokkan/Developer/jonfk_code/pi-web-dev-env`
- `rg --files wede | head -200`
  - Located frontend/backend files for audit.
- `git status --short`
  - No working tree changes before report creation.
- `sed` / `nl -ba` / `rg` / `find` / `ls`
  - Inspected implementation and gathered line references.
- `cd wede && npm run build`
  - Failed before build: `sh: vite: command not found`.
  - `wede/node_modules/vite` exists, but `wede/node_modules/.bin` does not, so this checkout appears to have an incomplete dependency install.
- `cd wede/backend && go test ./...`
  - Passed. All backend packages report `[no test files]`.

## Workflow Matrix

| Operation | Backend behavior | UI behavior | Scenario coverage | Audit result |
|---|---|---|---|---|
| List root | `GET /api/files?path=` maps empty path to workspace root. Filters `.git`, `node_modules`, `.DS_Store`; other hidden files are included. Sorts dirs first, case-insensitive. | `FileExplorer.loadRoot()` fetches root and only updates state if response JSON is an array. Errors are swallowed. | Manual scenario: open workspace with files, folders, `.env`, `.git`, `node_modules`; press refresh. | Mostly functional, but backend errors and non-array error payloads are invisible. |
| List nested folder | `GET /api/files?path=nested` calls `os.ReadDir` on safe path. | `TreeNode` lazily fetches children once when expanded. Refresh button only reloads root, not already-expanded child node state. | Manual scenario: expand `src/components`, create/delete a file in that folder externally, press Explorer refresh. | Nested refresh is unreliable; expanded children can stay stale until collapsed/remounted/workspace changes. |
| Read file | `GET /api/files/read?path=...` uses `os.Stat`, rejects files over 10 MB, then `os.ReadFile` and JSON string content. Does not reject directories before `ReadFile`. | `IDE.openFile()` reads content and opens tab. It does not check `res.ok` or validate `data.content`. Errors are swallowed. | Manual scenario: open normal text file, >10 MB file, unreadable file, binary file, directory path via API. | Text read works. Large/unreadable/binary failures have no user-visible error; binary is treated as UTF-8 text. |
| Write/save file | `PUT /api/files/write` decodes body through a 10 MB `LimitReader`, creates parent dirs, writes bytes from JSON string with mode `0644`. Overwrites unconditionally. | Save button calls write and marks tab unmodified regardless of response status if fetch resolves. | Manual scenario: edit file, save; separately make target unwritable or trigger 413/400, then save. | Functional for small text. Failed saves can be shown as successful; no conflict detection or mtime/version check. |
| Create file | `POST /api/files/create` creates parents and calls `os.WriteFile(path, []byte{}, 0644)`. Existing file is truncated to empty. | Header new-file input sends `path: newName`; supports nested names if user types slashes. Does not check response or show errors. | Manual scenario: create `notes.md`; then create `notes.md` again. | Dangerous conflict behavior: duplicate create truncates existing file without confirmation. |
| Create folder | `POST /api/files/create` with `isDir: true` calls `os.MkdirAll`; existing folder is treated as success. | Header new-folder input sends root-relative path only. | Manual scenario: create `tmp/a/b`; create same folder again. | Works, but no conflict signal and no UI placement inside selected/expanded folder. |
| Rename file | `POST /api/files/rename` creates destination parent dir and calls `os.Rename(old, new)`. Can overwrite an existing file on Unix-like systems. | Context menu opens a global rename input; submit preserves original directory and changes basename. Tabs are not updated. Errors are swallowed. | Manual scenario: open `a.txt`, rename to `b.txt`; then rename `a.txt` to existing `b.txt`. | Filesystem rename works but can overwrite conflicts; open tabs become stale and save can recreate/write old path. |
| Rename folder | Same backend `os.Rename`. Destination parent dirs auto-created. | Same global rename input. Expanded state and open child tabs are not reconciled. | Manual scenario: open `dir/file.txt`, rename `dir` to `dir2`, then edit/save open tab. | Folder rename works at filesystem level, but open child tabs point at old paths and can recreate old folder/files on save. |
| Delete file | `DELETE /api/files/delete?path=...` calls `os.RemoveAll`; workspace root deletion is blocked. Missing path generally succeeds. | Context menu delete calls API immediately, no confirmation, no tab cleanup. | Manual scenario: open and modify `a.txt`, delete `a.txt` in explorer. | Destructive and silent. Open modified tab survives and save can recreate deleted file. |
| Delete folder | Same `os.RemoveAll`, recursive. | Context menu delete calls immediately, no confirmation, no tab cleanup for descendant files. | Manual scenario: open `dir/file.txt`, delete `dir`. | High data-loss risk: recursive delete has no confirmation or recovery. |
| Copy file | No backend copy endpoint. UI implements copy as read source then write destination. | Context menu copy stores path; paste on folder writes same basename into target folder. Keyboard paste writes to root. | Manual scenario: copy `a.txt`, paste into `dir`; paste where `dir/a.txt` exists. | Works for small text files only. Overwrites destination silently; binary/large files fail or corrupt. |
| Copy folder | Backend has no recursive copy endpoint. UI allows copying a folder, but paste tries `/api/files/read` on folder then writes `data.content`. | Folder copy appears available, but paste cannot correctly copy trees. | Manual scenario: copy folder `dir`, paste into root or another folder. | Broken. Folder copy either silently fails or creates an empty/undefined-content file-like artifact depending backend response handling. |
| Hidden files | Backend hides only `.git`, `node_modules`, `.DS_Store`. | Explorer shows other dotfiles with normal file icon logic. | Manual scenario: workspace has `.env`, `.gitignore`, `.config/file`. | Mostly supported, but hidden policy is implicit and inconsistent. |
| Symlinks | `safePath` checks lexical path only; `os.Stat`, `ReadFile`, `WriteFile`, and `ReadDir` can follow symlinks. | Explorer likely renders symlink entries as files, but API can still access symlink target paths directly. | Manual scenario: workspace contains symlink `outside -> /tmp/outside`; call read/list/write through API. | Unsafe: symlinks can escape workspace for read/write/list operations. |
| Binary files | Backend converts bytes to Go string and JSON encodes content. Invalid UTF-8 is not preserved as original bytes. | Editor always treats content as text and status bar always says UTF-8. | Manual scenario: open/copy a PNG or file with invalid UTF-8 bytes. | Unsupported but not detected; read/copy/save can corrupt binary data. |

## Findings / Repro Steps

### 1. Path containment can be bypassed with sibling-prefix paths

Evidence: `safePath` builds `full := filepath.Join(ws, cleaned)` and checks `strings.HasPrefix(full, ws)` in `wede/backend/internal/files/files.go:53-56`.

Why it matters: if the workspace is `/tmp/ws`, a request path like `../ws-other/secret.txt` can produce `/tmp/ws-other/secret.txt`, which still has string prefix `/tmp/ws`. That can allow read/write/create/rename/delete/list outside the workspace.

Repro steps:

1. Open workspace `/tmp/ws`.
2. Ensure sibling path `/tmp/ws-other/secret.txt` exists.
3. Request `GET /api/files/read?path=..%2Fws-other%2Fsecret.txt`.
4. Expected: 403 outside workspace. Actual risk from code: allowed because of lexical prefix match.

Recommended fix direction: use `filepath.Rel` after cleaning/evaluating paths and reject `..` rel paths; consider `EvalSymlinks` for operations that must not escape via symlink.

### 2. Symlinks can escape the workspace

Evidence: backend never rejects symlink entries or resolves real paths before access. `Read` uses `os.Stat` and `os.ReadFile` in `wede/backend/internal/files/files.go:125-138`; `Write` uses `os.WriteFile` in `wede/backend/internal/files/files.go:174-177`.

Repro steps:

1. In workspace, create a symlink `outside-link` pointing to a file outside the workspace.
2. Call `GET /api/files/read?path=outside-link`.
3. Edit and save the symlink path from UI or API.
4. Expected: blocked or clearly labelled symlink policy. Actual risk: outside target is read/written.

### 3. Duplicate create truncates existing files

Evidence: create-file path calls `os.WriteFile(full, []byte{}, 0644)` in `wede/backend/internal/files/files.go:213-215`; `os.WriteFile` truncates existing files.

Repro steps:

1. Create `notes.md` with content.
2. Use Explorer new-file input and enter `notes.md` again.
3. Expected: conflict prompt/error. Actual: backend truncates the existing file to empty and UI shows no warning.

### 4. Rename can overwrite existing destination and stale tabs can recreate old paths

Evidence: rename calls `os.Rename(oldFull, newFull)` in `wede/backend/internal/files/files.go:280-283`; UI does not update open tabs after rename in `wede/src/components/FileExplorer.jsx:272-281`; save writes tab path unchanged in `wede/src/components/IDE.jsx:231-241`.

Repro steps:

1. Create `a.txt` and `b.txt` with different content.
2. Rename `a.txt` to `b.txt`.
3. Expected: conflict warning. Actual risk: `b.txt` is overwritten on Unix-like systems.
4. Open `dir/file.txt`, rename `dir` to `dir2`, edit the still-open tab, and save.
5. Expected: tab path updates or save blocked. Actual risk: old `dir/file.txt` is recreated.

### 5. Save success is optimistic even when backend rejects the write

Evidence: `saveFile` awaits `authFetch` but never checks `res.ok`; after any resolved response it marks the tab unmodified in `wede/src/components/IDE.jsx:235-242`.

Repro steps:

1. Open a file and edit it.
2. Make write fail, for example by saving payload above the backend limit or changing permissions.
3. Click Save.
4. Expected: error message and modified marker remains. Actual: tab can be marked clean even though write failed.

### 6. Backend and frontend size limits/content assumptions are mismatched

Evidence: read rejects files over 10 MB in `wede/backend/internal/files/files.go:132-135`; write decodes through a 10 MB `LimitReader` in `wede/backend/internal/files/files.go:161`; UI has no preflight size or binary handling in `IDE.openFile` (`wede/src/components/IDE.jsx:198-211`) or `saveFile` (`wede/src/components/IDE.jsx:231-245`).

Repro steps:

1. Open an 11 MB text file.
2. Open a small binary file with invalid UTF-8.
3. Paste/copy the binary file through Explorer.
4. Expected: visible "too large" or "binary unsupported" state. Actual: open can silently do nothing; binary can be corrupted through text conversion.

### 7. Folder copy is exposed but not implemented

Evidence: context menu always exposes `Copy` for files and directories in `wede/src/components/FileExplorer.jsx:121-124`; paste is implemented as read source file then write destination content in `wede/src/components/FileExplorer.jsx:246-258`.

Repro steps:

1. Right-click a folder and choose Copy.
2. Right-click another folder and choose Paste.
3. Expected: recursive folder copy or disabled copy action for folders. Actual: UI attempts file read/write and swallows failures.

### 8. Delete is immediate, recursive, and does not reconcile open tabs

Evidence: backend uses `os.RemoveAll` in `wede/backend/internal/files/files.go:247`; UI context menu calls delete immediately in `wede/src/components/FileExplorer.jsx:262-264`; no confirmation code exists (`rg confirm|alert|beforeunload` found none for file flows).

Repro steps:

1. Open `dir/file.txt`.
2. Modify it without saving.
3. Delete `dir` from Explorer.
4. Expected: confirm destructive recursive delete and warn about open/modified descendants. Actual: folder is removed immediately; open tab remains and saving may recreate files.

### 9. Explorer refresh does not refresh expanded nested nodes

Evidence: root refresh calls `loadRoot()` only in `wede/src/components/FileExplorer.jsx:309`; each `TreeNode` owns cached `children` state and only loads when `children === null` in `wede/src/components/FileExplorer.jsx:98-109`.

Repro steps:

1. Expand a nested folder.
2. Create/delete/rename a file inside it from terminal or backend.
3. Click Explorer refresh.
4. Expected: expanded nested folder updates. Actual risk: root updates, nested `children` cache remains stale.

### 10. Backend status codes collapse distinct errors

Evidence: list maps any `os.ReadDir` error to 404 in `wede/backend/internal/files/files.go:75-79`; read maps any stat error to 404 in `wede/backend/internal/files/files.go:125-129`; write/create/rename do not check `MkdirAll` errors before continuing in `wede/backend/internal/files/files.go:174-177`, `213-215`, `280-283`.

Repro steps:

1. Try listing unreadable directory.
2. Try creating under a parent where `MkdirAll` fails.
3. Expected: permission/conflict errors surfaced distinctly. Actual: UI often swallows error; backend may misclassify or defer errors.

## Data-Loss Risks

- Closing a modified tab loses unsaved edits without confirmation (`EditorTabs` calls `onClose`, `IDE.closeTab` removes it immediately).
- Switching workspace clears all tabs without checking `tabs.some(t => t.modified)` (`wede/src/components/IDE.jsx:190-195`).
- Browser reload persists only tab metadata, not unsaved content (`wede/src/components/IDE.jsx:57-64`), so modified unsaved edits are lost on reload.
- Logout path has no unsaved-change guard.
- Delete file/folder is immediate and recursive, with no confirmation, undo, trash, or open-tab reconciliation.
- Rename/delete of an open file leaves stale tabs; saving stale tabs can recreate deleted/renamed paths or old folder structures.
- Failed saves can be marked clean because response status is not checked.
- Duplicate create truncates existing files to empty.
- Rename can overwrite existing files on Unix-like systems.
- Copy/paste overwrites destination paths without confirmation.
- Binary read/copy/save can corrupt data due to UTF-8 string assumptions.

## Recommended Backend Tests

- `safePath` containment tests:
  - Allows root, nested relative paths.
  - Rejects `../outside`.
  - Rejects sibling-prefix escape such as workspace `/tmp/ws` and path `../ws-other/file`.
  - Defines and tests absolute path behavior explicitly.
- Symlink policy tests:
  - Symlink to file outside workspace.
  - Symlink to directory outside workspace.
  - Decide whether to block, display, or allow; test the chosen policy for read/write/list/delete.
- Create tests:
  - New file/folder success.
  - Nested parent creation success.
  - Existing file conflict must not truncate unless explicit overwrite is requested.
  - Existing folder behavior documented.
- Read tests:
  - File success.
  - Directory path returns meaningful 4xx.
  - Missing path returns 404.
  - Permission denied returns 403/500 as chosen, not "not found".
  - >10 MB returns 413.
  - Binary/invalid UTF-8 behavior is either rejected or encoded safely.
- Write tests:
  - New file and existing file writes.
  - Parent `MkdirAll` error is handled.
  - Body larger than limit returns 413 or a precise 400 with no clean-save ambiguity.
  - Conflict/version check if added.
- Rename tests:
  - File and folder rename success.
  - Destination exists returns conflict.
  - Missing source returns 404.
  - Rename outside workspace rejected for both old and new path.
- Delete tests:
  - File delete, folder recursive delete, missing path behavior.
  - Workspace root delete rejected.
  - Outside path and sibling-prefix path rejected.
- Copy tests if a backend copy endpoint is added:
  - File copy, folder recursive copy, nested copy.
  - Destination exists conflict.
  - Large/binary/symlink behavior.

## Recommended Frontend UX Improvements

- Check `res.ok` for every file API call and surface backend errors inline or via toast/status message.
- Keep modified marker when save fails; show exact save failure reason.
- Add unsaved-change guards for tab close, workspace switch, reload/navigation, logout, delete, and rename.
- Add delete confirmation, especially for folders, including child count/path preview when feasible.
- Add conflict confirmation or explicit "overwrite" flow for create, rename, save, and paste.
- Disable folder copy until recursive copy is implemented, or implement backend-supported recursive copy with conflict handling.
- Add binary and large-file states before opening in CodeMirror:
  - Show file too large message for >10 MB.
  - Detect binary/invalid UTF-8 and offer no editor or a safe preview/download-only state.
- Update or close tabs when files/folders are renamed/deleted:
  - Rename file updates matching tab path/name.
  - Rename folder updates descendant tab paths.
  - Delete prompts for modified descendant tabs and closes clean deleted tabs.
- Make Explorer refresh invalidate nested `TreeNode` child caches or centralize tree state so root/nested refresh is coherent.
- Let create/rename target the selected folder or context folder, not only root/global input.
- Show hidden-file policy explicitly in settings or docs; consider hiding more generated/vendor directories via config.
- Include path normalization and validation feedback for names containing `..`, absolute paths, slashes, empty segments, and platform-invalid characters.

## Followups / Ambiguities

- What is the intended symlink policy: follow symlinks, show but block edits, or hide/block entirely?
- Should the editor support binary files at all, or should binary be preview/download-only?
- Is 10 MB the desired text editing limit? The UI should know and explain the same limit.
- Should file operations overwrite by default, prompt on conflict, or always fail with `409 Conflict` unless an explicit overwrite flag is supplied?
- Should deletes move to trash/recycle when possible, or is permanent delete acceptable with confirmation?
- Should hidden file filtering be hard-coded, configurable, or modeled after `.gitignore`/common generated directories?
- Should copy/paste support folders recursively, preserve permissions/symlinks, and handle large files server-side?
