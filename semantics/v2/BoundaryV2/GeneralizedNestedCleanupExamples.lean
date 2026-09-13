import BoundaryV2.GeneralizedNestedCleanup
import BoundaryV2.GeneralizedExamples

namespace BoundaryV2.Generalized.Examples.Nested

open ExitComposition

/-- Distinct faults make nesting order observable. The existing scalar leaf
operations remain concrete; only their overflow fault is renamed to 255. -/
abbrev leafAlgebra : LeafAlgebra Data := {
  Value := Leaf, Fault := Nat, Reason := String, operation := Primitive,
  evaluate := fun operation values => match evaluate operation values with
    | .ok value => .ok value
    | .error _ => .error 255
}

abbrev Machine := NestedCleanup signature leafAlgebra []
abbrev CellType : TypeOf signature := .cell (.leaf .integer)
def emptyDiagnostics : CleanupDiagnostics Nat String := ⟨[], none⟩
def outerExit : ExitInfo Nat String := ⟨.failure 100, [90], none⟩
def childExit : ExitInfo Nat String := ⟨.failure 200, [], none⟩
def grandExit : ExitInfo Nat String := ⟨.failure 210, [], none⟩
def store : Target.ControlHeap signature leafAlgebra [] :=
  ⟨⟨[.owned ⟨9⟩ (.lexical ⟨0⟩ 0)], [], []⟩, [], []⟩
def cells : Cells signature leafAlgebra (fun context result => Target.Code signature leafAlgebra [] context [] result) :=
  [⟨⟨5⟩, ⟨1⟩, .leaf .integer, .datum (.leaf 0)⟩]
def writtenCells : Cells signature leafAlgebra (fun context result => Target.Code signature leafAlgebra [] context [] result) :=
  [⟨⟨5⟩, ⟨1⟩, .leaf .integer, .datum (.leaf (type := Data.integer) 7)⟩]
def captured : Target.RuntimeEnvironment signature leafAlgebra [] [CellType] := .cons (.cell ⟨5⟩ ⟨1⟩) .nil
def childBindings : Target.RuntimeEnvironment signature leafAlgebra [] [.exit, CellType] := .cons (.exit childExit) captured
def grandBindings : Target.RuntimeEnvironment signature leafAlgebra [] [.exit, .exit, CellType] := .cons (.exit grandExit) childBindings

def grandTail : Target.Code signature leafAlgebra [] [.exit, .exit, CellType] [.unit] .unit := .yieldThen (.fault 300)
def grandCode : Target.Code signature leafAlgebra [] [.exit, .exit, CellType] [] .unit :=
  .load (.there (.there .here)) (.push (.leaf (type := Data.integer) 7) (.cellWrite grandTail))
def childCode : Target.Code signature leafAlgebra [] [.exit, CellType] [] .unit := .protect grandCode (.fault 210) .ret
def rootRuntime : Runtime signature leafAlgebra [] :=
  ⟨⟨40⟩, .running (.failed 200 (.push (.protection ⟨41⟩ childCode captured) .done)) .active,
    store, cells, [⟨1⟩], outerExit⟩
def root : Machine := NestedCleanup.start rootRuntime
def child : Machine := root.push
  ⟨⟨⟨41⟩, .pending ⟨[CellType], childCode, captured⟩, store, cells, [⟨1⟩], childExit⟩, .unwind .done⟩
def childStarted : Machine := { child with focus := .executing (.running (.code childCode childBindings .nil .done) .active) emptyDiagnostics }
def childOutside : Target.Stack signature leafAlgebra [] .unit .unit := .push (.returnTo .ret childBindings .nil) .done
def nestedOutside : Target.Stack signature leafAlgebra [] .unit .unit := .push (.protection ⟨42⟩ grandCode childBindings) childOutside
def childBody : Machine := { child with focus := .executing (.running (.code (.fault 210) childBindings .nil nestedOutside) .active) emptyDiagnostics }
def childFailed : Machine := { child with focus := .executing (.running (.failed 210 nestedOutside) .active) emptyDiagnostics }
def grand : Machine := childFailed.push
  ⟨⟨⟨42⟩, .pending ⟨[.exit, CellType], grandCode, childBindings⟩, store, cells, [⟨1⟩], grandExit⟩, .unwind childOutside⟩
def grandStarted : Machine := { grand with focus := .executing (.running (.code grandCode grandBindings .nil .done) .active) emptyDiagnostics }
def grandLoaded : Machine := { grand with focus := .executing (.running
  (.code (.push (.leaf (type := Data.integer) 7) (.cellWrite grandTail)) grandBindings (.cons (.cell ⟨5⟩ ⟨1⟩) .nil) .done) .active) emptyDiagnostics }
