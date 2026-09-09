# Portable records, version 2, profile 1

This document specifies the candidate Boundary 2 wire records. Numeric tags below
are assigned explicitly in the data module; Zig memory layout is never encoded.
The implementation is `src/v2/data/`. This profile is still a development
candidate until the coordinated release freezes its conformance assets.

## Framing and primitive notation

Every top-level record has exactly this prefix:

```
magic[8] | record_version:u16LE=2 | flags:u16LE=0 | body_length:u64LE | body
```

The magic is one of `ABL_BPI2`, `ABL_PST2`, `ABL_PKI2`, `ABL_PKO2`,
`ABL_ERQ2`, `ABL_ERS2`. The length equals the remaining input length. Unknown
versions, nonzero flags, wrong families, padding, and trailing records reject.
Version 1 is an explicitly unsupported family at these entry points.

The record tables use these primitives:

| Notation | Bytes |
| --- | --- |
| `N` | Minimal unsigned LEB128, range 0 through 2^64−1; at most ten bytes. |
| `B` | `N(byte_length)` followed by exactly that many bytes. |
| `Text` | `B`, validated UTF-8, with no normalization or BOM removal. |
| `Bool` | Exactly one byte, 0 or 1. |
| `?T` | One byte 0 for absent; one byte 1 followed by `T` for present. |
| `[T]` | `N(element_count)` followed by each `T`, in order. |
| `Hash` | Exactly 32 bytes. |
| `(a:T, b:U)` | `T` followed by `U`; field names and padding are absent. |
| Tagged alternative | `N(tag)` followed by its listed fields. |

Counts and arithmetic are checked before platform-size conversion or allocation.
Unrepresentable lengths are malformed input, rather than requests for truncated
amounts of capacity. A field with a source-language default is still encoded.
Catalog IDs, slots, and ordinals all use `N`, but their meanings differ.
Caller-owned BPI2 and protocol encoders, and the raw framing helper, reject
overlap between borrowed input and the written output range before writing.
Snapshot and standalone-schema encoders first own their normalized records.

## Canonical external values

External values are schema directed, without repeated schema IDs:

| Schema | Value bytes |
| --- | --- |
| Unit | Empty. |
| Boolean | `Bool`. |
| Fixed-width integer | Its exact width in little endian; signed values use two's complement. |
| Bytes / text | `B` / `Text`. |
| Product | Field values concatenated in schema order. |
| Sum | `N(variant_index)` followed by that variant's value. |
| Seq / vector | `N(length)` followed by element values; vector length must not exceed its maximum. |
| Fixed array | Exactly the declared number of element values, without a count prefix. |
| Bounded bytes / text | The same bytes/text encoding, with encoded content length at most the schema maximum; text remains UTF-8. |
| Enumeration | A `u32LE` value belonging to the declared finite tag set. Empty enumerations admit no value. |

Ordinal alternatives can use a sum of Unit cases; `enumeration` preserves
explicit numeric tags and empty domains. An optional value is a sum of Unit and
the element schema, with indices 0 and 1. Recursive algebraic schemas use catalog
references; unguarded recursive size cycles are rejected. A dynamic Seq has no program-wide
semantic length limit. Internal schemas and any type containing one cannot cross
an external payload, result, error, or initial-argument boundary. InitialArgs is
the concatenation of the entry function's parameter values, in parameter order.

## BPI2 directory and catalogs

The BPI2 body begins with `N(9)` and nine entries
`(section:N, offset:N, length:N)`. IDs are exactly 1 through 9 in order. Offsets
are relative to the content immediately after the directory. The first offset
is zero; each next offset equals the preceding offset plus its length; the last
section ends at the end of the body. Each section is decoded to exact exhaustion.

| Section | Content |
| --- | --- |
| 1 | Roots `(profile:N=1, entry:FunctionID, result:SchemaID, failure:SchemaID)`. |
| 2 | `[Schema]`. |
| 3 | `[Literal]`, each `(schema:SchemaID, bytes:B)`. |
| 4 | `[Effect]`. |
| 5 | `[Function]`. |
| 6 | `[Block]`. |
| 7 | `[Handler]`. |
| 8 | Scope catalog `(captures:[Capture], region_count:N, resources:[Resource])`. |
| 9 | `[Constructor]`. |

