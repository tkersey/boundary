# Research Notes

This repo is now exploring the stackful side of one-shot `shift/reset` rather than the earlier managed-frame effect-machine model.

Current implementation choices:

- Audited assembly context-switch stubs instead of a large inline-assembly surface.
- Fiber-backed continuation capture.
- One-shot continuation ownership with explicit `resumeWith` and `discontinue`.
- Explicit `ErrorSet` threading through the public `reset`/`shift` surface.
- Collision-free internal prompt identity via per-type tokens rather than hashed type names.
- A hard runtime guard for known unsafe suspension regions.

Current open research edge:

- The benchmark suite still needs a preserved pre-rewrite baseline artifact if this project is going to make strong comparative performance claims.