def grandReadyToWrite : Machine := { grand with focus := .executing (.running
  (.code (.cellWrite grandTail) grandBindings (.cons (.datum (.leaf (type := Data.integer) 7)) (.cons (.cell ⟨5⟩ ⟨1⟩) .nil)) .done) .active) emptyDiagnostics }
def grandWritten : Machine := { grand with
  memory := ⟨store, writtenCells, [⟨1⟩]⟩,
  focus := .executing (.running (.code grandTail grandBindings (.cons (.datum .unit) .nil) .done) .active) emptyDiagnostics }
def yieldedCursor : Cursor signature leafAlgebra [] := .yielded (.code (.fault 300) grandBindings (.cons (.datum .unit) .nil) .done)
def grandYielded : Machine := { grandWritten with focus := .executing (.running yieldedCursor .active) emptyDiagnostics }
def grandCaptured : Machine := { grandWritten with focus := .executing (.running yieldedCursor (.captured ⟨70⟩)) emptyDiagnostics }
def cancelled : Machine := grandCaptured.cancel "first"
def reattached : Machine := { cancelled with focus := .executing (.running yieldedCursor .active) emptyDiagnostics }
def parked : Machine := { cancelled with focus := .executing (.running yieldedCursor .parked) emptyDiagnostics }
def resumed : Machine := { cancelled with focus := .executing (.running
  (.code (.fault 300) grandBindings (.cons (.datum .unit) .nil) .done) .active) emptyDiagnostics }
def grandFailed : Machine := { cancelled with focus := .executing (.running (.failed 300 .done) .active) emptyDiagnostics }
def grandFinished : Machine := { grandFailed with
  current := ⟨⟨42⟩, ⟨.failure 210, [300], none⟩⟩,
  focus := .executing (.finished (.failed 300)) emptyDiagnostics }
def childRejoined : Machine :=
  ⟨grandFinished.memory, ⟨⟨41⟩, childExit⟩,
    .executing (.running (.failed 210 childOutside) .active) ⟨[300], none⟩, cancelled.parents.drop 1⟩
def childReady : Machine := { childRejoined with focus := .executing (.running (.failed 210 .done) .active) ⟨[300], none⟩ }
def childFinished : Machine := { childReady with
  current := ⟨⟨41⟩, ⟨.failure 200, [210, 300], none⟩⟩,
  focus := .executing (.finished (.failed 210)) emptyDiagnostics }
def rootRejoined : Machine := ⟨childFinished.memory, ⟨⟨40⟩, outerExit.cancel "first"⟩,
  .executing (.running (.failed 200 .done) .active) ⟨[210, 300], none⟩, []⟩
def rootFinished : Machine := { rootRejoined with
  current := ⟨⟨40⟩, ⟨.failure 100, [90, 200, 210, 300], some "first"⟩⟩,
  focus := .executing (.finished (.failed 200)) emptyDiagnostics }

theorem enters_two_actual_cleanup_boundaries :
    NestedSteps (.nil : Target.Definitions signature leafAlgebra []) root 2 grandStarted := by
  refine .cons (count := 0) (rest := 2) (.enter (show root.enter = some child from rfl)) ?_
  have beginChild : NestedStep (.nil : Target.Definitions signature leafAlgebra []) child 1 childStarted :=
    .local (after := child.current.runtime (signature := signature) (algebra := leafAlgebra) (.running (.code childCode childBindings .nil .done) .active) child.memory)
      (.lifecycle .begin) rfl rfl
  refine .cons (count := 1) (rest := 1) beginChild ?_
  have install : Target.ExecutionStep (.nil : Target.Definitions signature leafAlgebra [])
      ⟨⟨store, .code childCode childBindings .nil .done⟩, cells, [⟨1⟩]⟩
      ⟨⟨store, .code (.fault 210) childBindings .nil nestedOutside⟩, cells, [⟨1⟩]⟩ :=
    .enterProtection [.name .obligation ⟨40⟩, .name .obligation ⟨41⟩] rfl
  refine .cons (count := 0) (rest := 1) (nested_single_execution install child.current emptyDiagnostics child.parents) ?_
  have failed : NestedStep (.nil : Target.Definitions signature leafAlgebra []) childBody 0 childFailed := by
    apply nested_single_execution (before := ⟨⟨store, .code (.fault 210) childBindings .nil nestedOutside⟩, cells, [⟨1⟩]⟩)
      (after := ⟨⟨store, .failed 210 nestedOutside⟩, cells, [⟨1⟩]⟩) _ child.current emptyDiagnostics child.parents
    exact .cell (.ordinary .fault)
  refine .cons (count := 0) (rest := 1) failed ?_
  refine .cons (count := 0) (rest := 1) (.enter (show childFailed.enter = some grand from rfl)) ?_
  have beginGrand : NestedStep (.nil : Target.Definitions signature leafAlgebra []) grand 1 grandStarted :=
    .local (after := grand.current.runtime (signature := signature) (algebra := leafAlgebra) (.running (.code grandCode grandBindings .nil .done) .active) grand.memory)
      (.lifecycle .begin) rfl rfl
  exact .cons (count := 1) (rest := 0) beginGrand .refl

