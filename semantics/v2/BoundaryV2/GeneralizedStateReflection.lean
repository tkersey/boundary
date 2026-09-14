import BoundaryV2.GeneralizedStateSimulation

namespace BoundaryV2.Generalized.Target

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}


/-- The existing control boundary reached by operand evaluation. Faults enter
failure under the same caller; successful operands are placed in their typed
positions. This only packages a reflection conclusion. -/
def expressionOutcome
    (next : Code signature algebra program context (type :: stack) input)
    (bindings : RuntimeEnvironment signature algebra program context)
    (values : RuntimeEnvironment signature algebra program stack)
    (outside : Stack signature algebra program input result) :
    Except algebra.Fault (RuntimeValue signature algebra program type) → Configuration signature algebra program result
  | .ok value => .code next bindings (.cons value values) outside
  | .error fault => .failed fault outside

def argumentsOutcome
    (next : Code signature algebra program context (types.reverse ++ stack) input)
    (bindings : RuntimeEnvironment signature algebra program context)
    (values : RuntimeEnvironment signature algebra program stack)
    (outside : Stack signature algebra program input result) :
    Except algebra.Fault (RuntimeEnvironment signature algebra program types) → Configuration signature algebra program result
  | .ok arguments => .code next bindings (arguments.pushReverse values) outside
  | .error fault => .failed fault outside

/-- An inspection view of the existing close instruction. Explicit indices
allow inversion without guessing a split of the reversed operand stack. It
contains no execution rule or evaluator. -/
structure CloseOperands (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect))
    (context : List (TypeOf signature)) (result : TypeOf signature) where
  use : Use
  parameters : List (TypeOf signature)
  answer : TypeOf signature
  capturedTypes : List (TypeOf signature)
  stack : List (TypeOf signature)
  body : Code signature algebra program (parameters ++ capturedTypes) [] answer
  next : Code signature algebra program context (.computation use parameters answer :: stack) result
  captured : RuntimeEnvironment signature algebra program capturedTypes
  values : RuntimeEnvironment signature algebra program stack

def closeViewCode (code : Code signature algebra program context types result)
    (values : RuntimeEnvironment signature algebra program types) :
    Option (CloseOperands signature algebra program context result) :=
  match code with
  | @Code.close _ _ _ parameters captured answer _ use stack _ body next =>
    let (capturedValues, rest) := Environment.popReverse captured values
    some ⟨use, parameters, answer, captured, stack, body, next, capturedValues, rest⟩
  | _ => none

def Operands.closeView (operands : Operands signature algebra program context result) :
    Option (CloseOperands signature algebra program context result) := closeViewCode operands.code operands.values

theorem close_view_exposes_exact_operands
    (body : Code signature algebra program (parameters ++ capturedTypes) [] answer)
    (captured : RuntimeEnvironment signature algebra program capturedTypes)
    (next : Code signature algebra program context (.computation use parameters answer :: stack) result)
    (values : RuntimeEnvironment signature algebra program stack) :
    Operands.closeView ⟨_, .close body next, captured.pushReverse values⟩ =
      some ⟨use, parameters, answer, capturedTypes, stack, body, next, captured, values⟩ := by
  simp only [Operands.closeView, closeViewCode, Environment.popReverse_pushReverse]


