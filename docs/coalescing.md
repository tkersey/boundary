# Whole-program coalescing — implementation evidence

Status: in progress; no compiler or linker behavior has changed. The shipping
path still performs no global code coalescing. This is not a qualification report.

The accepted source is the September 25, 2026 version 2.0 specification supplied
with this task (attachment `76f1c36f-9372-40cc-9466-f61061359f29/pasted-text-1.txt`).
All T01–T42 and promotion gates remain required. A finite graph test does not
prove the raw-record transformation, admission precision, or World execution.

## Starting tuple

Remote `main` identities were checked before implementation:

| Repository | Commit |
| --- | --- |
| Boundary | `f512dbbfb14ab61ed5e1d875518c2b683ff5d215` |
| Agent | `7b3215cecabd93e7b8d4c547f6c3948a838cf3f5` |
| World | `c20695e00056186a4b74564da6e4ca1c368cb33b` |

Agent's current lock selects those exact Boundary and World commits. Its expected
WASM SHA-256 is `7d31effb1d4e32523d0fcbd5b4d5f5a8a2289fbd4c731173a33b1c174524282f`.
This is a lock observation, not a new artifact authentication result.
Toolchain: Zig 0.16.0, Darwin arm64. Source moved from `src/v2` into `src`
after the specification's inspected revision. The current authored-handler
API additionally exposes the existing cleanup-obligation bound.

Unchanged Boundary `zig build check -Doptimize=ReleaseSafe` passed in the
isolated worktree before implementation. This includes current authoring,
pure-data, components, independent source-oracle, and codec checks; it does
not stand in for the new optimizer's runtime matrix.

The exact Python appendix, executed with `uv run python3` and assertions enabled,
reproduced 4,330 exhaustive graphs, 500 seeded graphs, and 11 adversarial assertions.
Unchanged Agent `zig build check-agent4 -Doptimize=ReleaseSafe` also passed.

## Identity audit in progress

| Identity | Current owning use | Required treatment / outstanding proof |
| --- | --- | --- |
| Effect | `program.Effect`, effect handling and ordered use-site evidence | Fixed nominal anchor; only already-resolved component bindings identify declarations. |
| Region | schemas, protection, runtime region descriptor and dynamic installation | Injective static relocation; preserve distinct dynamic region nodes. |
| Resource | `resource_admission.zig` authority membership, representation schemas | Injective relocation; every live introducer/eliminator function is singleton. |
| Entry function | roots and invocation interface | Singleton. |
| Function | call target, layout and custody; borrow queries indexed by entry block | Whole-body correspondence, fresh admission; prove caller/provenance precision. |
| Function equality | World `stable_session.zig:executeControl` self-tail restart | Sharing can expose the existing self-tail fast path. Check logical boundaries, state correspondence and capacity behavior; do not infer cost equivalence. |
| Block | function ownership, CFG, live-slot facts, saved controls | Total local correspondence; fresh facts; no within-function tail merging. |
| Slot / custody | activation layout, simultaneous assignments, custody parent tree | Function-local bijections, never catalogue relocation. |
| Constructor | closure descriptor and `borrow_flow.Step.environment` selector | Ordered capture contract and code correspondence; caller/provenance witness required. |
| Handler | installed description, `borrow_flow.Step.handler_state` selector | Full mode/strategy/contract comparison; distinct installations stay distinct. |
| Capture | immutable layout; source diagnostics and original capture observers | Share descriptions only; retain original occurrence evidence and accurate aliases. |
| Schema | exact type contracts, state admission, callable dispatch filtering | Reuse linker partition semantics; nominal anchors and ordered variants preserved. |
| Literal | schema plus immutable bytes | Exact schema class and payload equality. |
| Runtime node | World store, frames, cells, environments, resumptions, custody | No optimizer map; preserve allocations and original alias/separation relations. |
| Image / checkpoint | BPI3 identity, PST3 and authenticated request envelope | New image identity; no checkpoint or reply transplantation. |

