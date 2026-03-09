# Research Notes

This repo is now exploring the stackful side of one-shot `shift/reset` through a framework-builder-facing linear token API.

Current implementation choices:

- Audited assembly context-switch stubs instead of a large inline-assembly surface.
- Fiber-backed reset frames.
- Runtime-local reset-frame reuse to keep the no-capture path reasonable.
- Heap-backed, one-shot token records with explicit `resumeWith`, `discontinue`, and `cancel`.
- Library-owned terminal cancellation plus token auto-cancel on `deinit()`.
- Explicit spec structs that carry `tag`, `Request`, `Resume`, `Answer`, and `ErrorSet`.
- Collision-free internal prompt identity via per-type tokens rather than hashed type names.
- A hard runtime guard for known unsafe suspension regions.
- A repo-local docs-sanity gate so learnings records cannot silently contaminate markdown docs.

Current open research edge:

- The product semantics are now clearer than the older step/suspension surface, but future work may still revisit whether framework builders ultimately want a stable session object instead of a linear token.