/-- The surrounding typed caller and lexical environment of a close operand.
This is a view of Configuration.code, not a second control representation. -/
structure CloseFrame (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (result : TypeOf signature) where
  context : List (TypeOf signature)
  input : TypeOf signature
  operands : CloseOperands signature algebra program context input
  bindings : RuntimeEnvironment signature algebra program context
  outside : Stack signature algebra program input result

def CloseOperands.operands (view : CloseOperands signature algebra program context result) :
    Operands signature algebra program context result :=
  ⟨_, .close view.body view.next, view.captured.pushReverse view.values⟩

def Configuration.closeView : Configuration signature algebra program result → Option (CloseFrame signature algebra program result)
  | .code body bindings values outside =>
    (closeViewCode body values).map fun view => ⟨_, _, view, bindings, outside⟩
  | _ => none

theorem close_configuration_view
    (body : Code signature algebra program (parameters ++ capturedTypes) [] answer)
    (captured : RuntimeEnvironment signature algebra program capturedTypes)
    (next : Code signature algebra program context (.computation use parameters answer :: stack) input)
    (values : RuntimeEnvironment signature algebra program stack)
    (bindings : RuntimeEnvironment signature algebra program context)
    (outside : Stack signature algebra program input result) :
    (Configuration.code (.close body next) bindings (captured.pushReverse values) outside).closeView =
      some ⟨context, input, ⟨use, parameters, answer, capturedTypes, stack, body, next, captured, values⟩, bindings, outside⟩ := by
  simp only [Configuration.closeView, closeViewCode, Environment.popReverse_pushReverse, Option.map_some]

theorem close_view_requires_owning_execution
    {configuration : Configuration signature algebra program result}
    (viewed : configuration.closeView = some view) : configuration.needsOwnershipStep = true := by
  cases configuration with
  | code body bindings values outside =>
    cases body <;> simp_all [Configuration.closeView, closeViewCode, Configuration.needsOwnershipStep, Code.needsOwnershipStep]
  | returned | failed | requested | yielded => cases viewed

theorem close_view_is_operand
    (before : Operands signature algebra program context input)
    (bindings : RuntimeEnvironment signature algebra program context)
    (outside : Stack signature algebra program input result)
    (viewed : (Configuration.code before.code bindings before.values outside).closeView = some view) :
    before.code.isClosure = true := by
  cases before with
  | mk types body values =>
    cases body <;> simp_all [Configuration.closeView, closeViewCode, Code.isClosure]

variable [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]

/-- At a close instruction the actual state machine can only take an owning
operand step. The returned witness retains the exact lexical and caller data. -/
theorem ExecutionStep.close_operand_result
    {table : Definitions signature algebra program}
    {before after : State signature algebra program result}
    (step : ExecutionStep table before after)
    (viewed : before.control.configuration.closeView = some view) :
    ∃ changed operands,
      OwnedOperandStep view.bindings before.cells.reservations.custody before.control.store view.operands.operands changed operands ∧
      after = ⟨⟨changed, .code operands.code view.bindings operands.values view.outside⟩, before.cells, before.liveRegions⟩ := by
  cases step with
  | cell actual =>
    cases actual with
    | ordinary actual neutral =>
      have required := close_view_requires_owning_execution viewed
      simp only [neutral, Bool.false_eq_true] at required
    | allocate | read | write => cases viewed
  | control actual =>
    cases actual with
    | ordinary actual neutral =>
      have required := close_view_requires_owning_execution viewed
      simp only [neutral, Bool.false_eq_true] at required
    | @operand context input result beforeStore afterStore bindings beforeOps afterOps outside actual =>
      cases actual with
      | ordinary actual neutral =>
        have required := close_view_is_operand beforeOps bindings outside viewed
        simp only [neutral, Bool.false_eq_true] at required
      | ownedClose use body captured next values owner before remaining store partition =>
        simp only [close_configuration_view, Option.some.injEq] at viewed
        cases viewed
        exact ⟨_, _, .ownedClose use body captured next values owner before remaining _ partition, rfl⟩
      | sharedClose use permitted body captured next values copyable =>
        simp only [close_configuration_view, Option.some.injEq] at viewed
        cases viewed
        exact ⟨_, _, .sharedClose use permitted body captured next values copyable, rfl⟩
    | application | resume | successor | injection | handled => cases viewed
  | installHandler | enterProtection | enterRegion | packageOperand | unpackageOperand => cases viewed

/-- A neutral ordinary instruction has the same result through every admitted
stateful wrapper. This also covers return/caller administration and faults. -/
theorem ExecutionStep.ordinary_result
    {table : Definitions signature algebra program} {before after : State signature algebra program result}
    (step : ExecutionStep table before after)
    (expected : CallStep table before.control.configuration next)
    (neutral : before.control.configuration.needsOwnershipStep = false) :
    after = ⟨⟨before.control.store, next⟩, before.cells, before.liveRegions⟩ := by
  have ordinary : before.control.configuration.installsHandler = false := by
    cases before with
    | mk control storage regions => cases control with
      | mk store configuration => cases configuration with
        | code body bindings values outside => cases body <;> first | rfl | cases neutral
        | returned | failed | yielded | requested => rfl
  obtain ⟨attachment, computed⟩ := expected.computes_next
  cases step with
  | cell actual =>
    cases actual with
    | ordinary actual neutral =>
      have same := CallStep.deterministic ordinary expected actual
      subst next
      rfl
    | allocate | read | write => cases computed
  | control actual =>
    cases actual with
    | ordinary actual neutral =>
      have same := CallStep.deterministic ordinary expected actual
      subst next
      rfl
    | @operand context input result beforeStore afterStore bindings beforeOps afterOps outside actual =>
      cases actual with
      | ordinary actual neutral =>
        have actualNext := actual.code_next table attachment outside
        have same := Option.some.inj (computed.symm.trans actualNext)
        subst next
        rfl
      | ownedClose | sharedClose => cases neutral
    | application => cases neutral
    | resume | successor | injection | handled => cases computed
  | installHandler => cases neutral
  | enterProtection | enterRegion | packageOperand | unpackageOperand => cases computed

theorem ordinary_cancel_stateful_observed
    {table : Definitions signature algebra program}
    {before final : State signature algebra program result}
    (expected : CallStep table before.control.configuration next)
    (neutral : before.control.configuration.needsOwnershipStep = false)
    (run : ExecutionSteps table before count final)
    (head : HeadObservation final.control.configuration observation) :
    ∃ remaining, count = remaining + 1 ∧
      ExecutionSteps table ⟨⟨before.control.store, next⟩, before.cells, before.liveRegions⟩ remaining final := by
  cases run with
  | refl => exact False.elim (head.no_step table expected)
  | cons actual tail =>
    have same := actual.ordinary_result expected neutral
    subst_vars
    exact ⟨_, rfl, tail⟩

/-- Returning or failing at an empty caller is terminal in the current stateful
execution relation; neither observation can trigger an owning operation. -/
theorem ExecutionSteps.returned_done
    {table : Definitions signature algebra program}
    (value : RuntimeValue signature algebra program result)
    (store : ControlHeap signature algebra program)
    (storage : Cells signature algebra (fun context result => Code signature algebra program context [] result))
    (regions : List (Id .region))
    (run : ExecutionSteps table ⟨⟨store, .returned value .done⟩, storage, regions⟩ count final) :
    final = ⟨⟨store, .returned value .done⟩, storage, regions⟩ := by
  cases run with
  | refl => rfl
  | cons step tail =>
    cases step with
    | cell step => cases step with
      | ordinary step neutral => cases step
    | control step => cases step with
      | ordinary step neutral => cases step

theorem ExecutionSteps.failed_done
    {table : Definitions signature algebra program}
    (fault : algebra.Fault) (result : TypeOf signature)
    (store : ControlHeap signature algebra program)
    (storage : Cells signature algebra (fun context result => Code signature algebra program context [] result))
    (regions : List (Id .region)) {final : State signature algebra program result}
    (run : ExecutionSteps table (⟨⟨store, .failed fault .done⟩, storage, regions⟩ : State signature algebra program result) count final) :
    final = ⟨⟨store, .failed fault .done⟩, storage, regions⟩ := by
  cases run with
  | refl => rfl
  | cons step tail =>
    cases step with
    | cell step => cases step with
      | ordinary step neutral => cases step
    | control step => cases step with
      | ordinary step neutral => cases step

end BoundaryV2.Generalized.Target

namespace BoundaryV2.Generalized.Defunctionalization

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)} {SourceFuture TargetFuture : Type}