`borrow_flow.zig` filters constructor projections by exact constructor identity
and handler-state projections by exact handler identity. Merely proving equal
runtime bodies does not discharge the valid-input preservation requirement.
Original component borrow contracts are checked in `linker.checkBorrows` before
the existing reachable projection; that ordering must remain intact.

The audit is not yet exhaustive. No new identity exclusions or equivalence claims
are authorized merely by the table. Remaining work includes the complete opcode
argument, full checker mutation matrix, discovery views, live-image opportunity census,
selection, integration, all execution witnesses, and the measurement protocol.

## Discovery foundation

`coalescing_graph.zig` performs split-only refinement over exact typed keys.
Keys include length-delimited labels/anchors, edge roles and target kinds,
previous classes, and singleton pins. Exact lexicographic sorting is used;
there are no fingerprints whose collisions can authorize equivalence.
Equal keys choose the lowest original node index. Profile singleton restrictions
participate from the initial partition and propagate through predecessor edges.

Every changed refinement after local grouping splits a finite class. There are
at most as many such splits as nodes. No host recursion unfolds graph cycles.
Per-round keys are temporary; only the caller-owned representative array escapes.
The work counter charges node/edge visits, key bytes and conservative exact-sort
comparison byte bounds. Exhaustion returns `WorkLimit`, never a partial map.
The final optimizer must use that error to restore its original baseline across
all extraction rounds; this engine alone does not implement that transaction.

The independent Zig pair-deletion oracle covers the same exhaustive unary graph
domain as the appendix and 500 additional deterministic typed graphs. Its random
sequence is Zig's PRNG, not a claim to duplicate Python's random corpus.
Tests also cover quotient idempotence, recursive sharing, restricted profiles,
allocation failures, malformed references and work exhaustion.

## Raw-record validator foundation

`coalescing_witness.zig` checks map domains and candidate provenance, idempotent
representatives, injective nominal mappings, live resource/entry pins, profile
restrictions, and local slot/custody/block bijections. It retains the
representative's physical slot/custody layout. These checks alone are expressly
not record equivalence.

`coalescing_validation.zig` independently reads the original and actual candidate
records. It neither imports discovery nor calls the relocation rewriter. It
checks roots, all catalogues, schemas, function interfaces, slot schemas, custody
ancestry, instructions, failure tables and every control payload under the maps.
Explicit field inventories and exhaustive opcode/union switches fail compilation
when a record gains an unclassified field or operation. Ordered vectors preserve
order and multiplicity; only declared sets are sorted/deduplicated under mapping.
The validator borrows inputs only during the call and releases its scratch.

The initial negative test independently admits both a return-41 program and its
return-42 mutant, then requires correspondence rejection. Further tests cover
forged maps, changed continuation edges, authority merges, profile restrictions,
and allocation failures. No claim of complete T35/T36 coverage is made yet.
The checker is not yet called by production compilation/linking.

The existing linker's schema partition was moved unchanged into
`schema_partition.zig`; both paths will reuse this implementation. The linker
still performs its original interface/borrow checks and closed projection.

## Foundation verification

The current foundation passed:

- `zig build check -Doptimize=ReleaseSafe` (before final formatting only).
- `zig build check-data -Doptimize=Debug`.
- `zig build check-data -Doptimize=ReleaseSafe`.
- `zig build check-data -Doptimize=ReleaseFast`.
- `zig build check-components -Doptimize=ReleaseSafe`.
- `zig fmt --check` for changed Zig files and `git diff --check`.

The data checks were rerun after final formatting. The component witness retains
object lengths 160/375/612/195 bytes and linked lengths 811/842 bytes. The path
registry contains every new Zig file, and both test files are in the data aggregate.
No existing tests or assertions were removed or weakened.

These results establish only this foundation. Outstanding implementation includes
canonical function comparison views (including unused local layouts), the real
workload census, quotient construction through typed relocation, exact BPI3 cost
selection to a fixed point, original-to-final diagnostics, production invocation
of the validator, source/link/typed-authoring options, Agent propagation, and the
full acceptance and measurement matrices. Neither promotion nor delivery is complete.
