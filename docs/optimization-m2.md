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

`data.aggregate_reduction` forwards local immutable product projections from
available original operand versions, including moved product aliases. Its checker
traces raw definitions backwards, verifies the ordered field and rejects a source
overwritten after construction. Copy/drop permissions and original/fresh admission
remain required. Subsequent checked DCE removes unobserved product construction;
an externally returned aggregate remains materialized. The witness shrinks from
81 to 69 bytes. This is logical product scalar replacement; physical allocation
placement remains a separate obligation.

Data-only native tests now cover source-free BMO decoding and closed linking.
One links the product object before reduction. Another binds an independently
encoded caller's imported worker to a second object's exported worker; only after
linking does its known argument prune the branch and enable P03/P05. That witness
shrinks from 194 to 131 bytes, preserves World output, and runs final P01. The
optimizer reads linked records after the object byte buffers have been overwritten.
These tests exercise the transformation sequence explicitly; automatic semantic
compiler/final-link integration remains unfinished.

`data.expression_reuse` implements the early P04 total-expression subset. A
definition catalogue records opcode, output schema, immediate and ordered operand
slots; must-availability invalidates a definition on any source/operand write or
relevant parallel edge assignment. Intersections require availability on every
incoming path. Reuse is checked separately by backwards raw-record traversal to
the dominating successful producer. Mutable reads, faulting expressions, closures,
packages/resources and non-copy/drop values are excluded. No commutative or
copy-alias canonicalization is assumed. Cyclic proofs conservatively decline.

The diamond witness computes the same XOR before and after a control-flow region;
reuse reduces its dynamic XOR evaluations from two to one on both paths. A local
repetition also reuses its earlier value. The linked-record native witness shrinks
82 to 81 bytes and preserves outputs for both paths and multiple operands. This
does not establish a timing improvement. The pass bounds discovery and independent
correspondence work deterministically, defaults to one million work units, and
rolls back the complete candidate before final P01 when that budget is exhausted.
Original/fresh admission and P01 retain their own obligations and budgets.

`data.cell_reduction` implements the minimum private-cell case for a worker with
one returning block. A portable copy/drop payload replaces the cell's private slot;
allocation/read/store operations become value assignments and unit results at the
same ordered points. The independent checker matches the entire original record
sequence against those scalar state transitions and checks all uses, interfaces
and permissions. Original/fresh admission precedes final P01. Subsequent checked
DCE removes overwritten scalar assignments. Aliases, payload capture, suspension,
calls and intervening fault observations remain outside this local case.

The one-store witness shrinks 135 to 119 bytes. A source-free linked witness with
two stores before a read shrinks 136 to 119 bytes: one cell allocation, one read
and two cell stores disappear, and World preserves the final value for three
input pairs. Store unit results remain explicit until independently proved dead.
This establishes logical elimination, not physical stack placement or a measured
World latency/memory gain.

The cell-use inspection also exposed missing body-slot reads in P03's existing
scope-control census. Handler/region bodies and cleanup computations now count as
uses; a reusable computation applied and then used as a handler body retains its
construction. This repairs the existing specialization guard without expanding
authoring scope.

`data.capture_reduction` removes dead copy/drop capture fields from a private
constructor and rewrites its ordered worker inputs, every construction operand
list and every direct worker call together. Explicit application arguments stay
unchanged. The original capture descriptor is retained for other constructors;
the reduced constructor receives a fresh descriptor before P01 removes or shares
unused structural records. All ownership/use flags and nominal region references
remain unchanged. The checker verifies original demand and complete raw-record
field/input/argument correspondence with fresh candidate admission.

The initial privacy domain requires one constructor per worker, no host/handler/
resource entry role, and each constructed closure slot used only by local applies,
without aliases. Repeated applications are supported. Opaque uses decline the
transformation. The existing exact slot-use scanner is now shared by P03 and P07,
including its scope-body/cleanup reads. Evaluations that produced removed captures
remain, including arithmetic failures. A known-branch witness keeps its capture
before pruning and removes it afterwards; the simple reused-closure image shrinks
115 to 109 bytes.

The source-free retained-state witness captures a 4096-byte array, pauses after
construction and resumes both versions with their own image identities. Dead
capture removal changes the closure environment from one value to zero, reachable
serialized blob payload from 4096 to zero bytes, and checkpoint size from 4207 to
105 bytes. These are measured logical retention/checkpoint costs, not allocator
high-water or latency measurements. A second native witness returns both results
from repeated closure calls with distinct arguments across three input triples.

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
The product suite adds seven cases (26 tests including imported module tests),
covering wrong-field mutations, overwritten inputs, aliases, escaped outputs,
invalid original annotations and allocation failures. Native coverage now has
seven application/link tests and one product/link test. The initial cross-object
fixture violated imported declaration structure; it was repaired to use a missing
entry and only the imported ABI slots, preserving production component admission.
P04 adds twelve focused cases (30 tests including module tests): local/join reuse,
operand writes and parallel swaps, non-dominance, self-overwritten producers,
early/late budget rollback, differing fault payloads, distinct closure captures,
mutable cell reads and allocation failures. Three native tests cover linked
diamond execution, path-specific mutation and a real cell read after mutation.
The cell suite has seven focused cases (25 with module tests), including a wrong
stored-value mutation, aliases, suspension, fault observation and allocation
failures. The scope-census regression expands the specialization suite to 48 tests.
One additional native linked-cell test covers three input pairs before/after.
The dead-capture suite adds eight cases (27 with module tests), including direct
callers, shared descriptors, opaque aliases, forged correspondence, original
failure evaluation and allocation failures. Two native tests cover retained-state
measurement/resumption and repeated-call outputs.

## Remaining M2 obligations

This is not complete M2 or canonical pipeline adoption. Remaining work includes:

- Remaining P02 domains, return summaries and richer recursive/calling contexts
  beyond the current conservative argument fixed point.
- Context cloning where callers disagree, capture projection/summaries and product forwarding
  across control flow; broader cell cases remain conservative.
  Private dead arguments, local product scalar replacement, singleton incoming-callable specialization
  and polymorphic/opaque negatives are implemented.
- Remaining P04 value numbering across aliases/renaming and cyclic proofs;
  P07 product-field projection and non-projection XOR summaries (dead captures are
  implemented), and the remaining qualification of P05/P08's
  implemented private-cell/store subset, with independent certificates.
- Semantic/structural contract integration into compilation and final linking,
  the owned-consumer policy audit, deterministic semantic work budgets, and
  automatic source-free closed-link adoption (explicit linked-record execution
  witnesses now pass).
- Cross-package qualification, paired economics against the retained C0 corpus,
  and all applicable G/T obligations. M2.5's affine synthesis remains subsequent.

Reproduction of the native record witness uses only Boundary data and World:

```sh
zig test -O ReleaseSafe --dep boundary_data --dep world \
  -Mroot=test/v2/application_specialization.zig \
  -Mboundary_data=src/data/root.zig --dep boundary_data \
  -Mworld=/absolute/world/src/root.zig
```
