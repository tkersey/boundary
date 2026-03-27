# Source Lowering Contract

## Status

This track is an internal source-lowering contract for the repo-owned source
corpus and the promoted example and witness rows backed by the
`shift-source-lower` toolchain. It is not a public root API lane.

## Public Boundary

The public authored-body surface remains:

- `shift.Row(.{ ... })` / `shift.mergeRows(.{ ... })`
- `shift.effects.*`, `shift.handlers.*`, and `shift.Decision(...)`
- `const closed = shift.bind(...); try shift.run(&runtime, closed)`

The source-lowering toolchain exists only as internal proof scaffolding beneath
that public boundary. Its current implementation now compares covered rows
against the canonical repo-owned structural shape rather than exact source-text
hashes, then projects accepted rows onto canonical lowered scenarios.

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

- `example.early_exit`
- `example.resume_or_return`
- `example.nested_workflow`
- `example.state_basic`
- `example.reader_basic`
- `example.optional_basic`
- `example.exception_basic`
- `example.resource_basic`
- `example.writer_basic`
- `open_row_state_writer`
- witness rows

Every covered row must stay backed by:

1. direct source execution
2. structurally validated lowering through the internal source-lowering toolchain
3. canonical scenario transcript parity
4. witness rows also preserve evaluator, reference-machine, and runtime agreement

## Coverage Matrix

The checked steady-state coverage artifact is:

```text
docs/source_lowering_coverage_matrix.json
```

It records the current source-lowering label, law anchor, current proof signal,
and `coverage_status` for each covered witness and shipped open-row example/effect row.

The checked admission/replay artifact is stored at the legacy path:

```text
docs/lowering_equivalence_report.json
```

It records the current accepted source, promoted, witness, and bridge
rows together with authoring admission status, canonical replay status,
and the checked witness status (`supported`, `unsupported`, or
`not_applicable` when no matching source-lowering proof row exists).
It is not itself a direct source-vs-lowered equivalence proof; that proof
remains in the gauntlet and the direct-source parity suites.

The checked rejection artifact is:

```text
docs/lowering_rejection_report.json
```

It records representative fail-closed rows that must remain rejected by the
structural lowerer.

## Proof Surface

The source-lowering contract is only considered maintained when all of these
remain green:

```text
zig build source-lowering-gauntlet
zig build source-lowering-coverage-check
zig build lowering-equivalence-report-check
zig build lowering-rejection-report-check
zig build test
```

The gauntlet proves every source corpus case in two ways:

1. direct source fixture execution
2. execution through the internal restricted source-lowering path and canonical lowered engine

The checked corpus artifact is `docs/source_lowering_matrix.json`.
The checked coverage artifact is `docs/source_lowering_coverage_matrix.json`.
The checked admission/replay artifact is `docs/lowering_equivalence_report.json`.
The checked rejection artifact is `docs/lowering_rejection_report.json`.
