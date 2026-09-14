import BoundaryV2.GeneralizedExitWork
import BoundaryV2.GeneralizedProgramRelation

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

/-- Cancellation updates the outermost running cleanup's exit record. The
source retains its executable body, saved result, and authored continuation. -/
def Source.Program.cancelRunning (reason : algebra.Reason) :
    Source.Program signature algebra program result → Option (Source.Program signature algebra program result)
  | .evaluate _ _ | .returned _ | .failed _ => none
  | .bind first next description => (first.cancelRunning reason).map fun after => .bind after next description
  | .handler effect mode identity returnClause clauses bindings first =>
      (first.cancelRunning reason).map (.handler effect mode identity returnClause clauses bindings)
  | .region identity first => (first.cancelRunning reason).map (.region identity)
  | .protection identity cleanup bindings first => (first.cancelRunning reason).map (.protection identity cleanup bindings)
  | .cleaning identity original exit first => some (.cleaning identity original (exit.cancel reason) first)
  | .request operation attachment payload bodies future =>
      (future.cancelRunning reason).map (.request operation attachment payload bodies)
  | .yielded first => (first.cancelRunning reason).map .yielded

theorem Source.Context.running_cancellation_stable (first later : algebra.Reason)
    (future : Source.Context signature algebra program input result) :
    (future.cancelRunning first).isSome = (future.cancelRunning later).isSome ∧
      ∀ after, future.cancelRunning first = some after → after.cancelRunning later = some after := by
  suffices ∀ n {input result} (future : Source.Context signature algebra program input result),
      future.length ≤ n →
      (future.cancelRunning first).isSome = (future.cancelRunning later).isSome ∧
        ∀ after, future.cancelRunning first = some after → after.cancelRunning later = some after from
    this future.length future (Nat.le_refl _)
  intro n
  induction n with
  | zero =>
    intro input result future bounded
    cases future with
    | done => exact ⟨rfl, by intro after impossible; cases impossible⟩
    | push frame rest => simp [Source.Context.length] at bounded
  | succ n recurse =>
    intro input result future bounded
    cases future with
    | done => exact ⟨rfl, by intro after impossible; cases impossible⟩
    | push frame rest =>
      have induction := recurse rest (by simpa [Source.Context.length] using bounded)
      cases firstAt : rest.cancelRunning first with
      | none =>
        have laterAt : rest.cancelRunning later = none := by
          have same := induction.1
          rw [firstAt] at same
          cases found : rest.cancelRunning later <;> simp_all
        cases frame <;> simp [Source.Context.cancelRunning, firstAt, laterAt, ExitInfo.cancel_keeps_first_reason]
      | some updated =>
        have stable := induction.2 updated firstAt
        have present : (rest.cancelRunning later).isSome = true := by simpa [firstAt] using induction.1.symm
        cases laterAt : rest.cancelRunning later with
        | none => simp [laterAt] at present
        | some other =>
          simp only [Source.Context.cancelRunning, firstAt, laterAt]
          exact ⟨rfl, by intro after same; cases same; simp only [Source.Context.cancelRunning, stable]⟩

/-- Repeated cancellation leaves the actual source program unchanged. It does
not reinitialize cleanup, replace its saved result, or cancel a different frame. -/
theorem Source.Program.running_cancellation_stable (first later : algebra.Reason)
    (before : Source.Program signature algebra program result) :
    (before.cancelRunning first).isSome = (before.cancelRunning later).isSome ∧
      ∀ after, before.cancelRunning first = some after → after.cancelRunning later = some after := by
  suffices ∀ n {result} (before : Source.Program signature algebra program result),
      sizeOf before ≤ n →
      (before.cancelRunning first).isSome = (before.cancelRunning later).isSome ∧
        ∀ after, before.cancelRunning first = some after → after.cancelRunning later = some after from
    this (sizeOf before) before (Nat.le_refl _)
  intro n
  induction n with
  | zero =>
    intro result before bounded
    cases before <;> simp at bounded
  | succ n recurse =>
    intro result before bounded
    cases before with
    | evaluate | returned | failed => exact ⟨rfl, by intro after impossible; cases impossible⟩
    | cleaning identity original exit body =>
      exact ⟨rfl, by intro after same; cases same; simp only [Source.Program.cancelRunning, ExitInfo.cancel_keeps_first_reason]⟩
    | request operation attachment payload bodies future =>
      have stable := Source.Context.running_cancellation_stable first later future
      refine ⟨by simpa only [Source.Program.cancelRunning, Option.isSome_map] using stable.1, ?_⟩
      intro after accepted
      obtain ⟨updated, found, rfl⟩ := Option.map_eq_some_iff.mp accepted
      simp only [Source.Program.cancelRunning, stable.2 updated found, Option.map_some]
    | bind child next description | handler effect mode identity returnClause clauses bindings child
        | region identity child | protection identity cleanup bindings child | yielded child =>
      have stable := recurse child (by simp_all; omega)
      refine ⟨by simpa only [Source.Program.cancelRunning, Option.isSome_map] using stable.1, ?_⟩
      intro after accepted
      obtain ⟨updated, found, rfl⟩ := Option.map_eq_some_iff.mp accepted
      simp only [Source.Program.cancelRunning, stable.2 updated found, Option.map_some]


