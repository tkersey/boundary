# Research Notes

This implementation is informed by the same families of systems that shaped the plan:

- Racket prompts and composable continuations.
- SRFI delimited continuation operators.
- OCaml 5 one-shot continuation handling.
- `libmprompt` and delimcc-style direct implementations.

The current code deliberately narrows the scope to a managed-frame model so the implementation stays honest in Zig without pretending to capture arbitrary native call stacks.
