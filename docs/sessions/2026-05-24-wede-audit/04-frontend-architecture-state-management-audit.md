# Ticket 4: Frontend Architecture and State Management Audit

## Scope

Audited the React frontend architecture and state ownership for `wede`, focusing on component organization, persistence, data fetching, async safety, maintainability, hook dependencies, localStorage scoping, and mobile/desktop sharing.

Primary files reviewed:

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

No source changes were made.

## Commands Run

- `pwd && rg --files wede/src wede | sed -n '1,160p'`
- `git status --short`
- `sed -n '1,220p' wede/package.json`
- `sed -n '1,220p' wede/AGENTS.md`
- Multiple `sed`, `nl -ba`, and `rg` inspection commands over the files listed above.
- `cd wede && npm run lint`
  - Failed before linting: `sh: eslint: command not found`.
- `cd wede && npm run build`
  - Failed before building: `sh: vite: command not found`.

The lint/build failures appear to be dependency-installation state, not code execution failures. `node_modules` is missing or incomplete for the npm scripts.

## Component Map

- `App.jsx`
  - Owns top-level auth/theme/workspace gate.
  - Calls `/api/workspace`, renders `ThemePicker`, `Login`, `FolderPicker`, or `IDE`.
  - Passes `authFetch`, `token`, workspace path, recents, and logout into the IDE.

- `hooks/useAuth.js`
  - Owns token storage, login/logout, initial auth check, auth-disabled sentinel, and authenticated fetch wrapper.
  - LocalStorage key: `wede_token`.

- `hooks/useTheme.jsx`
  - Owns theme selection, document `data-theme`, and terminal color palette.
  - LocalStorage key: `wede_theme`.

- `hooks/useMobile.js`
  - Owns viewport breakpoint detection only.

- `IDE.jsx`
  - Main composition shell and largest state owner.
  - Owns tabs, active tab, editor save/open logic, browser-tab creation, sidebar/settings/terminal layout state, mobile panel state, workspace switch behavior, git status polling, status bar cursor state, and global link interception.
  - LocalStorage keys: `wede_tabs`, `wede_activeTab`.

- `FileExplorer.jsx`
  - Owns tree root state, expanded directories, lazy child loading per `TreeNode`, create/delete/rename/copy-paste actions, clipboard state, git status decoration polling, context menu state.
  - Receives selected path and file-open callback from `IDE`.

- `Editor.jsx`
  - Owns CodeMirror lifecycle and theme reconfiguration.
  - Treats file content as controlled input from `IDE`, but CodeMirror state/history is recreated on `file.path` changes.

- `EditorTabs.jsx`
  - Presentational tab strip.
  - Receives all tab state and actions from `IDE`.

- `TerminalPanel.jsx`
  - Owns terminal tabs, active terminal, terminal persistence, server-session reconciliation, mobile toolbar routing.
  - LocalStorage keys: `wede_terminals`, `wede_terminal_active`.

- `Terminal.jsx`
  - Owns one xterm instance, websocket lifecycle, reconnect loop, fit behavior, and imperative `send`.

- `GitPanel.jsx`
  - Owns source-control UI state, status/log/branches fetch, staging/unstaging/commit/checkout actions.
  - Receives only `authFetch` and visibility from parent.

- `Browser.jsx`
  - Owns iframe URL input and loaded URL state.
  - URL is also mirrored upward into the active browser tab in `IDE`.

## State/Data-Flow Risks

1. `IDE.jsx` is overloaded, but not yet beyond rescue.
   - It currently owns file tabs, persistence, file IO, browser tabs, layout, mobile navigation, terminal reset, git polling, global link interception, and workspace switching in one component (`IDE.jsx:25-245` plus rendering branches below).
   - This makes state interactions hard to test. For example, workspace switching clears tabs and bumps `terminalKey` (`IDE.jsx:190-195`), while persisted terminal metadata lives inside `TerminalPanel` under global keys (`TerminalPanel.jsx:7-23`). There is no single workspace-session model to reason about.
   - Recommendation: keep `IDE` as the shell, but extract tab/workspace/session concerns into small hooks before adding more IDE features.

