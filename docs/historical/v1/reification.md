# Boundary Reification v1

Boundary 1.6 reifies the defunctionalized computation independently of bounded
execution policy.

```text
source -> normalized Control IR -> semantic RNF -> Reified Program -> BPI1
                                              |                     |
                                              + MachineV2Profile    + MachineV2Profile
                                              v                     v
                                           direct v2             kernel v2
```

`BPI1(P)` is byte-identical under every MachineV2Profile. It contains static
reducer clauses and semantic RNF data, never fuel, Machine limits, ABI identity,
or a persisted instruction cursor. The profile owns the exact legacy metering,
checkpointing, Machine contract, and `ABL_RNF2` envelope.
Machine-v2 binding reconstructs the legacy v2 semantic digest from BPI1 and the
profile-owned deltas; profile bytes cannot alter metering while retaining the
same State or Request identity. The structural profile parser is internal;
public callers authenticate image and profile together through
`boundary.machine_v2.kernel.bindMachineV2`.
Valid images describe effects but grant no authority; the kernel returns a
typed request and stops.

The byte-level BPI1 clause evaluator remains internal. The public Process ABI
admits canonical bytes and exposes one finite reduction through a generated
`boundary.process_v1.CapacityStorage(...).advance` method and the fixed
import-free Process kernel. The bounded Machine ABI v2 path remains
compatibility and specialization.

The v2 compatibility claim is transition equivalence: outcome tag, caller fuel, State,
request identity and payload, result, failure, and operational rejection must
agree at every boundary. Run `zig build check-boundary-reification-receipt` for
the aggregate executable proof.
That Boundary-local receipt reports only Boundary-owned observations. World and
Agent compatibility remains proven in their owning repositories rather than
being asserted without a downstream witness in Boundary's artifact.

Debug names and source locations are not semantic image data. Boundary adds no
runtime definition loader, callback registry, source interpreter, or automatic
State migration mechanism. Process ABI v1 performs one finite reduction per
call without a predetermined semantic lifetime budget.