theorem Target.Stack.cancel_append_outer (reason : algebra.Reason)
    (inside : Target.Stack signature algebra program input middle)
    (outside after : Target.Stack signature algebra program middle result)
    (accepted : outside.cancelRunning reason = some after) :
    (inside.append outside).cancelRunning reason = some (inside.append after) := by
  induction inside with
  | done => exact accepted
  | push frame rest induction => simp only [Target.Stack.append, Target.Stack.cancelRunning, induction outside after accepted]

theorem Target.Stack.cancel_append_inner (reason : algebra.Reason)
    (inside : Target.Stack signature algebra program input middle)
    (outside : Target.Stack signature algebra program middle result)
    (absent : outside.cancelRunning reason = none) :
    (inside.append outside).cancelRunning reason =
      (inside.cancelRunning reason).map (fun after => after.append outside) := by
  induction inside with
  | done => exact absent
  | push frame rest induction =>
    simp only [Target.Stack.append, Target.Stack.cancelRunning, induction outside absent]
    cases found : rest.cancelRunning reason <;> cases frame <;> rfl

namespace Defunctionalization

theorem option_related_map {left : Option α} {right : Option β}
    {before : α → β → Prop} {after : γ → δ → Prop}
    (related : Option.Rel before left right) (first : α → γ) (second : β → δ)
    (preserves : ∀ a b, before a b → after (first a) (second b)) :
    Option.Rel after (left.map first) (right.map second) := by
  cases related with
  | none => exact .none
  | some matching => exact .some (preserves _ _ matching)

theorem option_related_some {left : Option α} {right : Option β} {relation : α → β → Prop}
    (related : Option.Rel relation left right) (accepted : left = some after) :
    ∃ targetAfter, right = some targetAfter ∧ relation after targetAfter := by
  rw [accepted] at related
  cases found : right with
  | none => rw [found] at related; cases related
  | some targetAfter =>
    rw [found] at related
    cases related with
    | some matching => exact ⟨_, rfl, matching⟩

/-- A running cleanup in the enclosing context takes precedence over every
cleanup inside the current computation, including a requested or yielded body. -/
theorem ProgramRelated.cancel_outside
    (related : ProgramRelated (source : Source.Program signature algebra program input) outside target)
    (reason : algebra.Reason) (accepted : outside.cancelRunning reason = some after) :
    ∃ targetAfter, target.cancelRunning reason = some targetAfter ∧ ProgramRelated source after targetAfter := by
  induction related with
  | evaluate body bindings future => exact ⟨_, by simp only [Target.Configuration.cancelRunning, accepted, Option.map_some], .evaluate body bindings _⟩
  | returned value future => exact ⟨_, by simp only [Target.Configuration.cancelRunning, accepted, Option.map_some], .returned value _⟩
  | failed fault future => exact ⟨_, by simp only [Target.Configuration.cancelRunning, accepted, Option.map_some], .failed fault _⟩
  | bind body bindings inner induction =>
    obtain ⟨final, step, matching⟩ := induction (by simp only [Target.Stack.cancelRunning, accepted]; rfl)
    exact ⟨final, step, .bind body bindings matching⟩
  | handler effect mode attachment returned clauses bindings inner induction =>
    obtain ⟨final, step, matching⟩ := induction (by simp only [Target.Stack.cancelRunning, accepted]; rfl)
    exact ⟨final, step, .handler effect mode attachment returned clauses bindings matching⟩
  | region identity inner induction =>
    obtain ⟨final, step, matching⟩ := induction (by simp only [Target.Stack.cancelRunning, accepted]; rfl)
    exact ⟨final, step, .region identity matching⟩
  | protection identity cleanup bindings inner induction =>
    obtain ⟨final, step, matching⟩ := induction (by simp only [Target.Stack.cancelRunning, accepted]; rfl)
    exact ⟨final, step, .protection identity cleanup bindings matching⟩
  | cleaning identity original exit inner induction =>
    obtain ⟨final, step, matching⟩ := induction (by simp only [Target.Stack.cancelRunning, accepted]; rfl)
    exact ⟨final, step, .cleaning identity original exit matching⟩
  | requested operation attachment payload bodies saved future =>
    exact ⟨_, by simp only [Target.Configuration.cancelRunning, Target.Stack.cancel_append_outer reason _ _ _ accepted, Option.map_some],
      .requested operation attachment payload bodies saved _⟩
  | yielded inner induction =>
    obtain ⟨final, step, matching⟩ := induction accepted
    exact ⟨_, by simp only [Target.Configuration.cancelRunning, step, Option.map_some], .yielded matching⟩
  | passthrough bindings inner induction =>
    obtain ⟨final, step, matching⟩ := induction (by simp only [Target.Stack.cancelRunning, accepted]; rfl)
    exact ⟨final, step, .passthrough bindings matching⟩

