# Effects

Residual effects are comptime-known typed sites:

```zig
const Lookup = boundary.effect.site(
    0,
    "research.lookup.v2",
    ResearchRequest,
    ResearchResponse,
);

const RoutedLookup = boundary.effect.site(
    0,
    "research.lookup.routed.v2",
    ResearchRequest,
    ResearchResponse,
);

const Body = struct {
    pub const effect_sites = .{Lookup};
    pub const effect_morphisms = .{
        boundary.effect.morphism(0, RoutedLookup),
    };
    // ...
};
```

Each site binds a dense ordinal, structural semantic identity, portable payload
type, and portable resume type. The compiler emits the residual effect row and
the request/response mapping into the Machine contract.

The tuple position is the source ordinal. If an authored site exposes `id` or
`site_id`, the compiler requires it to equal that position; the public
`boundary.effect.site` constructor emits both declarations consistently.

`boundary.effect.morphism` is a compile-time, type-preserving transformation.
The compiler requires the source and target `Payload` and `Resume` types to
match exactly, then substitutes the target semantic contract before residual
row construction. The source contract and morphism do not survive as runtime
dispatch state.

`boundary.effect.handler(source_id, helper_function_id)` eliminates a source
effect through a statically known Control IR helper. The helper entry must
accept exactly the source `Payload`, and its function result must equal the
source `Resume`. The compiler rewrites each matching suspension to a direct
typed call before reachability and RNF synthesis, so the handled site grants no
residual authority and no runtime handler survives.

Source declarations that no root-reachable Control IR effect suspension
references are eliminated before RNF. Sites referenced only from unreachable
control grant no Machine authority. Remaining sites are remapped to dense
residual ordinals in source order; only that canonical residual row reaches the
request union, Machine identity, or World.

World inspects the compiler-owned contract through
`Machine.EffectRow.site(ordinal)`. Each descriptor exposes the site ordinal,
`Payload`, `Resume`, result type, single-resume mode, and semantic identity.
It exposes two domain-separated SHA-256 digests. `semantic_contract_digest`
binds the declared semantic identity, canonical payload/resume schemas, and
response mode without the residual ordinal; local Driver handlers use it as
their compile-time capability. `contract_digest` additionally binds the dense
residual ordinal for Machine and request identity. The source `Body` and its
accidental declarations remain private.

A production handler owns its admitted `semantic_contract_digest`
independently of the Machine it is asked to handle. It must not derive that
capability declaration from `Machine.EffectRow`, because doing so would approve
semantic drift automatically. The shipped one-effect example pins the digest
as handler-owned bytes, so a source-contract change requires an explicit
handler-owner update before the example compiles again.

`Machine.step` can park at one effect constructor and return one typed request.
The canonical state retains the exact continuation environment. After the
caller validates and supplies the typed response, `Machine.resume` replaces the
await constructor transactionally. Each request carries a derived
`RequestIdentity` binding the Machine contract digest, sequence, constructor,
effect-site ordinal, structural effect-site digest, canonical payload digest,
and a domain-separated SHA-256 digest of that tuple. The identity is
reconstructed from canonical state rather than persisted as an independent
authority. Stale, forged, or cross-Machine responses are rejected. A second
response to the same already-advanced live State owner is rejected as stale.
Cloned, decoded, replayed, or branched equivalent State owners reconstruct the
same identity and may each accept one matching response; World and world-host
own branch-head advancement, replay policy, and external idempotency across
those owners.

Boundary-local after behavior compiles into RNF constructors. A completed
Machine exposes `EffectRow.after_site_count == 0` to World.

Boundary does not implement external authority. HTTP, filesystems, databases,
models, secrets, and vendor APIs belong in capability packs outside Boundary
and World.
