# BPC1: packed canonical program images

BPC1 stores the existing canonical profile-1 Program. It preserves every
logical field, ordered occurrence and `boundary.program-image/v2` identity.
Execution, PST2 and the external protocols retain their existing meanings.
This document describes the implementation on `perf/compact-program-images`;
the paired implementation is still undergoing performance and integration checks.

## Public codec

`boundary_data_v2.compact_image` exports `encodedLength(allocator, program)`,
`encode(allocator, program, output)` and `decode(allocator, bytes)`.
The first two operate on canonical records, including hand-authored records.
Sizing grants no admission; `encode` always checks the current records before
writing, including after a caller changes them between sizing and encoding.
They select BPC1 only when its complete size is strictly smaller than
BPI2; otherwise they use the exact existing BPI2 encoding. Ties select BPI2.
`decode` accepts either selected format and returns the existing `image.Decoded`
owner. Its `deinit` releases all decoded records and backing bytes.

Existing `Compiled.encode`, `image.encode`, `image.encodedLength` and
`image.identity` retain their contracts. The explicit legacy decoder retains
its old format domain. World recognizes BPC1 on its existing `.image` path.
An old kernel rejects BPC1; compact production requires an upgraded kernel.

The [executable example](../examples/compact_image.zig) changes the final codec
call after ordinary compilation. Run `zig build emit-compact-image
-Doptimize=ReleaseSafe` to emit it. `build-compact-image` builds a pure-data
stdin/stdout converter, and `build-compact-image-report` builds byte attribution.

## Framing

| Offset | Width | Value |
| --- | --- | --- |
| 0 | 8 bytes | ASCII `ABL_BPC1` |
| 8 | 2 bytes | unsigned little-endian container version `1` |
| 10 | 2 bytes | unsigned little-endian reserved flags `0` |
| 12 | 8 bytes | unsigned little-endian exact body byte length |
| 20 | declared length | body |

There is no alignment or padding. Extra bytes, nonzero flags and unsupported
versions reject. A recognized malformed BPC1 image never falls back to BPI2.

The body contains a natural-number parameter-backing count, that many **schema
ID sequences**, then the nine logical catalogs in Program declaration order:
roots, schemas, constants, effects, functions, blocks, handlers, scopes and
constructors. BPC1 has no section directory or stored identity claim.

## Record grammar

Except for sequences, block parameter references, literals and instructions below, use
the logical record grammar and declared tag values in [BPI2](bpi2-wire.md).
Struct fields retain their declaration order; unions contain their declared
natural-number tag followed by that case's payload. Booleans and optional
presence markers are exactly byte `0` or `1`. Unsigned integers use minimal
unsigned LEB128, at most ten bytes for `u64`; overlong and overflowing encodings
reject. Fixed byte arrays are raw bytes. Byte slices contain a natural byte
length followed by exactly those bytes. Other ordinary slices contain a
natural element count followed by records in order.

The schema/reference meaning comes from the owning field. Instruction operands,
schema IDs, function IDs, region IDs, capture bounds, byte strings and returned
arguments retain their separate meanings and admission rules.

### ID and continuation-argument sequences

A sequence starts with its natural logical element count `n`.

* `n = 0`: no further bytes.
* `n = 1` or `2`: exactly `n` literal elements, with no mode byte.
* `n > 2`: one mode byte followed by the selected spelling.

Mode `0` contains `n` literal elements. Mode `1` contains segments, ending when
their positive counts sum to exactly `n`. Each segment is a mode byte, a natural
positive count, and a payload:

| Segment | Mode | Payload and interpretation |
| --- | --- | --- |
| literal | 0 | `count` literal elements |
| repeat | 1 | one element, repeated `count` times |
| ascending range | 2 | one starting element; ordinal increases by one each time |

An ID element is one natural `u64`. An argument element is its existing tag:
`0` followed by a slot ID, or `1` for the returned value. An argument range must
start with a **slot**, never a returned marker. Range endpoints must fit `u64`.
There is no wrapping, implicit sorting or interchange of argument kinds.

Unknown modes, zero-length segments and segment totals above `n` reject.
Segments are flat; there is no recursive expansion or sequence-node graph.

### Shared block parameters

