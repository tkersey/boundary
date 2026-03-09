# Cost Model

This runtime is not zero-cost in the old managed-frame sense.

## Current costs

- Every `reset` enters a stackful fiber.
- Every `reset` uses heap-backed reset-frame storage.
- The first `reset` on a runtime allocates a stack mapping.
- Later resets usually reuse a cached stack.
- Every `shift(...)` allocates one suspension record and returns `Step.suspended`.
- Every `resumeWith` or `discontinue` performs another context switch back into the captured frame.

## Current cheap path

- A no-capture `reset` still switches into a fiber, but after warm-up it usually reuses both the stack cache and the frame cache.
- The benchmark in `bench/no_capture_bench.zig` measures this path.

## Current expensive path

- First suspension involves a cached-or-fresh reset frame, one heap allocation for the suspension record, two context switches, and caller-side driver logic.
- Nested reset frames keep paying stackful control costs even though outer-prompt bubbling still works.

The README, benchmark artifacts, and benchmark outputs are the source of truth for current performance claims.
