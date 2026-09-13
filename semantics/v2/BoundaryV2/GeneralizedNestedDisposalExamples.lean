import BoundaryV2.GeneralizedDisposalExamples

namespace BoundaryV2.Generalized.Examples.NestedDisposal

open ExitComposition

def cleanup : Source.Computation signature algebra [] [.exit] .unit :=
  .protect (.yieldThen (.returnValue (.datum .unit))) (.returnValue (.datum .unit))
def cleanupCode := Defunctionalization.computation cleanup
def innerCode : Target.Code signature algebra [] [.exit, .exit] [] .unit := .yieldThen (.push .unit .ret)
def sourceFuture : Source.Resumption signature algebra [] .shallow .choose (.leaf .boolean) .unit :=
  ⟨⟨8⟩, .push (.protection ⟨7⟩ cleanup .nil) (.push (.bindAuthored disposalReturn .nil) .done)⟩
def targetFuture : Target.Resumption signature algebra [] .shallow .choose (.leaf .boolean) .unit :=
  ⟨⟨8⟩, .push (.protection ⟨7⟩ cleanupCode .nil) disposalTail⟩
def sourceStore : Source.ControlHeap signature algebra [] :=
  { disposalSourceStore with controls := [⟨⟨10⟩, ⟨100⟩, .linear, ⟨disposeShape, sourceFuture⟩⟩] }
def targetStore : Target.ControlHeap signature algebra [] :=
  { disposalTargetStore with controls := [⟨⟨10⟩, ⟨100⟩, .linear, ⟨disposeShape, targetFuture⟩⟩] }
def start : Target.DisposalStart signature algebra [] (.leaf .integer) :=
  { disposalTargetStart with future := ⟨disposeShape, targetFuture⟩ }

theorem authored_nested_dispose_has_corresponding_owned_entry :
    Source.DisposeEntry (.nil : Source.Definitions signature algebra [])
      ⟨⟨sourceStore, disposalSourceOutside.plug (.evaluate (.dispose (.reference .here)) disposalBindings)⟩, [], []⟩
      ⟨disposalSourceAfter, [], [], ⟨disposeShape, sourceFuture⟩, disposalSourceOutside⟩ ∧
    ∃ targetStart count, 0 < count ∧ Defunctionalization.DisposalStartRelated
      ⟨disposalSourceAfter, [], [], ⟨disposeShape, sourceFuture⟩, disposalSourceOutside⟩ targetStart ∧
      Target.DisposalRun (.nil : Target.Definitions signature algebra [])
        (.evaluating ⟨⟨targetStore, .code (Defunctionalization.computation (.dispose (.reference .here)))
          (Defunctionalization.environment disposalBindings) .nil disposalTargetOutside⟩, [], []⟩) count (.disposing targetStart.begin) := by
  have future : Defunctionalization.ResumptionRelated sourceFuture targetFuture :=
    ⟨rfl, .push (.protection ⟨7⟩ cleanup .nil) (.push (.bind disposalReturn .nil) .done)⟩
  exact Defunctionalization.compiled_disposal_entry (signature := signature) (algebra := algebra)
    .nil .linear (.reference .here) disposalBindings disposeView [] []
    (sourceStore := sourceStore) (evaluated := sourceStore) (targetStore := targetStore) .reference
    ⟨rfl, .cons ⟨rfl, rfl, rfl, .same future⟩ .nil, .nil⟩
    ⟨disposalSourceAfter, ⟨disposeShape, sourceFuture⟩⟩ rfl (.push (.bind disposalCaller .nil) .done)

abbrev Machine := NestedCleanup signature algebra []
def abandonedExit : ExitInfo Fault String := ⟨.abandoned, [], none⟩
def normalExit : ExitInfo Fault String := ⟨.normal, [], none⟩
def diagnostics : CleanupDiagnostics Fault String := ⟨[], none⟩
def rootBindings : Target.RuntimeEnvironment signature algebra [] [.exit] := .cons (.exit abandonedExit) .nil
def innerBindings : Target.RuntimeEnvironment signature algebra [] [.exit, .exit] := .cons (.exit normalExit) rootBindings
def rootPending := disposalRuntime (.pending ⟨[], cleanupCode, .nil⟩)
def rootScope : ScopeExit signature algebra [] .unit := ⟨rootPending, .unwind disposalTail⟩
def root : Machine := NestedCleanup.start rootPending
def rootStarted : Machine := { root with focus := .executing (.running (.code cleanupCode rootBindings .nil .done) .active) diagnostics }
def rootOutside : Target.Stack signature algebra [] .unit .unit := .push (.returnTo .ret rootBindings .nil) .done
def nestedOutside : Target.Stack signature algebra [] .unit .unit := .push (.protection ⟨8⟩ innerCode rootBindings) rootOutside
def rootBody : Machine := { root with focus := .executing (.running (.code (.push .unit .ret) rootBindings .nil nestedOutside) .active) diagnostics }
def rootReturned : Machine := { root with focus := .executing (.running (.returned (.datum .unit) nestedOutside) .active) diagnostics }
def child : Machine := rootReturned.push
  ⟨⟨⟨8⟩, .pending ⟨[.exit], innerCode, rootBindings⟩, disposalTargetAfter, [], [], normalExit⟩,
    .returned (.datum .unit) rootOutside⟩
