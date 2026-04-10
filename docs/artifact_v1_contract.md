# ArtifactV1 Contract

## Status

ArtifactV1 is the internal binary contract for the agent-VM campaign.
It is the design input for `st-505`, `st-506`, `st-510`, and `st-511`.

ArtifactV1 is intentionally not the current `ProgramPlan` JSON surface and not
the current durable sidecar format in `src/durable.zig`.
Those remain implementation scaffolding and replay artifacts.
ArtifactV1 v1 is intentionally tool-only; model and durable capability kinds
are reserved for a later revision.

## Goals

- exact bytes with no host-layout dependence
- deterministic encode, decode, and disasm
- canonical hashing over the emitted bytes
- explicit build and capability identity for exact-build rejection
- reserved space for future bundle, signature, and lineage work

## Non-Goals

- session bundles
- signatures
- source maps
- self-rewrite lineage payloads
- async host effects
- direct reuse of the current durable JSON schema

## Binary Layout

ArtifactV1 is one little-endian binary file with this top-level layout:

1. fixed-size header
2. section directory
3. section payloads

The wire format never depends on Zig struct layout, pointer width, enum layout,
or allocator-specific packing.

### Header

The header is exactly 72 bytes.

| Field | Type | Meaning |
| --- | --- | --- |
| `magic` | `[8]u8` | ASCII `SFTARTV1` |
| `header_len` | `u16` | must be `72` |
| `format_version` | `u16` | must be `1` |
| `directory_offset` | `u64` | byte offset of the first directory entry |
| `directory_count` | `u16` | number of section directory entries |
| `entry_function_index` | `u16` | entry function in the function table |
| `semantic_ir_hash64` | `u64` | carried forward from `ProgramPlan.ir_hash` |
| `hash_kind` | `u8` | `1 == blake3_256` |
| `flags` | `u8` | must be `0` in v1 |
| `reserved0` | `[6]u8` | zero |
| `artifact_hash_blake3_256` | `[32]u8` | canonical artifact hash, zeroed during hashing |

If any reserved byte is non-zero, decode fails closed.

### Section Directory Entry

Each directory entry is exactly 32 bytes.

| Field | Type | Meaning |
| --- | --- | --- |
| `section_id` | `u16` | stable section kind id |
| `flags` | `u16` | bit 0 = optional, all other bits zero in v1 |
| `reserved0` | `u32` | zero |
| `offset` | `u64` | byte offset of the section payload |
| `size` | `u64` | byte length of the section payload |
| `entry_count` | `u32` | logical row count for table-like sections |
| `reserved1` | `u32` | zero |

Directory entries must be sorted by `section_id` ascending.
Overlapping sections, duplicate section ids, out-of-bounds offsets, or unknown
required sections fail decode.

## Required Sections

ArtifactV1 requires these sections:

| Section Id | Name | Notes |
| --- | --- | --- |
| `0x0001` | `capability_manifest` | exact-build identity plus declared host capabilities |
| `0x0002` | `string_table` | UTF-8 storage for all labels and ids |
| `0x0003` | `requirement_table` | lowered requirement descriptors |
| `0x0004` | `op_table` | lowered op descriptors |
| `0x0005` | `output_table` | lowered output descriptors |
| `0x0006` | `local_table` | lowered local descriptors |
| `0x0007` | `call_arg_table` | helper call argument indexes |
| `0x0008` | `function_table` | lowered function descriptors |
| `0x0009` | `block_table` | lowered block descriptors |
| `0x000a` | `terminator_table` | lowered terminators |
| `0x000b` | `instruction_table` | lowered instructions |

This preserves the executable-plan semantics from
`src/internal/program_plan.zig` without promoting that JSON format unchanged.

## Requirement Table

Each requirement row is exactly 16 bytes:

- `label: StringRef`
- `first_op: u16`
- `op_count: u16`
- `capability_id: u16`
- `reserved0: u16` zero

`capability_id` links each lowered requirement to the declared capability row in
the manifest so runtime dispatch does not depend on manifest row order.

## Canonical Encoding

ArtifactV1 uses these encoding rules:

- all integers are fixed-width little-endian values
- all enums are explicit `u8` tags
- all booleans are `u8` with values `0` or `1`
- all strings are UTF-8 and NUL-free
- every string reference is `StringRef { offset: u32, len: u32 }` into the
  string table
- the string table stores each distinct byte sequence once
- row order is semantic and must match compiler emission order exactly
- all reserved bytes are zero
- any unknown enum tag fails decode

The current executable-plan fields carried into ArtifactV1 are the current
function, requirement, op, output, local, block, terminator, instruction, and
call-argument tables from `src/internal/program_plan.zig`.

