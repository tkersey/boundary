# M2 — executable-record optimization (in progress)

Base: the accepted Boundary cutover `ef25b3d`. Agent's recorded cutover costs
are accepted tradeoffs; they remain in cumulative comparisons. No frontend
uniformity migration is part of this work.

## Implemented first consumer

`data.value_facts` admits the original records, binds facts to their BPI3 identity,
and records a distinct definition for each stable-slot write. It currently derives
block-local constants, constructor origins, unsigned masks and sequence length
facts. An incoming vector's maximum is not its actual length. Cross-block inputs
remain unknown in this initial implementation.

`data.application_specialization.run` consumes those facts. It replaces a locally
constructed computation and its single application with the existing function's
direct call, passing captures before explicit arguments in their original order.
It requires one definition/consumption, available capture versions, portable
captures and no captured/required regions. An independent raw-record checker
checks correspondence without consuming the finder's facts, followed by fresh
admission and mandatory P01. This is an external-semantics transformation;
it does not promise the same internal microsteps across different images.

The first witness removes one `computation` instruction and one `apply`, retains
one direct call, and reduces BPI3 from 108 to 97 bytes. Unchanged native World
returns the same ordered pair for three distinct runtime capture/argument pairs.
This is synthetic capability evidence, not a real-Agent speed claim.

Focused checks cover swapped equal-type operands, capture reassignment, stale
facts after constructor mutation, range/known-bit and length/bound distinctions,
and every allocation-failure point in the small transformation witness.

## Remaining M2 obligations

This is not complete M2 or canonical pipeline adoption. Remaining work includes:

- Checked joins, simultaneous edge assignments, feasible edges, loops/SCCs and
  conservative interprocedural summaries; the branch-to-constructor witness.
- Incoming-callable caller specialization, polymorphic/opaque negatives and
  applicable dead argument/capture/aggregate reductions.
- The specified early P04/P05/P07/P08 transformations and independent certificates.
- Semantic/structural contract integration into compilation and final linking,
  the owned-consumer policy audit, deterministic semantic work budgets, and
  source-free closed-link execution.
- Cross-package qualification, paired economics against the retained C0 corpus,
  and all applicable G/T obligations. M2.5's affine synthesis remains subsequent.

Reproduction of the native record witness uses only Boundary data and World:

```sh
zig test -O ReleaseSafe --dep boundary_data --dep world \
  -Mroot=test/v2/application_specialization.zig \
  -Mboundary_data=src/data/root.zig --dep boundary_data \
  -Mworld=/absolute/world/src/root.zig
```
