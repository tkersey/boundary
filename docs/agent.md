# Boundary Agent Profile v0

Agent Profile v0 defines an agent as an ordinary Boundary program. It is a
typed construction profile over existing portable-v2 execution and Certified
Boundary Module surfaces. It does not add a calculus, runtime, scheduler, model
client, tool registry, or host callback system.

The framing is:

> The agent is not a host loop. The agent is a Boundary program. World turns it
> into portable execution. world-host operates the resulting process.

## Agent.Profile v0

`boundary.Agent.Profile` records deterministic limits and surface identity:

- profile format and fingerprint versions;
- profile fingerprint;
- maximum iterations, model calls, tool calls, observation bytes, action bytes,
  tool-result bytes, and trace entries;
- supported `Agent.Action` variants;
- supported closed `Agent.ToolId` variants;
- value-schema fingerprints;
- metadata bytes.

The fingerprint binds the limit fields, supported action variants, closed tool
variants, value-schema fingerprints, and metadata bytes. Validation rejects
unsupported format/fingerprint versions, empty capacities, incomplete tool or
schema surfaces, action-surface mismatch, and fingerprint drift. The
`Agent.State` schema binds the concrete `TerminalStatus` tag mapping, and
`Agent.Action` schema binds the concrete closed sum tag mapping, so renumbering
terminal states or actions changes the profile/corpus fingerprint surface.

`Agent.canonical_value_schemas` defines the Agent-owned portable value schemas
and fingerprints for `Agent.Goal`, `Agent.Observation`,
`Agent.Budget`, `Agent.TraceSummary`, `Agent.State`, `Agent.DecisionPrompt`,
`Agent.Action`, `Agent.ToolId`, `Agent.ToolPayload`, `Agent.ToolRequest`,
`Agent.ToolResult`, `Agent.FinalResult`, and `Agent.Failure`.
`Agent.canonicalValueSchemaFingerprints()` returns that fingerprint list for
`Agent.Profile` construction.

## Module Artifact Provenance

`boundary.Agent.ModuleArtifact` records the Boundary module role, Agent profile
fingerprint, Certified Boundary Module fingerprint, Protocol.Manifest
fingerprint, world-surface fingerprint, import count, exported result
fingerprint, full-module byte length, and full-module byte fingerprint.

`Agent.buildRootModule`, `Agent.buildToolboxModule`, and
`Agent.buildFixtureModelModule` are helper builders over existing compile-time
Boundary module targets. Each helper emits owned full-module bytes and a
validated `ModuleArtifact` for the requested role, byte identity, and decoded
module facts.

It is not a package registry or a new execution path. It is a small provenance
record that lets conformance examples prove that an Agent profile is bound to
actual full-module bytes before World seals those bytes into an
`Executable.Image`.

## Agent.State

`Agent.State` is the portable state shape for the agent loop:

- goal;
- current observation;
- prior observation summary;
- iteration index;
- remaining budget;
- model call count;
- tool call count;
- terminal status;
- bounded trace summary.

The state helpers fail closed when model, tool, or iteration budgets are
exhausted. They do not widen the accepted state space by silently allowing extra
model or tool calls.

## Agent.Action

`Agent.Action` is a closed sum:

- `final(text)`;
- `tool(tool_id, payload)`;
- `fail(reason)`.

The `tool` action carries a closed `ToolId` plus payload bytes. Display labels
are diagnostics only; semantic tool dispatch is by the closed tool variant.

## Decision Port

The model is not in Boundary. A model decision is a residual port consumed by
World as external Actuation and resolved by a host driver. Boundary owns the
portable request/response schemas and the agent loop that decodes the
`Agent.Action` value.

## Toolbox Provider

The toolbox provider is also a Boundary module. It receives a closed `ToolId`
and payload, dispatches over the closed tool set, and either runs pure helper
logic or calls residual ports such as `file.read` and `file.write`.

World Fabric routes the root agent toolbox call to the loaded toolbox provider
export. The host does not act as a semantic tool registry.

## Closed ToolId

`Agent.ClosedToolSet` constructs a fixed tool-id surface at module-build time.
It rejects empty label sets and duplicate labels at comptime. Label lookup is a
builder/diagnostic convenience; runtime dispatch uses the closed generated
variant index, and out-of-range tool ids fail closed before a toolbox label can
be projected.

## Budget Semantics

Budgets are part of the profile and state. The root agent loop consumes
iteration/model/tool budget before the corresponding step. Exhaustion is a
deterministic failure, not a host policy decision.

## Generated/Loaded Parity

Agent Profile v0 is intended to be exercised through both generated
`Program.Session` and target-neutral `LoadedModule.Session` surfaces. The root
agent module now has skeleton, fixture, budget-exhaustion, malformed-action,
and unknown-tool parity coverage: the same Boundary program is executed through
generated session semantics and through loaded full-module bytes, with residual
identity compared at each model/tool site. Budget exhaustion and unknown-tool
cases compare declared failure identity; malformed-action coverage compares the
same model request identity and requires both execution surfaces to reject the
malformed action image before any tool dispatch.

The toolbox-provider module also has generated/loaded parity coverage for the
actuate, read-file, and write-file fixture tools. The fixture module dispatches
inside Boundary module bytes from a closed generated tool index and compares
file residual identity, canonical payload bytes, and final results across
generated and loaded execution.

## Conformance Cases

Agent Closure v0 conformance grows around:

- skeleton one-tool agent;
- fixture read/write agent;
- budget exhaustion;
- malformed action;
- unknown tool id;
- generated-versus-loaded parity.

The current Boundary slice provides the public namespace, deterministic profile
fingerprinting, closed tool-id checks, action validation, malformed tag
rejection, budget checks, bounded trace summaries, skeleton/fixture flow
accounting, full-module byte provenance, root and toolbox module bytes, and
generated/loaded parity for skeleton/fixture root-agent executions plus
budget/unknown-tool root-agent declared failures, malformed action-image
rejection on both root-agent execution surfaces, and actuate/read/write
toolbox-provider executions.

The tracked corpus catalog lives at
`conformance/v0/agent/corpus.boundary-agent.txt`. The
`check-boundary-agent-conformance-corpus` gate compares that catalog against the
generated corpus text and runs the scenario tests.
`check-boundary-agent-generated-loaded-parity` also runs the Agent module
transfer fixture and the root-agent/toolbox-provider parity tests, comparing
generated `Program.Session` output, declared failures, and loaded full-module
execution.

## Non-Goals

Boundary Agent Profile v0 does not add:

- a new Boundary calculus;
- new instruction semantics;
- real LLM APIs;
- credentials or URLs as authority;
- a production tool registry;
- host object handles;
- scheduler behavior;
- package discovery or remote module fetching.

## Release Requirements

Adding `boundary.Agent` is public Boundary surface. World may consume it only
after the Boundary PR is reviewed, merged, tagged, and verified as an exact
archive/package hash. If future work uses only prebuilt full-module bytes and
does not import or treat new Boundary API as released, that future World slice
may record exact Boundary commit provenance instead of requiring a new tag.