The op table also carries one `has_after` flag so explicit manifests and
default capability derivation can preserve the presence or absence of authored
post-resume hooks without guessing from codec shape alone.

Declared output values are not stored in `output_table`; hosts surface those at
execution completion through `HostAdapterV1.collectOutputsFn`.

Instruction string literals are stored in the string table and referenced by
`StringRef`; they are not inline variable-length blobs.

## Capability Manifest

The capability manifest is what makes ArtifactV1 more than a plan dump.
It binds the executable artifact to exact-build identity and to the external
tool capabilities that `HostAdapterV1` must implement in v1.

The manifest begins with:

| Field | Type | Meaning |
| --- | --- | --- |
| `manifest_version` | `u16` | must be `1` |
| `reserved0` | `u16` | zero |
| `build_fingerprint_blake3_256` | `[32]u8` | exact-build identity |
| `capability_count` | `u16` | number of capability rows |
| `op_count` | `u16` | number of capability-op rows |
| `reserved1` | `[12]u8` | zero |

Each capability row has:

- `capability_id: u16`
- `kind: u8` where `2=tool` and all other values are reserved in v1
- `flags: u8` where bit 0 means required
- `label: StringRef`
- `first_op: u16`
- `op_count: u16`

In v1 every capability row must set the required bit. Optional tool
capabilities are reserved for a later revision.

Each capability-op row has:

- `capability_id: u16`
- `op_id: u16`
- `global_op_name: StringRef`
- `payload_codec: u8`
- `result_codec: u8`
- `plan_op_ordinal: u16`

`result_codec` follows the resume path for `transform` and `choice` ops.
For `abort` ops it follows the terminal function value codec.
When a `choice` op returns early with `return_now`, the terminal payload must
still satisfy the owning function value codec even though the manifest row
stores the resume codec.

Capability codec tags are:

- `1 = unit`
- `2 = bool`
- `3 = i32`
- `4 = string`
- `5 = bytes`
- `6 = data_value`
- `7 = usize`

`usize` is the precise manifest codec for `ValueCodec.usize`.
Hosts must not treat `usize`-typed ops as generic `data_value` rows.

Capability-op rows use these global ids in v1:

- `tool.call`
  - the primary lowered host-effect dispatch for one requirement op
- `tool.after`
  - an optional post-resume dispatch for one lowered `transform` or `choice` op
  - payload and result codecs must both equal the owning function answer codec
  - the runtime only invokes it while unwinding a resumed answer path

`plan_op_ordinal` links a capability op back to the lowered requirement-op slot so
runtime dispatch does not depend on capability-op row order.
`tool.call` and `tool.after` may legitimately share the same `plan_op_ordinal`;
duplicates are only invalid when both `global_op_name` and `plan_op_ordinal`
match.

Default capability derivation must only emit `tool.after` for lowered ops whose
op-table metadata explicitly marks an authored after hook.

`build_fingerprint_blake3_256` is not the same thing as
`artifact_hash_blake3_256`.
The artifact hash changes on any byte-level drift.
The build fingerprint changes when the exact compiler/build surface changes in a
way that should reject same-build handoff.

## Canonical Hashing

ArtifactV1 exposes two hashes:

- `semantic_ir_hash64`
  - copied from the current executable-plan `ir_hash`
  - stable across equivalent binary re-encodings
- `artifact_hash_blake3_256`
  - Blake3-256 over the complete artifact bytes with the header hash field
    zeroed during hashing
  - changes on any byte-level artifact drift

Hashing rules:

- the header is included in the Blake3 input
- the `artifact_hash_blake3_256` field is treated as 32 zero bytes while
  hashing
- reserved bytes must remain zero before hashing
- two encoders that produce the same semantic artifact must emit identical
  bytes and therefore identical artifact hashes

## Reserved Versioning Space

ArtifactV1 reserves these section-id ranges for later work:

- `0x1000` through `0x10ff`
  - bundle and session packaging
- `0x1100` through `0x11ff`
  - signatures and attestation metadata
- `0x1200` through `0x12ff`
  - self-rewrite lineage and source provenance

Optional sections may only appear in the reserved ranges above.
Unknown required sections fail decode in v1.

## Readability Requirements

`st-505` must ship readable decode and disasm tooling over this contract.
That tooling must:

- print header fields in a stable order
- print section ids and sizes
- reconstruct labels and global op ids through the string table
- print function, requirement, op, block, terminator, and instruction tables
  without relying on host struct layouts

The textual disasm is an operator aid only.
It is not part of the canonical artifact hash.
