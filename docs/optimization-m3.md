# M3 — Specialization, joins, and global control

Continue P06–P10 and P21 on Boundary #161 and the existing consumer drafts.
M2.5's bounded checkpoint is qualified; all remaining programme requirements
and final-review scheduling remain unchanged.

## P06 first production slice

`partial_redundancy.zig` performs latest placement of total unsigned word
bitwise expressions and unsigned-word equality at a join's first instruction.
At least one incoming path must already compute the expression. Availability
is currently local to an immediate predecessor; entry-position demand proves
that the original expression must execute on every selected edge into the join.
Pure functions with identical lexical custody are required. This is a bounded
fragment, not general global PRE or speculative code motion.

An available value is passed through a simultaneous edge assignment. A missing
value is computed at the end of an unconditional assignment-free predecessor,
or in a new block reached only by the selected incoming edge. Original parallel
assignments occur before the inserted expression. Other successors, including
early returns, retain their original instructions and edges.

The checker does not trust the reverse invalidation used by discovery. It
reconstructs operand and result versions by a forward scan, applies edge
assignments from the predecessor view, checks definite availability, enumerates
every original incoming edge, and compares all changed/unchanged records.
Original and candidate admission, bounded work rollback and final P01 remain
mandatory. Wrong reused operands, stale mutable operands, omitted paths and an
admissible speculative early-path evaluation are rejected. Allocation failures
release temporary owners.

## Selection and witnesses

The existing static instruction sum cannot value a partial redundancy whose
static expression count stays constant. The shared candidate portfolio now also
uses a bounded per-function longest-path work estimate. Calls retain the existing
opaque dispatch weight; cyclic or deeper-than-512 CFGs yield unknown rather than
a fabricated finite bound. The metric is a heuristic, not a whole-program runtime
bound. Image/admission guards and independent transformation acceptance remain.

The default semantic pipeline selects a live comparison diamond whose arm result
also controls a branch, preventing prior dead-code removal from erasing the
opportunity. Source-free closed linking selects the same transformation.
Independent record execution counts and native World outputs cover both branch
choices and several input pairs. The critical-edge witness changes expression
evaluations 2→1 on the reuse path, 1→1 on the missing-definition path, and 0→0 on
the early-return path. These are path-specific evaluations, not a claimed speedup.

Focused tests, the data aggregate and native execution have passed for the initial
slice. Final proof counts and remaining qualification are recorded with delivery.
Broader placement, a dedicated borrowed-owner negative witness, platform/economic
qualification, P09 specialization/inlining, P10 contification and P21 remain open.
No new branch, PR, persistence infrastructure or intermediate review gate is added.

Initial terminal results: **41/41 focused tests**, **3/3 data steps and 306/306
tests** before the last mutation-only addition, and **2/2 native World tests**.
The focused result covers that addition. `performance/m3-pre-initial.json`
records exact scope and raw-log identities. No full M3 or performance acceptance
is claimed.