/-- Invert the target's actual close instruction. Its chosen owner and capture
partition construct a legitimate source closure; the source conclusion is not
a premise and the target evaluator never invokes source execution. -/
theorem closure_operand_reflected
    (futureRelation : SourceFuture → TargetFuture → Prop)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (selection : Selection context capturedTypes)
    (body : Source.Computation signature algebra program (parameters ++ capturedTypes) answer)
    (reserved : List (Id .custody))
    {sourceStore : UseScope.ControlStore SourceFuture} {targetStore changed : UseScope.ControlStore TargetFuture}
    (stores : UseScope.ControlStore.Related futureRelation sourceStore targetStore)
    (next : Target.Code signature algebra program context (.computation use parameters answer :: stack) result)
    (values : Target.RuntimeEnvironment signature algebra program stack)
    (step : Target.OwnedOperandStep (environment bindings) reserved targetStore
      ⟨_, .close (computation body) next, (environment (bindings.select selection)).pushReverse values⟩ changed after) :
    ∃ sourceValue sourceAfter,
      Source.ClosureEvaluation bindings reserved (.lambda (use := use) selection body) sourceStore sourceValue sourceAfter ∧
      UseScope.ControlStore.Related futureRelation sourceAfter changed ∧
      after = ⟨_, next, .cons (value sourceValue) values⟩ := by
  generalize atStart : (⟨_, .close (computation body) next, (environment (bindings.select selection)).pushReverse values⟩ :
    Target.Operands signature algebra program context result) = initial at step
  cases step with
  | ordinary actual neutral =>
    rw [← atStart] at neutral
    cases neutral
  | ownedClose actualUse actualBody actualCaptured actualNext actualValues owner before remaining store partition =>
    have same := congrArg Target.Operands.closeView atStart
    simp only [Target.close_view_exposes_exact_operands, Option.some.injEq] at same
    cases same
    have sourcePartition : sourceStore.fields.active = before ++ (bindings.select selection).owningFields ++ remaining := by
      simpa only [← stores.fields, environment, Environment.map_preserves_owning_fields] using partition
    have matched := owned_computation_creation_corresponds
      (Before := Source.Computation signature algebra program)
      (After := fun context result => Target.Code signature algebra program context [] result)
      futureRelation (fun _ _ body => computation body)
      actualUse body (bindings.select selection) owner before remaining reserved stores sourcePartition partition
    exact ⟨_, _, .owned actualUse selection body owner before remaining sourceStore sourcePartition, matched.2.2,
      congrArg (fun value => (⟨_, next, .cons value values⟩ : Target.Operands signature algebra program context result)) matched.2.1⟩
  | sharedClose actualUse permitted actualBody actualCaptured actualNext actualValues copyable =>
    have same := congrArg Target.Operands.closeView atStart
    simp only [Target.close_view_exposes_exact_operands, Option.some.injEq] at same
    cases same
    have sourceCopyable : (bindings.select selection).copyable = true := by
      simpa only [environment, Environment.copyable_map] using copyable
    exact ⟨_, _, .shared use permitted selection body sourceCopyable, stores, rfl⟩

variable [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]

