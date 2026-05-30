# PLAN-004 Phase 3: Target-Based Transitions

## Goal

Move all cwd/session-changing commands to the selected target model. At the end of this phase, runtime-changing flows resolve a new target first, then create or replace the runtime from that target. `lastCwd` is persisted only after explicit target transitions.

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
  | { kind: "cwd"; cwd: string; source: "picker" | "slash_cwd" | "workspace" | "new_session" }
  | { kind: "session"; sessionPath: string; cwd: string; source: "resume" | "picker" | "switch_session" };

export async function resolveCwdTransition(args): Promise<TargetTransition>;
export async function resolveWorkspaceTransition(args): Promise<TargetTransition>;
export async function resolveSessionTransition(args): Promise<TargetTransition>;
export function shouldPersistLastCwd(transition: TargetTransition): boolean;
```

The exact type names can change. The important behavior is:

- transition resolution happens before runtime replacement;
- transition resolution does not read cwd from the current runtime as the authority;
- persistence uses transition cwd, not `runtime.cwd`;
- session transitions use session header cwd.

## Commands To Migrate

- `/cwd <path>`
- `/cwd` picker result
- `/workspace <name-or-path>`
- `/workspace` picker result
- `/resume <path>`
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
   - `/cwd <path>` resolves cwd transition with validated cwd.
   - Workspace selection resolves cwd transition from saved workspace path.
   - Session resume resolves session transition with header cwd.
   - Missing/corrupt/headerless session resume fails before runtime switch.
   - New session resolves cwd transition using current selected cwd target.
   - Transition persistence uses transition cwd.

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
   - Keep cancellation semantics where runtime hooks still apply.

4. Remove generic cwd persistence.
   - Delete generic `setLastCwd(agentDir, this.runtime.cwd)` from command success.
   - Delete duplicate `setLastCwd` calls inside migrated commands after persistence is centralized.
   - Keep persistence only in explicit target transition flow.

5. Migrate cwd and workspace commands.
   - `/cwd <path>` resolves and applies cwd transition.
   - `/cwd` with no arg still opens picker.
   - `/workspace <selector>` resolves and applies cwd transition.
   - Workspace picker uses the same transition path.

6. Migrate session commands.
   - `/resume <path>` resolves and applies session transition.
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

## Phase 3 Verification

Run:

```bash
npm test --prefix pi-webui
```

Prefer integration tests that drive commands through the same WebSocket protocol as the browser. Add browser e2e coverage for URL and picker behavior where feasible.

## Phase 3 Validation Scenarios

- Use `/cwd <path>` from an active session. Confirm target changes first, runtime restarts in that cwd, URL moves to cwd mode, and `lastCwd` is updated from the transition cwd.
- Use `/workspace <name>`. Confirm target resolves from workspace path and runtime starts in workspace cwd.
- Use `/resume <session>`. Confirm target resolves from session header cwd, runtime starts in that cwd, and `lastCwd` becomes the session header cwd.
- Use session picker from runtime state. Confirm selection follows the same session target rules as typed `/resume`.
- Use `/new` from a durable session. Confirm URL moves to cwd mode without encoding empty session identity.
- Use `new_session` protocol command. Confirm it creates a fresh session in the selected cwd target.
- Run prompt, bash, model, and read-only session commands. Confirm they do not rewrite `lastCwd`.
- Try a malformed or missing session path through resume/switch. Confirm it fails before runtime replacement and leaves the current runtime target intact.

## Done Criteria

- Runtime-changing commands resolve selected targets before runtime replacement.
- Runtime cwd no longer acts as source of truth for selected cwd.
- `lastCwd` is persisted only from explicit target transitions.
- Session resume persists header cwd.
- Generic command success no longer persists cwd.
- Runtime-free and runtime-required command availability is clear in the Slash Command Catalog.