2. Persisted tabs are global, not workspace-scoped.
   - Tabs and active tab are loaded from `wede_tabs` and `wede_activeTab` (`IDE.jsx:25-31`) and saved back globally (`IDE.jsx:60-71`).
   - On a reload after changing workspaces, restored paths can point at the previous workspace because paths are relative API paths and the key does not include the current workspace (`IDE.jsx:73-91`).
   - The restore effect intentionally omits dependencies (`IDE.jsx:91`), so it only runs on mount with whatever workspace/auth context existed then.
   - Risk: stale tabs, empty-content fallback, active tab pointing to a missing file, or accidental editing of same relative path in a different workspace.

3. Terminal persistence is global and only partially reconciled.
   - Terminal metadata and active terminal are global localStorage keys (`TerminalPanel.jsx:7-23`, `TerminalPanel.jsx:37-39`).
   - Server reconciliation runs once per mount and does not include workspace in its identity (`TerminalPanel.jsx:44-73`).
   - `IDE` resets the panel by changing `terminalKey` on workspace open (`IDE.jsx:190-195`), but the panel reloads the same global terminal IDs afterward.
   - Risk: terminal tabs from one workspace visually survive into another, while backend sessions may or may not match user expectation.

4. Async fetches are guarded inconsistently and are not cancellable.
   - `useAuth` uses a cancelled boolean for initial auth check (`useAuth.js:14-44`), but does not use `AbortController`.
   - `IDE` git polling guards setState with `active` and clears the interval (`IDE.jsx:94-109`), which is good.
   - Restored tab loading calls `Promise.all(...).then(setTabs)` with no active/cancel guard (`IDE.jsx:73-91`).
   - `openFile` can race with tab changes or workspace changes and still append a tab after the awaited read returns (`IDE.jsx:198-212`).
   - `FileExplorer` root/child/git fetches have no request ordering or cancellation (`FileExplorer.jsx:98-109`, `FileExplorer.jsx:201-226`).
   - `GitPanel.refresh` can set status/log/branches after visibility changes or workspace changes because it has no cancellation guard (`GitPanel.jsx:267-278`).

5. Errors are mostly swallowed, so UI state can become stale with no feedback.
   - Many `catch {}` blocks silently ignore failures: workspace fetch (`App.jsx:16-23`), tab restore/open/save (`IDE.jsx:78-91`, `IDE.jsx:198-245`), file tree and git status (`FileExplorer.jsx:201-217`), git panel refresh (`GitPanel.jsx:267-275`), folder browse/open (`FolderPicker.jsx:17-42`), and terminal session reconciliation (`TerminalPanel.jsx:49-72`).
   - `authFetch` only treats `401` specially and otherwise returns failed HTTP responses to callers (`useAuth.js:90-99`), so many callers will parse error responses as success unless the backend shape happens to fail.
   - Risk: save failures leave the user thinking a file saved, git actions can fail without message, and workspace load errors fall through to `loading=false` with ambiguous UI.

6. Workspace updates use captured `workspace` objects.
   - `App` updates workspace with object spreads from the current render (`App.jsx:71`, `App.jsx:84`).
   - This is probably fine today because these callbacks are user-triggered, but functional updates would be safer if recents or other workspace metadata starts changing concurrently.

7. Global link interception is broad.
   - `IDE` captures every document `click` and `auxclick` on `a[href]` and redirects all HTTP(S) links into the preview browser (`IDE.jsx:132-153`).
   - This can also intercept links in settings/about or future embedded UI surfaces. It is clever, but it is application-global behavior living inside the main IDE shell.

8. Mobile and desktop share domain state reasonably, but layout state is mixed with data state.
   - Good: both views use the same `tabs`, `activeTab`, `FileExplorer`, `EditorTabs`, `TerminalPanel`, `GitPanel`, and `Settings`.
   - Risk: mobile-only state (`mobilePanel`, `mobileMenu`, `termFullscreen`) and desktop-only state (`showSidebar`, widths, `showSettings`) live alongside file/session state in `IDE`, increasing the chance of regressions when changing either layout.

9. Hook dependency practices are mostly okay, with one intentional escape hatch.
   - The biggest dependency smell is the tab-restore effect disabling exhaustive deps (`IDE.jsx:73-91`).
   - `FileExplorer` keyboard paste effect depends only on `clipboard` but closes over `handlePaste`, which is recreated each render (`FileExplorer.jsx:284-292`). The current behavior works because `clipboard` changes usually trigger re-registration, but lint may flag or future edits may break this.
   - `Browser` effect depends only on `initialUrl` while reading `loadedUrl` (`Browser.jsx:9-14`); this is a small stale-closure risk.

