# Programs

A Boundary program is a comptime-known typed source definition:

```zig
const Program = boundary.program("lookup", Body);
const Machine = Program.compile(.{
    .maximum_frames = 16,
    .maximum_state_bytes = 64 * 1024,
    .maximum_machine_fuel = 100_000,
});
```

`Body` declares:

- portable `InitialArgs` and `Result` types, plus an exhaustive authored
  `Failure` enum;
- a tuple of typed `effect_sites`;
- optional declarative `effect_handlers`;
- optional declarative `effect_morphisms`;
- a tuple of structured `schema_types`;
- optional canonical constants in a heterogeneous tuple or homogeneous array;
- optional bounded `compiler_limits`;
- optional `maximum_image_bytes`, a physical image-emission capacity;
- one typed `control_ir`.

The source label is diagnostic. Executable semantics, portable schemas, RNF
constructors, effect sites, fuel rules, and identity-bearing limits determine
the Machine contract digest.

`boundary.ir` is an advanced source-authoring surface, not a deployment
bytecode. Its blocks define typed values, explicit edges, effects, helper calls,
returns, and failures. Compilation validates the definition before RNF
synthesis.

`Program.image()` materializes canonical BPI1 bytes at comptime. Build tools
can instead call `Program.encodeImage(output, workspace)` at runtime, using a
caller-owned byte buffer and `Program.ImageEncodingWorkspace`. Both paths use
the same encoder and produce identical bytes. Successful encoding returns the
written prefix length; on error, discard the output prefix. The workspace may
be reused after either success or failure and does not need initialization.
Large tools should allocate the output and workspace outside the stack.

When `Body.maximum_image_bytes` is declared, both emission paths enforce it.
`image()` reports a compile error for an oversized image; `encodeImage()` returns
`error.OutputCapacity` even when the caller supplies a larger buffer, and never
writes beyond the declared capacity. The limit is checked when emitting an image,
not when declaring the Program type. It does not alter successful image bytes,
transition identity, or direct Machine ABI v2 specialization.

The portable instruction set includes `enum_to_u32`, which projects an
exhaustive enum value to its canonical unsigned tag without relying on the
enum's backing integer type. This is the boundary-owned lowering for persisted
or wire-visible enum discriminants; consumers do not need a parallel tag table.

`text_byte_at` projects one code unit from Text's canonical UTF-8 encoding.
The operation takes a `u32` byte index, returns `u8`, and uses the standard
`invalid_index` failure role. It exposes no pointer, storage slack, or mutable
view. Reachable use emits evaluator semantics version 3.

`bytes_byte_at` applies the same checked byte-index law to canonical Bytes. It
preserves arbitrary payload bytes, including malformed UTF-8, and likewise
uses `invalid_index` without exposing spare storage.

Failures have two source forms. `.fail = tag` retains the compile-time failure
tag used by existing programs. `.fail_value = value_id` returns the exact
runtime value at that id and is admitted only when its type is exactly
`Body.Failure`. Both lower through the same Machine ABI v2 `Outcome.failed`
transition.

A fallible instruction may append one canonical constant `Body.Failure` value
operand per Boundary-defined failure role after its ordinary operands. This
selects the exact authored Failure returned by that instruction and emits
evaluator semantics version 2. Ordinary instructions retain the version-1
role-name behavior.

Evaluator semantics version 3 retains version-2 authored failures and admits
the generic byte-projection operations. Images without a reachable version-3
operation remain version 1 or 2, so their canonical bytes and transition
identities do not change.

Authored Failure operands have type `Body.Failure`, are defined by canonical
constant instructions, and appear in Boundary-defined role order. Boundary
validates and executes this rule directly; compiler-private source,
reachability, and canonicalization remain private.

`compiler_limits` has type `boundary.ir.CompilerLimits`. It can lower the
implementation ceilings for values, blocks, constructors, constructor
environments, invariants, and generated reducer work. These admission ceilings
are excluded from semantic identity when the resulting RNF is unchanged.

`effect_morphisms` contains values returned by
`boundary.effect.morphism(source_id, TargetSite)`. Morphisms are
type-preserving compiler inputs: they rewrite the residual effect contract
before RNF and leave no runtime handler or callback.

`effect_handlers` contains values returned by
`boundary.effect.handler(source_id, helper_function_id)`. Each declaration
lowers the source effect to a statically typed helper call before RNF. The
helper receives the source payload, returns the source resume type, and leaves
no runtime dispatch surface.

Boundary has no source-language interpreter, runtime Zig-definition loader,
callback registry, or host-owned continuation. `Program.compile` remains the
direct specialization route; canonical BPI1 may also be evaluated one finite
reducer segment at a time by a
`boundary.process_v1.CapacityStorage(...).advance` method or the fixed
import-free Process kernel.

For local use, instantiate `boundary.Driver(Machine)`. The Driver owns only
Machine state and handler-local resources; it repeatedly calls `Machine.step`
and `Machine.resume`, so it shares the same compiled Machine semantics.

`boundary.Agent` is deprecated compatibility surface. New agent-specific
authoring belongs in the separate Agent package; both direct and Agent-authored
programs lower to the same Boundary program semantics.