/-- The inverse closure law applies to the complete permission-sensitive target
state step, including callers and cells. It does not require an operand-driver
witness from the caller. -/
theorem closure_state_step_reflected
    (table : Source.Definitions signature algebra program)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (selection : Selection context capturedTypes)
    (body : Source.Computation signature algebra program (parameters ++ capturedTypes) answer)
    {sourceStore : Source.ControlHeap signature algebra program}
    {targetStore : Target.ControlHeap signature algebra program}
    (stores : ControlHeapRelated sourceStore targetStore)
    (storage : Cells signature algebra (Source.Computation signature algebra program))
    (regions : List (Id .region))
    (next : Target.Code signature algebra program context (.computation use parameters answer :: stack) input)
    (values : Target.RuntimeEnvironment signature algebra program stack)
    (outside : Target.Stack signature algebra program input result)
    (step : Target.ExecutionStep (definitions table)
      ⟨⟨targetStore, .code (.close (computation body) next) (environment bindings)
        ((environment (bindings.select selection)).pushReverse values) outside⟩, cells storage, regions⟩ targetAfter) :
    ∃ sourceValue sourceAfter changed,
      Source.ClosureEvaluation bindings storage.reservations.custody (.lambda (use := use) selection body)
        sourceStore sourceValue sourceAfter ∧
      ControlHeapRelated sourceAfter changed ∧
      targetAfter = ⟨⟨changed, .code next (environment bindings) (.cons (value sourceValue) values) outside⟩,
        cells storage, regions⟩ := by
  obtain ⟨changed, operands, owned, afterAt⟩ := step.close_operand_result
    (Target.close_configuration_view (computation body) (environment (bindings.select selection)) next values (environment bindings) outside)
  have reservations : (cells storage).reservations = storage.reservations := Cells.reservations_mapBodies _ storage
  dsimp only [Target.CloseOperands.operands] at owned afterAt
  rw [reservations] at owned
  obtain ⟨sourceValue, sourceAfter, evaluated, matched, valuesAt⟩ :=
    closure_operand_reflected (UseScope.PackedControlRelated controlPayloadRelated) bindings selection body
      storage.reservations.custody stores next values owned
  refine ⟨sourceValue, sourceAfter, changed, evaluated, matched, ?_⟩
  rw [valuesAt] at afterAt
  exact afterAt

/-- A finite observing run must execute each lexical capture load in order.
The residual run starts at the original receiving code with the exact captured
values above its original operand suffix. -/
theorem selection_cancel_stateful_observed
    (captures : Selection context captured)
    (bindings : Target.RuntimeEnvironment signature algebra program context)
    (next : Target.Code signature algebra program context (captured.reverse ++ stack) input)
    (values : Target.RuntimeEnvironment signature algebra program stack)
    (store : Target.ControlHeap signature algebra program)
    (storage : Cells signature algebra (fun context result => Target.Code signature algebra program context [] result))
    (regions : List (Id .region)) (outside : Target.Stack signature algebra program input result)
    (table : Target.Definitions signature algebra program)
    {final : Target.State signature algebra program result}
    (run : Target.ExecutionSteps table
      ⟨⟨store, .code (selection captures next) bindings values outside⟩, storage, regions⟩ count final)
    (head : Target.HeadObservation final.control.configuration observation) :
    ∃ remaining, remaining ≤ count ∧
      Target.ExecutionSteps table
        ⟨⟨store, .code next bindings ((bindings.select captures).pushReverse values) outside⟩, storage, regions⟩ remaining final := by
  induction captures generalizing stack count with
  | nil => exact ⟨count, Nat.le_refl _, run⟩
  | cons reference rest induction =>
    let nextRest : Target.Code signature algebra program context (_ ++ _ :: stack) input := by
      simpa only [List.reverse_cons, List.append_assoc, List.singleton_append] using next
    have first : Target.CallStep table (.code (selection (.cons reference rest) next) bindings values outside)
        (.code (selection rest nextRest) bindings (.cons (bindings.lookup reference) values) outside) := .operand .load
    obtain ⟨remaining, decreased, tail⟩ := Target.ordinary_cancel_stateful_observed first rfl run head
    obtain ⟨last, bounded, finished⟩ := induction nextRest (.cons (bindings.lookup reference) values) tail
    refine ⟨last, by omega, ?_⟩
    have reindexed := Target.Operands.reindex (by simp only [List.reverse_cons, List.append_assoc, List.singleton_append]) next
      ((bindings.select rest).pushReverse (.cons (bindings.lookup reference) values))
    have configuration := congrArg (fun operands : Target.Operands signature algebra program context input =>
      Target.State.mk ⟨store, .code operands.code bindings operands.values outside⟩ storage regions) reindexed
    exact configuration ▸ finished

