# M2 — executable-record optimization (in progress)

Base: the accepted Boundary cutover `ef25b3d`. Agent's recorded cutover costs
are accepted tradeoffs; they remain in cumulative comparisons. No frontend
uniformity migration is part of this work.

## Implemented first consumer

`data.value_facts` admits the original records, binds facts to their BPI3 identity,
and records a distinct definition for each stable-slot write. It currently derives
constants, constructor origins, unsigned masks and sequence length facts. A
worklist transfers predecessor values simultaneously and joins incoming facts;
cycles lose unsupported constant precision. Constructor sets widen to explicit
unknown above four possibilities. Host, constructor, handler and resource-authority
entries remain open-world unknown roots. Private direct-call workers receive
ordered caller argument facts through the same monotone worklist, including
recursive components. Return values remain conservatively unknown. An incoming
vector’s maximum is not its actual length.

`data.application_specialization.run` consumes those facts. It replaces a locally
constructed computation and its single application with the existing function's
direct call, passing captures before explicit arguments in their original order.
It requires one definition/consumption, available capture versions, portable
captures and no captured/required regions. An independent raw-record checker
checks correspondence without consuming the finder's facts, followed by fresh
admission and mandatory P01. This is an external-semantics transformation;
it does not promise the same internal microsteps across different images.

`data.branch_reduction` uses feasible-edge facts and an independent backwards
constant-origin proof. It preserves evaluation of the condition and original
admission, then runs P01. The proof conservatively declines ambiguous joins and
cycles, and a depth limit is reported rather than risking native stack exhaustion.
A proven branch removes an alternative constructor path, enabling a closed
constructor application to become a direct call across blocks. That witness
shrinks from 163 to 121 bytes. An unknown external condition retains both targets.

`data.dead_computation` now consumes that specialized candidate. Backwards demand
removes unused total instructions only when their results and operands permit both
copy and drop. It excludes calls, mutable operations, faulting instructions and
resource/cleanup operations. Zero-capture constructions additionally require no
owned or borrowed regions. The independent checker compares the retained raw
subsequence and candidate liveness, with original and fresh candidate admission.
A deterministic instruction-work limit rolls back to the original before final
P01. This removes the remaining unused constructor and condition in the branch
witness, reducing 121 to 106 bytes (163 bytes before the combined transformations).
Native World preserves its output; unused division by zero still produces failure.
This is the dead-computation subset of P05, not dead-argument/store completion.

The first witness removes one `computation` instruction and one `apply`, retains
one direct call, and reduces BPI3 from 108 to 97 bytes. Unchanged native World
returns the same ordered pair for three distinct runtime capture/argument pairs.
This is synthetic capability evidence, not a real-Agent speed claim.

The known-argument witness now calls a private worker with a constant boolean;
that argument proves one worker branch infeasible and enables P03, reducing the
witness from 194 to 152 bytes. A separate
worker receiving a singleton closed callable specializes its incoming `apply`.
The backwards checker reconstructs all raw direct callers and accepts only
agreement, without reusing the forward analysis. Two incoming constructors,
unknown host arguments, constructor-visible workers and opaque captured
environments retain conservative behavior. A recursive worker that changes its
argument joins both values instead of freezing its initial caller's constant.

`data.dead_arguments` removes unused copy/drop parameters from private direct-call
workers and the corresponding ordered argument at every call. It retains argument
evaluation. The independent checker verifies the complete call set, input liveness,
usage permissions and exact ABI subsequences; original and candidate admission
precede final P01. This lets dead-computation elimination remove the construction
formerly passed to the specialized callable worker: one parameter, one argument
and one constructor disappear, reducing that witness from 131 to 119 bytes.
Host, constructor, handler and resource-authority interfaces retain their inputs.

Focused checks cover swapped equal-type operands, capture reassignment, stale
facts after constructor mutation, range/known-bit and length/bound distinctions,
and every allocation-failure point in the small transformation witness.
The dead-computation slice adds live-overwrite and fault-deletion mutations,
work-limit rollback, and allocation-failure coverage. Its focused suite has 36
passing tests, and the native record suite has four. The initial division fixture
was rejected because its fault table used the wrong wire order; correcting the
fixture to the admitted overflow/zero order left production admission unchanged.
The caller/argument slice expands this to 46 focused tests and six native World
tests, including a faulting computation whose now-unused argument is removed while
its evaluation still fails. A temporary parameter-removal statistics bug was
corrected: count before transferring the list storage, whose length then resets.

## Remaining M2 obligations

This is not complete M2 or canonical pipeline adoption. Remaining work includes:

- Remaining P02 domains, return summaries and richer recursive/calling contexts
  beyond the current conservative argument fixed point.
- Context cloning where callers disagree, and remaining dead
  store/capture/aggregate reductions. Private dead arguments, singleton incoming-callable specialization
  and polymorphic/opaque negatives are implemented.
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
