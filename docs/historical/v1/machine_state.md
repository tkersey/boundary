# Canonical Machine state

Machine ABI v2 uses `ABL_RNF2`, format version 1:

```text
magic                  8 bytes
format_version         u16 little-endian
machine_abi_version    u16 little-endian
machine_digest         32 bytes
sequence               u64 little-endian
cumulative_fuel        u64 little-endian
frame_count            u32 little-endian
flags                  u32 little-endian
```

Each frame contains:

```text
constructor_id         u32 little-endian
environment_length     u32 little-endian
environment_bytes      exact constructor schema
```

For a non-root constructor, that schema begins with compiler-generated
activation context: the call-entry constructor id and the typed invocation
arguments that were live at the callee entry. An immediate call-entry frame
omits those parameters from the future-live product, leaving one persisted
authority. A progressed loop may retain its distinct current value. Both
products are Machine-identity-bearing, bounded by the
constructor field ceiling, and encoded without source or interpreter cursors.

An await-effect constructor owns pending effect state; there is no independent
generic pending-instruction record.

Encoding stores logical lengths and live values only. It contains no pointers,
allocator capacities, padding, nominal type names, function/block/instruction
cursors, local-slot bitmaps, condition caches, or generic after stack.

The allocator-backed live state is a private ownership carrier, not a second
portable representation. Initial and decoded states allocate exactly the
logical typed frame count. A retained live state may preserve the bounded
high-water capacity it already reached, and candidate transitions clone that
private capacity while copying only logical frames. This prevents repeated
unwind/regrow histories from extending the predecessor allocation chain under
allocators that cannot resize in place. `maximum_frames` remains the admission
bound, and canonical state bytes still encode only logical frames.

Opaque prepared resumes may retain a private lease on the live state allocation
whose pending request they validated. `deinitState` marks that allocation for
release, but physical destruction waits for both terminal-result rendezvous and
all prepared-resume leases. Lease count and release state are private ownership
metadata: cloning resets them, and encoding never observes them.

Decode is fail-closed. It checks the exact Machine digest, versions, total
length, frame bounds, dense constructor schemas, portable-value bounds,
constructor-local invariants, stack compatibility, pending-request state, fuel
arithmetic, and trailing bytes. Sequence cannot exceed cumulative fuel, and a
parked request must have a nonzero sequence. Decode executes no effects or user
callbacks. Stack compatibility compares every waiting parent with the child's
preserved activation context; it does not replay the child's historical path.

The bytes are transferable bearer authority. Decode validates the current
cumulative counter against fixed bounds and local arithmetic relations; it does
not claim that an unsigned self-contained counter authenticates the history that
issued it. World and host persistence own branch-head retention, rollback, and
replay policy.

State bytes are compatible only when the Machine contract digest is identical.
There is no automatic migration from `ABL_STM1`.
