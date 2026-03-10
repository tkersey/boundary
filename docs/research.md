# Research Notes

This repo is now treating research as a first-class implementation lane rather than background reading.

The immediate goal is not to genericize `shift` into a broad PL project. The goal is to explain the current runtime precisely enough that future ergonomic waves can be *derived* from it instead of guessed. The repo is still the source of truth: the runtime, tests, examples, and benchmark artifacts come first, and external literature only counts when it sharpens a concrete repo decision.

## Current implementation choices

- Audited assembly context-switch stubs instead of a large inline-assembly surface.
- Fiber-backed reset frames.
- Runtime-local reset-frame reuse to keep the no-capture path reasonable.
- Heap-backed, one-shot owner records with explicit `resumeWith`, `discontinue`, and `cancel`.
- Library-owned terminal cancellation plus escaped-owner auto-cancel on `deinit()`.
- Explicit spec structs that carry `tag`, `Request`, `Resume`, `Answer`, and `ErrorSet`.
- Collision-free internal prompt identity via per-type tokens rather than hashed type names.
- Internal machine vocabulary in the implementation now mirrors the research language: machine state, machine signal, delimiter frame, pending edge, and resolution.
- A hard runtime guard for known unsafe suspension regions.
- A repo-local docs-sanity gate so learnings records cannot silently contaminate markdown docs.

## Current research questions

- Which witness best pins the repo’s actual semantic boundary?
- What evaluator-to-machine derivation best explains escaped-owner delayed resolution without inventing a new semantic surface?
- Which future public breaks remain allowed once the witness and machine story are fixed?

## Research artifacts in this repo

- [research_laws.md](research_laws.md): witness-first law set and operator-position note
- [research_machine.md](research_machine.md): evaluator-to-machine sketch and runtime correspondence matrix
- [research_decision.md](research_decision.md): future-break constraints for the pending-owner-first public surface

## How to use this track

Read the three documents in order:

1. Start with the laws to pin what the runtime actually promises today.
2. Read the machine account to see which parts of the runtime are already explicit control-machine structure.
3. Use the decision dossier to decide which future ergonomic layers are still faithful to that machine.

## Current open research edge

- A future ergonomic wrapper may still be useful for framework builders, but it must remain additive rather than replacing the pending-owner-first semantic center.