def childStarted : Machine := { child with focus := .executing (.running (.code innerCode innerBindings .nil .done) .active) diagnostics }
def yieldCursor : Cursor signature algebra [] := .yielded (.code (.push .unit .ret) innerBindings .nil .done)
def childYielded : Machine := { child with focus := .executing (.running yieldCursor .active) diagnostics }
def childParked : Machine := { child with focus := .executing (.running yieldCursor .parked) diagnostics }
def childResumed : Machine := { child with focus := .executing (.running (.code (.push .unit .ret) innerBindings .nil .done) .active) diagnostics }
def childReturned : Machine := { child with focus := .executing (.running (.returned (.datum .unit) .done) .active) diagnostics }
def childFinished : Machine := { child with focus := .executing (.finished .returned) diagnostics }
def rootRejoined : Machine := { root with focus := .executing (.running (.returned (.datum .unit) rootOutside) .active) diagnostics }
def rootReady : Machine := { root with focus := .executing (.running (.returned (.datum .unit) .done) .active) diagnostics }
def rootFinished : Machine := { root with focus := .executing (.finished .returned) diagnostics }

def state (cursor : Cursor signature algebra []) : Target.State signature algebra [] .unit :=
  ⟨⟨disposalTargetAfter, cursor⟩, [], []⟩

theorem saved_cleanup_enters_its_nested_protection :
    NestedSteps (.nil : Target.Definitions signature algebra []) root 2 childStarted := by
  have beginRoot : NestedStep (.nil : Target.Definitions signature algebra []) root 1 rootStarted :=
    .local (after := root.current.runtime (.running (.code cleanupCode rootBindings .nil .done) .active) root.memory)
      (.lifecycle .begin) rfl rfl
  have enter : Target.ExecutionStep (.nil : Target.Definitions signature algebra [])
      (state (.code cleanupCode rootBindings .nil .done)) (state (.code (.push .unit .ret) rootBindings .nil nestedOutside)) :=
    .enterProtection [] rfl
  have body : Target.ExecutionSteps (.nil : Target.Definitions signature algebra [])
      (state (.code (.push .unit .ret) rootBindings .nil nestedOutside)) 2 (state (.returned (.datum .unit) nestedOutside)) :=
    .cons (middle := state (.code .ret rootBindings (.cons (.datum .unit) .nil) nestedOutside))
      (.cell (.ordinary (.operand .push))) (.single (.cell (.ordinary .returned)))
  have begunChild : NestedStep (.nil : Target.Definitions signature algebra []) child 1 childStarted :=
    .local (after := child.current.runtime (.running (.code innerCode innerBindings .nil .done) .active) child.memory)
      (.lifecycle .begin) rfl rfl
  have enterChild : NestedSteps (.nil : Target.Definitions signature algebra []) rootReturned 1 childStarted :=
    .cons (count := 0) (rest := 1) (.enter (show rootReturned.enter = some child from rfl)) (.cons begunChild .refl)
  have inside := (nested_target_execution body root.current diagnostics root.parents).trans enterChild
  exact .cons beginRoot (.cons (nested_single_execution enter root.current diagnostics root.parents) inside)

theorem nested_disposal_yields_without_returning_to_the_caller :
    NestedSteps (.nil : Target.Definitions signature algebra []) childStarted 0 childParked ∧ childParked.finished = none := by
  have yielded : Target.ExecutionStep (.nil : Target.Definitions signature algebra [])
      (state (.code innerCode innerBindings .nil .done)) (state yieldCursor) := .cell (.ordinary .yield)
  have parked : NestedStep (.nil : Target.Definitions signature algebra []) childYielded 0 childParked :=
    .local (after := child.current.runtime (.running yieldCursor .parked) child.memory) (.lifecycle .parkYield) rfl rfl
  exact ⟨.cons (nested_single_execution yielded child.current diagnostics child.parents) (.cons parked .refl), rfl⟩