/-- Reverse a complete compiled lambda prefix from an actual finite observing
run. The recovered source allocation uses the target's chosen permission data;
its following run has strictly fewer target steps. -/
theorem lambda_observing_run_reflected
    (table : Source.Definitions signature algebra program)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (captures : Selection context capturedTypes)
    (body : Source.Computation signature algebra program (parameters ++ capturedTypes) answer)
    {sourceStore : Source.ControlHeap signature algebra program}
    {targetStore : Target.ControlHeap signature algebra program}
    (stores : ControlHeapRelated sourceStore targetStore)
    (storage : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region))
    (next : Target.Code signature algebra program context (.computation use parameters answer :: stack) input)
    (values : Target.RuntimeEnvironment signature algebra program stack)
    (outside : Target.Stack signature algebra program input result)
    {final : Target.State signature algebra program result}
    (run : Target.ExecutionSteps (definitions table)
      ⟨⟨targetStore, .code (expression (.lambda captures body) next) (environment bindings) values outside⟩, cells storage, regions⟩ count final)
    (head : Target.HeadObservation final.control.configuration observation) :
    ∃ sourceValue sourceAfter changed remaining,
      Source.ExpressionEvaluation bindings storage.reservations.custody sourceStore (.lambda (use := use) captures body) (.ok sourceValue) sourceAfter ∧
      ControlHeapRelated sourceAfter changed ∧ remaining < count ∧
      Target.ExecutionSteps (definitions table)
        ⟨⟨changed, .code next (environment bindings) (.cons (value sourceValue) values) outside⟩, cells storage, regions⟩ remaining final := by
  obtain ⟨remaining, bounded, tail⟩ := selection_cancel_stateful_observed captures (environment bindings)
    (.close (computation body) next) values targetStore (cells storage) regions outside (definitions table) run head
  have selected : (environment bindings).select captures = environment (bindings.select captures) :=
    Environment.select_map (fun _ _ body => computation body) captures bindings
  rw [selected] at tail
  cases tail with
  | refl => cases head
  | cons step rest =>
    obtain ⟨sourceValue, sourceAfter, changed, evaluated, matched, configuration⟩ :=
      closure_state_step_reflected table bindings captures body stores storage regions next values outside step
    rw [configuration] at rest
    exact ⟨sourceValue, sourceAfter, changed, _, .closure evaluated, matched, by omega, rest⟩

