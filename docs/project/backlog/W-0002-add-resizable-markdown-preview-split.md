# Add Resizable Markdown Preview Split

## Summary

Improve markdown Split mode after `PLAN-006` v1 ships by making the desktop editor/preview split resizable.

## Context

`docs/project/plans/PLAN-006-wede-markdown-preview.md` uses a fixed 50/50 desktop split for v1. Mobile does not offer Split mode and falls back to Preview when retained Split state is encountered after resizing.

## Desired Outcome

Allow desktop users to adjust the editor/preview split width while preserving the v1 mobile fallback behavior.

## Notes

- Keep v1 fixed-width; do not pull this into the initial markdown preview implementation.
- Decide whether split width is global, per tab, per workspace, or not persisted.
- Reuse Wede's existing resize interaction style where practical.
