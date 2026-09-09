# Boundary Program Image v1

BPI1 is the canonical, target-neutral serialization of one Reified Program.
Executable truth is owned by
`src/image_v1.zig`, `src/image_emit_v1.zig`, and the conformance vectors.

The fixed header prefix is 76 bytes. It contains `ABL_BPI1`, image version 1,
the program-evaluator semantics version, flags, exact header and total lengths,
section count, `program_transition_digest`, and derived schema/evaluator
scratch maxima. A 240-byte directory follows, so the exact v1 header length is
316 bytes.

Exactly ten contiguous sections occur in this order:

1. roots
2. schemas
3. failures
4. constants
5. effects
6. values
7. functions
8. segments
9. constructors
10. entry transitions

Integers are little-endian; lengths are logical and exact; reserved bytes are
zero; there is no padding or trailing data. Schemas are structurally interned
in depth-first postorder. Constants are interned by schema and canonical bytes.
All program identities are dense semantic identities, not source ordinals.

Segment records have a 16-byte prefix and contain no metering word. Synthetic
caller-fuel suspensions are normalized to semantic edges; explicit authored
yields remain. Dead fields from the unreleased BEI1 draft were removed rather
than preserved as archaeology.

Evaluator semantics version 1 retains the original role-name lookup for
instruction failures. Version 2 uses the same BPI1 container and instruction
record layout, but permits each fallible instruction to append one canonical
`Failure` value operand per failure role. Each operand must name a canonical
constant definition and selects the exact authored failure returned by that
instruction. Images without reachable authored-failure operands remain version
1, so all existing canonical BPI1 bytes are unchanged.

Evaluator semantics version 3 retains version-2 failure operands and admits
wire operations 58 and 59: `text_byte_at` and `bytes_byte_at`. They project one
byte from validated Text UTF-8 or arbitrary canonical Bytes and fail through
`invalid_index`. The compiler emits version 3 only when either operation is
reachable, and validators reject them under earlier evaluator versions or a
version-3 image that does not use one.

Validation checks the complete structure, dynamic values, graph references,
constructor laws, effect/schema/program-transition digests, scratch requirements,
and exact canonical re-encoding before execution. Image validity never grants
effect authority.

BPI1 contains no Machine ABI, State-format binding, Machine contract digest,
fuel law, segment cost, frame limit, State-byte limit, or lifetime budget.