private theorem operand_observation_reflection_bounded
    (table : Source.Definitions signature algebra program)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (storage : Cells signature algebra (Source.Computation signature algebra program))
    (regions : List (Id .region)) (bound : Nat) :
    (∀ {type} (source : Source.Expression signature algebra program context type), sizeOf source < bound →
      ∀ {sourceStore : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program},
      ControlHeapRelated sourceStore targetStore →
      ∀ {stack input result} (next : Target.Code signature algebra program context (type :: stack) input)
      (values : Target.RuntimeEnvironment signature algebra program stack) (outside : Target.Stack signature algebra program input result)
      {count} {final : Target.State signature algebra program result} {observation},
      Target.ExecutionSteps (definitions table)
        ⟨⟨targetStore, .code (expression source next) (environment bindings) values outside⟩, cells storage, regions⟩ count final →
      Target.HeadObservation final.control.configuration observation →
      ∃ outcome sourceAfter changed remaining,
        Source.ExpressionEvaluation bindings storage.reservations.custody sourceStore source outcome sourceAfter ∧
        ControlHeapRelated sourceAfter changed ∧ remaining < count ∧
        Target.ExecutionSteps (definitions table)
          ⟨⟨changed, Target.expressionOutcome next (environment bindings) values outside (outcome.map value)⟩, cells storage, regions⟩ remaining final) ∧
    (∀ {types} (source : Source.Arguments signature algebra program context types), sizeOf source < bound →
      ∀ {sourceStore : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program},
      ControlHeapRelated sourceStore targetStore →
      ∀ {stack input result} (next : Target.Code signature algebra program context (types.reverse ++ stack) input)
      (values : Target.RuntimeEnvironment signature algebra program stack) (outside : Target.Stack signature algebra program input result)
      {count} {final : Target.State signature algebra program result} {observation},
      Target.ExecutionSteps (definitions table)
        ⟨⟨targetStore, .code (arguments source next) (environment bindings) values outside⟩, cells storage, regions⟩ count final →
      Target.HeadObservation final.control.configuration observation →
      ∃ outcome sourceAfter changed remaining,
        Source.ArgumentsEvaluation bindings storage.reservations.custody sourceStore source outcome sourceAfter ∧
        ControlHeapRelated sourceAfter changed ∧ remaining ≤ count ∧
        (∀ fault, outcome = .error fault → remaining < count) ∧
        Target.ExecutionSteps (definitions table)
          ⟨⟨changed, Target.argumentsOutcome next (environment bindings) values outside (outcome.map environment)⟩, cells storage, regions⟩ remaining final) := by
  cases bound with
  | zero => constructor <;> intro type source sized <;> omega
  | succ bound =>
    obtain ⟨expressions, argumentLists⟩ := operand_observation_reflection_bounded table bindings storage regions bound
    constructor
    · intro type source sized sourceStore targetStore stores stack input result next values outside count final observation run head
      cases source with
      | datum datum =>
        obtain ⟨remaining, counted, tail⟩ := Target.ordinary_cancel_stateful_observed (Target.CallStep.operand .push) rfl run head
        exact ⟨.ok (.datum datum), sourceStore, targetStore, remaining, .datum, stores, by omega, tail⟩
      | reference reference =>
        obtain ⟨remaining, counted, tail⟩ := Target.ordinary_cancel_stateful_observed (Target.CallStep.operand .load) rfl run head
        refine ⟨.ok (bindings.lookup reference), sourceStore, targetStore, remaining, .reference, stores, by omega, ?_⟩
        simpa only [Target.expressionOutcome, Except.map, lexical_lookup_corresponds] using tail
      | lambda captures body =>
        obtain ⟨sourceValue, sourceAfter, changed, remaining, evaluated, matched, smaller, tail⟩ :=
          lambda_observing_run_reflected table bindings captures body stores storage regions next values outside run head
        exact ⟨.ok sourceValue, sourceAfter, changed, remaining, evaluated, matched, smaller, tail⟩
      | pair first second =>
        obtain ⟨firstOutcome, middleSource, middleTarget, middleCount, firstEval, middleRelated, firstLess, middleRun⟩ :=
          expressions first (by simp_all; omega) stores (expression second (.pair next)) values outside run head
        cases firstOutcome with
        | error fault => exact ⟨.error fault, middleSource, middleTarget, middleCount, .pairFirstFault firstEval, middleRelated, firstLess, middleRun⟩
        | ok firstValue =>
          obtain ⟨secondOutcome, afterSource, afterTarget, afterCount, secondEval, afterRelated, secondLess, afterRun⟩ :=
            expressions second (by simp_all; omega) middleRelated (.pair next) (.cons (value firstValue) values) outside middleRun head
          cases secondOutcome with
          | error fault => exact ⟨.error fault, afterSource, afterTarget, afterCount, .pairSecondFault firstEval secondEval,
              afterRelated, by omega, afterRun⟩
          | ok secondValue =>
            obtain ⟨remaining, counted, tail⟩ := Target.ordinary_cancel_stateful_observed (Target.CallStep.operand .pair) rfl afterRun head
            exact ⟨.ok (.pair firstValue secondValue), afterSource, afterTarget, remaining,
              .pair firstEval secondEval, afterRelated, by omega, tail⟩
      | first operand =>
        obtain ⟨outcome, sourceAfter, changed, rest, evaluated, matched, smaller, following⟩ :=
          expressions operand (by simp_all; omega) stores (.first next) values outside run head
        cases outcome with
        | error fault => exact ⟨.error fault, sourceAfter, changed, rest, .firstFault evaluated, matched, smaller, following⟩
        | ok pair =>
          obtain ⟨remaining, counted, tail⟩ := Target.ordinary_cancel_stateful_observed (Target.CallStep.operand .first) rfl following head
          refine ⟨.ok pair.first, sourceAfter, changed, remaining, .first evaluated, matched, by omega, ?_⟩
          simpa only [Target.expressionOutcome, Except.map, value, Value.first_map] using tail
      | second operand =>
        obtain ⟨outcome, sourceAfter, changed, rest, evaluated, matched, smaller, following⟩ :=
          expressions operand (by simp_all; omega) stores (.second next) values outside run head
        cases outcome with
        | error fault => exact ⟨.error fault, sourceAfter, changed, rest, .secondFault evaluated, matched, smaller, following⟩
        | ok pair =>
          obtain ⟨remaining, counted, tail⟩ := Target.ordinary_cancel_stateful_observed (Target.CallStep.operand .second) rfl following head
          refine ⟨.ok pair.second, sourceAfter, changed, remaining, .second evaluated, matched, by omega, ?_⟩
          simpa only [Target.expressionOutcome, Except.map, value, Value.second_map] using tail
      | left operand =>
        obtain ⟨outcome, sourceAfter, changed, rest, evaluated, matched, smaller, following⟩ :=
          expressions operand (by simp_all; omega) stores (.left next) values outside run head
        cases outcome with
        | error fault => exact ⟨.error fault, sourceAfter, changed, rest, .leftFault evaluated, matched, smaller, following⟩
        | ok inner =>
          obtain ⟨remaining, counted, tail⟩ := Target.ordinary_cancel_stateful_observed (Target.CallStep.operand .left) rfl following head
          exact ⟨.ok (.left inner), sourceAfter, changed, remaining, .left evaluated, matched, by omega, tail⟩
      | right operand =>
        obtain ⟨outcome, sourceAfter, changed, rest, evaluated, matched, smaller, following⟩ :=
          expressions operand (by simp_all; omega) stores (.right next) values outside run head
        cases outcome with
        | error fault => exact ⟨.error fault, sourceAfter, changed, rest, .rightFault evaluated, matched, smaller, following⟩
        | ok inner =>
          obtain ⟨remaining, counted, tail⟩ := Target.ordinary_cancel_stateful_observed (Target.CallStep.operand .right) rfl following head
          exact ⟨.ok (.right inner), sourceAfter, changed, remaining, .right evaluated, matched, by omega, tail⟩
      | primitive operation inputs =>
        obtain ⟨outcome, sourceAfter, changed, rest, evaluated, matched, smaller, faultSmaller, following⟩ :=
          argumentLists inputs (by simp_all; omega) stores (.primitive operation next) values outside run head
        cases outcome with
        | error fault =>
          exact ⟨.error fault, sourceAfter, changed, rest, .primitiveInputFault evaluated, matched, faultSmaller fault rfl, following⟩
        | ok arguments =>
          cases computed : algebra.evaluate operation arguments.leaves with
          | ok resultValue =>
            have targetComputed : algebra.evaluate operation (environment arguments).leaves = .ok resultValue := by
              simpa only [environment, Environment.leaves_map] using computed
            obtain ⟨remaining, counted, tail⟩ := Target.ordinary_cancel_stateful_observed
              (Target.CallStep.operand (.primitive targetComputed)) rfl following head
            exact ⟨.ok (.datum (.leaf resultValue)), sourceAfter, changed, remaining,
              .primitive evaluated computed, matched, by omega, tail⟩
          | error fault =>
            have targetComputed : algebra.evaluate operation (environment arguments).leaves = .error fault := by
              simpa only [environment, Environment.leaves_map] using computed
            obtain ⟨firstRest, firstCount, faultRun⟩ := Target.ordinary_cancel_stateful_observed
              (Target.CallStep.operand (.primitiveFault targetComputed)) rfl following head
            obtain ⟨remaining, counted, tail⟩ := Target.ordinary_cancel_stateful_observed Target.CallStep.fault rfl faultRun head
            exact ⟨.error fault, sourceAfter, changed, remaining, .primitiveFault evaluated computed, matched, by omega, tail⟩
    · intro types source sized sourceStore targetStore stores stack input result next values outside count final observation run head
      cases source with
      | nil => exact ⟨.ok .nil, sourceStore, targetStore, count, .nil, stores, Nat.le_refl _, (by intro fault impossible; cases impossible), run⟩
      | cons first rest =>
        let nextRest : Target.Code signature algebra program context (_ ++ _ :: stack) input := by
          simpa only [List.reverse_cons, List.append_assoc, List.singleton_append] using next
        obtain ⟨firstOutcome, middleSource, middleTarget, middleCount, firstEval, middleRelated, firstLess, middleRun⟩ :=
          expressions first (by simp_all; omega) stores (arguments rest nextRest) values outside run head
        cases firstOutcome with
        | error fault => exact ⟨.error fault, middleSource, middleTarget, middleCount, .firstFault firstEval, middleRelated, by omega, (by intros; omega), middleRun⟩
        | ok firstValue =>
          obtain ⟨restOutcome, afterSource, afterTarget, afterCount, restEval, afterRelated, restLess, restFaultLess, afterRun⟩ :=
            argumentLists rest (by simp_all; omega) middleRelated nextRest (.cons (value firstValue) values) outside middleRun head
          cases restOutcome with
          | error fault => exact ⟨.error fault, afterSource, afterTarget, afterCount, .restFault firstEval restEval, afterRelated, by omega, (by intros; omega), afterRun⟩
          | ok restValues =>
            refine ⟨.ok (.cons firstValue restValues), afterSource, afterTarget, afterCount, .cons firstEval restEval, afterRelated, by omega, (by intro fault impossible; cases impossible), ?_⟩
            have reindexed := Target.Operands.reindex (by simp only [List.reverse_cons, List.append_assoc, List.singleton_append]) next
              ((environment restValues).pushReverse (.cons (value firstValue) values))
            have configuration := congrArg (fun operands : Target.Operands signature algebra program context input =>
              Target.State.mk ⟨afterTarget, .code operands.code (environment bindings) operands.values outside⟩ (cells storage) regions) reindexed
            exact configuration ▸ afterRun