def grandState (cursor : Cursor signature leafAlgebra [])
    (currentCells : Cells signature leafAlgebra (fun context result => Target.Code signature leafAlgebra [] context [] result) := cells) :
    Target.State signature leafAlgebra [] .unit := ⟨⟨store, cursor⟩, currentCells, [⟨1⟩]⟩

theorem inner_cleanup_writes_shared_state_then_yields :
    NestedSteps (.nil : Target.Definitions signature leafAlgebra []) grandStarted 0 grandYielded := by
  have written : Cells.writeCopy (signature := signature) (algebra := leafAlgebra) ⟨5⟩ ⟨1⟩ (.datum (.leaf (type := Data.integer) 7)) cells = some writtenCells := by
    simp [Cells.writeCopy, Cells.exchange, cells, writtenCells, Value.copyable, Datum.copyable]
  have run : Target.ExecutionSteps (.nil : Target.Definitions signature leafAlgebra [])
      (grandState (.code grandCode grandBindings .nil .done)) 4 (grandState yieldedCursor writtenCells) := by
    refine .cons (middle := grandState (.code (.push (.leaf (type := Data.integer) 7) (.cellWrite grandTail)) grandBindings
      (.cons (.cell ⟨5⟩ ⟨1⟩) .nil) .done)) (.cell (.ordinary (.operand .load))) ?_
    refine .cons (middle := grandState (.code (.cellWrite grandTail) grandBindings
      (.cons (.datum (.leaf (type := Data.integer) 7)) (.cons (.cell ⟨5⟩ ⟨1⟩) .nil)) .done)) (.cell (.ordinary (.operand .push))) ?_
    refine .cons (middle := grandState (.code grandTail grandBindings (.cons (.datum .unit) .nil) .done) writtenCells)
      (.cell (.write List.mem_cons_self written)) ?_
    exact .cons (.cell (.ordinary .yield)) .refl
  exact nested_target_execution run grand.current emptyDiagnostics grand.parents

theorem captured_inner_cleanup_cancels_the_outer_exit_without_restarting :
    NestedSteps (.nil : Target.Definitions signature leafAlgebra []) grandYielded 0 resumed ∧
    grandCaptured.join = none ∧ cancelled.complete = none ∧ cancelled.cancel "later" = cancelled ∧
    cancelled.current.exit = grandExit ∧ cancelled.memory.cells = writtenCells := by
  refine ⟨?_, rfl, rfl, repeated_nested_cancellation "first" "later" grandCaptured, rfl, rfl⟩
  have capture : NestedStep (.nil : Target.Definitions signature leafAlgebra []) grandYielded 0 grandCaptured :=
    .local (after := grand.current.runtime (signature := signature) (algebra := leafAlgebra) (.running yieldedCursor (.captured ⟨70⟩)) grandWritten.memory) (.lifecycle .capture) rfl rfl
  have attach : NestedStep (.nil : Target.Definitions signature leafAlgebra []) cancelled 0 reattached :=
    .local (after := cancelled.current.runtime (signature := signature) (algebra := leafAlgebra) (.running yieldedCursor .active) cancelled.memory) (.lifecycle .reattach) rfl rfl
  have park : NestedStep (.nil : Target.Definitions signature leafAlgebra []) reattached 0 parked :=
    .local (after := cancelled.current.runtime (signature := signature) (algebra := leafAlgebra) (.running yieldedCursor .parked) cancelled.memory) (.lifecycle .parkYield) rfl rfl
  have resume : NestedStep (.nil : Target.Definitions signature leafAlgebra []) parked 0 resumed :=
    .local (after := cancelled.current.runtime (signature := signature) (algebra := leafAlgebra) (.running (.code (.fault 300) grandBindings (.cons (.datum .unit) .nil) .done) .active) cancelled.memory)
      (.lifecycle .continueYield) rfl rfl
  exact .cons capture (.cons (.cancel (reason := "first"))
    (.cons (by simpa [cancelled, repeated_nested_cancellation] using (NestedStep.cancel (table := (.nil : Target.Definitions signature leafAlgebra [])) (before := cancelled) (reason := "later")))
      (.cons attach (.cons park (.cons resume .refl)))))

