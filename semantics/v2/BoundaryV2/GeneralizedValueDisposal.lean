import BoundaryV2.GeneralizedExitTransitions

namespace BoundaryV2.Generalized.ExitComposition

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

variable [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]

theorem ValueDisposalSteps.trans {table : Target.Definitions signature algebra program}
    (first : ValueDisposalSteps table before count middle retained) (second : ValueDisposalSteps table middle rest after retained) :
    ValueDisposalSteps table before (count + rest) after retained := by
  induction count generalizing before with
  | zero => cases first; simpa using second
  | succ count induction =>
    cases first with
    | cons step tail => simpa only [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using ValueDisposalSteps.cons step (induction tail)

/-- Each nested transition remains a visible disposal state. In particular,
the prefix may end at a yield, request, capture, or unfinished region handoff. -/
theorem ValueDisposalSteps.of_nested {table : Target.Definitions signature algebra program}
    {before after : NestedProgress signature algebra program}
    (resume : ResumePoint signature algebra program answer) (pending : DisposalValues signature algebra program)
    (steps : NestedProgressSteps table before count after
      (resume.references ++ pending.flatMap (fun value => Target.valueReferences value.snd) ++ retained)) :
    ValueDisposalSteps table (.nested before resume pending) count (.nested after resume pending) retained := by
  induction count generalizing before with
  | zero => cases steps; exact .refl
  | succ count induction =>
    cases steps with
    | cons step tail => exact .cons (.nested step) (induction tail)

/-- The former whole-run constructor is now a consequence of entry, the
visible finite run, and checked completion with its current runtime. -/
theorem ValueDisposalSteps.nested_cleanup {table : Target.Definitions signature algebra program}
    (scope : ScopeExit signature algebra program answer) (pending : DisposalValues signature algebra program)
    (steps : NestedProgressSteps table (.active (NestedCleanup.start scope.cleanup)) count after
      (scope.resume.references ++ pending.flatMap (fun value => Target.valueReferences value.snd) ++ retained))
    (finished : after.finished = some runtime) :
    ValueDisposalSteps table (.control ⟨answer, .cleaning scope, .done⟩ pending) (count + 2)
      (.control ⟨answer, .cleaning ⟨runtime, scope.resume⟩, .done⟩ pending) retained := by
  have run := ValueDisposalSteps.of_nested scope.resume pending steps
  simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using
    ((ValueDisposalSteps.cons (.enterNested scope) .refl).trans run).trans (.cons (.leaveNested finished) .refl)

theorem nested_value_disposal_keeps_its_pending_queue
    {table : Target.Definitions signature algebra program}
    {before after : NestedProgress signature algebra program}
    {resume : ResumePoint signature algebra program answer}
    (step : ValueDisposalStep table (.nested before resume first) (.nested after resume second) retained) :
    first = second := by cases step; rfl

theorem nested_value_disposal_cannot_skip_to_pending_values
    {table : Target.Definitions signature algebra program}
    (machine : NestedProgress signature algebra program) (resume : ResumePoint signature algebra program answer)
    (pending : DisposalValues signature algebra program) (runtime : Runtime signature algebra program) :
    ¬ ValueDisposalStep table (.nested machine resume pending) (.ready runtime rest) retained := by
  intro step
  cases step

theorem active_control_disposal_keeps_its_remaining_queue
    {table : Target.Definitions signature algebra program}
    {before after : Target.Disposal signature algebra program .unit}
    (step : ValueDisposalStep table (.control before first) (.control after second) retained) : first = second := by
  cases step <;> rfl

theorem structural_disposal_preserves_store_validity
    {table : Target.Definitions signature algebra program}
    {before after : Runtime signature algebra program}
    (step : ValueDisposalStep table (.ready before first) (.ready after second) retained)
    (valid : UseScope.ControlStore.Valid before.store) : UseScope.ControlStore.Valid after.store := by
  cases step with
  | stale | pair | left | right | datumPair | datumLeft | datumRight => exact valid
  | package handoff => exact ⟨handoff.preserves_ownership valid.1, valid.2⟩
  | closure handoff => exact ⟨handoff.preserves_ownership valid.1, valid.2⟩
  | resource grant => exact ⟨UseScope.grant_consumption_preserves valid.1 grant, valid.2⟩

theorem structural_disposal_keeps_exit_and_live_storage
    {table : Target.Definitions signature algebra program}
    {before after : Runtime signature algebra program}
    (step : ValueDisposalStep table (.ready before first) (.ready after second) retained) :
    after.exit = before.exit ∧ after.cells = before.cells ∧ after.liveRegions = before.liveRegions := by
  cases step <;> exact ⟨rfl, rfl, rfl⟩

theorem structural_disposal_never_restores_spent_authority
    {table : Target.Definitions signature algebra program}
    {before after : Runtime signature algebra program}
    (step : ValueDisposalStep table (.ready before first) (.ready after second) retained) :
    ∀ token ∈ before.store.fields.spent, token ∈ after.store.fields.spent := by
  cases step with
  | stale | pair | left | right | datumPair | datumLeft | datumRight => exact fun _ member => member
  | package handoff => rw [handoff.spends_outer_grant]; exact fun _ member => List.mem_cons_of_mem _ member
  | closure handoff => exact handoff.preserves_spent
  | resource => exact fun _ member => List.mem_cons_of_mem _ member

omit [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)] in
theorem unfinished_control_cannot_finish_all_values
    (control : Target.Disposal signature algebra program .unit) (pending : DisposalValues signature algebra program) :
    ValueDisposal.finished (.control control pending) = none := rfl

end BoundaryV2.Generalized.ExitComposition