Each catalog has zero-based IDs. Nominal region IDs range from zero to
`region_count−1`. No executable debug section is admitted.

`Use` tags are reusable=0, affine=1, linear=2, multi=3. `Mode` tags are deep=0,
shallow=1. These describe checked interfaces, not authority to assert
CopySafe, DropSafe, or CloneSafe: admission derives those properties and checks
all uses and captures.

Admission derives the borrow dependencies and lifetime requirements of code
inputs through calls, projections, stored values, and scoped control. A fresh
capability cannot leave its handler; suspension packages retain the enclosing
handler evidence and regions even when their explicit environments are empty.
Clause and return writes use the state of the selected attachment. These are
derived checks, with no additional wire fields or trusted source annotations.
Capabilities depend on evidence ancestry; regions, cells, and resource loans
depend on region ancestry. Suspensions retain both components. Calls and
use-site injection preserve the selected component of an implicit context.
An operation clause uses the context outside its selected delimiter: its own
capability cannot enter as payload, while an older live capability can.

### Schemas

| Tag | Schema | Fields |
| --- | --- | --- |
| 0 | unit | Empty. |
| 1 | boolean | Empty. |
| 2, 3, 4, 5 | i8, i16, i32, i64 | Empty. |
| 6, 7, 8, 9 | u8, u16, u32, u64 | Empty. |
| 10, 11 | bytes, text | Empty. |
| 12 | product | `fields:[SchemaID]`. |
| 13 | sum | `variants:[SchemaID]`; nonempty. |
| 14 | seq | `element:SchemaID`. |
| 15 | vector | `(element:SchemaID, maximum:N)`. |
| 16 | internal | `Internal`, below. |
| 17 | array | `(element:SchemaID, length:N)`; exact fixed length. |
| 18 | bounded_bytes | `maximum:N`, in bytes. |
| 19 | bounded_text | `maximum:N`, in UTF-8 bytes. |
| 20 | enumeration | `tags:[N]`, each at most `2^32-1`, strictly increasing. The list may be empty. |

| Internal tag | Name | Fields, in order |
| --- | --- | --- |
| 0 | computation | `parameters:[SchemaID], result:SchemaID, effects:[EffectID], capture_bound:[SchemaID], use:Use, regions:[RegionID]`. |
| 1 | capability | `effect:EffectID`. |
| 2 | cell | `element:SchemaID, region:RegionID`. |
| 3 | region | `region:RegionID`. |
| 4 | resumption | `effect:EffectID, input:SchemaID, answer:SchemaID, effects:[EffectID], capture_bound:[SchemaID], handled:[EffectID], escaping:[EffectID], mode:Mode, use:Use, owned_regions:[RegionID], obligations:Bool`. |
| 5 | suspension_package | `resumption:SchemaID`. |
| 6 | abstract_resource | `resource:ResourceID`. |
| 7 | borrowed | `value:SchemaID, region:RegionID`. |

`escaping` records effects of a shallow capture that can still select outside
attachments after successor installation. `obligations` is an upper bound
checked at protected call and capture edges. It does not authorize an exclusive
capture to become multi-shot.

### Code and interfaces

