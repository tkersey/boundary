# Portable values

Boundary Machine values have explicit first-order, target-neutral semantics.

Supported scalars:

```text
void, bool
i8, i16, i32, i64
u8, u16, u32, u64
```

Supported algebraic values are structs, exhaustive enums, tagged unions,
optionals, and fixed arrays whose members are portable.

Bounded dynamic values are:

```zig
boundary.Bytes(MaxBytes)
boundary.Text(MaxBytes)
boundary.Vector(T, MaxItems)
```

Capacity is compile-time and contract-bearing. Canonical encoding stores only
logical length and live contents; spare storage and allocator identity are not
observable. Machine initialization and effect resumption recursively rebuild
typed values into that same canonical representation before the values enter
authoritative RNF state.

Zig makes the fields of inline by-value structs visible across modules. Those
fields are caller-owned source representation, not canonical Machine authority
or a supported semantic egress API. Callers can use them to construct malformed
test inputs, but portable observation, encoding, Machine initialization, and
effect resumption validate and canonicalize owned copies before accepting them.
Pointer addresses and spare capacity never participate in canonical equality,
encoding, state, or Machine identity. Vector exposes elements through canonical
by-value `get` and `pop`; it does not provide a borrowed arbitrary-element slice.
`Bytes.slice`, `Text.slice`, and every bounded `len` observer are fallible source
views: they reject an excessive logical length before returning a canonical-
looking value, and `Text.slice` also rejects invalid UTF-8. Unchecked logical
length and slice access remain private to validation-owning portable-value
internals.

Vector pop, truncate, and clear reset every vacated element to its canonical
default before returning. Bytes truncate and clear likewise zero every vacated
byte, including malformed-length repair, so logically removed data does not
remain observable through supported operations. Capacity overflow and invalid
UTF-8 fail before mutation. Zero-width Vector elements are a canonical quotient:
truncate, clear, encoding, and equality do not iterate over their logical length.

The source algebra includes deterministic fixed-width integer computation,
branching, product construction/extraction, vector construction and access, and
bounded text/byte construction. Text and Bytes expose canonical logical length,
copy, comparison, join, and append operations; Bytes also admits one-byte
scalar append, while Text admits Unicode-scalar and integer formatting.
Text additionally permits checked read-only projection of one byte from its
canonical UTF-8 payload; an out-of-range byte index is an authored failure.
Ordering returns an error for malformed logical lengths, and Text ordering
also rejects invalid UTF-8 before comparing bytes. Operations charge
deterministic fuel.

Unsupported values include `usize`, `isize`, raw pointers, arbitrary slices,
floats, function values, opaque host handles, non-exhaustive enums, comptime
fields, hash maps, unordered sets, unbounded collections, and identity-bearing
object graphs.
