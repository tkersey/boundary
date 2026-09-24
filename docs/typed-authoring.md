# Structured staged authoring (in progress)

`boundary.authoring` constructs the existing Boundary source language. A native
Zig `if` chooses source to build; `Body.conditional` builds runtime selection.
Native `try` propagates construction errors; it does not implement an authored
failure. Native `defer` tears down emitter resources, not portable cleanup.

The initial surface has arena-owned, category-distinct schema, operation,
function, value and computation handles. `Context.init` borrows a source builder;
keep that builder at a stable address and destroy it after the handles and source
modules are no longer needed. Field names are copied into that arena. Scalars are
canonicalized, while named product layouts retain their field relationships.

See `examples/structured_branch.zig`: declare schemas and an external operation,
declare the named function interface and its explicit allowed effects, open a
body, build both branch bodies, join, return, and define. `program.lower` and
`Compiled.encode` retain the normal admission and BPI3 path.

Bodies append bindings in forward order. `ret` closes a body, and values from its
children cannot escape except through a join. Opaque handles cannot be exchanged
between semantic categories. Cross-context and lexical errors are checked during
authoring; source admission remains authoritative for use, captures and effects.
`Context.diagnostic` is inspectable and renders the same error relationship.
Allocation failures poison the context: discard its handles and deinitialize the
source builder. Module publication copies the source arrays into the arena so
later builder-array growth cannot invalidate the returned snapshot.

This is the first implementation slice, not the complete specified API. Callable,
handler, recursive-demand, package-consumer and remaining discriminator work is
still pending. No review convergence is claimed.

## Validation account

Baseline: `ab0c52636023b7db7690f647f0fedc10bbba93ef`, tree
`43f598f4ed6b58d267e293f7c4186849bdb63194`. Zig 0.16.0 and Node 26.9.0.

The fixed World delivery uses source
`669a37a563363541f2a92ba3cee644dba7b86a70`, tree
`f803635405f997c8e072112da42cefc8491f9cb4`, and Boundary-data
`1b00c8c159f0cb490a1223fac8d3d208cef41cb1`. Verified identities:

- archive: `99c3eb8a2cb24e5002824050b24aab9f816436215c0b70f39f353057a31a3f70`
- manifest: `47af5517108c550ab7ecef9a188ba3e545e916bb1e196b065ef6a342a2dfa69d`
- kernel: `df7fe1ae0ed0de7b2976c98b1534d1d55f4c341b7148837ce32f42ed8d011084`
- native companion: `c77e77fd568d52284c3c973080852fa1aa515f6e3c47ac14213d2cc051fc061e`

The package inventory verifier checked 35 files and its bounded execution/restore
smoke passed. ABI 3, wasm32 ReleaseSmall, 65,536-byte stack, 256 MiB maximum memory;
smoke uses input/working/output limits 65,536 / 1,048,576 / 65,536 bytes.
The native companion's bytes are verified; native execution is not yet claimed.

Newly executed baseline reciprocal demand: payload 19, reply 19, result 42,
1,234-byte image, 83 fresh-instance transfers at quantum 1. Its existing driver
uses 2 MiB / 8 MiB / 2 MiB execution limits. Other replies remain to be checked.

`zig build check-authoring -Doptimize=ReleaseSafe` passed with the first authoring
slice. Allocation-failure injection covers its constructors and snapshot.
`test/structured_authoring.mjs RUNTIME_DIR IMAGE` executes both branches with the
verified kernel: false returns 42 without a request; true requests payload 19 and
returns the independently supplied reply 71 after fresh-instance restoration.

## Integration progress

The second slice adds callables, nested lexical captures, named application,
checked addition, local capabilities, derived responders, handlers and resumptions,
sequence construction, tagged cases and protection entry points. The handler body
and continuation have separate capture allowances. All four requested migrations
now use the new surface; the hyperfunction bridge contains only interface setup
and checked calls into the existing library.

The new client in `examples/authoring_client.zig` constructs a reusable callable,
invokes it twice under a responder with an external residual lookup, and selects
that work using a runtime Boolean. Its alternate branch performs checked addition.
Native/Node execution agrees on two distinct reply sequences and on overflow in
both branches. The image is 501 bytes. Building this client outside the source tree
and its rejected sibling remain pending.

Further newly executed evidence:

- Focused tests preserve valid nested capture and reject foreign/escaped values.
- Existing scoped-choice tests retain borrowed-cell returns, owned regions and
  protected-resource capture rejection/acceptance.
- `zig build check-authoring -Doptimize=ReleaseSafe` passed after the integrations.
- `zig build emit-examples check-semantics -Doptimize=ReleaseSafe` passed: 42
  independent source fixtures plus cancellation/cleanup scenarios.
- The existing World source-agreement driver, pointed at the selected runtime,
  passed 6,433 native/Node comparisons over those 42 newly emitted fixtures.
- Baseline and migrated one-effect images are both 85 bytes and agree on two
  independently supplied replies.
- Baseline and migrated recursive demand agree for replies 19 and 29 (results 42
  and 52), and maximal-u64 reply (authored failure), using actual State across
  fresh native/Node instances. The candidate is 1,220 bytes versus 1,234 baseline;
  successful quantum-1 runs take 85 versus 83 transfers. Transfer counts are
  scheduling observations, not extra external effects.

Full A01–A18 coverage, public-package construction, economic timing and serial
review convergence are still in progress. This draft does not claim completion.