| Record | Fields, in order |
| --- | --- |
| Effect | `identity:Text, payload:SchemaID, result:SchemaID, use_site_effects:[EffectID], bodies:[SchemaID], control_use:Use, external:Bool`. |
| Function | `entry:BlockID, parameters:[SchemaID], result:SchemaID, effects:[EffectID], regions:[RegionID]`. |
| Block | `function:FunctionID, parameters:[SchemaID], instructions:[Instruction], terminator:Terminator`. |
| Instruction | `opcode:N, result_type:SchemaID, operands:[Slot], immediate:N, failures:[InstructionFailure]`. |
| InstructionFailure | `kind:N, value:ConstantID`; overflow=0, division-by-zero=1, capacity-exceeded=2, invalid-UTF8=3, invalid-index=4, invalid-variant=5. |
| Edge | `block:BlockID, arguments:[Argument]`. |
| Argument | slot=0 followed by `Slot`; returned=1 with no payload. |
| Clause | `effect:EffectID, function:FunctionID, resumption:SchemaID, direct:Bool`. |
| Handler | `mode:Mode, input:SchemaID, answer:SchemaID, return_function:FunctionID, clauses:[Clause], forward_function:?FunctionID, state:[SchemaID], effects:[EffectID]`. |
| Capture | `fields:[SchemaID], owned_regions:[RegionID], borrowed_regions:[RegionID], use:Use`. |
| Resource | `representation:SchemaID, introducers:[FunctionID], eliminators:[FunctionID]`. |
| Constructor | `function:FunctionID, capture:CaptureID, schema:SchemaID`. |

Within a block, parameter slots come first. Each instruction appends one result
slot. Operands refer only to already available slots. An Edge stays within its
function and supplies the target block's exact signature. `returned` is a typed
result hole and is allowed only where the terminator provides a result.

Effect rows (`effects` and `escaping`) and region-bound sets contain unique IDs
in increasing order. `Effect.use_site_effects`, `Resumption.handled`, and
`Handler.clauses` are ordered evidence lists: they contain unique effects but
their order is preserved because executable parameters align with that order.
Capture fields, state fields, product fields, parameters, and operands are also
ordered. Effect identities are nonempty UTF-8. Distinct nominal effects can use
the same text; text equality does not select an activation.

Every effect result (the value supplied on resumption) is first-order and
exportable. External payloads are also exportable; internal scoped operations
can carry their checked internal payloads and computation arguments.

### Instructions

Except where specified, `immediate` is zero. Failure entries are exactly the
required roles, in the order below, and name constants of the root failure
schema. Add/sub/mul require overflow. Div/rem require overflow then
division-by-zero; both reject signed minimum with divisor -1. Division truncates
toward zero and remainder has the dividend's sign. Integer conversion requires
overflow only when the source integer's range is not contained in the target's.

Checked variant projection requires invalid-variant. Sequence set requires
invalid-index. Bounded-vector append/concat require capacity-exceeded. Blob
concat requires capacity-exceeded; blob slice requires capacity-exceeded, then
invalid-UTF8 for a text result. Scalar-to-text requires invalid-UTF8. All other
instructions have no failure entries. Allocation failure is operational and
never substitutes for one of these authored failures.

