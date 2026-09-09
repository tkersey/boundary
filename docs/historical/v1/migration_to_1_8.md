# Migration to Boundary 1.8

Boundary 1.8 adds two generic Control IR operations:

```text
text_byte_at(Text, u32) -> u8
bytes_byte_at(Bytes, u32) -> u8
```

The index addresses the value's canonical logical payload. `text_byte_at`
observes UTF-8 code units after Text validation; `bytes_byte_at` preserves
arbitrary bytes without text decoding. Out-of-range access uses the standard
`invalid_index` failure role, including authored Failure operands. Neither
operation exposes storage slack or a borrowed view.

Programs that reach either byte-projection operation emit BPI1 evaluator
semantics version 3.
Version 3 retains version-2 authored-failure semantics and does not change the
BPI1 container, Process State, or Process ABI. Programs that do not reach the
new operation retain their prior evaluator version and byte-identical images.

Evaluator semantics and fixed-kernel capacity are independent. A program using
1,025–1,280 canonical values or 129–192 reachable segments may retain evaluator
semantics version 1 or 2 because its instruction meaning has not changed, but a
Boundary 1.7 kernel will reject that larger catalog. Hosts pinning the 1.7
kernel must upgrade to the Boundary 1.8 kernel before executing an image that
crosses either released capacity frontier, even when the image uses no
version-3 operation. Capacity alone does not introduce another evaluator
semantics version.

The BPI1 schema catalog remains independently bounded at 1,024 structurally
interned nodes. The 1,280-value frontier does not raise that limit: many values
normally share one portable schema. Schema emission and image validation
enforce the same bound.

The compiler-only RNF invariant-term ceiling is 128. This bounds compile-time
proof synthesis for deeply staged first-order programs; it is not a runtime,
State, or process-lifetime limit.

The fixed Process kernel must explicitly admit evaluator semantics version 3.
Hosts pinning the Boundary 1.7 kernel must therefore upgrade to the Boundary
1.8 kernel before executing a version-3 image. Historical Boundary 1.7 images,
kernel assets, and the v1.7 Process conformance corpus remain unchanged.
