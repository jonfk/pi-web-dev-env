# Optimize Markdown Preview Rerenders

## Summary

Improve markdown Split mode performance after `PLAN-006` v1 ships by avoiding a full markdown preview parse/render on every editor keystroke.

## Context

`docs/project/plans/PLAN-006-wede-markdown-preview.md` renders preview content directly from unsaved tab content. In Split mode, that means each source edit updates both the CodeMirror editor state and the rendered `MarkdownPreview`.

This is acceptable for v1, but large markdown files may make typing pay the full `react-markdown` plus GFM render cost on every change.

## Desired Outcome

Keep Split mode responsive while preserving live preview behavior for ordinary markdown files.

## Notes

- Keep v1 simple; do not pull this into the initial markdown preview implementation unless typing performance is already poor in manual testing.
- Consider `useDeferredValue`, a small debounce, memoization at the preview boundary, or another React-native scheduling approach.
- Preserve preview correctness for unsaved content.
- Avoid adding defensive parsing behavior; malformed markdown should render according to the markdown renderer's normal rules.
