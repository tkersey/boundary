# Migration from Boundary 0.7

Boundary 1.0 is source- and state-incompatible with Boundary 0.7.

- Existing applications remain supported by pinning the immutable Boundary
  0.7 and World 1.0 releases.
- There is no automatic migration for live Session, Capsule, loaded-module, or
  StaticMachine ABI v1 continuations.
- Rewrite source types to the fixed-width and bounded portable value algebra.
- Replace `boundary.staticMachine(Program, options)` with
  `Program.compile(options)`.
- Replace `Program.run`, `Program.Session`, and root `Runtime` local execution
  with `boundary.Driver(Machine)`.
- Replace runtime handler/interpreter pipelines with compiler-known
  transformations or ordinary typed residual effects.
- Rebuild World applications against Machine ABI v2; do not alter persisted
  ABI v1 Frames or Effect v1 messages.

Boundary 1.0 intentionally does not include a `boundary-legacy` package,
loaded-program compatibility layer, or `ABL_STM1` decoder. The old release is
the compatibility implementation.
