# PLAN-004 Phase 1: Target Startup

## Goal

Introduce selected target resolution before runtime creation and remove process/env cwd fallback from startup. At the end of this phase, pi-webui can start in one of four states:

- valid cwd target;
- valid session target;
- invalid URL state;
- cwd-required state.

Only valid cwd/session targets create a Pi runtime.

## Files To Add

- `pi-webui/src/server/runtime-target.ts`
- `pi-webui/test/server-runtime-target.test.mjs`

File names can change during implementation if a clearer local naming pattern emerges. Keep the module concept stable.

## Files To Update

- `pi-webui/src/server/index.ts`
- `pi-webui/src/server/url-session-startup.ts`
- `pi-webui/src/server/session-info.ts`
- `pi-webui/test/server-url-session-startup.test.mjs`
- `pi-webui/test/server-url-state.test.mjs`
- `pi-webui/test/workspace-store.test.mjs`

## Module Interface Sketch

### Runtime Target Module

Own target resolution and runtime eligibility.

```ts
export type RuntimeTarget =
  | { kind: "cwd_required"; message: string; value?: string }
  | { kind: "invalid_url"; invalidKind: InvalidUrlStateKind; value: string | null; message: string }
  | { kind: "cwd"; cwd: string; source: "url" | "lastCwd" }
  | { kind: "session"; sessionPath: string; cwd: string; source: "url" };

export async function resolveRuntimeTarget(args: {
  urlState: ServerUrlState;
  agentDir: string;
  sessionDir?: string;
  policy: CwdPolicy;
}): Promise<RuntimeTarget>;
```

Rules:

- `urlState.kind === "cwd"` returns a cwd target.
- `urlState.kind === "session"` validates the session file and returns a session target with cwd from the header/session manager.
- `urlState.kind === "invalid"` returns invalid URL target.
- `urlState.kind === "new"` loads workspace registry.
- If registry has valid `lastCwd`, return cwd target with source `lastCwd`.
- If registry has no `lastCwd`, return cwd-required.
- If registry has invalid/deleted `lastCwd`, return cwd-required with a message that includes the invalid value.
- Never call `process.cwd()`.
- Never read a cwd environment variable.

### Runtime Creation Helper

Convert only valid targets into runtime inputs.

```ts
export function runtimeSessionManagerForTarget(args: {
  target: Extract<RuntimeTarget, { kind: "cwd" | "session" }>;
  sessionDir?: string;
}): SessionManager;

export function assertRuntimeMatchesTarget(args: {
  target: Extract<RuntimeTarget, { kind: "cwd" | "session" }>;
  runtimeCwd: string;
}): void;
```

The exact split can vary. The important seam is that tests can prove target cwd and runtime cwd agreement.

## Implementation Sequence

1. Add target resolution tests.
   - No URL, no `lastCwd` returns cwd-required.
   - No URL, valid `lastCwd` returns cwd target.
   - No URL, deleted `lastCwd` returns cwd-required.
   - No URL, invalid `lastCwd` outside cwd policy returns cwd-required.
   - Valid URL cwd returns cwd target and does not inspect `lastCwd`.
   - Valid URL session returns session target with header cwd.
   - Invalid URL cwd returns invalid URL target.
   - Invalid URL session returns invalid URL target.

2. Implement runtime target resolution.
   - Move initial cwd selection out of `index.ts`.
   - Preserve existing URL session prevalidation behavior.
   - Stop requiring `defaultCwd` for invalid URL handling.

3. Wire controller startup.
   - Resolve target in controller initialization.
   - For invalid URL target, send invalid URL packet and return without runtime.
   - For cwd-required target, send cwd-required packet and return without runtime.
   - For cwd/session target, create runtime from the target.
   - Assert runtime cwd matches target cwd immediately after creation.

4. Update invalid URL packet contract.
   - Remove `defaultCwd`.
   - Remove eager `sessions`.
   - Keep invalid kind, value, and message.

5. Update browser minimum handling.
   - Existing invalid URL rendering may temporarily show fewer actions until Phase 2.
   - Add minimal cwd-required rendering and composer blocking.
   - Do not build full recovery yet.

6. Remove startup fallback tests.
   - Replace tests that expect new URL state to create a runtime from `defaultCwd`.
   - Add tests proving no process cwd fallback.

## Phase 1 Verification

Run:

```bash
npm test --prefix pi-webui
```

Prefer WebSocket/controller integration tests for this phase. The target resolver should have focused module tests, but the phase should be accepted by observing startup packets and runtime creation behavior.

## Phase 1 Validation Scenarios

- Start with no `lastCwd` and no URL params. Confirm cwd-required packet is sent, no normal `connected` bootstrap is sent, and no runtime is created.
- Start with deleted `lastCwd`. Confirm cwd-required packet includes an explanation and no process cwd fallback occurs.
- Start with invalid-policy `lastCwd`. Confirm cwd-required packet includes an explanation and no runtime is created.
- Start with valid `lastCwd`. Confirm normal runtime startup in that cwd.
- Open valid `?cwd=<path>`. Confirm normal runtime startup in that cwd and `lastCwd` is not consulted.
- Open valid `?session=<path>`. Confirm runtime startup uses the session header cwd.
- Open missing session URL. Confirm invalid URL packet is sent, no runtime is created, and the missing file is not created.
- Open corrupt/headerless/missing-cwd session URL. Confirm invalid URL packet is sent and the file contents are unchanged.
- Open invalid cwd URL. Confirm invalid URL packet has no `defaultCwd` or session lists.

## Done Criteria

- Startup no longer calls `process.cwd()` for cwd selection.
- There is no env cwd fallback path.
- Missing/invalid `lastCwd` creates cwd-required state.
- Invalid URL state creates no runtime and carries no eager recovery data.
- Runtime is created only from valid cwd/session targets.
- Runtime cwd is asserted against selected target cwd.
