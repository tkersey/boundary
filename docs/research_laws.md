# Current Law Set

This document is the semantic source of truth for the live kernel.

## 1. Static Delimitation

`shift/reset` is static delimited control.

When a continuation is resumed, the resumed work remains under the same delimiter.

Consequence:
- the kernel must pass a witness that separates it from `control/prompt`

## 2. Prompt Identity Is Real

Prompt values are first-class and typed.

Two distinct prompt values must delimit different continuation slices even when they share the same prompt type and are nested.

Consequence:
- the kernel must pass a multi-prompt separation witness

## 3. Continuations Are One-Shot

The public kernel is intentionally one-shot.

The same captured continuation cannot be resumed twice.

Consequence:
- reuse is semantic misuse, not a performance footnote

## 4. Direct-Style Handlers Return the Enclosing Answer

The handler passed to `shift` is evaluated in the enclosing answer type.

It may:
- resume the continuation exactly once, or
- return an enclosing answer directly

Consequence:
- early exit is part of the direct-style surface

## 5. User Errors Stay Typed

User errors belong to the host-language embedding, not to extra control branches.

Consequence:
- typed user errors stay in `ControlError(ErrorSet)` and `ResetError(ErrorSet)`

## First Hard Witness Families

1. static-vs-dynamic extent
2. multi-prompt separation
