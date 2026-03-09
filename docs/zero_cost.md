# Cost Model

This runtime is not zero-cost in the old managed-frame sense.

## Current costs

- Every `reset` enters a stackful fiber.
- The first `reset` on a runtime allocates a stack mapping.
- Later resets usually reuse a cached stack.
- Every `shift` performs a context switch to the parent context.
- Every `resumeWith` or `discontinue` performs another context switch back into the captured frame.

## Current cheap path

- A no-capture `reset` still switches into a fiber, but it does not allocate after the stack cache is warm.
- The benchmark in `bench/no_capture_bench.zig` measures this direct-style fast path.

## Current expensive path

- Capturing and resuming involves two explicit context switches plus handler execution.
- Nested reset frames still pay stackful control costs even though outer-prompt capture now works across them.

The README and benchmark outputs are the source of truth for current performance claims.
