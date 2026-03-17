# Ordinary Zig Contract

## Status

This track is **public experimental** and additive. It does not replace the
current canonical `shift` product story, and it does not expose a public
ordinary-Zig lowering surface yet.

Wave one adds an **internal-only restricted lowering path** plus a checked
ordinary-Zig corpus. The purpose of the wave is to make a small, exact, all-green
subset true without broadening the public API.

## Long-Term Canonical Target

The long-term target is a canonical **ordinary-body generalized algebraic
effects** front door that still lowers onto the current lowered machine.

That long-term canonical story is expected to:

- keep the current lowered machine as the semantic/runtime substrate
- keep the current semantic core intact
- internalize prompts and `PromptMode` from the canonical public story
- replace the current prompt-mode/protocol-shaped public surfaces only after
  full transcript-and-law parity is proven

## Preserved Semantic Invariants

The long-term campaign is not allowed to violate these invariants without being
explicitly reopened:

- static delimitation
- one-shot linearity
- internal typed prompt discipline
- current answer-type discipline

## Wave-One Supported Subset

Wave one supports exactly these ordinary-Zig case ids:

- `ordinary.local_mutation_resume`
- `ordinary.branch_resume`
- `ordinary.loop_resume`
- `ordinary.helper_call_resume`
- `ordinary.cross_module_helper_resume`
- `ordinary.cross_module_helper_chain_resume`
- `ordinary.nested_prompt_static_redelim`
- `ordinary.typed_error_try`
- `ordinary.cross_module_typed_error_try`
- `ordinary.defer_resume`
- `ordinary.errdefer_error`

These cases cover the wave-one subset:

- local variables and mutation
- `if` / `else`
- `while`
- same-module helper calls
- static imported helper calls and helper chains
- nested prompts with static re-delimitation made visible in the transcript
- typed error propagation with `try` / `catch`
- typed error propagation through imported helpers
- `defer`
- `errdefer`

## Wave-One Exclusions

- No public continuation handle
- No runtime2
- No recursion
- No dynamic callee lowering
- No arbitrary cross-module lowering
- No user-invocable lowering entrypoint
- No performance contract

Anything outside the exact wave-one subset is out of scope for this contract and
must not appear as a partial, skipped, or unsupported row in the wave-one
matrix.

## Surface Replacement Matrix

Wave one also adds a second checked artifact:

```text
docs/surface_replacement_matrix.json
```

Unlike `docs/ordinary_zig_matrix.json`, which tracks the currently promised
green-only ordinary-Zig wave, the replacement matrix tracks the **long-horizon
cutover bar**. It records every current witness, example, built-in effect
family, and user-defined effect capability class that must eventually be
replaced by the canonical ordinary-body path.

The replacement matrix does **not** mean those rows are already green. It is a
coverage ledger and cutover gate, not a promised-wave success surface.
Its row statuses are expected to progress through:

- `planned`
- `candidate_green`
- `parity_green`
- `canonical`

## Proof Surface

Wave one is only considered complete when both of these remain green:

```text
zig build ordinary-zig-gauntlet
zig build surface-replacement-check
zig build test
```

The ordinary-Zig gauntlet must prove every wave-one case in two ways:

1. direct source fixture execution
2. execution through the internal restricted lowering path and canonical lowered engine

The checked artifact for the wave is `docs/ordinary_zig_matrix.json`.
The checked long-horizon replacement ledger is `docs/surface_replacement_matrix.json`.