theorem nested_failure_details_rejoin_in_order_with_the_latest_cells :
    NestedSteps (.nil : Target.Definitions signature leafAlgebra []) resumed 0 rootFinished ∧
    rootFinished.finished = some ⟨⟨40⟩, .finished (.failed 200), store, writtenCells, [⟨1⟩],
      ⟨.failure 100, [90, 200, 210, 300], some "first"⟩⟩ := by
  refine ⟨?_, rfl⟩
  have faultStep : Target.ExecutionStep (.nil : Target.Definitions signature leafAlgebra [])
      (grandState (.code (.fault 300) grandBindings (.cons (.datum .unit) .nil) .done) writtenCells)
      (grandState (.failed 300 .done) writtenCells) := .cell (.ordinary .fault)
  refine .cons (count := 0) (rest := 0) (nested_single_execution faultStep cancelled.current emptyDiagnostics cancelled.parents) ?_
  refine .cons (count := 0) (rest := 0) (.complete (show grandFailed.complete = some grandFinished from rfl)) ?_
  refine .cons (count := 0) (rest := 0) (.join (show grandFinished.join = some childRejoined from rfl)) ?_
  have caller : Target.ExecutionStep (.nil : Target.Definitions signature leafAlgebra [])
      (grandState (.failed 210 childOutside) writtenCells) (grandState (.failed 210 .done) writtenCells) := .cell (.ordinary .callerFault)
  refine .cons (count := 0) (rest := 0) (nested_single_execution caller childRejoined.current ⟨[300], none⟩ childRejoined.parents) ?_
  refine .cons (count := 0) (rest := 0) (.complete (show childReady.complete = some childFinished from rfl)) ?_
  refine .cons (count := 0) (rest := 0) (.join (show childFinished.join = some rootRejoined from rfl)) ?_
  exact .cons (.complete (show rootRejoined.complete = some rootFinished from rfl)) .refl

theorem complete_nested_run_retains_the_callers_failure_and_ownership :
    NestedSteps (.nil : Target.Definitions signature leafAlgebra []) root 2 rootFinished ∧
    UseScope.inventory rootFinished.memory.store.fields = [⟨9⟩] ∧
    rootFinished.finishScope (.unwind (.done : Target.Stack signature leafAlgebra [] .unit .unit)) =
      some (.reenter ⟨⟨store, .failed 100 .done⟩, writtenCells, [⟨1⟩]⟩
        ⟨.failure 100, [90, 200, 210, 300], some "first"⟩) := by
  refine ⟨?_, rfl, rfl⟩
  exact enters_two_actual_cleanup_boundaries.trans
    (inner_cleanup_writes_shared_state_then_yields.trans
      (captured_inner_cleanup_cancels_the_outer_exit_without_restarting.1.trans nested_failure_details_rejoin_in_order_with_the_latest_cells.1))

def pendingOutside : Target.Stack signature leafAlgebra [] .unit .unit :=
  .push (.protection ⟨75⟩ (.fault 400) grandBindings) .done
def protectedCapture : Machine := { grandCaptured with
  focus := .executing
    (.running (.yielded (.code (.fault 300) grandBindings (.cons (.datum .unit) .nil) pendingOutside)) (.captured ⟨70⟩)) emptyDiagnostics }
def abandonedCapture : Machine := { protectedCapture with focus := .unwinding ⟨.abandoned, [], none⟩ pendingOutside }
def disposalCleanup : Machine := abandonedCapture.push
  ⟨⟨⟨75⟩, .pending ⟨[.exit, .exit, CellType], .fault 400, grandBindings⟩,
    store, writtenCells, [⟨1⟩], ⟨.abandoned, [], none⟩⟩, .unwind .done⟩

theorem abandoning_capture_selects_its_actual_pending_cleanup :
    protectedCapture.abandon = some abandonedCapture ∧
    abandonedCapture.advanceUnwind = some disposalCleanup ∧
    disposalCleanup.current.id = ⟨75⟩ ∧ disposalCleanup.memory.cells = writtenCells ∧
    disposalCleanup.focus.right = 1 ∧ disposalCleanup.finished = none := ⟨rfl, rfl, rfl, rfl, rfl, rfl⟩

theorem equal_nested_faults_remain_separate_occurrences :
    (outerExit.nestedFailure 300 [300] none).failures = [90, 300, 300] := rfl

end BoundaryV2.Generalized.Examples.Nested