/-- With no enclosing running cleanup, each evaluator independently locates
the same running cleanup in the computation or its suspended request context. -/
theorem ProgramRelated.cancel_inside
    (related : ProgramRelated (source : Source.Program signature algebra program input) outside target)
    (reason : algebra.Reason) (absent : outside.cancelRunning reason = none) :
    Option.Rel (fun sourceAfter targetAfter => ProgramRelated sourceAfter outside targetAfter)
      (source.cancelRunning reason) (target.cancelRunning reason) := by
  induction related with
  | evaluate body bindings future => simp only [Source.Program.cancelRunning, Target.Configuration.cancelRunning, absent, Option.map_none]; exact .none
  | returned value future => simp only [Source.Program.cancelRunning, Target.Configuration.cancelRunning, absent, Option.map_none]; exact .none
  | failed fault future => simp only [Source.Program.cancelRunning, Target.Configuration.cancelRunning, absent, Option.map_none]; exact .none
  | bind body bindings inner induction =>
    have matched := induction (by simp only [Target.Stack.cancelRunning, absent])
    simpa only [Source.Program.bindAuthored, Source.Program.cancelRunning, Option.map_id, id_eq] using
      option_related_map matched (fun first => Source.Program.bindAuthored first body bindings) id
        (fun _ _ matching => ProgramRelated.bind body bindings matching)
  | handler effect mode attachment returned clauses bindings inner induction =>
    have matched := induction (by simp only [Target.Stack.cancelRunning, absent])
    simpa only [Source.Program.cancelRunning, Option.map_id, id_eq] using
      option_related_map matched (Source.Program.handler effect mode attachment returned clauses bindings) id
        (fun _ _ matching => ProgramRelated.handler effect mode attachment returned clauses bindings matching)
  | region identity inner induction =>
    have matched := induction (by simp only [Target.Stack.cancelRunning, absent])
    simpa only [Source.Program.cancelRunning, Option.map_id, id_eq] using
      option_related_map matched (Source.Program.region identity) id (fun _ _ matching => ProgramRelated.region identity matching)
  | protection identity cleanup bindings inner induction =>
    have matched := induction (by simp only [Target.Stack.cancelRunning, absent])
    simpa only [Source.Program.cancelRunning, Option.map_id, id_eq] using
      option_related_map matched (Source.Program.protection identity cleanup bindings) id
        (fun _ _ matching => ProgramRelated.protection identity cleanup bindings matching)
  | cleaning identity original exit inner induction =>
    obtain ⟨final, step, matching⟩ := inner.cancel_outside reason (by simp only [Target.Stack.cancelRunning, absent]; rfl)
    rw [step]
    exact .some (.cleaning identity original (exit.cancel reason) matching)
  | requested operation attachment payload bodies saved future =>
    have matched := running_cancellation_corresponds reason saved
    simp only [Source.Program.cancelRunning, Target.Configuration.cancelRunning,
      Target.Stack.cancel_append_inner reason _ _ absent]
    simpa only [Option.map_map, Function.comp_def] using option_related_map matched
      (Source.Program.request operation attachment payload bodies)
      (fun after => Target.Configuration.requested operation attachment (value payload) (environment bodies) (after.append future))
      (fun _ _ matching => ProgramRelated.requested operation attachment payload bodies matching future)
  | yielded inner induction =>
    have matched := induction absent
    exact option_related_map matched Source.Program.yielded Target.Configuration.yielded
      (fun _ _ matching => ProgramRelated.yielded matching)
  | passthrough bindings inner induction =>
    have matched := induction (by simp only [Target.Stack.cancelRunning, absent])
    simpa only [Option.map_id, id_eq] using option_related_map matched id id
      (fun _ _ matching => ProgramRelated.passthrough bindings matching)

end Defunctionalization
end BoundaryV2.Generalized
