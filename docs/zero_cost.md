# Cost Model

This runtime is not zero-cost in the old managed-frame sense.

## Current costs

- Every `reset` enters a stackful fiber.
- Every `reset` uses heap-backed reset-frame storage.
- The first `reset` on a runtime allocates a stack mapping.
- Later resets usually reuse a cached stack.
- Every `shift(...)` allocates one owner record and returns `Outcome.pending`.
- Every `resumeWith`, `discontinue`, or `cancel` performs another context switch back into the captured frame.

## Current cheap path

- A no-capture `reset` still switches into a fiber, but after warm-up it usually reuses both the stack cache and the frame cache.
- The benchmark in `bench/no_capture_bench.zig` measures this path with an internal warm-up and a five-sample median so cold cache fill does not pollute the steady-state number.

## Current expensive path

- First pending-owner creation involves a cached-or-fresh reset frame, one heap allocation for the owner record, two context switches, and caller-side lifecycle logic.
- Nested reset frames still pay stackful control costs even though outer-prompt bubbling still works.
- The benchmark in `bench/direct_first_suspend_bench.zig` uses the same warmed five-sample median contract for the steady-state first-suspend path.

The README and benchmark artifacts remain the source of truth for current performance claims, but performance is no longer the primary design driver of this pass.

The warmed benchmark envelope is still a semantic guardrail for the current runtime shape: changes that clarify the machine model or public contract are only accepted when neither tracked path becomes more than the documented threshold slower than baseline.