| Opcode | Name | Operands / immediate / result |
| --- | --- | --- |
| 0 | constant | No operands; immediate is ConstantID; result has its schema. |
| 1 | move | One value of the result schema; ownership moves where required. |
| 2–5 | integer_add, integer_sub, integer_mul, integer_div | Two same-schema integers; same-schema result or authored failure. |
| 6 | equal | Two same-schema integers or Booleans; Boolean result. |
| 7 | less | Two same-schema integers; Boolean result. |
| 8 | boolean_not | One Boolean; Boolean result. |
| 9 | product | Ordered fields of the result product. |
| 10 | field | One product; immediate is field index. |
| 11 | variant | One payload; immediate is the result sum's variant index. |
| 12 | variant_tag | One sum; u64 variant index. |
| 13 | variant_payload | One sum; immediate selects a statically typed case. Return its payload or fail with invalid-variant. |
| 14 | sequence | Element operands; Seq, bounded vector, or fixed array result. An array requires exactly its declared number of operands. |
| 15 | sequence_length | One Seq/vector/array; u64 result, or u32 when a declared vector/array bound fits u32. |
| 16 | sequence_get | Seq/vector/array and u64 index; optional element result. |
| 17 | sequence_append | Seq/vector and element; same-schema result. A vector checks its capacity. |
| 18 | sequence_concat | Two same-schema Seq/vector values; same-schema result. A vector checks its capacity. |
| 19 | sequence_pop | Seq/vector; optional `(first element, remaining elements)` result. |
| 20 | computation | Capture fields; immediate is ConstructorID. |
| 21 | cell_new | Region capability and initial value; checked cell schema. |
| 22 | cell_get | Cell reference; element result, subject to use checking. |
| 23 | cell_set | Cell reference and replacement value; Unit result. |
| 24 | clone_resumption | Owned clone-safe resumption consumed into a multi template. |
| 25, 26 | package, unpack | Transfer between a one-shot resumption and its owned package. |
| 27, 28 | resource_pack, resource_unpack | Introduce/eliminate the declared representation, only in authorized functions. |
| 29 | integer_rem | Two same-schema integers; checked remainder. |
| 30 | integer_bit_not | One integer; complement within its fixed width. |
| 31–33 | integer_bit_and, integer_bit_or, integer_bit_xor | Two same-schema integers; bitwise result of that schema. |
| 34 | integer_convert | One integer; checked mathematical-value conversion into the result integer schema. |
| 35 | enum_tag | One enumeration; its explicit u32 tag. There is no inverse integer-to-enumeration operation. |
| 36 | blob_length | Bytes/text, bounded or unbounded; UTF-8 byte count as u64, or u32 when the declared bound fits. |
| 37 | blob_concat | Two bytes or two texts, possibly with different bounds; same-category result checked against its bound. |
| 38 | blob_slice | Bytes/text and u64 start/end byte offsets; half-open slice. Reject reversed/out-of-range offsets or excess result capacity before checking UTF-8. |
| 39 | blob_compare | Two bytes or two texts; unsigned bytewise lexicographic order as i8 -1, 0, or 1. |
| 40 | blob_byte | Bytes/text and u64 byte index; optional u8. |
| 41 | text_scalar | u32 Unicode scalar; unbounded Text containing its UTF-8 encoding. Surrogates and values above U+10FFFF fail. |
| 42 | text_integer | Any integer; unbounded Text containing its signed or unsigned decimal representation. |
| 43 | sequence_set | Seq/vector/array, u64 index, replacement element; same-schema result. Replaced elements must be DropSafe. |
| 44 | sequence_take | Seq/vector and u64 count; same-schema prefix, clamped to its length. Elements must be DropSafe. |
| 45 | blob_from_byte | One u8; unbounded Bytes containing exactly that byte. |
| 46 | sequence_pop_last | Seq/vector; `(remaining elements, optional last element)` product. Empty input returns empty and None. |
| 47 | select | Boolean and two same-schema alternatives; selected value. Alternatives must be DropSafe. |

### Terminators

Every field called a slot below is a block slot, even when its value is a
computation. In particular `body` and `cleanup` do not identify functions.

`Perform` is `(effect:EffectID, capability:?Slot, payload:Slot, bodies:[Slot],
use_site_capabilities:[Slot], next:Edge)`. An absent capability is valid only for
an external effect. A present capability selects a particular attachment.

| Tag | Name | Fields, in order |
| --- | --- | --- |
| 0 | return_value | `value:Slot`. |
| 1 | jump | `Edge`. |
| 2 | branch | `condition:Slot, when_true:Edge, when_false:Edge`. |
| 3 | switch_variant | `value:Slot, cases:[Edge]`. |
| 4 | unpack_product | `value:Slot, block:BlockID, arguments:[Slot]`. |
| 5 | call | `function:FunctionID, arguments:[Slot], next:Edge`. |
| 6 | perform | `Perform`. |
| 7 | yield_value | `next:Edge`. |
| 8 | fail | `value:Slot`. |
| 9 | apply | `computation:Slot, arguments:[Slot], next:Edge`. |
| 10 | handle | `handler:HandlerID, body:Slot, arguments:[Slot], state:[Slot], next:Edge`. |
| 11 | resume_value | `resumption:Slot, argument:Slot, next:Edge`. |
| 12 | resume_with | `resumption:Slot, argument:Slot, handler:HandlerID, state:[Slot], next:Edge`. |
| 13 | resume_computation | `resumption:Slot, computation:Slot, next:Edge`. |
| 14 | forward | `Perform`. |
| 15 | dispose | `owned:Slot, next:Edge`. |
| 16 | protect | `body:Slot, cleanup:Slot, arguments:[Slot], resource:?Slot, loan_region:?RegionID, next:Edge`. |
| 17 | with_region | `region:RegionID, body:Slot, arguments:[Slot], next:Edge`. |

