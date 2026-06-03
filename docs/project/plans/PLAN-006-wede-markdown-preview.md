# PLAN-006: wede Markdown Preview

## Source Material

- Existing backlog item: `TODO.md`
- wede frontend shell: `wede/src/components/IDE.jsx`
- Code editor component: `wede/src/components/Editor.jsx`
- Editor tab UI: `wede/src/components/EditorTabs.jsx`
- Existing browser preview component: `wede/src/components/Browser.jsx`
- Existing theme and CodeMirror CSS: `wede/src/index.css`
- wede dev instructions: `wede/AGENTS.md`

Use this plan as the implementation checklist for the first markdown preview version.

## Goal

Add markdown preview support to wede for markdown files. Markdown tabs can switch between edit, rendered preview, and split edit/preview modes. Preview renders from the current in-memory tab content so unsaved edits are visible immediately.

## Locked Decisions

- Use `react-markdown` for React-native markdown rendering.
- Use `remark-gfm` for GitHub-flavored markdown features.
- Add exactly these first-version dependencies unless implementation discovers a blocker:
  - `react-markdown`
  - `remark-gfm`
- Do not render raw HTML in v1.
- Raw HTML should appear as inert literal content according to the renderer's safe default behavior.
- Do not add `rehype-raw`, `rehype-sanitize`, DOMPurify, `marked`, `markdown-it`, or syntax highlighters in v1.
- Do not add special handling for relative images in v1.
- Do not add code block syntax highlighting in v1.
- Keep save behavior unchanged.
- Keep markdown preview client-side; no backend markdown rendering endpoint.
- Scope the feature to markdown file extensions only.

## First-Version Behavior

- Files ending in `.md` are treated as markdown preview candidates.
- Markdown files still open as editable CodeMirror tabs by default.
- A markdown-only toolbar offers three modes:
  - Edit
  - Preview
  - Split
- Edit mode shows only CodeMirror.
- Preview mode shows only rendered markdown.
- Split mode shows CodeMirror and rendered markdown side by side on desktop.
- On mobile, split mode may stack vertically or fall back to preview/edit switching if side-by-side layout is too cramped.
- Preview updates from `currentTab.content`, including unsaved edits.
- Existing `Mod-s` save behavior continues to save the markdown source while the editor is visible.
- Existing modified indicators continue to reflect source content changes.
- Markdown preview links render as normal anchors and are not routed through the app's in-browser preview tab.
- Relative links and images render without special workspace rewriting in v1.
- Raw HTML is not mounted as live DOM.

## Dependency Plan

Install from `wede/`:

```bash
npm install react-markdown remark-gfm
```

This should update:

- `wede/package.json`
- `wede/package-lock.json`

Do not hand-edit package lock contents.

## Phase Split

1. Markdown preview rendering component.
2. Markdown mode UI integration.
3. Styling and verification.

This split keeps the renderer small and testable before threading it through the IDE shell.

## Phase 1: Markdown Preview Rendering Component

### Files To Add

- `wede/src/components/MarkdownPreview.jsx`

### Component Responsibilities

- Accept markdown source content.
- Render with `react-markdown`.
- Enable GFM through `remark-gfm`.
- Use React element rendering, not `dangerouslySetInnerHTML`.
- Keep raw HTML inert by relying on the renderer's default behavior.
- Style generated elements through a wrapper class, not inline styles on every element.
- Render code blocks as plain styled `<pre><code>` blocks.

### Interface Sketch

```jsx
export default function MarkdownPreview({ content }) {
  return (
    <div className="markdown-preview">
      <Markdown remarkPlugins={[remarkGfm]}>
        {content || ''}
      </Markdown>
    </div>
  )
}
```

The exact implementation can differ, but it should preserve the locked decisions above.

## Phase 2: Markdown Mode UI Integration

### Files To Update

- `wede/src/components/IDE.jsx`
- `wede/src/components/EditorTabs.jsx` only if tab affordances are needed
- `wede/src/components/Editor.jsx` only if editor sizing needs a small adjustment

