# wede Markdown Preview Phase 1 Handoff

Date: 2026-06-03

## Context

Continue from:

- Feature plan: `docs/project/plans/PLAN-006-wede-markdown-preview.md`
- Prototype handoff: `docs/project/handoffs/2026-06-03-wede-markdown-preview-prototypes-handoff.md`
- Follow-up tickets:
  - `docs/project/backlog/W-0001-handle-relative-markdown-preview-links.md`
  - `docs/project/backlog/W-0002-add-resizable-markdown-preview-split.md`

The next step is Phase 2 of `PLAN-006-wede-markdown-preview.md`.

## Current Thread Summary

Phase 1 has been implemented by adding `wede/src/components/MarkdownPreview.jsx`.

The component:

- Uses `react-markdown` with `remark-gfm`.
- Renders through React elements, not `dangerouslySetInnerHTML`.
- Relies on `react-markdown` defaults for inert raw HTML.
- Renders HTTP(S) links as normal anchors so Wede's document-level link interception can keep working.
- Renders non-HTTP(S) markdown links as inert unsupported inline content with the original target exposed through text, `title`, and `data-markdown-link-target`.
- Leaves styling to wrapper classes for Phase 3.

`react-markdown` and `remark-gfm` were already present in `wede/package.json` and `wede/package-lock.json` from the prototype work, so this thread did not change either dependency file.

## Verification Completed

From `wede/`:

```bash
./node_modules/.bin/eslint src/components/MarkdownPreview.jsx
npm run build
```

Both passed. `npm run build` still prints the existing large chunk warning.

## Worktree Notes

At handoff time, repository status showed modified `wede` and `pi-webui` entries at the top level. Inside `wede`, the relevant new file is:

- `wede/src/components/MarkdownPreview.jsx`

No Phase 2 integration has been started in this thread.

## Phase 2 Starting Point

Use `PLAN-006-wede-markdown-preview.md` as the checklist. The likely first files are:

- `wede/src/components/IDE.jsx`
- `wede/src/components/MarkdownPreview.jsx`
- `wede/src/index.css` only if small layout hooks are needed before Phase 3

Key continuation notes:

- Import and wire `MarkdownPreview` into `IDE.jsx`.
- Add in-memory markdown mode state keyed by tab path.
- Default markdown tabs to edit mode.
- Clear per-tab mode on close and clear all markdown modes when switching workspaces.
- Keep browser and non-markdown editor tabs unchanged.
- Use the existing `Editor` for edit and split modes.
- Preserve the current save and cursor flows by routing `onChange`, `onSave`, and `onCursorChange` only through visible `Editor` instances.
- Hide `Ln/Col` only for preview-only mode and the mobile split fallback.
- Keep mobile split behavior as a render fallback without mutating stored mode.

