# Source Lowering Contract

## Status

This track is an internal source-lowering contract for the repo-owned source
corpus and the promoted example and witness rows backed by the
`shift-source-lower` toolchain. It is not a public root API lane.

## Public Boundary

The public authored-body surface remains:

- `shift.Program(.{ ... }, Body)`
- `shift.run(&runtime, Program, bindings)`
- `shift.Decl.*`, `shift.Op.*`, and `shift.Decision(...)`

The source-lowering toolchain exists only as internal proof scaffolding beneath
that public boundary.

## Preserved Semantic Invariants

- static delimitation
- one-shot linearity
- internal typed prompt discipline
- current answer-type discipline

## Source Corpus

The checked source corpus uses these stable source-lowering case ids:

- `source.local_mutation_resume`
- `source.branch_resume`
- `source.loop_resume`
- `source.helper_call_resume`
- `source.nested_prompt_static_redelim`
- `source.typed_error_try`
- `source.defer_resume`
- `source.errdefer_error`

These cases cover the structural subset promised by the internal source-lowering
track:

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

## Covered Rows

The internal source-lowering track currently covers these repo-owned authored
rows:

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
- `example.resource_basic`
- `example.writer_basic`
- `example.algebraic_abortive_validation`
- `example.algebraic_artifact_search`
- `built_in.state`
- `built_in.reader`
- `built_in.optional`
- `built_in.exception`
- `built_in.resource`
- `built_in.writer`
- `user_defined.transform`
- `user_defined.choice`
- `user_defined.abort`
- witness rows

Every covered row must stay backed by:

1. direct source execution
2. source-validated lowering through the internal source-lowering toolchain
3. canonical scenario transcript parity
4. witness rows also preserve evaluator, reference-machine, and runtime agreement

## Coverage Matrix

The checked steady-state coverage artifact is:

```text
docs/source_lowering_coverage_matrix.json
```

It records the current source-lowering label, law anchor, current proof signal,
and `coverage_status` for each covered witness, example, built-in declaration,
and user-defined effect row.

## Proof Surface

The source-lowering contract is only considered maintained when all of these
remain green:

```text
zig build source-lowering-gauntlet
zig build source-lowering-coverage-check
zig build test
```

The gauntlet proves every source corpus case in two ways:

1. direct source fixture execution
2. execution through the internal restricted source-lowering path and canonical lowered engine

The checked corpus artifact is `docs/source_lowering_matrix.json`.
The checked coverage artifact is `docs/source_lowering_coverage_matrix.json`.
