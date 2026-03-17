# Ordinary Zig Contract

## Status

This track is now **canonical** for the repo-owned authored-body surfaces covered
by `docs/surface_replacement_matrix.json`. It exposes a source-validated lowering
surface through `shift.ordinary` and the `shift-ordinary-lower` tool, while the
lexical `shift.with(...)` family remains a public compatibility/runtime surface.

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

## Canonical Corpus

The canonical ordinary corpus includes these former wave-one ordinary-Zig case ids:

- `ordinary.local_mutation_resume`
- `ordinary.branch_resume`
- `ordinary.loop_resume`
- `ordinary.helper_call_resume`
- `ordinary.nested_prompt_static_redelim`
- `ordinary.typed_error_try`
- `ordinary.defer_resume`
- `ordinary.errdefer_error`

These cases still define the structural core of the ordinary lowering subset:

- local variables and mutation
- `if` / `else`
- `while`
- same-module helper calls
- nested prompts with static re-delimitation made visible in the transcript
- typed error propagation with `try` / `catch`
- `defer`
- `errdefer`

## Structural Exclusions

- No public continuation handle
- No runtime2
- No recursion
- No dynamic callee lowering
- No arbitrary cross-module lowering
- No reflective raw-body lowering API
- No stable non-experimental runtime-call lowering API
- No performance contract

Anything outside the restricted structural subset remains out of scope for this
contract, even though every current replacement-ledger row now maps onto it.

## Canonical Replacement Rows

The canonical ordinary surface now covers these repo-owned authored-body rows:

- `example.define_basic`
- `example.define_choice_basic`
- `example.define_abort_basic`
- `example.early_exit`
- `example.resume_or_return`
- `example.nested_workflow`
- `example.state_basic`
- `example.reader_basic`
- `example.optional_basic`
- `example.exception_basic`
- `effect.state_basic`
- `effect.reader_basic`
- `effect.optional_basic`
- `effect.exception_basic`
- `example.resource_basic`
- `example.writer_basic`
- `example.algebraic_abortive_validation`
- `example.algebraic_artifact_search`
- `user_defined.*`
- witness rows

The canonical replacement ledger is only honest when every row remains backed by:

1. direct source execution
2. source-validated lowering through `shift.ordinary` / `shift-ordinary-lower`
3. canonical scenario transcript parity
4. witness rows also preserve evaluator/reference-machine/runtime agreement

## Surface Replacement Matrix

The checked artifact is:

```text
docs/surface_replacement_matrix.json
```

It records every current witness, example, built-in effect family, and
user-defined effect capability class that has been replaced by the canonical
ordinary-body path. Historical row states progressed through:

- `planned`
- `candidate_green`
- `parity_green`
- `canonical`

## Proof Surface

The ordinary-canonical state is only considered maintained when all of these remain green:

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
