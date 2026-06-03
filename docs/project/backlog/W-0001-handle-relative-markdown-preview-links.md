# Handle Relative Markdown Preview Links

## Summary

Improve markdown preview relative link behavior after `PLAN-006` v1 ships.

## Context

`docs/project/plans/PLAN-006-wede-markdown-preview.md` intentionally leaves relative links and images without workspace rewriting in v1.

HTTP(S) markdown links should keep using Wede's existing browser-tab interception. This ticket is only for relative markdown references such as `docs/example.md`, `./image.png`, and `../README.md`.

## Desired Outcome

Decide and implement how markdown preview should handle relative links and images in a workspace-aware way.

## Notes

- Keep v1 simple; do not pull this into the initial markdown preview implementation.
- Decide whether relative markdown links should open files in editor tabs, open browser tabs, or remain normal anchors.
- Decide whether relative images should load through an existing file API, a new static workspace asset route, or remain unsupported.
