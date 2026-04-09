# HostAdapterV1 Contract

## Status

HostAdapterV1 is the internal synchronous host boundary for the agent-VM
campaign.
It is the design input for `st-503`, `st-507`, `st-508`, and `st-509`.

HostAdapterV1 is intentionally new.
It does not reuse the current proof transcript shapes from
`src/parity_scenarios.zig` or the current durable sidecar rows from
`src/durable.zig` as its public effect log.

## Goals

- provider-neutral host boundary for model, tool, and durable-state effects
- typed request and result envelopes
- stable request IDs
- canonical global tool IDs
- synchronous v1 semantics with one request resolved before execution resumes
- structured model-turn tool-call intents instead of text reparsing

## Non-Goals

- async or streaming host effects
- hidden host exceptions
- implicit fallback to undeclared tools or durable slots
- timestamps inside the canonical request/result payload

## Shared Data Model

HostAdapterV1 uses one recursive typed value tree:

`DataValueV1 = null | bool | i64 | string | bytes | array<DataValueV1> | object<(string, DataValueV1)>`

Canonical rules:

- strings are UTF-8
- object keys are unique
- object entries are serialized in ascending UTF-8 byte order by key
- bytes are explicit byte arrays, not base64-in-string hacks

## Request ID Discipline

`request_id` is a `u64` assigned by the VM runtime.

Rules:

- request ids start at `1` for each execution
- request ids increase strictly by one in emission order
- only one request may be outstanding at a time in v1
- every result must echo the matching `request_id`
- a request id is never reused after rejection or failure

Stable request IDs are required because the execution is synchronous today but
later proofs still need deterministic host-effect logs and replay order.

## Common Envelope

Every host effect request has this outer shape:

- `schema_version: u16 = 1`
- `request_id: u64`
- `capability_id: u16`
- `op_id: u16`
- `kind: enum { model_turn, tool_call, durable_load, durable_store }`
- `body: variant`

Every host effect result has this outer shape:

- `schema_version: u16 = 1`
- `request_id: u64`
- `status: enum { ok, rejected, failed }`
- `body: variant`

## Model Turn Contract

The canonical model op id is `model.turn`.

`ModelTurnRequestV1` contains:

- `prompt_messages: []ModelMessageV1`
- `allowed_tool_ids: []ToolIdV1`
- `response_mode: enum { final_only, allow_tool_call_intents }`

`ModelMessageV1` contains:

- `role: enum { system, developer, user, assistant, tool }`
- `parts: []ModelPartV1`

`ModelPartV1` contains either:

- `text: string`
- `tool_result: { tool_id: ToolIdV1, call_id: u64, value: DataValueV1 }`

`ModelTurnResultV1` contains:

- `segments: []ModelSegmentV1`

`ModelSegmentV1` contains either:

- `text: string`
- `tool_call_intent: ToolCallIntentV1`
- `final_value: DataValueV1`

`ToolCallIntentV1` contains:

- `call_id: u64`
- `tool_id: ToolIdV1`
- `arguments: DataValueV1`

Model turns must support structured tool-call intents.
Returning unstructured text that the VM later reparses into tool calls is out
of contract in v1.

## Tool Contract

The canonical tool op id is `tool.call`.

### ToolIdV1

Tool ids are canonical global ids in this exact shape:

`<authority>/<name>@v<major>`

Rules:

- ASCII lowercase only
- `authority` and `name` use `[a-z0-9._-]+`
- `major` is decimal and non-zero

Examples:

- `builtin/web.search_query@v1`
- `repo/example.weather_lookup@v1`

`ToolCallRequestV1` contains:

- `tool_id: ToolIdV1`
- `call_id: u64`
- `arguments: DataValueV1`

`ToolCallResultV1` contains:

- `tool_id: ToolIdV1`
- `call_id: u64`
- `value: DataValueV1`

Unknown or undeclared tool ids fail closed.

## Durable-State Contract

The canonical durable ops are `durable.load` and `durable.store`.
Durable state is addressed by declared slot ids, not by arbitrary file paths.

`DurableLoadRequestV1` contains:

- `slot_id: string`
- `expected_codec: enum { unit, bool, i32, string, bytes, data_value }`

`DurableLoadResultV1` contains:

- `present: bool`
- `etag: ?u64`
- `value: ?DataValueV1`

`DurableStoreRequestV1` contains:

- `slot_id: string`
- `expected_prev_etag: ?u64`
- `value: DataValueV1`

`DurableStoreResultV1` contains:

- `written_etag: u64`

Undeclared slot ids fail closed.
HostAdapterV1 does not expose arbitrary delete, rename, or directory mutation in
v1.

## Sync Semantics

HostAdapterV1 is sync-only in v1.

Rules:

- the VM emits one request
- the adapter resolves it completely
- the VM resumes

There is no pending result, no cancellation token, no async continuation, and
no background tool execution in v1.

## Failure Model

HostAdapterV1 never throws hidden host exceptions across the boundary.

Typed failures use:

- `unsupported_capability`
- `unsupported_operation`
- `undeclared_tool_id`
- `undeclared_slot_id`
- `invalid_arguments`
- `provider_failure`
- `concurrency_violation`
- `etag_mismatch`

`rejected` means the request was invalid against the declared contract.
`failed` means the request was valid but the host provider could not satisfy it.

## Relationship To ArtifactV1

ArtifactV1 declares the capability inventory.
HostAdapterV1 executes against that inventory.

Required linkage rules:

- `capability_id` and `op_id` in every request/result must exist in the
  artifact capability manifest
- `kind` must match the declared canonical global op id
- `allowed_tool_ids` in a model turn must be a subset of the declared tool ids
- durable effects may only target declared slot ids

## Logging Rule

The canonical host-effect log is the ordered sequence of
`HostEffectRequestV1` and `HostEffectResultV1` pairs.

Timestamps, wall-clock durations, provider debug strings, and transport traces
may exist in non-canonical sidecars, but they are outside the v1 replay and
parity contract.
