# Research Notes

This repo is now semantics-first.

The question is not “what control API feels convenient?” The question is “what exact operator family does the runtime implement, and how do we keep that answer stable as the code evolves?”

The current ladder is:

1. law
2. executable reference witness
3. CoreSR-Full typed derivation
4. machine account
5. runtime realization

The runtime is accepted only when it matches the earlier rungs.

## Current Focus

- exact static `shift/reset`
- explicit typed prompt values
- explicit continuation argument
- one-shot restriction
- honest answer-type pressure if required

## Current Repository Discipline

- every kernel feature needs a law entry
- every semantic claim needs a witness
- every witness needs a stable transcript
- every runtime change touching capture, resume, prompt matching, or answer-type behavior must preserve ladder agreement
- every prompt mode must appear in `docs/protocol_matrix.md`
- every attempted plain-Zig one-shot encoding family must be logged in `docs/closure_ledger.md`
- every branch that advances answer-type pressure must update `docs/atm_surface_table.md`
- every non-diagonal ATM witness that executes must be logged in `docs/atm_witness_ledger.md`
