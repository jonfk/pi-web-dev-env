
This directory contains tickets to be worked on. Each ticket can be a task, a bug to be fixed, a feature to be implemented, an epic that links multiple tickets together for a larger feature, etc.
It is the equivalent of github issues or jira tickets but stored on the filesystem as files in the repository.

Each ticket should have an id followed by a short stable slug. e.g `W-0001-short-action-oriented-slug.md`, `W-0001-add-oauth-login.md`, `W-0002-refactor-cache-layer.md`.

Do not duplicate content already captured in other artifacts (PRDs, plans, ADRs, issues, commits, diffs, package documentation). Reference them by path or URL instead.

Once implemented, rejected, or no longer relevant, move the ticket to archived and add a status to it. 