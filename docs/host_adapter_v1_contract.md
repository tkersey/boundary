# HostAdapterV1 Contract

## Status

HostAdapterV1 is the internal synchronous host boundary for the agent-VM
campaign.
It is the design input for `st-503`, `st-507`, `st-508`, and `st-509`.
HostAdapterV1 v1 is intentionally tool-only.

HostAdapterV1 is intentionally new.
It does not reuse the current proof transcript shapes from
`src/parity_scenarios.zig` or the current durable sidecar rows from
`src/durable.zig` as its public effect log.

## Goals

- provider-neutral tool boundary for the agent-VM v1 surface
- typed request and result envelopes
- stable request IDs
- canonical global tool IDs
- synchronous v1 semantics with one request resolved before execution resumes

## Non-Goals

- model turns
- durable-state effects
- async or streaming host effects
- hidden host exceptions
- implicit fallback to undeclared tools
- timestamps inside the canonical request/result payload

## Shared Data Model

HostAdapterV1 uses one recursive typed value tree:

`DataValueV1 = null | bool | i64 | u64 | string | bytes | array<DataValueV1> | object<(string, DataValueV1)>`

Canonical rules:

- strings are UTF-8
- `u64` carries full-range unsigned payloads such as `ValueCodec.usize`
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
- `kind: enum { tool_call }`
- `body: variant`

Every host effect result has this outer shape:

- `schema_version: u16 = 1`
- `request_id: u64`
- `status: enum { success, rejected, failed }`
- `body: variant`

Requests or results whose `schema_version` is not `1` fail closed.

## Tool Contract

The canonical tool op ids are `tool.call` and `tool.after`.

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
- `op_name: string`
- `arguments: DataValueV1`

`ToolCallResultV1` contains:

- `tool_id: ToolIdV1`
- `call_id: u64`
- `control: enum { resume, return_now, abort }`
- `value: DataValueV1`

Unknown or undeclared tool ids fail closed.

`tool.after` is optional per declared capability-op row.
When present, it represents one post-resume callback for a lowered
`transform` or `choice` op and must use the same `tool_id`, `call_id`, and
declared payload/result codecs carried by the ArtifactV1 manifest.

## Reserved Future Expansion

Model-turn and durable-state host effects are reserved for a later agent-VM
revision.
They are intentionally out of scope for HostAdapterV1 so the public boundary
does not advertise payloads or result shapes that the current runtime cannot
construct or consume.

## Sync Semantics

HostAdapterV1 is sync-only in v1.

Rules:

- the VM emits one request
- the adapter resolves it completely
- the VM resumes

There is no pending result, no cancellation token, no async continuation, and
no background tool execution in v1.

## Declared Outputs

ArtifactV1 may declare entry outputs in its `output_table`.
When the entry function declares outputs, `HostAdapterV1` must provide one
completion snapshot through `collectOutputsFn`.

Rules:

- `collectOutputsFn` runs only after the root returns successfully
- returned values must be allocator-owned
- returned values must match the declared output count and order exactly
- each returned value must satisfy the declared output codec
- output collection is not part of the canonical host-effect log

## Failure Model

HostAdapterV1 never throws hidden host exceptions across the boundary.

Typed failures use:

- `unsupported_capability`
- `unsupported_operation`
- `undeclared_tool_id`
- `invalid_arguments`
- `provider_failure`
- `concurrency_violation`

`rejected` means the request was invalid against the declared contract.
`failed` means the request was valid but the host provider could not satisfy it.

## Relationship To ArtifactV1

ArtifactV1 declares the capability inventory.
HostAdapterV1 executes against that inventory.

Required linkage rules:

- `capability_id` and `op_id` in every request/result must exist in the
  artifact capability manifest
- `kind` must be `tool_call` in v1
- the declared global op id must be `tool.call` or `tool.after`

## Logging Rule

The canonical host-effect log is the ordered sequence of
`HostEffectRequestV1` and `HostEffectResultV1` pairs.

Timestamps, wall-clock durations, provider debug strings, and transport traces
may exist in non-canonical sidecars, but they are outside the v1 replay and
parity contract.
