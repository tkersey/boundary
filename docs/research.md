# Research Notes

This repo is now exploring the stackful side of one-shot `shift/reset` through an escaping, step-driven public API rather than an immediate callback handler.

Current implementation choices:

- Audited assembly context-switch stubs instead of a large inline-assembly surface.
- Fiber-backed reset frames.
- Runtime-local reset-frame reuse to keep the escaping core within the preserved no-capture benchmark budget.
- Heap-backed, one-shot suspension records with explicit `resumeWith` and `discontinue`.
- Explicit spec structs that carry `tag`, `Request`, `Resume`, `Answer`, and `ErrorSet`.
- Collision-free internal prompt identity via per-type tokens rather than hashed type names.
- A hard runtime guard for known unsafe suspension regions.
- A repo-local docs-sanity gate so learnings records cannot silently contaminate markdown docs.

Current open research edge:

- The escaping API now clears the initial no-capture regression budget with runtime-local frame reuse, but future work may still need to trim first-suspend overhead if the suspension-record allocation path becomes the next dominant cost.
