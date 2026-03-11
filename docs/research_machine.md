# CPS Sketch and Defunctionalized Machine

This document records the machine shape the runtime is required to realize.
The repo now also keeps an executable reference machine backend for the active hard witnesses so the optimized runtime can be checked against a first-order oracle, not only prose.

## Working CPS Intuition

The kernel exposes:

- an explicit continuation argument
- an explicit prompt value
- an `InAnswer` / `OutAnswer` split once `CoreSR-Full` lands

The CPS account therefore needs:

- a current continuation
- a delimiter-specific meta-continuation
- enough type structure to express answer-type pressure honestly

In the branch target, that means:

- `resumeWith(...)` returns `InAnswer`
- handlers and `reset(...)` return `OutAnswer`

## Defunctionalized Machine View

The current stackful runtime should correspond to these machine pieces:

- delimiter frame
- prompt token
- captured continuation shell
- resumed frame
- completed answer
- propagated user error

## Minimal Machine States

- `Running(frame)`
- `Captured(frame, continuation)`
- `DeliverResume(frame, value)`
- `Complete(answer)`
- `Failed(err)`

## Why This Matters

The runtime is not allowed to invent a different semantic story than this machine account.

In particular:

- capture must target the nearest matching prompt
- resumed work must be re-delimited
- returning from a handler without resuming must still produce the enclosing answer lawfully