theorem nested_disposal_resumes_and_finishes_both_cleanups :
    NestedSteps (.nil : Target.Definitions signature algebra []) childParked 0 rootFinished ∧
    rootFinished.finished = some disposalCompleted := by
  have resumed : NestedStep (.nil : Target.Definitions signature algebra []) childParked 0 childResumed :=
    .local (after := child.current.runtime (.running (.code (.push .unit .ret) innerBindings .nil .done) .active) child.memory)
      (.lifecycle .continueYield) rfl rfl
  have body : Target.ExecutionSteps (.nil : Target.Definitions signature algebra [])
      (state (.code (.push .unit .ret) innerBindings .nil .done)) 2 (state (.returned (.datum .unit) .done)) :=
    .cons (middle := state (.code .ret innerBindings (.cons (.datum .unit) .nil) .done))
      (.cell (.ordinary (.operand .push))) (.single (.cell (.ordinary .returned)))
  have caller : Target.ExecutionSteps (.nil : Target.Definitions signature algebra [])
      (state (.returned (.datum .unit) rootOutside)) 2 (state (.returned (.datum .unit) .done)) :=
    .cons (middle := state (.code .ret rootBindings (.cons (.datum .unit) .nil) .done))
      (.cell (.ordinary .caller)) (.single (.cell (.ordinary .returned)))
  have last : NestedSteps (.nil : Target.Definitions signature algebra []) rootRejoined 0 rootFinished :=
    (nested_target_execution caller root.current diagnostics root.parents).trans
      (.cons (.complete (show rootReady.complete = some rootFinished from rfl)) .refl)
  have join : NestedSteps (.nil : Target.Definitions signature algebra []) childReturned 0 rootFinished :=
    .cons (count := 0) (rest := 0) (.complete (show childReturned.complete = some childFinished from rfl))
      (.cons (.join (show childFinished.join = some rootRejoined from rfl)) last)
  exact ⟨.cons resumed ((nested_target_execution body child.current diagnostics child.parents).trans join), rfl⟩

theorem authored_disposal_finishes_nested_cleanup_before_reentering_its_caller :
    ∃ count, Target.DisposalRun (.nil : Target.Definitions signature algebra [])
      (.evaluating ⟨⟨targetStore, .code (Defunctionalization.computation (.dispose (.reference .here)))
        (Defunctionalization.environment disposalBindings) .nil disposalTargetOutside⟩, [], []⟩) count
      (.resolved disposedResolution) := by
  have admission : Target.DisposalRun (.nil : Target.Definitions signature algebra [])
      (.evaluating ⟨⟨targetStore, .code (Defunctionalization.computation (.dispose (.reference .here)))
        (Defunctionalization.environment disposalBindings) .nil disposalTargetOutside⟩, [], []⟩) 2 (.disposing start.begin) :=
    .cons (.evaluate (.cell (.ordinary (.operand .load)))) (.cons (.enter (Target.DisposeEntry.enter (use := .linear) rfl)) .refl)
  have selected : Target.DisposalRun (.nil : Target.Definitions signature algebra [])
      (.disposing start.begin) 1 (.disposing ⟨.unit, .cleaning rootScope, start.outside⟩) :=
    .cons (.unwind (.unwind (.select (by intro impossible; cases impossible) rfl))) .refl
  have nested := saved_cleanup_enters_its_nested_protection.trans
    (nested_disposal_yields_without_returning_to_the_caller.1.trans nested_disposal_resumes_and_finishes_both_cleanups.1)
  obtain ⟨nestedCount, completed⟩ := Target.DisposalRun.run_nested_cleanup rootScope start.outside nested
    nested_disposal_resumes_and_finishes_both_cleanups.2
  have done : Target.DisposalRun (.nil : Target.Definitions signature algebra [])
      (.disposing ⟨.unit, .cleaning ⟨disposalCompleted, .unwind disposalTail⟩, start.outside⟩) 3 (.resolved disposedResolution) :=
    .cons (.unwind (.unwind (.finish rfl (by intro impossible; cases impossible))))
      (.cons (.unwind (.unwind (.complete rfl))) (.cons (.finish rfl) .refl))
  exact ⟨2 + 1 + nestedCount + 3, ((admission.trans selected).trans completed).trans done⟩

theorem nested_disposal_keeps_the_consumed_grant_and_unrelated_owner :
    rootFinished.memory.store.fields.spent = [⟨100⟩] ∧
    UseScope.inventory rootFinished.memory.store.fields = [⟨900⟩] ∧
    UseScope.disposeOwned disposeView rootFinished.memory.store = none := ⟨rfl, rfl, rfl⟩

end BoundaryV2.Generalized.Examples.NestedDisposal