### Implementation Sequence

1. Add an `isMarkdownFile(filename)` helper near existing file/language helpers in `IDE.jsx` or a small shared helper module if duplication appears.
2. Add markdown preview mode state, defaulting to `edit`.
3. Do not persist markdown mode in local storage for v1; each opened markdown tab starts in edit mode.
4. In `renderTabContent`, detect markdown tabs and route them through a markdown-aware wrapper.
5. Keep browser tabs and non-markdown editor tabs unchanged.
6. Add a compact markdown toolbar visible only for markdown tabs.
7. Use lucide icons where suitable:
   - edit/source icon for Edit
   - eye icon for Preview
   - split/panel icon for Split
8. In Edit mode, render the existing `Editor`.
9. In Preview mode, render `MarkdownPreview`.
10. In Split mode, render both the existing `Editor` and `MarkdownPreview`, each with stable dimensions and independent scrolling.
11. Make sure `onChange`, `onSave`, and `onCursorChange` still flow only through the `Editor`.
12. Opt markdown preview links out of the current global link interception so clicks are not routed into wede Browser tabs.
13. Keep the status bar language display as Markdown for markdown files.

### State Notes

The markdown mode is UI state, not tab content. For v1, keep it in memory and default new markdown tabs to edit mode. If per-tab mode or persisted mode becomes desirable later, it can be added without changing the markdown rendering component.

## Phase 3: Styling And Verification

### Files To Update

- `wede/src/index.css`

### Styling Requirements

- Match the existing wede theme variables.
- Use a readable document width in preview-only mode while still filling the editor area.
- In split mode, let each pane scroll independently.
- Keep headings, paragraphs, lists, blockquotes, tables, links, inline code, code blocks, horizontal rules, and task lists legible in dark and light themes.
- Do not use a card-heavy or marketing-style preview surface.
- Do not introduce a new color palette; use existing theme variables.
- Text must not overlap toolbar, tabs, terminal, or status bar.

### Suggested CSS Surface

- `.markdown-preview-shell`
- `.markdown-preview-toolbar`
- `.markdown-preview-layout`
- `.markdown-preview-layout[data-mode="split"]`
- `.markdown-preview`
- `.markdown-preview table`
- `.markdown-preview pre`
- `.markdown-preview code`
- `.markdown-preview blockquote`

## Verification Strategy

Run from `wede/`:

```bash
npm run build
```

If Go/backend changes are not made, `npm run build` is enough for compile verification. If implementation unexpectedly touches backend or embed behavior, also run:

```bash
npm run build:all
```

Manual browser verification should cover:

- Open a `.md` file.
- Confirm it starts in Edit mode.
- Toggle to Preview mode.
- Toggle to Split mode.
- Type unsaved markdown and confirm preview updates.
- Save edited markdown with the existing Save button and `Mod-s` while the editor is visible.
- Confirm `Mod-s` is not required to work while the markdown tab is in preview-only mode.
- Confirm raw HTML is displayed inertly and does not execute.
- Confirm tables, task lists, strikethrough, fenced code blocks, blockquotes, and links render acceptably.
- Confirm markdown preview links use normal browser link behavior and do not open wede Browser tabs.
- Confirm a non-markdown file still opens exactly as before.
- Confirm browser tabs still open and render exactly as before.
- Confirm dark and light themes both look acceptable.
- Confirm desktop layout with terminal open.
- Confirm mobile layout does not overflow or overlap controls.

## Acceptance Checklist

- Markdown tabs have Edit, Preview, and Split modes.
- Markdown preview is scoped to `.md` files only.
- Preview renders from unsaved `currentTab.content`.
- Source editing and save flow are unchanged.
- Raw HTML is not rendered as live DOM.
- GFM tables and task lists render.
- Relative images are not specially rewritten in v1.
- Code blocks are styled but not syntax highlighted.
- Non-markdown files are unaffected.
- Browser tabs are unaffected.
- `wede/package.json` and `wede/package-lock.json` include only the agreed markdown dependencies.
- `npm run build` passes from `wede/`.