termination_by bound

/-- Invert a compiled expression in any finite observing target execution.
The recovered evaluation is the independent ownership-sensitive source rule. -/
theorem expression_observing_run_reflected
    (table : Source.Definitions signature algebra program)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (storage : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region))
    (source : Source.Expression signature algebra program context type)
    {sourceStore : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (stores : ControlHeapRelated sourceStore targetStore)
    (next : Target.Code signature algebra program context (type :: stack) input)
    (values : Target.RuntimeEnvironment signature algebra program stack) (outside : Target.Stack signature algebra program input result)
    {final : Target.State signature algebra program result}
    (run : Target.ExecutionSteps (definitions table)
      ⟨⟨targetStore, .code (expression source next) (environment bindings) values outside⟩, cells storage, regions⟩ count final)
    (head : Target.HeadObservation final.control.configuration observation) :
    ∃ outcome sourceAfter changed remaining,
      Source.ExpressionEvaluation bindings storage.reservations.custody sourceStore source outcome sourceAfter ∧
      ControlHeapRelated sourceAfter changed ∧ remaining < count ∧
      Target.ExecutionSteps (definitions table)
        ⟨⟨changed, Target.expressionOutcome next (environment bindings) values outside (outcome.map value)⟩,
          cells storage, regions⟩ remaining final :=
  (operand_observation_reflection_bounded table bindings storage regions (sizeOf source + 1)).1
    source (Nat.lt_succ_self _) stores next values outside run head

theorem arguments_observing_run_reflected
    (table : Source.Definitions signature algebra program)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (storage : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region))
    (source : Source.Arguments signature algebra program context types)
    {sourceStore : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (stores : ControlHeapRelated sourceStore targetStore)
    (next : Target.Code signature algebra program context (types.reverse ++ stack) input)
    (values : Target.RuntimeEnvironment signature algebra program stack) (outside : Target.Stack signature algebra program input result)
    {final : Target.State signature algebra program result}
    (run : Target.ExecutionSteps (definitions table)
      ⟨⟨targetStore, .code (arguments source next) (environment bindings) values outside⟩, cells storage, regions⟩ count final)
    (head : Target.HeadObservation final.control.configuration observation) :
    ∃ outcome sourceAfter changed remaining,
      Source.ArgumentsEvaluation bindings storage.reservations.custody sourceStore source outcome sourceAfter ∧
      ControlHeapRelated sourceAfter changed ∧ remaining ≤ count ∧
      (∀ fault, outcome = .error fault → remaining < count) ∧
      Target.ExecutionSteps (definitions table)
        ⟨⟨changed, Target.argumentsOutcome next (environment bindings) values outside (outcome.map environment)⟩,
          cells storage, regions⟩ remaining final :=
  (operand_observation_reflection_bounded table bindings storage regions (sizeOf source + 1)).2
    source (Nat.lt_succ_self _) stores next values outside run head

/-- Every computation constructor uses this same reflected operand prefix.
Successful prefixes stop at the existing receiving instruction; faults retain
the actual prefix store and propagate under the same caller. -/
theorem computation_operands_observing_run_reflected
    (table : Source.Definitions signature algebra program)
    (body : Source.Computation signature algebra program context input)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (storage : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region))
    {sourceStore : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (stores : ControlHeapRelated sourceStore targetStore) (outside : Target.Stack signature algebra program input result)
    {final : Target.State signature algebra program result}
    (run : Target.ExecutionSteps (definitions table)
      ⟨⟨targetStore, .code (computation body) (environment bindings) .nil outside⟩, cells storage, regions⟩ count final)
    (head : Target.HeadObservation final.control.configuration observation) :
    ∃ outcome sourceAfter changed remaining,
      Source.ArgumentsEvaluation bindings storage.reservations.custody sourceStore body.operandPrefix.arguments outcome sourceAfter ∧
      ControlHeapRelated sourceAfter changed ∧ remaining ≤ count ∧
      (∀ fault, outcome = .error fault → remaining < count) ∧
      Target.ExecutionSteps (definitions table)
        ⟨⟨changed, Target.argumentsOutcome (operandTail body) (environment bindings) .nil outside (outcome.map environment)⟩,
          cells storage, regions⟩ remaining final := by
  rw [computation_operand_prefix] at run
  exact arguments_observing_run_reflected table bindings storage regions body.operandPrefix.arguments stores (operandTail body) .nil outside run head

/-- Full finite observation reflection for an authored return expression,
including arbitrary structured/closure operands and their failures. This is a
consumer of operand reflection, not an assumed source evaluation premise. -/
theorem returned_expression_observation_reflected
    (table : Source.Definitions signature algebra program)
    (expression : Source.Expression signature algebra program context result)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (storage : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region))
    {sourceStore : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (stores : ControlHeapRelated sourceStore targetStore)
    {targetFinal : Target.State signature algebra program result}
    (observed : Target.StateObserves (definitions table)
      ⟨⟨targetStore, .code (computation (.returnValue expression)) (environment bindings) .nil .done⟩,
        cells storage, regions⟩ targetFinal observation) :
    ∃ sourceFinal sourceObservation,
      Source.StateObserves table ⟨⟨sourceStore, .evaluate (.returnValue expression) bindings⟩, storage, regions⟩ sourceFinal sourceObservation ∧
      StateObservationRelated sourceFinal targetFinal sourceObservation observation := by
  obtain ⟨count, run, head⟩ := observed
  obtain ⟨outcome, sourceAfter, changed, remaining, evaluated, matched, smaller, tail⟩ :=
    expression_observing_run_reflected table bindings storage regions expression stores .ret .nil .done run head
  cases outcome with
  | error fault =>
    have finalAt := Target.ExecutionSteps.failed_done fault result changed (cells storage) regions tail
    subst targetFinal
    cases head
    exact ⟨⟨⟨sourceAfter, .failed fault⟩, storage, regions⟩, .failed fault,
      ⟨1, .cons (.operandFault (body := .returnValue expression) (outside := .done) (.firstFault evaluated)) .refl, .failed⟩,
      ⟨matched, rfl, rfl, .failed fault⟩⟩
  | ok returned =>
    obtain ⟨rest, counted, finished⟩ := Target.ordinary_cancel_stateful_observed Target.CallStep.returned rfl tail head
    have finalAt := Target.ExecutionSteps.returned_done (value returned) changed (cells storage) regions finished
    subst targetFinal
    cases head
    exact ⟨⟨⟨sourceAfter, .returned returned⟩, storage, regions⟩, .returned returned,
      ⟨1, .cons (.returnOperand (outside := .done) evaluated) .refl, .returned⟩,
      ⟨matched, rfl, rfl, .returned returned⟩⟩

end BoundaryV2.Generalized.Defunctionalization
