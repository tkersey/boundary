import BoundaryV2.GeneralizedDisposal
import BoundaryV2.GeneralizedPackages
import BoundaryV2.GeneralizedComputationHandoff

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {Body Before After : List (TypeOf signature) → TypeOf signature → Type}

def Environment.disposalValues : {types : List (TypeOf signature)} → Environment signature algebra Body types →
    List (Sigma (Value signature algebra Body))
  | _, .nil => []
  | _, .cons value rest => ⟨_, value⟩ :: rest.disposalValues

def Value.hasActiveRoot (fields : UseScope.State) (value : Value signature algebra Body type) : Bool :=
  value.roots.any fun (token, owner) => (UseScope.takeGrant token owner (UseScope.activeFields fields.active)).isSome

theorem Value.roots_map (transform : ∀ context type, Before context type → After context type)
    (value : Value signature algebra Before type) : (value.map transform).roots = value.roots := by
  cases value with
  | datum | closure | continuation | package | cell | exit => rfl
  | pair first second => simp only [Value.map, Value.roots, roots_map transform first, roots_map transform second]
  | left value | right value => exact roots_map transform value
termination_by sizeOf value

theorem Value.active_root_check_commutes (transform : ∀ context type, Before context type → After context type)
    (fields : UseScope.State) (value : Value signature algebra Before type) :
    (value.map transform).hasActiveRoot fields = value.hasActiveRoot fields := by
  simp only [Value.hasActiveRoot, Value.roots_map]

theorem Environment.disposal_values_map (transform : ∀ context type, Before context type → After context type)
    (values : Environment signature algebra Before types) :
    (values.map transform).disposalValues = values.disposalValues.map (fun value => ⟨value.fst, value.snd.map transform⟩) := by
  cases values with
  | nil => rfl
  | cons value rest => simp only [Environment.map, Environment.disposalValues, List.map_cons, disposal_values_map transform rest]
termination_by sizeOf values

namespace ExitComposition

variable {program : List (BodyType signature.Data signature.Effect)}

abbrev DisposalValues (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) := List (Sigma (Target.RuntimeValue signature algebra program))

/-- Queue entries are views. The current runtime, or the active control
disposal, owns all physical fields. No older resource snapshot is retained. -/
inductive ValueDisposal (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) where
  | ready : Runtime signature algebra program → DisposalValues signature algebra program → ValueDisposal signature algebra program
  | control : Target.Disposal signature algebra program .unit → DisposalValues signature algebra program → ValueDisposal signature algebra program

def ValueDisposal.start (runtime : Runtime signature algebra program) (value : Target.RuntimeValue signature algebra program type) :
    ValueDisposal signature algebra program := .ready runtime [⟨type, value⟩]

def ValueDisposal.finished : ValueDisposal signature algebra program → Option (Runtime signature algebra program)
  | .ready runtime [] => some runtime
  | _ => none

variable [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]