### Program normalization and identity

Admission checks all input declarations before pruning unreachable ones.
Normalization follows the finite reference graph with iterative depth-first
first-visit numbering, independently for each catalog. Roots are visited in
order: entry function, result schema, failure schema. References within each
record are visited in the table's field order, and within ordered lists in list
order. Block instructions precede their terminator. Slots and variant ordinals
are not catalog references and are not renamed.

For unordered effect-row traversal, effects are visited in UTF-8 byte order of
their identity; equal identities retain the row's existing order. Emitted rows
are sorted by their new IDs. Region sets are emitted in increasing new-ID order.
Identical constants with the same schema ID and bytes are interned at first
encounter. Other distinct catalog records are preserved. This numbering does
not assert that distinct nominal declarations or all bisimilar target schemas
are interchangeable. Canonical image admission rejects unreferenced declarations,
duplicate internable constants, and any numbering requiring normalization.

Let `LP(x) = N(byte_length(x)) || x`, `H(x) = SHA-256(x)`, and `S_i` be the exact
canonical content bytes of section `i`. Program identity is:

```
H(UTF8("boundary.program-image/v2") || LP(N(profile)) ||
  LP(N(1)) || LP(S_1) || ... || LP(N(9)) || LP(S_9))
```

The directory and framing do not enter this preimage. Profile is intentionally
included both explicitly and in the roots section. `image.identity` takes
already admitted canonical records; `canonical.normalize` prepares native
records before identity derivation and execution. There is no program hash field
inside BPI2.

## PST2 logical State

The body is `(program_identity:Hash, status:N, roots:Roots, nodes:[Node],
blobs:[Blob])`. Status tags are active=0, yielded=1, parked=2, unwinding=3.
Roots fields are `(current:?NodeRef, evidence:?NodeRef, detached:[OwnedRef],
exit:?NodeRef, pending:?NodeRef)`.

`NodeRef` and `BlobRef` each encode one `N` ID. `OwnedRef` also encodes a node ID
but denotes custody. `Value` is `(schema:SchemaID, body:ValueBody)`.

| ValueBody tag | Fields |
| --- | --- |
| 0 scalar | Exactly eight bytes; unused bytes are zero; the schema determines scalar width. |
| 1 blob | BlobRef. |
| 2 reference | NodeRef, for copy-safe values. |
| 3 owned | OwnedRef, for exclusively owned values. |

A Blob is `(schema:SchemaID, bytes:B)` and contains a complete canonical
exportable nonscalar value. Pointer-bearing values use typed nodes, not blobs.
The following reusable records occur in Node alternatives:

| Record | Fields, in order |
| --- | --- |
| Control | `block:BlockID, arguments:[Value], parent:?NodeRef, evidence:?NodeRef, region:?NodeRef`. |
| Continuation | `source_block:BlockID, arguments:[?Value], parent:?NodeRef, evidence:?NodeRef, region:?NodeRef`. |
| CaptureState | `schema:SchemaID, capture:?NodeRef, delimiter:NodeRef, evidence:?NodeRef, use_site_capabilities:[Value]`. |
| Exit | `reason:ExitReason, cleanup_failures:[Value], cancellation:?Reason, stop:?NodeRef, outer:?NodeRef, discarded:[Value]`. |
| ExitReason | normal=0 plus Value; failure=1 plus Value; cancellation=2; abandoned=3. |

Continuation arguments contain only live edge arguments; absent values are
typed result holes. Its `source_block` identifies the terminator supplying that
edge. Exit `stop` is a borrowed destination; the unwind/cleanup position owns
the active frames.

