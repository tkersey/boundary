# Compositional execution: implementation status

This is an incomplete Boundary 3 / World 6 implementation milestone. The accepted
September 16, 2026 specification remains the completion contract, including Agent
migration, measured performance, legacy retirement, linked draft PRs and serial
review closeout. Nothing has been merged or released.

The dedicated `feat/compositional-execution` worktrees start at Boundary
`42a09b92c2870ab3eab923fe68ca2645eb710000`, World
`d075169a4805d999ceba4c37b3e1c925b78c3bf9`, and Agent
`1f3297b8cd7eeb7638bd1bb2a81c9ba609e2e311`. Remote heads were fetched and matched
these inputs. Toolchains are Zig 0.16.0 and Node 26.8.2.

## Stable activation construction

`data/activation.zig` represents function-local slots, ordered call inputs,
instruction destinations, and changed-only continuation assignments. It has no
block parameter catalogs or pass-through argument vectors. Destinations obtain
their types from the function layout. Branch assignments have simultaneous
predecessor-view semantics; runtime execution of that contract remains pending.

`source/activation_lower.zig` lowers staged terms directly into those records.
It does not call the predecessor compiler or translate an old Program. Real
function arguments and lexical closure captures remain explicit. A persistent
indexed lexical scope avoids copying live environments or searching binding
history. Its search path is bounded by the number of source variable names.
Safe expression sharing reuses the existing source rules; operations with
observable effects and noncopyable results do not acquire new sharing rights.
The returned construction owns copied result records; source AST and analysis
scratch are released before return. Allocation failures destroy partial results.

The representation decision retains Boundary's static contract and World's
dynamic activation ownership. Wire compression alone does not eliminate the
incumbent's repeated interfaces. A mutable whole-function frame would not satisfy
retained-version isolation or dead-value reclamation; the static layout does not
authorize retaining all its slots. The runtime must implement delimited views.

`data/activation_structure.zig` checks slot references, unique destinations,
function-local edges and result-site types. It deliberately grants no trusted
executable status: initialization, use/ownership, effects, region flow, complete
instruction checking and canonical admission are still required. In particular,
a successor handler's answer is distinct from the captured resumption's answer.

## Evidence and limits

Run from this worktree with an isolated global cache:

```sh
zig build check-stable-lowering check-v2-data check-v2-authoring \
  --global-cache-dir .zig-global-cache --summary all
zig build check-stable-lowering check-v2-data check-v2-authoring \
  -Doptimize=ReleaseSafe --global-cache-dir .zig-global-cache --summary all
```

The installation test uses the unchanged public construction at 1/8/64/128/256.
For `n` installations its entry function has `4n+1` slots, `3n+1` instructions,
`2n+1` blocks and exactly `n` returned-value assignments. All checked additions
remain in the final result block, after all handlers. There is no unchanged-value
edge assignment. These are target construction counts, not full compiler or
runtime performance results. The source checker still materializes flat
free-variable sets; its compact-analysis migration is unresolved.

Construction and structure checks cover 36 existing generalized-effect examples,
heterogeneous join destinations, shadowed names, expression DAG sharing, malformed
slot/edge references, permutations, repeated copyable inputs, answer transformation,
source-owner release and allocation-failure sweeps. The existing data/authoring
expectations remain enabled. These checks do not establish behavior under World.

## Remaining work

The next implementation seam is compact initialization/liveness/ownership analysis
and disposition insertion, followed by integration into World's evaluator and
activation store. The M1 runtime slice must include non-tail handling, an external
request, a join, escaping one-shot control, retained loop versions and reentrant
multi-shot behavior before the main migration is accepted.

BPI3/PST3/current protocols, independently checked BMO1 linking, selective execution,
efficient values, prepared/resident transactions, browser byte embedding, Agent's
complete migration and compiled-tool transfer, performance comparisons, retirement,
package validation and publication/review closeout remain mandatory. The current
public compiler/runtime still use the predecessor. The internal construction is
not a second supported production pipeline or a completed successor.