/-- Structural order follows the value/capture order. Sealed containers use
their existing physical-field handoffs before their contents enter the queue. -/
inductive ValueDisposalStep (table : Target.Definitions signature algebra program) :
    ValueDisposal signature algebra program → ValueDisposal signature algebra program → Prop where
  | stale : value.hasActiveRoot runtime.store.fields = false →
      ValueDisposalStep table (.ready runtime (⟨type, value⟩ :: rest)) (.ready runtime rest)
  | pair : ValueDisposalStep table (.ready runtime (⟨_, .pair first second⟩ :: rest))
      (.ready runtime (⟨_, first⟩ :: ⟨_, second⟩ :: rest))
  | left : ValueDisposalStep table (.ready runtime (⟨_, .left value⟩ :: rest)) (.ready runtime (⟨_, value⟩ :: rest))
  | right : ValueDisposalStep table (.ready runtime (⟨_, .right value⟩ :: rest)) (.ready runtime (⟨_, value⟩ :: rest))
  | datumPair : ValueDisposalStep table (.ready runtime (⟨_, .datum (.pair first second)⟩ :: rest))
      (.ready runtime (⟨_, .datum first⟩ :: ⟨_, .datum second⟩ :: rest))
  | datumLeft : ValueDisposalStep table (.ready runtime (⟨_, .datum (.left value)⟩ :: rest))
      (.ready runtime (⟨_, .datum value⟩ :: rest))
  | datumRight : ValueDisposalStep table (.ready runtime (⟨_, .datum (.right value)⟩ :: rest))
      (.ready runtime (⟨_, .datum value⟩ :: rest))
  | package : PackageHandoff value token owner runtime.store.fields fields →
      ValueDisposalStep table (.ready runtime (⟨_, .package token owner value⟩ :: rest))
        (.ready { runtime with store := { runtime.store with fields := fields } } (⟨_, value⟩ :: rest))
  | closure {body : Target.Code signature algebra program (parameters ++ capturedTypes) [] result} :
      ComputationHandoff captured use authority runtime.store.fields fields →
      ValueDisposalStep table (.ready runtime (⟨_, .closure (use := use) body captured authority⟩ :: rest))
        (.ready { runtime with store := { runtime.store with fields := fields } } (captured.disposalValues ++ rest))
  | resource : UseScope.takeGrant token owner (UseScope.activeFields runtime.store.fields.active) = some active →
      ValueDisposalStep table (.ready runtime (⟨_, .datum (.resource identity token owner)⟩ :: rest))
        (.ready { runtime with store := { runtime.store with
          fields := ⟨active, runtime.store.fields.retained, token :: runtime.store.fields.spent⟩ } } rest)
  | enterControl : UseScope.disposeOwned ⟨identity, authority, owner⟩ runtime.store = some acquired →
      ValueDisposalStep table (.ready runtime (⟨_, .continuation identity (some (authority, owner))⟩ :: rest))
        (.control ⟨acquired.future.fst.answer, .seeking
          ⟨runtime.id, .finished .abandoned, acquired.store, runtime.cells, runtime.liveRegions, runtime.exit⟩
          acquired.future.snd.future, .done⟩ rest)
  | control : Target.DisposalStep table before selected after →
      ValueDisposalStep table (.control before rest) (.control after rest)
  | nestedControl (scope : ScopeExit signature algebra program answer) :
      NestedSteps table (NestedCleanup.start scope.cleanup) initiations after → after.finished = some runtime →
      ValueDisposalStep table (.control ⟨answer, .cleaning scope, .done⟩ rest)
        (.control ⟨answer, .cleaning ⟨runtime, scope.resume⟩, .done⟩ rest)
  | finishControl : ValueDisposalStep table (.control ⟨answer, .complete runtime, .done⟩ rest) (.ready runtime rest)

inductive ValueDisposalSteps (table : Target.Definitions signature algebra program) :
    ValueDisposal signature algebra program → Nat → ValueDisposal signature algebra program → Prop where
  | refl : ValueDisposalSteps table state 0 state
  | cons : ValueDisposalStep table before middle → ValueDisposalSteps table middle count after → ValueDisposalSteps table before (count + 1) after

theorem ValueDisposalSteps.trans {table : Target.Definitions signature algebra program}
    (first : ValueDisposalSteps table before count middle) (second : ValueDisposalSteps table middle rest after) :
    ValueDisposalSteps table before (count + rest) after := by
  induction first with
  | refl => simpa using second
  | cons step tail induction => simpa only [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using ValueDisposalSteps.cons step (induction second)

theorem active_control_disposal_keeps_its_remaining_queue
    {table : Target.Definitions signature algebra program}
    {before after : Target.Disposal signature algebra program .unit}
    (step : ValueDisposalStep table (.control before first) (.control after second)) : first = second := by
  cases step <;> rfl

theorem structural_disposal_preserves_store_validity
    {table : Target.Definitions signature algebra program}
    {before after : Runtime signature algebra program}
    (step : ValueDisposalStep table (.ready before first) (.ready after second))
    (valid : UseScope.ControlStore.Valid before.store) : UseScope.ControlStore.Valid after.store := by
  cases step with
  | stale | pair | left | right | datumPair | datumLeft | datumRight => exact valid
  | package handoff => exact ⟨handoff.preserves_ownership valid.1, valid.2⟩
  | closure handoff => exact ⟨handoff.preserves_ownership valid.1, valid.2⟩
  | resource grant => exact ⟨UseScope.grant_consumption_preserves valid.1 grant, valid.2⟩

theorem structural_disposal_keeps_exit_and_live_storage
    {table : Target.Definitions signature algebra program}
    {before after : Runtime signature algebra program}
    (step : ValueDisposalStep table (.ready before first) (.ready after second)) :
    after.exit = before.exit ∧ after.cells = before.cells ∧ after.liveRegions = before.liveRegions := by
  cases step <;> exact ⟨rfl, rfl, rfl⟩

theorem structural_disposal_never_restores_spent_authority
    {table : Target.Definitions signature algebra program}
    {before after : Runtime signature algebra program}
    (step : ValueDisposalStep table (.ready before first) (.ready after second)) :
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

end ExitComposition
end BoundaryV2.Generalized
