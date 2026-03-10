# Job Workflow Walkthrough

`examples/job_workflow/` is the repo's larger "why would I use this?" example.

Its request loop now goes through `examples/support/driver.zig`. That helper is shared example infrastructure only; it is not part of the public `shift` API.

Run it with:

```bash
zig build run-job-workflow
```

The example keeps one idea per branch:

- `approved`: shows the normal `resumeWith(...)` path.
- `rejected`: shows `discontinue(error.ApprovalDenied)` and recovery inside the workflow body.
- `cancelled`: shows library-owned terminal cancellation via `cancel()`.

## What the driver owns

`runScenario(...)` drives `shift.reset(...)` until the workflow either:

- completes with a `ScenarioResult`
- yields a token carrying a `WorkflowRequest`
- reaches terminal cancellation

The driver prints each request before resolving it:

- `log=...` requests are acknowledged with `resumeWith(.{ .ack = {} })`
- `approval=...` requests are resolved according to the active scenario:
  - `approved` -> `resumeWith(.{ .approved = true })`
  - `rejected` -> `discontinue(error.ApprovalDenied)`
  - `cancelled` -> `cancel()`

If the writer fails while a token is outstanding, the driver drains that token before returning the I/O error. That keeps the runtime teardown invariant intact.

## How each branch maps to control flow

### Approved

1. The workflow logs `queued ingest`.
2. It enters a `NoShiftGuard`, performs a small critical update, leaves the guard, and then logs `critical metadata prepared`.
3. It logs `nested audit started`.
4. It enters a nested `reset` with a different prompt tag.
5. The nested body calls `shift(workflow_spec, .{ .approval = "ingest" })`.
6. That request bubbles to the outer driver, proving the outer prompt is still the active handler across the nested reset.
7. The driver resumes with approval, the nested reset completes, the workflow logs `nested audit finished`, and the scenario returns `completed`.

### Rejected

1. The workflow logs `queued publish`.
2. It performs the same guarded critical section and logs `critical metadata prepared`.
3. It requests approval for `publish`.
4. The driver resolves that token with `discontinue(error.ApprovalDenied)`.
5. The workflow catches that user-owned error and converts it into a recovery path by logging `recovered publish skipped`.
6. The scenario returns `recovered`.

### Cancelled

1. The workflow logs `queued cleanup`.
2. It performs the same guarded critical section and logs `critical metadata prepared`.
3. It requests approval for `cleanup`.
4. The driver calls `cancel()`.
5. The runtime terminates the workflow with library-owned cancellation, and the scenario reports `cancelled`.

## Where the advanced semantics show up

- Nested `reset`: only the `approved` path uses it, to demonstrate outer-prompt bubbling through an inner delimiter.
- `NoShiftGuard`: every scenario uses it around the critical metadata update to model "do not suspend here."
- `error.ShiftForbidden`: this rejection path is proven in `test/job_workflow_test.zig`, not in the printed showcase output, so the transcript stays readable.

## Files to read

- `examples/job_workflow/workflow.zig`: reusable scenario logic and the driver loop
- `examples/job_workflow/main.zig`: thin executable entrypoint
- `test/job_workflow_test.zig`: scenario proofs, output lock, and guard rejection proof
