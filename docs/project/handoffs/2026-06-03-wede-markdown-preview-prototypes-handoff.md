# wede Markdown Preview Prototype Handoff

Date: 2026-06-03

## Goal

Continue the `wede` markdown preview work by prototyping the small uncertain pieces before implementation.

Do not restate the full feature plan. Use `docs/project/plans/PLAN-006-wede-markdown-preview.md` as the source of truth for desired v1 behavior.

## References

- Feature plan: `docs/project/plans/PLAN-006-wede-markdown-preview.md`
- Relative markdown links follow-up ticket: `docs/project/backlog/W-0001-handle-relative-markdown-preview-links.md`
- Resizable split follow-up ticket: `docs/project/backlog/W-0002-add-resizable-markdown-preview-split.md`
- Current IDE shell and tab state: `wede/src/components/IDE.jsx`
- Current CodeMirror editor: `wede/src/components/Editor.jsx`
- Current tab strip: `wede/src/components/EditorTabs.jsx`
- Current browser tab component: `wede/src/components/Browser.jsx`
- Current theme/CSS surface: `wede/src/index.css`
- Local wede instructions: `wede/AGENTS.md`

## Decisions Already Captured

- Per-tab markdown mode is in-memory only, keyed by tab path.
- The markdown toolbar lives in the tab content area, directly below `EditorTabs`.
- HTTP(S) markdown preview links keep Wede's existing browser-tab interception behavior.
- Relative links and images remain simple in v1 and are tracked by `docs/project/backlog/W-0001-handle-relative-markdown-preview-links.md`.
- Preview-only mode hides `Ln/Col` cursor status.
- Desktop Split mode uses a fixed 50/50 width in v1.
- Mobile offers only Edit and Preview; retained Split state renders Preview as fallback without mutating the in-memory mode.

## Loading State Recommendation

The cleanest v1 behavior is no explicit markdown tab loading state.

Current restored editor tabs in `IDE.jsx` re-fetch content after mount and pass `content` through to `Editor.jsx`; the editor renders an empty document while content is `undefined`. Other components have simple text loading states, but tab content does not have a shared loading model.

For v1, keep markdown preview consistent with the editor by rendering `currentTab.content ?? ''`. If a visible loading state is desired later, first introduce a tab-level loading/error model that both editor and preview can share.

## Prototype 1: Mode Switching And Editor Remount

Why: `Editor.jsx` creates its CodeMirror instance by `file?.path`. Switching Edit -> Preview unmounts the editor, and switching back recreates it. This may lose undo history, selection, and scroll position.

Prototype enough UI to answer:

- Does losing undo history on mode toggles feel acceptable for v1?
- Does cursor/scroll reset feel acceptable after Preview -> Edit?
- Does Split mode preserve editor behavior while both panes are visible?

Recommended default: accept remount behavior for v1 unless the prototype makes it feel clearly bad.

## Prototype 2: Desktop And Mobile Layout

Why: the toolbar and split/fallback behavior must fit both desktop and mobile without overlap.

Prototype or implement a minimal wrapper around fake markdown content to verify:

- toolbar placement below `EditorTabs`;
- desktop Edit, Preview, and fixed 50/50 Split;
- independent scrolling in desktop Split;
- mobile toolbar accessibility with only Edit and Preview;
- mobile fallback from retained Split state to Preview;
- layout with the terminal open;
- no text/control overlap in dark and light themes.

## Prototype 3: react-markdown Raw HTML Behavior

Why: the plan relies on `react-markdown` safe defaults and intentionally does not add `rehype-raw`, `rehype-sanitize`, DOMPurify, `marked`, or `markdown-it`.

After installing the planned dependencies, smoke-test content containing raw HTML fragments, event-handler attributes, and script tags. Confirm raw HTML is not mounted as live DOM and that the rendered output matches the plan's v1 expectations.

## Prototype 4: Existing Link Interception

Why: Wede currently intercepts document-level HTTP(S) anchor clicks in capture phase and opens them in the browser tab. The v1 decision is to keep that behavior for markdown preview links.

Verify that anchors rendered by `react-markdown` trigger the existing interception path and open/update a Wede browser tab.

Do not prototype relative link rewriting for v1; use `docs/project/backlog/W-0001-handle-relative-markdown-preview-links.md` for that follow-up.

## Suggested Order

1. Install the planned dependencies in `wede/`.
2. Smoke-test `react-markdown` raw HTML behavior.
3. Prototype the markdown shell/toolbar layout with fake content.
4. Verify mode switching/remount behavior with the real `Editor`.
5. Verify markdown HTTP(S) links use existing Wede browser-tab interception.

## Out Of Scope

- Relative markdown link/image workspace rewriting.
- Resizable desktop markdown split.
- Syntax highlighting in preview code blocks.
- Global save shortcuts for preview-only mode.
- Persisting markdown mode in localStorage or tab metadata.