Only `Block.parameters` may additionally use sequence mode `2` (prefix) or `3`
(suffix). Its payload is a natural index into the preceding schema-ID backing
table. It denotes exactly the first or last `n` IDs of that backing, retaining
their original order. The index must exist and its length must be
at least `n`. Backings themselves use only the literal/segmented sequence
grammar above, so forward references and cycles cannot be expressed.
Every backing element must name an existing schema. Each backing must have at
least one full-length block-parameter reference; unused backings and unused tails
reject. This is a local ownership/work bound, not a minimum-compression check.

Each backing is materialized once. Referencing blocks borrow immutable prefix/suffix
slices from it. A block's original parameter order and count remain unchanged.
Logical recursive code and schema references remain supported.

### Constant payloads

A Literal contains its schema ID, natural byte length, and payload. If the
length is exactly eight, one mode byte precedes the payload: `0` stores eight
raw bytes; `1` stores their unsigned little-endian bit pattern as a minimal
natural number. Mode `1` reconstructs exactly eight little-endian bytes in
owned storage. Other lengths have no mode byte and store the raw payload.
Unknown modes reject. This preserves the byte string independently of its
schema; normal scalar/schema admission still applies. The writer chooses mode
`1` only if the natural number uses fewer than eight bytes. Ties remain raw.

### Instructions

An instruction begins with a minimal natural header in `0..255`. Bits `0..5`
contain the existing opcode; unused opcode values reject. Bit `6` indicates a
stored immediate, and bit `7` indicates stored failures. The remaining fields
are result schema ID, operand sequence, optional immediate, and optional
failure-record slice, in that order. An absent immediate reconstructs exactly
zero; absent failures reconstruct exactly an empty slice. Other original values
are always retained. No instruction occurrence is merged or removed.

## Deterministic writer policy

The writer compares complete byte costs, including tags and counts. For a
sequence it scans maximal equal/ascending runs, selects economical runs, and
groups intervening values as literals. It chooses the segmented spelling only
when smaller than the literal spelling; ties remain literal. It does not solve
a global partition problem.

Two block-parameter plans are considered: numeric lexicographic order for
prefixes and reversed numeric lexicographic order for suffixes, each breaking
ties by original block index. Adjacent matching chains nominate their longest
sequence as a backing. A backing is retained only when the exact savings of its
economical references exceed its encoding and any increase in pool-count
width and the longest vector itself has a profitable full-length reference.
Unprofitable references retain their ordinary spelling. The plan with the
smaller complete dictionary/reference cost wins; ties select prefixes. If every
vector is constant, reversal leaves the candidate set identical and the second
sort is unnecessary. No hash-table
iteration, allocation address, runtime timing or program name affects output.

This policy examines the logical input and adjacent sorted candidates; it does
not compare each vector against every preceding vector. Only block parameters
share this dictionary. Literal operands and unrelated metadata remain available
without a dictionary requirement.

Multiple legal packed spellings may represent the same logical Program. The
decoder checks logical canonicality and format validity; it does not solve the
encoder's optimization problem. Re-encoding may choose another spelling.
Tests compare logical records, legacy bytes and identity, not an unsupported
claim of unique packed byte round trips.

## Ownership, capacity and admission

The decoder owns a copy of input bytes and all materialized records in its
returned arena. Raw payloads borrow that owned input; pooled parameters borrow
arena-owned backings. Admission scratch uses the caller allocator and is freed
before return. Overwriting or freeing the caller's input cannot invalidate the
decoded Program.

Counts and allocation-size arithmetic are checked. Literal counts are bounded
by available encoded bytes before allocation. Compressed sequences validate
their complete descriptors, segment totals and endpoints before allocation or
expansion. Pool references check indexes and lengths before creating views.
Allocator failure releases every partial owner and publishes no Program.
No semantic execution limit or enlarged default workspace is introduced.

Parsing traverses encoded records and flat descriptors. Materialization visits
the requested physical backing elements. Canonical admission and the unchanged
streaming legacy hash still visit the expanded logical records; their work is
not bounded solely by compressed byte length. In particular, the preserved
legacy hash remains quadratic on growing installation interfaces.

Encoding completes admission, planning, exact sizing, capacity and source/output
overlap checks before writing caller output. Allocation, invalid-input and
undersized/overlapping-output failures leave that output unchanged. Operational
errors remain distinct from authored failures, and fresh invocation can retry
unchanged input with additional physical capacity.
