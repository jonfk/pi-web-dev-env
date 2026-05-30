# PLAN-004 Phase 3: Target-Based Transitions

## Goal

Move all cwd/session-changing commands to the selected target model. At the end of this phase, runtime-changing flows resolve a new target first, then create or replace the runtime from that target. `lastCwd` is persisted only after explicit target transitions.

A valid URL Cwd Pointer startup, for example `/?cwd=/absolute/project`, counts as an explicit target selection for persistence. Opening that URL must persist the validated URL cwd to `lastCwd` after the runtime target is accepted. Missing URL state, invalid URL state, and plain startup from an existing `lastCwd` must not create a new persistence event.

The target transition applicator must also own transition ordering. A controller/browser tab may have at most one runtime-creating target transition in flight. Concurrent target transitions must be serialized or rejected consistently by the applicator, not guarded separately by individual command or recovery handlers.

## Known Regressions Absorbed By Phase 3

- Valid URL cwd startup must persist `lastCwd`. After generic command-success cwd persistence is removed, opening `/?cwd=<valid-absolute-path>` can start in the requested cwd without remembering it for future plain `/` startup. Phase 3 should treat validated URL cwd startup as an explicit target transition and persist the validated URL cwd through the same persistence decision path as `/cwd`, workspace selection, and session selection.
- Runtime-free recovery can currently overlap runtime creation. In the Phase 2 recovery shape, blocked startup requests enter `handleRuntimeFreeRecovery(...)`; `select_cwd`, runtime-free `/cwd <path>`, and `select_session` can call `recoverRuntime(...)`; and `recoverRuntime(...)` clears `startupBlock` only after awaiting runtime creation. Two quick recovery selections can therefore both create/bind/bootstrap runtimes. Phase 3 should remove this race by routing runtime-free recovery through the target transition applicator, whose Interface owns transition serialization or rejection.

## Files To Add

- `pi-webui/src/server/target-transitions.ts`
- `pi-webui/test/server-target-transitions.test.mjs`

Optional if command capability logic becomes too large:

- `pi-webui/src/server/slash-command-availability.ts`
- `pi-webui/test/server-slash-command-availability.test.mjs`

## Files To Update

- `pi-webui/src/server/index.ts`
- `pi-webui/src/server/workspace-store.ts`
- `pi-webui/public/app.js`
- `pi-webui/public/url-state.mjs`
- `pi-webui/test/url-state.test.mjs`
- `pi-webui/test/workspace-store.test.mjs`

## Target Transition Interface Sketch

```ts
export type TargetTransition =
  | { kind: "cwd"; cwd: string; source: "url_cwd_startup" | "picker" | "slash_cwd" | "workspace" | "new_session" }
  | { kind: "session"; sessionPath: string; cwd: string; source: "import" | "picker" | "switch_session" };

export async function resolveCwdTransition(args): Promise<TargetTransition>;
export async function resolveWorkspaceTransition(args): Promise<TargetTransition>;
export async function resolveSessionTransition(args): Promise<TargetTransition>;
export function shouldPersistLastCwd(transition: TargetTransition): boolean;
```

The exact type names can change. The important behavior is:

- transition resolution happens before runtime replacement;
- transition resolution does not read cwd from the current runtime as the authority;
- persistence uses transition cwd, not `runtime.cwd`;
- URL cwd startup persistence uses the validated URL cwd, not a runtime-derived cwd;
- transition application serializes or rejects concurrent runtime-creating transitions for the same controller;
- session transitions use session header cwd.

## Commands To Migrate

- `/cwd <path>`
- `/cwd` picker result
- `/workspace <name-or-path>`
- `/workspace` picker result
- `/resume` picker result
- `/new`
- `new_session`
- `switch_session`
- any direct session picker selection

## Commands That Stay Runtime-Required

- prompt submission
- bash execution
- abort
- compact
- name
- reload
- session details
- settings/model/scoped-models/login/logout
- export/import/clone/fork/tree unless explicitly redesigned later
- prompt template commands
- extension commands

Some of these commands may change selected target as a side effect today. Keep Phase 3 focused on the commands listed under migration unless implementation shows a command is part of the same transition path.

## Implementation Sequence

1. Add target transition tests.
   - Valid `/?cwd=<path>` startup is treated as an explicit cwd target and persists the validated cwd to `lastCwd`.
   - Plain `/` startup from existing valid `lastCwd` creates a runtime but does not rewrite `lastCwd`.
   - Invalid URL state and cwd-required state do not persist `lastCwd`.
   - `/cwd <path>` resolves cwd transition with validated cwd.
   - Workspace selection resolves cwd transition from saved workspace path.
   - Picker/protocol session switching resolves session transition with header cwd.
   - Missing/corrupt/headerless session switching fails before runtime switch.
   - New session resolves cwd transition using current selected cwd target.
   - Transition persistence uses transition cwd.
   - Concurrent runtime-creating transitions for one controller are serialized or rejected by the transition applicator.
   - Double `select_cwd`, double `select_session`, and mixed cwd/session recovery races cannot create duplicate runtimes, duplicate bindings, or interleaved bootstraps.

