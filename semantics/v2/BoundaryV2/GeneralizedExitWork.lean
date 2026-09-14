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

/-- Only the active phase owns the runtime. A value disposal keeps the region
identity, outside continuation, and offered-cell names, not a heap snapshot. -/
inductive RegionDisposal (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (result : TypeOf signature) where
  | offering {input : TypeOf signature} : RegionHandoff signature algebra program input result → RegionDisposal signature algebra program result
  | disposing {input : TypeOf signature} : Id .region → Target.Stack signature algebra program input result →
      List (Id .cell) → ValueDisposal signature algebra program → RegionDisposal signature algebra program result

def RegionDisposal.begin (resolution : Resolution signature algebra program result) :
    Option (RegionDisposal signature algebra program result) :=
  if !resolution.cleanupFinished then none else
  match resolution with
  | .unwind runtime future => match Target.unwindBoundary future with
    | .region identity outside => some (.offering (beginRegionHandoff identity runtime outside))
    | _ => none
  | _ => none

def RegionDisposal.offer : RegionDisposal signature algebra program result → Option (RegionDisposal signature algebra program result)
  | .offering handoff =>
    if !(Resolution.unwind handoff.runtime handoff.outside).cleanupFinished then none else
    handoff.offerNext.map fun (value, after) =>
      .disposing after.identity after.outside after.kept (ValueDisposal.start after.runtime value.snd)
  | _ => none

def RegionDisposal.returnValue : RegionDisposal signature algebra program result → Option (RegionDisposal signature algebra program result)
  | .disposing identity outside kept work => work.finished.map fun runtime => .offering ⟨identity, runtime, outside, kept⟩
  | _ => none

theorem unfinished_cleanup_cannot_offer_region_cells
    (handoff : RegionHandoff signature algebra program input result)
    (unfinished : (Resolution.unwind handoff.runtime handoff.outside).cleanupFinished = false) :
    RegionDisposal.offer (.offering handoff) = none := by
  change (if !(Resolution.unwind handoff.runtime handoff.outside).cleanupFinished then none else _) = none
  simp only [unfinished, Bool.not_false, if_true]

/-- An exhausted offer loop does not itself authorize retirement. The existing
retirement operation checks completion, physical fields, and all surviving roots. -/
def RegionDisposal.finish (external : List Reference) :
    RegionDisposal signature algebra program result → Option (Resolution signature algebra program result)
  | .offering handoff =>
    if handoff.offerNext.isNone then (Resolution.unwind handoff.runtime handoff.outside).retireRegions [handoff.identity] external
    else none
  | _ => none

/-- A region detour owns resources in RegionDisposal. Only the suspended
cleanup's information and parent continuations accompany it, never old memory. -/
inductive NestedProgress (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) where
  | active : NestedCleanup signature algebra program → NestedProgress signature algebra program
  | region : CleanupInfo algebra.Fault algebra.Reason → List (CleanupParent signature algebra program) →
      RegionDisposal signature algebra program .unit → NestedProgress signature algebra program

def ResumePoint.references : ResumePoint signature algebra program result → List Reference
  | .returned value outside => Target.valueReferences value ++ outside.installationReferences
  | .unwind outside => outside.installationReferences

def CleanupParent.references (parent : CleanupParent signature algebra program) : List Reference :=
  .name .obligation parent.info.id :: parent.resume.references

def NestedProgress.enterRegion : NestedProgress signature algebra program → Option (NestedProgress signature algebra program)
  | .active machine => match machine.focus with
    | .unwinding exit outside =>
      let stopped : Runtime signature algebra program :=
        ⟨machine.current.id, .finished .abandoned, machine.memory.store, machine.memory.cells, machine.memory.regions, exit⟩
      (RegionDisposal.begin (.unwind stopped outside)).map fun work => .region machine.current machine.parents work
    | _ => none
  | .region _ _ _ => none

def NestedProgress.finishRegion (external : List Reference) :
    NestedProgress signature algebra program → Option (NestedProgress signature algebra program)
  | .region current parents work =>
    (work.finish (parents.flatMap CleanupParent.references ++ external)).bind fun resolution =>
      match resolution with
      | .unwind runtime outside => some (.active
          ⟨CleanupMemory.ofRuntime runtime, current, .unwinding runtime.exit outside, parents⟩)
      | .reenter _ _ => none
  | .active _ => none

def NestedProgress.finished : NestedProgress signature algebra program → Option (Runtime signature algebra program)
  | .active machine => machine.finished
  | .region _ _ _ => none

def NestedProgress.cancel (reason : algebra.Reason) : NestedProgress signature algebra program → NestedProgress signature algebra program
  | .active machine => .active (machine.cancel reason)
  | .region current parents work => .region
      (if parents.isEmpty then { current with exit := current.exit.cancel reason } else current)
      (cancelOutermostParent reason parents) work

theorem nested_region_entry_uses_current_resources
    (machine : NestedCleanup signature algebra program)
    (focused : machine.focus = .unwinding exit future)
    (boundary : Target.unwindBoundary future = .region identity outside) :
    NestedProgress.enterRegion (.active machine) = some (.region machine.current machine.parents
      (.offering (beginRegionHandoff identity
        ⟨machine.current.id, .finished .abandoned, machine.memory.store, machine.memory.cells, machine.memory.regions, exit⟩ outside))) := by
  simp only [NestedProgress.enterRegion, focused, RegionDisposal.begin, Resolution.cleanupFinished, Bool.not_true,
    Bool.false_eq_true, ↓reduceIte, boundary, Option.map_some]

theorem nested_region_prevents_completion (current : CleanupInfo algebra.Fault algebra.Reason)
    (parents : List (CleanupParent signature algebra program)) (work : RegionDisposal signature algebra program .unit) :
    NestedProgress.finished (.region current parents work) = none := rfl

/-- Parent continuations and saved results remain roots of region retirement;
the nested caller cannot accidentally omit them from the local lifetime check. -/
theorem nested_region_exit_preserves_current_resources
    (current : CleanupInfo algebra.Fault algebra.Reason) (parents : List (CleanupParent signature algebra program))
    (work : RegionDisposal signature algebra program .unit)
    (accepted : NestedProgress.finishRegion external (.region current parents work) = some after) :
    ∃ (input : TypeOf signature), ∃ (runtime : Runtime signature algebra program)
      (outside : Target.Stack signature algebra program input .unit),
      work.finish (parents.flatMap CleanupParent.references ++ external) = some (.unwind runtime outside) ∧
      after = .active ⟨CleanupMemory.ofRuntime runtime, current, .unwinding runtime.exit outside, parents⟩ := by
  obtain ⟨resolution, finished, result⟩ := Option.bind_eq_some_iff.mp accepted
  cases resolution with
  | reenter => cases result
  | unwind runtime outside =>
    cases result
    exact ⟨_, runtime, outside, finished, rfl⟩

theorem nested_region_cancellation_keeps_the_active_work
    (reason : algebra.Reason) (current : CleanupInfo algebra.Fault algebra.Reason)
    (parents : List (CleanupParent signature algebra program)) (work : RegionDisposal signature algebra program .unit) :
    NestedProgress.cancel reason (.region current parents work) =
      .region (if parents.isEmpty then { current with exit := current.exit.cancel reason } else current)
        (cancelOutermostParent reason parents) work := rfl

end ExitComposition
end BoundaryV2.Generalized
