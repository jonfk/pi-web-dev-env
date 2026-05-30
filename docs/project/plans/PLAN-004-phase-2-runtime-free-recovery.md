# PLAN-004 Phase 2: Runtime-Free Recovery

## Goal

Make invalid URL and cwd-required states recoverable without creating a Pi runtime. At the end of this phase, users can choose a cwd or session from no-runtime state using the same picker ergonomics as normal runtime state.

## Files To Add

- `pi-webui/src/server/runtime-free-recovery.ts`
- `pi-webui/test/server-runtime-free-recovery.test.mjs`

Optional if client code becomes too broad:

- `pi-webui/public/recovery-state.mjs`
- `pi-webui/test/recovery-state.test.mjs`

## Files To Update

- `pi-webui/src/server/index.ts`
- `pi-webui/src/server/session-info.ts`
- `pi-webui/public/app.js`
- `pi-webui/public/invalid-url-state.mjs`
- `pi-webui/public/url-state.mjs`
- `pi-webui/test/invalid-url-state.test.mjs`
- `pi-webui/test/url-state.test.mjs`

## Runtime-Free Interface Sketch

### Server Requests

Add protocol handling that is allowed without a runtime:

```js
{ type: "list_all_sessions" }
{ type: "list_recent_cwds" }
{ type: "list_dir", path }
{ type: "select_cwd", cwd }
{ type: "select_session", sessionPath }
```

Responses can use existing command result style or dedicated result packets. Prefer consistency with existing command results unless it obscures mode handling.

Rules:

- `list_all_sessions` calls static session listing only.
- `list_recent_cwds` derives cwd recents from all sessions and/or trusted persisted workspace state.
- `list_dir` remains runtime-free.
- `select_cwd` validates cwd, creates cwd target, persists `lastCwd`, creates runtime, and sends normal bootstrap.
- `select_session` validates session, creates session target, persists session header cwd as `lastCwd`, creates runtime, and sends normal bootstrap.
- No runtime-free request may call `this.session` or `this.runtime`.

### Client Recovery Model

Invalid URL and cwd-required messages should offer actions that request recovery data:

- Choose cwd: fetch recent cwds and open cwd picker.
- Choose session: fetch all sessions and open session picker.

No-runtime session picker rules:

- Show all sessions only.
- Do not show current-project scope.
- Selecting a session sends/selects a session target or navigates to a URL Session Pointer, depending on the chosen final protocol.

Recommendation:

- For consistency with URL source of truth, selecting a session may navigate to `/?session=...`.
- For faster no-runtime recovery without page reload, `select_session` may create the target directly.
- Choose one path during implementation and use it consistently. If direct select is chosen, URL state must be updated after runtime bootstrap.

## Implementation Sequence

1. Add runtime-free recovery module tests.
   - List all sessions without cwd.
   - List recent cwds without runtime.
   - List directory validates using cwd policy.
   - Select cwd validates and returns cwd target.
   - Select session validates and returns session target with header cwd.
   - Invalid select cwd/session returns typed failure without runtime.

2. Implement runtime-free recovery module.
   - Reuse existing cwd validation.
   - Reuse existing session serialization.
   - Reuse URL session prevalidation rules from Phase 1.

3. Wire server mode handling.
   - Allow runtime-free requests in cwd-required and invalid URL states.
   - Reject runtime-required requests with a clear error.
   - Keep `ready` a no-op in no-runtime states.
   - Keep `list_dir` available without runtime.

4. Update client invalid and cwd-required UI.
   - Render clear explanatory pseudo messages.
   - Disable composer prompt submission.
   - Show recovery actions for choosing cwd and choosing session.
   - Fetch recovery data only when action is selected.

5. Update session picker for no-runtime state.
   - Add all-sessions-only mode.
   - Do not render current-project/all-project segmented control in no-runtime mode.
   - Ensure selecting a session recovers through the chosen no-runtime path.

6. Update cwd picker for no-runtime state.
   - Open with recent cwds from runtime-free response.
   - Use runtime-free `list_dir`.
   - Selecting a cwd recovers through `select_cwd` or URL Cwd Pointer navigation.

7. Update slash command catalog for no-runtime state.
   - Expose only runtime-free commands.
   - Keep runtime-required commands unavailable or unsupported with clear copy.

## Phase 2 Verification

Run:

```bash
npm test --prefix pi-webui
```

Prefer browser e2e or browser-like integration tests for this phase. Server request tests should verify no-runtime recovery without creating an agent runtime, but the phase should be accepted by user-visible recovery behavior.

## Phase 2 Validation Scenarios

- Start with no target. Confirm cwd-required message renders and composer prompt submission is blocked.
- From cwd-required state, choose cwd from recovery UI. Confirm runtime starts, URL moves to cwd mode, and `lastCwd` is persisted.
- From cwd-required state, choose session. Confirm all sessions are shown without current-project scope and runtime starts with session header cwd.
- Open invalid session URL. Confirm invalid URL message renders, bad URL remains visible, and prompt submission is blocked.
- From invalid session URL, choose session. Confirm all sessions are shown and selecting one recovers without fallback cwd.
- Open invalid cwd URL. Choose cwd and confirm directory browsing works without runtime.
- Use directory listing from no-runtime cwd picker. Confirm disallowed, nonexistent, and file paths fail with visible errors.
- Invoke a runtime-required command in no-runtime state. Confirm it fails clearly and does not create a runtime.

## Done Criteria

- Invalid URL and cwd-required states are recoverable without fallback cwd.
- Recovery data is fetched on demand through runtime-free requests.
- No-runtime Choose session shows all sessions only.
- Cwd picker works without runtime.
- Runtime-required commands are blocked clearly without touching runtime.