2. Implement target transition module.
   - Reuse cwd validation and session prevalidation.
   - Reuse workspace registry lookup.
   - Return explicit transition source.

3. Refactor controller runtime replacement.
   - Add one helper that applies a target transition:
     - stop file watch;
     - unsubscribe;
     - dispose old runtime;
     - create runtime from new target;
     - assert runtime cwd matches target cwd;
     - persist `lastCwd` when the transition says to persist;
     - bind session;
     - send bootstrap.
   - The helper owns the in-flight transition gate for runtime-creating target transitions.
   - The in-flight policy may be serialize or reject, but it must be one consistent applicator behavior and tests must pin it down.
   - Use the same persistence decision path for valid URL cwd startup, even if startup remains outside the command transition helper.
   - Keep cancellation semantics where runtime hooks still apply.

4. Remove generic cwd persistence.
   - Delete generic `setLastCwd(agentDir, this.runtime.cwd)` from command success.
   - Delete duplicate `setLastCwd` calls inside migrated commands after persistence is centralized.
   - Keep persistence only in explicit target transition flow.
   - Preserve URL cwd startup persistence explicitly; do not accidentally remove it with generic command persistence.

5. Migrate cwd and workspace commands.
   - `/cwd <path>` resolves and applies cwd transition.
   - `/cwd` with no arg still opens picker.
   - `/workspace <selector>` resolves and applies cwd transition.
   - Workspace picker uses the same transition path.

6. Migrate session commands.
   - `/resume` opens the session picker.
   - Session picker selection uses URL navigation or target transition consistently with Phase 2 choice.
   - `switch_session` uses session transition.
   - Session header cwd is persisted as `lastCwd`.

7. Migrate new-session commands.
   - `/new` and `new_session` create a fresh session in the current selected cwd target.
   - They do not infer cwd from runtime as source of truth.
   - Their command result still includes cwd for browser URL Cwd Pointer sync.

8. Tighten slash command availability.
   - Catalog reflects runtime-free vs runtime-required modes.
   - Runtime-changing commands are available in both runtime and no-runtime modes only when their arguments/actions can resolve a target.
   - Prompt-routed commands remain runtime-required.

9. Route runtime-free recovery through target transition application.
   - `select_cwd`, runtime-free `/cwd <path>`, and `select_session` should resolve targets, then use the same transition applicator as normal runtime-changing commands.
   - Runtime-free recovery handlers should not keep a separate recovery-only concurrency guard once the applicator exists.

## Phase 3 Verification

Run:

```bash
npm test --prefix pi-webui
```

Prefer integration tests that drive commands through the same WebSocket protocol as the browser. Add browser e2e coverage for URL and picker behavior where feasible.

## Phase 3 Validation Scenarios

- Open `/?cwd=<valid-absolute-path>`. Confirm runtime starts in that cwd and `workspaces.json:lastCwd` is updated to the validated URL cwd.
- Open `/` with an existing valid `lastCwd`. Confirm runtime starts in that cwd and no new persistence write is required.
- Open invalid URL state or cwd-required state. Confirm no `lastCwd` write happens until the user chooses a recovery target.
- Use `/cwd <path>` from an active session. Confirm target changes first, runtime restarts in that cwd, URL moves to cwd mode, and `lastCwd` is updated from the transition cwd.
- Use `/workspace <name>`. Confirm target resolves from workspace path and runtime starts in workspace cwd.
- Use `/resume`. Confirm the session picker opens.
- Use session picker from runtime state. Confirm target resolves from session header cwd, runtime starts in that cwd, and `lastCwd` becomes the session header cwd.
- Use `/new` from a durable session. Confirm URL moves to cwd mode without encoding empty session identity.
- Use `new_session` protocol command. Confirm it creates a fresh session in the selected cwd target.
- Run prompt, bash, model, and read-only session commands. Confirm they do not rewrite `lastCwd`.
- Try a malformed or missing session path through protocol session switching. Confirm it fails before runtime replacement and leaves the current runtime target intact.
- Trigger two recovery selections quickly, including double cwd selection, double session selection, and mixed cwd/session selection. Confirm the transition applicator serializes or rejects the second transition consistently and only one runtime/bind/bootstrap sequence wins.

## Done Criteria

- Runtime-changing commands resolve selected targets before runtime replacement.
- Runtime cwd no longer acts as source of truth for selected cwd.
- `lastCwd` is persisted only from explicit target transitions.
- Valid URL cwd startup persists the validated URL cwd as an explicit target selection.
- Runtime-creating target transitions for a controller cannot overlap; the applicator owns serialization or rejection.
- Session picker/protocol switching persists header cwd.
- Generic command success no longer persists cwd.
- Runtime-free and runtime-required command availability is clear in the Slash Command Catalog.
