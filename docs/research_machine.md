# CPS Sketch and Defunctionalized Machine

This document records the machine shape the runtime is required to realize.

## Working CPS Intuition

The kernel exposes:

- an explicit continuation argument
- an explicit prompt tag
- an enclosing answer type

The CPS account therefore needs:

- a current continuation
- a delimiter-specific meta-continuation
- enough type structure to express answer-type pressure honestly

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
