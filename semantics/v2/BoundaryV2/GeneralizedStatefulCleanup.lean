import BoundaryV2.GeneralizedExit
import BoundaryV2.GeneralizedStateExecution

namespace BoundaryV2.Generalized.ExitComposition

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

/-- The phase owns the sole cursor. Resource state is held once, in the same
control store and cells used by ordinary execution. Lifecycle snapshots of the
owning fields are projections, not a second mutable resource inventory. -/
structure Runtime (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) where
  id : Id .obligation
  phase : Phase signature algebra program
  store : Target.ControlHeap signature algebra program
  cells : Cells signature algebra (fun context result => Target.Code signature algebra program context [] result)
  liveRegions : List (Id .region)
  exit : ExitInfo algebra.Fault algebra.Reason

def Runtime.fields (runtime : Runtime signature algebra program) : List UseScope.Field :=
  runtime.store.fields.active ++ runtime.store.fields.retained ++ runtime.cells.fields

def Runtime.physicalInventory (runtime : Runtime signature algebra program) : List (Id .custody) :=
  UseScope.inventory runtime.store.fields ++ UseScope.tokens runtime.cells.fields

def Runtime.obligation (runtime : Runtime signature algebra program) : Obligation signature algebra program :=
  ⟨runtime.id, runtime.phase, runtime.fields, runtime.exit⟩

theorem Runtime.fields_preserve_physical_inventory (runtime : Runtime signature algebra program) :
    UseScope.tokens runtime.fields = runtime.physicalInventory := by
  simp only [Runtime.fields, Runtime.physicalInventory, UseScope.inventory, UseScope.tokens_append, List.append_assoc]

variable [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]

inductive RuntimeStep (table : Target.Definitions signature algebra program) :
    Runtime signature algebra program → Nat → Runtime signature algebra program → Prop where
  | lifecycle
      (step : LifecycleStep ⟨identity, before, store.fields.active ++ store.fields.retained ++ cells.fields, exit⟩ initiations
        ⟨identity, after, store.fields.active ++ store.fields.retained ++ cells.fields, afterExit⟩) :
      RuntimeStep table ⟨identity, before, store, cells, regions, exit⟩ initiations
        ⟨identity, after, store, cells, regions, afterExit⟩
  | execute {before after : Target.State signature algebra program .unit} :
      Target.ExecutionStep table before after →
      RuntimeStep table ⟨identity, .running before.control.configuration .active, before.control.store, before.cells, before.liveRegions, exit⟩ 0
        ⟨identity, .running after.control.configuration .active, after.control.store, after.cells, after.liveRegions, exit⟩

variable {table : Target.Definitions signature algebra program}

theorem RuntimeStep.initiation_conservation {before after : Runtime signature algebra program} (step : RuntimeStep table before initiations after) :
    initiations + after.phase.right = before.phase.right := by
  cases step with
  | lifecycle step => exact step.initiation_conservation
  | execute step => rfl

inductive RuntimeSteps (table : Target.Definitions signature algebra program) :
    Runtime signature algebra program → Nat → Runtime signature algebra program → Prop where
  | refl : RuntimeSteps table runtime 0 runtime
  | cons : RuntimeStep table first count middle → RuntimeSteps table middle rest last → RuntimeSteps table first (count + rest) last

variable {before middle after : Runtime signature algebra program}

theorem RuntimeSteps.trans (first : RuntimeSteps table before count middle) (second : RuntimeSteps table middle rest after) :
    RuntimeSteps table before (count + rest) after := by
  induction first with
  | refl => simpa only [Nat.zero_add] using second
  | cons step tail induction => simpa only [Nat.add_assoc] using RuntimeSteps.cons step (induction second)

theorem stateful_cleanup_execution {before after : Target.State signature algebra program .unit}
    (steps : Target.ExecutionSteps table before count after) :
    RuntimeSteps table
      ⟨identity, .running before.control.configuration .active, before.control.store, before.cells, before.liveRegions, exit⟩ 0
      ⟨identity, .running after.control.configuration .active, after.control.store, after.cells, after.liveRegions, exit⟩ := by
  induction steps with
  | refl => exact .refl
  | cons step tail induction => exact .cons (.execute step) induction

theorem RuntimeSteps.initiation_conservation (steps : RuntimeSteps table before initiations after) :
    initiations + after.phase.right = before.phase.right := by
  induction steps with
  | refl => simp
  | cons step tail induction =>
    rw [Nat.add_assoc, induction]
    exact step.initiation_conservation

theorem RuntimeSteps.at_most_one_initiation (steps : RuntimeSteps table before initiations after) : initiations ≤ 1 := by
  have conserved := steps.initiation_conservation
  have bounded : before.phase.right ≤ 1 := by cases before.phase <;> simp [Phase.right]
  omega

theorem RuntimeSteps.running_never_restarts
    (steps : RuntimeSteps table ⟨identity, .running cursor location, store, cells, regions, exit⟩ initiations after) : initiations = 0 := by
  have conserved := steps.initiation_conservation
  simp only [Phase.right] at conserved
  omega

end BoundaryV2.Generalized.ExitComposition