## Quick Wins

- Namespace localStorage keys by workspace for tabs and terminals.
  - Example shape: `wede:${workspaceHash}:tabs`, `wede:${workspaceHash}:activeTab`, `wede:${workspaceHash}:terminals`.
  - Keep `wede_theme` global. Consider whether `wede_token` should remain host-global or include origin/server identity.

- Add a tiny shared API/error helper around `authFetch`.
  - Centralize `res.ok` checks and JSON parsing.
  - Return consistent `{ data, error }` or throw typed errors.
  - This would reduce the many silent `catch {}` blocks without introducing framework churn.

- Add cancellation/ignore guards to async effects that update state after awaits.
  - Prioritize tab restore, file open, file tree loads, folder browsing, and GitPanel refresh.
  - A simple `let active = true` cleanup is enough for most current code; `AbortController` can come later if the API wrapper supports it.

- On workspace change, validate or reset workspace-owned persisted state in one place.
  - Today `handleWorkspaceOpen` clears visible tabs but persistence and terminal metadata are split across components (`IDE.jsx:190-195`, `TerminalPanel.jsx:7-23`).

- Surface minimal errors where user action occurred.
  - Save file, open file, create/delete/rename file, folder open, git commit/stage/checkout should show at least a small inline or status-bar message.
  - This can be a single `IDE`-level notification/status state at first.

- Make active tab restoration resilient.
  - If restored `activeTab` does not exist in restored tabs, reset it to the first restored tab or `null`.
  - If a restored file read fails, mark the tab as failed instead of silently loading empty content.

- Remove unused imports found during inspection.
  - `createRef` is imported but unused in `TerminalPanel.jsx:1`.
  - Lint could not run because dependencies were unavailable, so this should be confirmed after `npm ci`.

## Larger Refactors

- Extract `useEditorTabs({ authFetch, workspace, isMobile })`.
  - Own tabs, activeTab, persistence, restore, openFile, closeTab, updateContent, saveFile.
  - This is the highest-value split because it isolates the riskiest persistence and async behavior from layout rendering.

- Extract `useWorkspaceSession(workspace)`.
  - Provide workspace-scoped storage keys and reset behavior for tabs, terminal sessions, and possibly sidebar expansion later.
  - This keeps the app small while making workspace changes explicit and testable.

- Extract `useGitStatusSummary(authFetch, workspace)`.
  - `IDE` and `FileExplorer` both poll `/api/git/status` separately (`IDE.jsx:94-109`, `FileExplorer.jsx:209-226`), while `GitPanel` fetches status on visibility (`GitPanel.jsx:267-278`).
  - A lightweight shared hook or parent-owned summary would avoid duplicate polling and inconsistent refresh timing.

- Split `IDE` into shell/layout components without changing frameworks.
  - Suggested shape:
    - `IDE` owns hooks and passes state down.
    - `DesktopIDELayout` renders desktop chrome.
    - `MobileIDELayout` renders mobile chrome.
    - `usePanelLayoutState` owns sidebar/settings/terminal dimensions and visibility.
  - This preserves the current architecture but makes mobile/desktop changes less risky.

- Introduce a small user-action status channel.
  - Avoid a global state library. A local `useStatusMessage` or `useToast` hook at `IDE`/`App` level is enough.
  - Standardize failure/success messages for save, git, file operations, and folder opening.

## Followups/Ambiguities

- Should tabs and terminal sessions be restored per workspace, or should switching folders intentionally clear them permanently?
  - Recommendation: restore per workspace. It matches IDE expectations and avoids cross-workspace stale paths.

- Should terminal sessions represent workspace-specific backend processes?
  - Recommendation: yes, if backend sessions are tied to cwd/workspace. The frontend should include workspace identity in persisted terminal metadata or reset persistence on workspace change.

- Should the preview browser be global across workspaces?
  - Recommendation: browser tab URL can probably be workspace-scoped with editor tabs, because it is currently persisted inside `wede_tabs`.

- What is the desired error UX?
  - Recommendation: start with a compact status-bar or toast message rather than introducing a full notification system.

- Verification is incomplete until dependencies are installed.
  - Run `cd wede && npm ci` first, then rerun `npm run lint` and `npm run build`.