A region-scope frame and its saved return continuation identify the same
`with_region` source block. State admission enforces this binding together with
the result type and outer region when checking the saved invocation's effects.

| Node tag | Name | Fields, in order |
| --- | --- | --- |
| 0 | control | Control. |
| 1 | continuation | Continuation. |
| 2 | handler | `definition:HandlerID, state:[Value], evidence:?NodeRef, region:?NodeRef`. |
| 3 | attachment | `handler:NodeRef, outer:?NodeRef, return_to:?NodeRef, phase:N, region:?NodeRef`; active=0, suspended=1. |
| 4 | environment | `values:[Value], tail:?NodeRef`. |
| 5 | aggregate | `schema:SchemaID, tag:N, fields:[Value]`. |
| 6 | region | `descriptor:RegionID, outer:?NodeRef, obligations:[OwnedRef]`. |
| 7 | region_scope | `source_block:BlockID, region:NodeRef, return_to:?NodeRef`. |
| 8 | injection | `continuation:NodeRef`. |
| 9 | protection | `source_block:BlockID, obligation:OwnedRef, return_to:?NodeRef, evidence:?NodeRef, region:?NodeRef, loan:?NodeRef`. |
| 10 | cleanup_return | `obligation:OwnedRef, parent:?NodeRef, exit:NodeRef`. |
| 11 | disposal_return | `schema:SchemaID, parent:?NodeRef, values:[Value]`. |
| 12 | unwind | `cursor:?NodeRef, values:[Value]`. |
| 13 | cell | `schema:SchemaID, region:NodeRef, value:?Value`. |
| 14, 15 | one_shot, multi_template | CaptureState. |
| 16 | branch | `template:NodeRef, attachment:NodeRef, regions:[(source:NodeRef, target:NodeRef)]`. |
| 17 | package | `schema:SchemaID, continuation:Value`. |
| 18 | computation | `constructor:ConstructorID, environment:NodeRef`. |
| 19 | resource | `schema:SchemaID, value:Value`. |
| 20 | borrow | `schema:SchemaID, resource:NodeRef, region:NodeRef`. |
| 21 | obligation | `source_block:BlockID, cleanup:?Value, resource:?Value, status:ObligationStatus`. |
| 22 | pending | `effect:EffectID, payload:Value, continuation:NodeRef, source_block:BlockID`. |
| 23 | exit | Exit. |

ObligationStatus tags are pending=0, running=1 plus its continuation NodeRef,
completed=2, failed=3 plus its error Value. The pending node's `source_block`
is the operation's executable block, not a computation constructor ID.

Canonicalization performs iterative depth-first first-visit traversal of all
roots in their field order, then each node's fields and containers in table
order. A node gets its ID before children are visited, preserving cycles and
aliases. Different mutable nodes never merge. Blobs are interned by exact
`(schema ID, bytes)` and numbered at first encounter. Unreachable nodes/blobs,
alternate numbering, and duplicate blobs reject during canonical byte admission.
State has no self-hash, cached request, generation counter, or execution fuel.

`snapshot.decodeGraph` checks structural canonicality. Before execution, pure
`state_admission.validate` additionally checks the Program identity, all types,
capability attachments, regions, complete-graph ownership, clone restrictions,
cleanup states, and the single pending position. A graph checksum is never
evidence of those properties or of historical reachability.

Restored block arguments and saved continuations must also satisfy the code's
derived borrow requirements at their actual owners and outward return contexts.
Substituting a younger capability of the same effect family cannot grant it an
older lifetime. Projection through a helper result preserves field selection.

## Schema descriptors, ERQ2, and ERS2

A standalone exportable schema descriptor is **unframed**
`(root:N=0, types:[Schema])`, using the schema tags above. It contains only
reachable exportable types. Bisimilar recursive definitions are merged by
structural refinement, then numbered by depth-first first visit from root zero.
The decoder re-encodes this canonical result and requires byte equality.

ERQ2 fields are, in order:

