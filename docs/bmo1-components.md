# BMO1 components and source-independent linking

`source.component.compile` uses the stable-activation compiler to produce a
relocatable object. `boundary_data_v2.component.decode` checks its first-order
records. `boundary_data_v2.linker.link` binds objects and independently admits a
closed BPI3 Program. The linker neither runs source emitters nor executes code.
These development APIs remain under the current migration namespace until the
coordinated default cutover.

## Format

```
"ABL_BMO1"[8] | version:u16LE=1 | flags:u16LE=0 | body_length:u64LE | body
body = ProgramRecords | [Symbol] imports | [Symbol] exports
Symbol = name:Text | kind:N | id:N
```

`ProgramRecords` is exactly the body grammar in [BPI3](bpi3-wire.md), without
its frame. Symbols use ordinary length-prefixed lists and minimal unsigned
LEB128 naturals. They do not use the Program's compact ID-vector encoding.
Names must be nonempty UTF-8 and each symbol list must be strictly sorted by
name bytes. Imports cannot repeat the same local reference. Exports may give
several distinct names to the same declaration.

Kind tags are schema=0, constant=1, effect=2, function=3, block=4, handler=5,
capture=6, region=7, resource=8, constructor=9. Every reference is checked against
its catalog. Constant, block and capture imports are unsupported and reject.
All ten kinds may be exported; executable entry selection requires a function.

An imported function has no blocks, has exactly its parameter slots, and has
entry `2^64-1`. Other functions have ordinary local entries. The object root is
a locally defined compilation entry whose parameters/result may be internal;
it is not an executable claim. Its failure schema is the component's failure
contract. A closed link requires one compatible failure contract across every
instance. Bodyless imports cannot enter BPI3 admission.

Decoding owns its input, checks all local records, and compares canonical
re-emission. Unknown families/versions/flags, trailing bytes, overlong integers,
invalid references and malformed symbols reject. Wire plus decoded-record
storage has a 64 MiB admission budget. There is also a total catalog-entry limit
of 1,048,576 per object and per link, including declared regions; a tiny region
count field cannot request an unbounded relocation table. Analysis scratch is
additional caller-allocated memory and can fail with `OutOfMemory`.

Component identity is SHA-256 of `boundary.component/v1`, one zero byte, and the
entire canonical BMO1 image. It is distinct from linked Program identity.

## Bindings and identity

An instance is an explicit nonempty UTF-8 key plus BMO1 bytes. Duplicate keys
reject. A binding names an importing instance/symbol and an exporting
instance/symbol. Every import resolves exactly once. Aliases are followed
iteratively with a finite bound; cycles without an implementation reject.
Mutually recursive function bodies may reference each other's concrete exports.

Instances are sorted by key bytes before catalog allocation. Concrete local
records retain local order. Relocation follows typed record fields, including
schema references, constants, effect/region/resource identities, functions,
blocks, constructors, captures and handler clauses. Slots, custody IDs and
immediate field/variant ordinals remain local. Ordered signatures and evidence
lists preserve order; set-valued rows are sorted and deduplicated after binding.

Private nominal declarations remain distinct between instances. Explicit imports
alone unify them. Structural schema partitioning then merges equal relocated
shapes while preserving those nominal distinctions. Filesystem paths and input
enumeration order do not participate. Keys determine ordering and sharing;
their spelling is not independently hashed into the closed Program. Renaming
keys while preserving the same ordered records and bindings can retain identity.

The linker compares parameter/result schemas, residual effects, regions,
callable/resumption use and capture schemas, handler contracts and constructor
captures. Resource imports cannot declare introducer/eliminator authority;
representation compatibility is checked and only defining-instance function
identities receive those rights. Full closed type/effect/use/borrow admission
runs after relocation. Names, hashes and interface summaries do not bypass it.

The current object checker validates local types, effects, regions, ownership
and capture bounds. Borrow analysis runs separately for each local function; only
queries that actually reach a bodyless import remain deferred. An independent
unresolved call cannot suppress a locally decidable borrow violation. A regression
distinguishes older-capability clause payloads from invalid fresh-capability
payloads, both directly and through local helper calls. Removing local checking
causes that test to accept an invalid fresh-capability payload.

Closed-link admission checks the complete code. Discharging the remaining local
queries under explicit imported borrow contracts remains an open
successor requirement; this component implementation is not full migration
completion.

## Standalone use and witnesses

```
zig build build-compiler
zig-out/bin/boundary-link link.json > application.bpi3
zig build check-components
```

The linker executable imports only Boundary's pure data module. It accepts one
JSON manifest; instance paths are relative to its working directory:

```json
{
  "instances": [
    {"key":"client","path":"client.bmo1"},
    {"key":"library","path":"library.bmo1"}
  ],
  "bindings": [
    {"required":{"instance":"client","symbol":"read"},
     "supplied":{"instance":"library","symbol":"read"}},
    {"required":{"instance":"client","symbol":"value"},
     "supplied":{"instance":"library","symbol":"value"}}
  ],
  "entry":{"instance":"client","symbol":"main"}
}
```

`test/components.mjs` compiles four objects in separate emitter invocations,
transports only objects and the data-only linker into a temporary directory,
and runs three links without invoking an emitter again. Three components combine
an effectful reusable callable, a private counter interpretation and an owned
suspension with cleanup. The fourth wraps that same composition. Their current
object sizes are 142/366/603/186 bytes; the two closed images are 839/875 bytes.
These sizes are fixture observations, not the required full performance report.

World's current kernel suite executes both images using native, fresh WASM and
resident WASM operations. The private counter supplies 41 then 42; the first
Program returns 83 and the wrapper returns 166. Each yields once and performs
one external release carrying 83. It also runs a separately compiled mutually
recursive even/odd pair. Agent tool integration and the required real-file
browser transfer remain separate unfinished migration work.

`library/combinators.zig` authors `twice` once and specializes from a callable's
declared signature. Tests instantiate it for one-effect and two-effect residual
contexts and verify specialization reuse; callers do not rewrite its body or
copy residual rows. This is staged specialization, not runtime polymorphism.