```
program_identity:Hash
pending_state_digest:Hash
residual_contract_digest:Hash
continuation_binding_digest:Hash
semantic_identity:Text
payload_schema:B
resume_schema:B
payload:B
request_identity:Hash
```

The two schema fields contain complete standalone descriptors. Payload contains
one value of `payload_schema`. With the `LP` and `H` notation above:

```
P = canonical program identity
S = H(complete current PST2 bytes, including its frame)
R = H(resume_schema)
C = H(UTF8("boundary.residual-contract/v2") ||
      LP(semantic_identity) || LP(payload_schema) || LP(resume_schema))
K = H(UTF8("boundary.continuation-binding/v2") ||
      LP(P) || LP(S) || LP(N(pending.source_block)) || LP(R))
Q = H(UTF8("boundary.effect-request/v2") || LP(P) || LP(S) || LP(C) || LP(K) ||
      LP(semantic_identity) || LP(payload_schema) || LP(resume_schema) || LP(payload))
```

The ERQ2 hash fields contain `P, S, C, K, Q` in their corresponding positions.
Domain text is included directly, with no length prefix or terminating NUL.
An ERQ2 standalone validator checks C, Q, both descriptors, and payload typing.
Matching P, S, and K to executable State additionally requires that State and
Program; World constructs them from its admitted current pending position.

ERS2 is `(request_identity:Hash, resume_schema_digest:Hash, value:B)`.
Admission requires equality with Q and R of the current request, and a complete
canonical value of its resume schema. No coercion or effect-name lookup occurs.
The environmental truth of the supplied value remains outside this contract.

## PKI2, PKO2, cancellation, and capacity

PKI2 is `(mode:N, image:B, instance:Instance, control:Control)`. Modes are
advance=0 and run=1. Instance tags are initial_args=0 plus `B`, state=1 plus
`B` containing complete PST2. Control tags are continue_value=0 plus `?B`
containing an ERS2 when present, cancel=1 plus `Reason`. Reason tags are text=0
plus `Text`, bytes=1 plus `B`.

InitialArgs accepts neither a result nor cancellation. A result is accepted only
at its matching parked request. Result and cancellation are alternative control
constructors, so one record cannot contain both. Cancelling a body abandons its
pending request and unwinds obligations. Cancelling while cleanup is parked
preserves the cleanup position and payload. The first reason is retained; any
changed State produces a new S, K, and Q. An already obtained typed result can
be encoded against that successor ERQ2 without repeating the environmental
operation. The old ERS2 rejects. A preexisting primary failure wins over later
cancellation; cleanup continues outward and records failures in order.

PKO2 has these alternatives:

| Tag | Outcome | Fields, in order |
| --- | --- | --- |
| 0 | Progressed | `state:B`. |
| 1 | Requested | `state:B, request:B`. |
| 2 | Yielded | `state:B`. |
| 3 | Completed | `value:B`. |
| 4 | Failed | `value:B, cleanup_failures:B, cancellation:?Reason`. |
| 5 | Cancelled | `reason:Reason, cleanup_failures:B`. |
| 6 | NeedsCapacity | Capacity. |

State and request fields contain complete framed PST2 and ERQ2. Completed and
Failed values use the root result and failure schemas. The cleanup_failures
field contains the unframed encoding `[B]`, each element one root failure value;
an empty sequence is the single byte 0. It is a dynamically sized sequence.

Capacity is `(arena:N, input:Bound, working:Bound, output:Bound,
memory_pages:Bound)`, with arena tags input=0, working=1, output=2, memory=3.
Bound is `(amount:N, provenance:N)`, with not_observed=0, exact=1, lower_bound=2.
The first three amounts count bytes; memory_pages counts 65,536-byte WASM pages.
The Zig field named `bytes` holds that amount even in memory_pages. Unobserved
fields produced by World have amount zero. A lower bound must not be reported as
an exact successful-run requirement. Capacity reports do not contain successor
State. Retrying the unchanged input with sufficient storage must yield the same
logical outcome; storage profiles can produce different capacity observations.
