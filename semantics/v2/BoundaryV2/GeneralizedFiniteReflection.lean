import BoundaryV2.GeneralizedControlReflection

namespace BoundaryV2.Generalized

namespace Source

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)} {Future : Type}

/-- Inverting a completed singleton prefix recovers its actual expression
transition and resulting store, including allocations before that completion. -/
theorem ArgumentsEvaluation.singleton
    {bindings : RuntimeEnvironment signature algebra program context}
    {expression : Expression signature algebra program context type}
    {before after : UseScope.ControlStore Future}
    (evaluated : ArgumentsEvaluation bindings reserved before (.cons expression .nil) (.ok (.cons value .nil)) after) :
    ExpressionEvaluation bindings reserved before expression (.ok value) after := by
  cases evaluated with
  | cons first rest => cases rest; exact first

end Source

namespace Target

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}
  [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]

/-- A successful ordinary next instruction and its ownership gate identify the
ordinary branch of actual execution; the current resources are unchanged. -/
theorem ExecutionStep.ordinary_of_next
    {table : Definitions signature algebra program} {before after : State signature algebra program result}
    (step : ExecutionStep table before after)
    (computed : nextWithAttachment table attachment before.control.configuration = some next)
    (neutral : before.control.configuration.needsOwnershipStep = false) :
    after.control.store = before.control.store ∧ after.cells = before.cells ∧ after.liveRegions = before.liveRegions ∧
      CallStep table before.control.configuration after.control.configuration := by
  cases step with
  | cell actual =>
    cases actual with
    | ordinary actual neutral => exact ⟨rfl, rfl, rfl, actual⟩
    | allocate | read | write => cases computed
  | control actual =>
    cases actual with
    | ordinary actual neutral => exact ⟨rfl, rfl, rfl, actual⟩
    | operand actual =>
      cases actual with
      | ordinary actual neutral => exact ⟨rfl, rfl, rfl, .operand actual⟩
      | ownedClose | sharedClose => cases neutral
    | application => cases neutral
    | resume | successor | injection | handled => cases computed
  | installHandler => cases neutral
  | enterProtection | enterRegion | packageOperand | unpackageOperand => cases computed

/-- Entry forms currently owned by the separate disposal/template drivers.
This records the remaining execution-embedding obligation; it is not a claim
that their required behavior is absent from the generalized core. -/
def Configuration.separateDriver : Configuration signature algebra program result → Bool
  | .code instruction _ _ _ => match instruction with
    | .dispose _ | .clone _ => true
    | _ => false
  | _ => false

/-- A nonowning continuation view cannot enter the one-shot dispatcher.
Registered multi views have a distinct admitted entry operation. -/
def missingGrantCode (instruction : Code signature algebra program context operands input)
    (values : RuntimeEnvironment signature algebra program operands) : Bool :=
  match instruction with
  | .resume _ | .replaceHandler _ _ _ _ | .inject _ =>
    match values with
    | .cons _ (.cons (.continuation _ authority) _) => authority.isNone
  | _ => false

def Configuration.missingControlGrant : Configuration signature algebra program result → Bool
  | .code instruction _ values _ => missingGrantCode instruction values
  | _ => false

theorem ExecutionStep.uses_current_driver
    {table : Definitions signature algebra program} {before after : State signature algebra program result}
    (step : ExecutionStep table before after) :
    before.control.configuration.separateDriver = false ∧ before.control.configuration.missingControlGrant = false := by
  cases step with
  | cell actual =>
    cases actual with
    | ordinary actual neutral =>
      cases actual with
      | operand instruction => cases instruction <;> exact ⟨rfl, rfl⟩
      | _ => exact ⟨rfl, rfl⟩
    | allocate | read | write => exact ⟨rfl, rfl⟩
  | control actual =>
    cases actual with
    | ordinary actual neutral =>
      cases actual with
      | operand instruction => cases instruction <;> exact ⟨rfl, rfl⟩
      | _ => exact ⟨rfl, rfl⟩
    | operand actual => cases actual with
      | ordinary actual neutral => cases actual <;> exact ⟨rfl, rfl⟩
      | ownedClose | sharedClose => exact ⟨rfl, rfl⟩
    | application | resume | successor | injection | handled => exact ⟨rfl, rfl⟩
  | installHandler | enterProtection | enterRegion | packageOperand | unpackageOperand => exact ⟨rfl, rfl⟩

theorem ExecutionStep.returned_is_ordinary
    {table : Definitions signature algebra program}
    (value : RuntimeValue signature algebra program input) (outside : Stack signature algebra program input result)
    (store : ControlHeap signature algebra program)
    (storage : Cells signature algebra (fun context result => Code signature algebra program context [] result))
    (regions : List (Id .region))
    (step : ExecutionStep table ⟨⟨store, .returned value outside⟩, storage, regions⟩ after) :
    after.control.store = store ∧ after.cells = storage ∧ after.liveRegions = regions ∧
      CallStep table (.returned value outside) after.control.configuration := by
  cases step with
  | cell actual => cases actual with
    | ordinary actual neutral => exact ⟨rfl, rfl, rfl, actual⟩
  | control actual => cases actual with
    | ordinary actual neutral => exact ⟨rfl, rfl, rfl, actual⟩

theorem ExecutionStep.failed_is_ordinary
    {table : Definitions signature algebra program}
    (fault : algebra.Fault) (outside : Stack signature algebra program input result)
    (store : ControlHeap signature algebra program)
    (storage : Cells signature algebra (fun context result => Code signature algebra program context [] result))
    (regions : List (Id .region))
    (step : ExecutionStep table ⟨⟨store, .failed fault outside⟩, storage, regions⟩ after) :
    after.control.store = store ∧ after.cells = storage ∧ after.liveRegions = regions ∧
      CallStep table (.failed fault outside) after.control.configuration := by
  cases step with
  | cell actual => cases actual with
    | ordinary actual neutral => exact ⟨rfl, rfl, rfl, actual⟩
  | control actual => cases actual with
    | ordinary actual neutral => exact ⟨rfl, rfl, rfl, actual⟩

theorem ExecutionStep.no_yielded_step
    {table : Definitions signature algebra program} (next : Configuration signature algebra program result)
    (store : ControlHeap signature algebra program)
    (storage : Cells signature algebra (fun context result => Code signature algebra program context [] result))
    (regions : List (Id .region)) :
    ¬ ExecutionStep table ⟨⟨store, .yielded next⟩, storage, regions⟩ after := by
  intro step
  cases step with
  | cell actual => cases actual with
    | ordinary actual neutral => cases actual
  | control actual => cases actual with
    | ordinary actual neutral => cases actual

end Target

namespace Defunctionalization

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}
  [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]

/-- Reflect the ordinary receiving instruction after an ownership-sensitive
prefix. These are source execution constructors, not pure-evaluation premises. -/
theorem ordinary_receiver_execution_reflected
    (table : Source.Definitions signature algebra program)
    (body : Source.Computation signature algebra program context input)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (values : Source.RuntimeEnvironment signature algebra program body.operandPrefix.types)
    (storage : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region))
    {sourceStore evaluated : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (operands : Source.ArgumentsEvaluation bindings storage.reservations.custody sourceStore body.operandPrefix.arguments (.ok values) evaluated)
    (stores : ControlHeapRelated evaluated targetStore)
    {sourceOutside : Source.Context signature algebra program input result} {targetOutside : Target.Stack signature algebra program input result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    {targetAfter : Target.Configuration signature algebra program result}
    (step : Target.CallStep (definitions table)
      (.code (operandTail body) (environment bindings) ((environment values).pushReverse .nil) targetOutside) targetAfter)
    (neutral : (Target.Configuration.code (operandTail body) (environment bindings) ((environment values).pushReverse .nil) targetOutside).needsOwnershipStep = false) :
    ∃ sourceAfter,
      Source.ExecutionStep table ⟨⟨sourceStore, sourceOutside.plug (.evaluate body bindings)⟩, storage, regions⟩ sourceAfter ∧
      ExecutionStateRelated sourceAfter ⟨⟨targetStore, targetAfter⟩, cells storage, regions⟩ := by
  obtain ⟨attachment, computed⟩ := step.computes_next
  cases body with
  | returnValue expression =>
    cases values with
    | cons value rest =>
      cases rest
      change some (.returned (Defunctionalization.value value) targetOutside) = some targetAfter at computed
      cases computed
      exact ⟨_, .returnOperand operands.singleton, ⟨stores, rfl, rfl, (EntryRelated.returned value outside).as_program⟩⟩
  | primitive operation inputs =>
    cases values with
    | cons value rest =>
      cases rest
      cases value with
      | datum datum => cases datum with
        | leaf value =>
          change some (.returned (.datum (.leaf value)) targetOutside) = some targetAfter at computed
          cases computed
          exact ⟨_, .primitiveOperands operands.singleton, ⟨stores, rfl, rfl, (EntryRelated.returned (.datum (.leaf value)) outside).as_program⟩⟩
  | call reference arguments =>
    simp only [operandTail, Target.nextWithAttachment, Target.codeNext, Target.operandNextCode,
      Environment.popReverse_pushReverse, recursive_table_lookup, Option.some.injEq] at computed
    subst targetAfter
    exact ⟨_, .namedOperands operands, ⟨stores, rfl, rfl,
      (EntryRelated.evaluate (reference.lookup table) values (.passthrough bindings outside)).as_program⟩⟩
  | @apply context use parameters answer function arguments =>
    cases values with
    | cons closure actual =>
      cases closure with
      | datum datum => cases datum
      | closure body captured authority =>
        have atCall : Target.Configuration.code (operandTail (.apply function arguments)) (environment bindings)
            ((environment (.cons (.closure body captured authority) actual)).pushReverse .nil) targetOutside =
            .code (.callClosure (use := use) (parameters := parameters) .ret) (environment bindings)
              ((environment actual).pushReverse (.cons (.closure (computation body) (environment captured) authority) .nil)) targetOutside := by
          simp only [operandTail, environment, Environment.map, Value.map, Environment.pushReverse]
          apply configuration_reindex
          simp [List.reverse_cons]
        rw [atCall] at neutral
        cases neutral
  | handle => cases neutral
  | matchSum expression left right =>
    cases values with
    | cons value rest =>
      cases rest
      change (match (Defunctionalization.value value).asSum with
        | .inl payload => some (.code (computation left) (.cons payload (environment bindings)) .nil targetOutside)
        | .inr payload => some (.code (computation right) (.cons payload (environment bindings)) .nil targetOutside)) = some targetAfter at computed
      cases selected : value.asSum with
      | inl payload =>
        simp only [Defunctionalization.value, Value.map_asSum, selected, Sum.map_inl, Option.some.injEq] at computed
        subst targetAfter
        exact ⟨_, .branchLeftOperands operands.singleton selected,
          ⟨stores, rfl, rfl, (EntryRelated.evaluate left (.cons payload bindings) outside).as_program⟩⟩
      | inr payload =>
        simp only [Defunctionalization.value, Value.map_asSum, selected, Sum.map_inr, Option.some.injEq] at computed
        subst targetAfter
        exact ⟨_, .branchRightOperands operands.singleton selected,
          ⟨stores, rfl, rfl, (EntryRelated.evaluate right (.cons payload bindings) outside).as_program⟩⟩
  | perform operation capability payload bodies =>
    cases values with
    | cons capabilityValue rest =>
      cases rest with
      | cons payloadValue bodyValues =>
        cases capabilityValue with
        | datum datum => cases datum with
          | capability identity =>
            have atDispatch : Target.Configuration.code (operandTail (.perform operation capability payload bodies)) (environment bindings)
                ((environment (.cons (.datum (.capability identity)) (.cons payloadValue bodyValues))).pushReverse .nil) targetOutside =
                .code (.dispatch operation .ret) (environment bindings)
                  ((environment bodyValues).pushReverse (.cons (value payloadValue) (.cons (.datum (.capability identity)) .nil))) targetOutside := by
              simp only [operandTail, environment, Environment.map, Value.map, Environment.pushReverse, value,
                eq_mpr_eq_cast, cast_cast]
              apply configuration_reindex
              simp [List.reverse_cons, List.append_assoc]
            rw [atDispatch] at computed
            simp only [Target.nextWithAttachment, Target.codeNext, Target.operandNextCode,
              Environment.popReverse_pushReverse, Option.some.injEq] at computed
            subst targetAfter
            exact ⟨_, .performOperands operands,
              ⟨stores, rfl, rfl, (EntryRelated.requested operation identity payloadValue bodyValues (.passthrough bindings outside)).as_program⟩⟩
  | bind first rest =>
    cases values
    cases operands
    change some (.code (computation first) (environment bindings) .nil
      (.push (.returnTo (.enter (computation rest)) (environment bindings) .nil) targetOutside)) = some targetAfter at computed
    cases computed
    exact ⟨_, Source.Step.in_state_context .bind rfl sourceOutside sourceStore storage regions,
      ⟨stores, rfl, rfl, outside.close_program (.bind rest bindings (.evaluate first bindings _))⟩⟩
  | fail fault =>
    cases values
    cases operands
    change some (.failed fault targetOutside) = some targetAfter at computed
    cases computed
    exact ⟨_, Source.Step.in_state_context .fail rfl sourceOutside sourceStore storage regions,
      ⟨stores, rfl, rfl, (EntryRelated.failed fault outside).as_program⟩⟩
  | yieldThen body =>
    cases values
    cases operands
    change some (.yielded (.code (computation body) (environment bindings) .nil targetOutside)) = some targetAfter at computed
    cases computed
    exact ⟨_, Source.Step.in_state_context .yield rfl sourceOutside sourceStore storage regions,
      ⟨stores, rfl, rfl, outside.close_program (.yielded (.evaluate body bindings _))⟩⟩
  | resume | resumeWith | inject | cellNew | cellRead | cellWrite | dispose | clone | package | unpackage | withRegion | protect =>
    simp only [operandTail, computation, Target.nextWithAttachment, Target.codeNext, Target.operandNextCode] at computed
    cases computed

private theorem ordinary_receiver_observing_reflected
    (table : Source.Definitions signature algebra program)
    (body : Source.Computation signature algebra program context input)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (values : Source.RuntimeEnvironment signature algebra program body.operandPrefix.types)
    (storage : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region))
    {sourceStore evaluated : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (operands : Source.ArgumentsEvaluation bindings storage.reservations.custody sourceStore body.operandPrefix.arguments (.ok values) evaluated)
    (stores : ControlHeapRelated evaluated targetStore)
    {sourceOutside : Source.Context signature algebra program input result} {targetOutside : Target.Stack signature algebra program input result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    {final : Target.State signature algebra program result}
    (run : Target.ExecutionSteps (definitions table)
      ⟨⟨targetStore, .code (operandTail body) (environment bindings) ((environment values).pushReverse .nil) targetOutside⟩,
        cells storage, regions⟩ count final)
    (head : Target.HeadObservation final.control.configuration observation)
    (available : (Target.nextWithAttachment (definitions table) ⟨0⟩
      (.code (operandTail body) (environment bindings) ((environment values).pushReverse .nil) targetOutside)).isSome = true)
    (neutral : (Target.Configuration.code (operandTail body) (environment bindings) ((environment values).pushReverse .nil) targetOutside).needsOwnershipStep = false) :
    ∃ sourceAfter targetAfter remaining, remaining < count ∧
      Source.ExecutionStep table ⟨⟨sourceStore, sourceOutside.plug (.evaluate body bindings)⟩, storage, regions⟩ sourceAfter ∧
      ExecutionStateRelated sourceAfter targetAfter ∧ Target.ExecutionSteps (definitions table) targetAfter remaining final := by
  cases run with
  | refl => cases head
  | @cons first middle rest last step tail =>
    obtain ⟨next, computed⟩ := Option.isSome_iff_exists.mp available
    obtain ⟨stored, cellsAt, regionsAt, ordinary⟩ := step.ordinary_of_next computed neutral
    obtain ⟨sourceAfter, sourceStep, matched⟩ := ordinary_receiver_execution_reflected table body bindings values storage regions operands stores outside ordinary neutral
    refine ⟨sourceAfter, _, _, by omega, sourceStep, ?_, tail⟩
    cases middle with
    | mk control targetCells targetRegions =>
      cases control
      simp only at stored cellsAt regionsAt
      subst_vars
      exact matched

/-- Assemble the receiving-instruction inverses of the current execution
relation. Separate-driver exclusions below remain explicit coverage debt for D;
this lemma is not the completed whole-core adequacy claim. -/
theorem evaluated_receiver_run_reflected
    (table : Source.Definitions signature algebra program)
    (body : Source.Computation signature algebra program context input)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (values : Source.RuntimeEnvironment signature algebra program body.operandPrefix.types)
    (storage : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region))
    {sourceStore evaluated : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (operands : Source.ArgumentsEvaluation bindings storage.reservations.custody sourceStore body.operandPrefix.arguments (.ok values) evaluated)
    (stores : ControlHeapRelated evaluated targetStore)
    {sourceOutside : Source.Context signature algebra program input result} {targetOutside : Target.Stack signature algebra program input result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    {final : Target.State signature algebra program result}
    (run : Target.ExecutionSteps (definitions table)
      ⟨⟨targetStore, .code (operandTail body) (environment bindings) ((environment values).pushReverse .nil) targetOutside⟩,
        cells storage, regions⟩ count final)
    (head : Target.HeadObservation final.control.configuration observation) :
    ∃ sourceAfter targetAfter remaining, remaining < count ∧
      Source.ExecutionStep table ⟨⟨sourceStore, sourceOutside.plug (.evaluate body bindings)⟩, storage, regions⟩ sourceAfter ∧
      ExecutionStateRelated sourceAfter targetAfter ∧ Target.ExecutionSteps (definitions table) targetAfter remaining final := by
  cases body with
  | returnValue expression | primitive operation inputs =>
    cases values with
    | cons value rest =>
      cases rest
      exact ordinary_receiver_observing_reflected table _ bindings _ storage regions operands stores outside run head rfl rfl
  | bind first rest | fail fault | yieldThen body =>
    cases values
    exact ordinary_receiver_observing_reflected table _ bindings _ storage regions operands stores outside run head rfl rfl
  | call reference arguments =>
    apply ordinary_receiver_observing_reflected table _ bindings _ storage regions operands stores outside run head ?_ rfl
    simp only [operandTail, Target.nextWithAttachment, Target.codeNext, Target.operandNextCode, Environment.popReverse_pushReverse, Option.isSome_some]
  | matchSum test left right =>
    cases values with
    | cons value rest =>
      cases rest
      apply ordinary_receiver_observing_reflected table _ bindings _ storage regions operands stores outside run head ?_ rfl
      change (match (Defunctionalization.value value).asSum with
        | .inl payload => some (Target.Configuration.code (computation left) (.cons payload (environment bindings)) .nil targetOutside)
        | .inr payload => some (Target.Configuration.code (computation right) (.cons payload (environment bindings)) .nil targetOutside)).isSome = true
      cases (Defunctionalization.value value).asSum <;> rfl
  | perform operation capability payload bodies =>
    cases values with
    | cons capabilityValue rest => cases rest with
      | cons payloadValue bodyValues => cases capabilityValue with
        | datum datum => cases datum with
          | capability identity =>
            apply ordinary_receiver_observing_reflected table _ bindings _ storage regions operands stores outside run head ?_ ?_
            all_goals
              have atDispatch : Target.Configuration.code (operandTail (.perform operation capability payload bodies)) (environment bindings)
                  ((environment (.cons (.datum (.capability identity)) (.cons payloadValue bodyValues))).pushReverse .nil) targetOutside =
                  .code (.dispatch operation .ret) (environment bindings)
                    ((environment bodyValues).pushReverse (.cons (value payloadValue) (.cons (.datum (.capability identity)) .nil))) targetOutside := by
                simp only [operandTail, environment, Environment.map, Value.map, Environment.pushReverse, value, eq_mpr_eq_cast, cast_cast]
                apply configuration_reindex
                simp [List.reverse_cons, List.append_assoc]
              rw [atDispatch]
            · simp only [Target.nextWithAttachment, Target.codeNext, Target.operandNextCode, Environment.popReverse_pushReverse, Option.isSome_some]
            · rfl
  | @apply context use parameters input function arguments =>
    cases values with
    | cons closure actual => cases closure with
      | datum datum => cases datum
      | closure body captured authority =>
        have atCall : Target.Configuration.code (operandTail (.apply function arguments)) (environment bindings)
            ((environment (.cons (.closure body captured authority) actual)).pushReverse .nil) targetOutside =
            .code (.callClosure (use := use) (parameters := parameters) .ret) (environment bindings)
              ((environment actual).pushReverse (.cons (.closure (computation body) (environment captured) authority) .nil)) targetOutside := by
          simp only [operandTail, environment, Environment.map, Value.map, Environment.pushReverse]
          apply configuration_reindex
          simp [List.reverse_cons]
        rw [atCall] at run
        exact application_execution_reflected table function arguments body captured actual authority bindings storage regions operands stores outside run head
  | handle effect mode returned clauses body =>
    cases values
    cases operands
    exact installation_execution_reflected table effect mode returned clauses body bindings storage regions stores outside run head
  | protect cleanup body =>
    cases values
    cases operands
    exact protection_execution_reflected table cleanup body bindings storage regions stores outside run head
  | withRegion body =>
    cases values
    cases operands
    exact region_execution_reflected table body bindings storage regions stores outside run head
  | package expression =>
    cases values with
    | cons value rest =>
      cases rest
      exact package_execution_reflected table expression bindings value storage regions operands.singleton stores outside run head
  | unpackage expression =>
    cases values with
    | cons value rest =>
      cases rest
      cases value with
      | datum datum => cases datum
      | package token owner value =>
        exact unpackage_execution_reflected table expression bindings value token owner storage regions operands.singleton stores outside run head
  | cellRead expression =>
    cases values with
    | cons value rest =>
      cases rest
      cases value with
      | datum datum => cases datum
      | cell identity region =>
        exact cell_read_execution_reflected table expression bindings storage regions operands.singleton stores outside run head
  | cellWrite reference replacement =>
    cases values with
    | cons referenceValue rest => cases rest with
      | cons value rest =>
        cases rest
        cases referenceValue with
        | datum datum => cases datum
        | cell identity region =>
          exact cell_write_execution_reflected table reference replacement bindings value storage regions operands stores outside run head
  | cellNew regionExpression initializer =>
    cases values with
    | cons regionValue rest => cases rest with
      | cons value rest =>
        cases rest
        cases regionValue with
        | datum datum => cases datum with
          | region identity =>
            exact cell_allocation_execution_reflected table regionExpression initializer bindings value storage regions operands stores outside run head
  | resume continuation response =>
    cases values with
    | cons control rest => cases rest with
      | cons value rest =>
        cases rest
        cases control with
        | datum datum => cases datum
        | continuation identity authority =>
          cases authority with
          | none =>
            cases run with
            | refl => cases head
            | cons step tail => cases step.uses_current_driver.2
          | some grant => cases grant with
            | mk token owner =>
              exact resume_execution_reflected table continuation response bindings value ⟨identity, token, owner⟩ storage regions operands stores outside run head
  | resumeWith effect continuation response returned clauses =>
    cases values with
    | cons control rest => cases rest with
      | cons value rest =>
        cases rest
        cases control with
        | datum datum => cases datum
        | continuation identity authority =>
          cases authority with
          | none =>
            cases run with
            | refl => cases head
            | cons step tail => cases step.uses_current_driver.2
          | some grant => cases grant with
            | mk token owner =>
              exact successor_execution_reflected table continuation response returned clauses bindings value ⟨identity, token, owner⟩ storage regions operands stores outside run head
  | inject continuation injected =>
    cases values with
    | cons control rest => cases rest with
      | cons bodyValue rest =>
        cases rest
        cases control with
        | datum datum => cases datum
        | continuation identity authority =>
          cases authority with
          | none =>
            cases run with
            | refl => cases head
            | cons step tail => cases step.uses_current_driver.2
          | some grant => cases grant with
            | mk token owner =>
              cases bodyValue with
              | datum datum => cases datum
              | closure body captured authority =>
                exact injection_execution_reflected table continuation injected body captured authority bindings ⟨identity, token, owner⟩
                  storage regions operands stores outside run head
  | dispose | clone =>
    cases run with
    | refl => cases head
    | cons step tail => cases step.uses_current_driver.1

/-- A finite target run from compiled syntax yields one actual source
transition and a strictly shorter related residual run. The operand and
receiving-operation inverses share the same current resources. -/
theorem computation_stateful_step_reflected
    (table : Source.Definitions signature algebra program)
    (body : Source.Computation signature algebra program context input)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (storage : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region))
    {sourceStore : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (stores : ControlHeapRelated sourceStore targetStore)
    {sourceOutside : Source.Context signature algebra program input result} {targetOutside : Target.Stack signature algebra program input result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    {final : Target.State signature algebra program result}
    (run : Target.ExecutionSteps (definitions table)
      ⟨⟨targetStore, .code (computation body) (environment bindings) .nil targetOutside⟩, cells storage, regions⟩ count final)
    (head : Target.HeadObservation final.control.configuration observation) :
    ∃ sourceAfter targetAfter remaining, remaining < count ∧
      Source.ExecutionStep table ⟨⟨sourceStore, sourceOutside.plug (.evaluate body bindings)⟩, storage, regions⟩ sourceAfter ∧
      ExecutionStateRelated sourceAfter targetAfter ∧ Target.ExecutionSteps (definitions table) targetAfter remaining final := by
  obtain ⟨outcome, sourceEvaluated, targetEvaluated, remaining, operands, evaluatedRelated, bounded, faultLess, tail⟩ :=
    computation_operands_observing_run_reflected table body bindings storage regions stores targetOutside run head
  cases outcome with
  | error fault =>
    exact ⟨_, _, remaining, faultLess fault rfl, .operandFault operands,
      ⟨evaluatedRelated, rfl, rfl, (EntryRelated.failed fault outside).as_program⟩, tail⟩
  | ok values =>
    obtain ⟨sourceAfter, targetAfter, rest, smaller, sourceStep, matched, following⟩ :=
      evaluated_receiver_run_reflected table body bindings values storage regions operands evaluatedRelated outside tail head
    exact ⟨sourceAfter, targetAfter, rest, by omega, sourceStep, matched, following⟩

/-- Reflect a handled request across its whole logical context. Source
selection owns the source interpretation; target selection supplies only the
observed transition whose corresponding source selection is derived. -/
theorem requested_state_step_reflected
    (table : Source.Definitions signature algebra program)
    (operation : signature.operation effect) (attachment : Id .attachment)
    (payload : Source.RuntimeValue signature algebra program (signature.payload operation))
    (bodies : Source.RuntimeEnvironment signature algebra program ((signature.bodies operation).map BodyType.type))
    (saved : Source.Context signature algebra program (signature.result operation) input)
    (around : Source.Context signature algebra program input result)
    (targetFuture : Target.Stack signature algebra program (signature.result operation) result)
    (future : ContextRelated signature algebra program (saved.append around) targetFuture)
    (storage : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region))
    {sourceStore : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (stores : ControlHeapRelated sourceStore targetStore)
    (step : Target.ExecutionStep (definitions table)
      ⟨⟨targetStore, .requested operation attachment (value payload) (environment bodies) targetFuture⟩, cells storage, regions⟩ targetAfter) :
    ∃ sourceAfter,
      Source.ExecutionStep table ⟨⟨sourceStore, around.plug (.request operation attachment payload bodies saved)⟩, storage, regions⟩ sourceAfter ∧
      ExecutionStateRelated sourceAfter targetAfter := by
  generalize atRequest : Target.Configuration.requested operation attachment (value payload) (environment bodies) targetFuture = initial at step
  cases step with
  | cell actual => cases actual with
    | ordinary actual neutral =>
      obtain ⟨choice, computed⟩ := actual.computes_next
      rw [← atRequest] at computed
      cases computed
    | allocate | read | write => cases atRequest
  | control actual => cases actual with
    | ordinary actual neutral =>
      obtain ⟨choice, computed⟩ := actual.computes_next
      rw [← atRequest] at computed
      cases computed
    | operand | application | resume | successor | injection => cases atRequest
    | @handled actualAttachment owner actualEffect actualOperation operationEquality mode context body answer result returned clauses bindings actualPayload actualBodies inside outside store before captured after partition clause nearest accepted =>
      cases atRequest
      have targetSelected := Target.matching_delimiter_after_prefix attachment inside effect mode returned clauses bindings outside nearest
      obtain ⟨sourceSelected, sourceFound, selectedRelated⟩ := corresponding_target_acceptance
        (selection_corresponds attachment future) targetSelected
      have sourcePartition : sourceStore.fields.active = before ++ captured ++ after := by
        rw [stores.fields]
        exact partition
      have reservations : (cells storage).reservations = storage.reservations := Cells.reservations_mapBodies _ storage
      rw [reservations] at accepted
      cases selectedRelated with
      | selected effect mode identity sourceReturned sourceClauses sourceBindings insideRelated outsideRelated =>
        obtain ⟨sourceClause, sourceAccepted, matched⟩ := corresponding_target_acceptance
          (owned_clause_dispatch_corresponds operation attachment sourceReturned sourceClauses sourceBindings insideRelated
            payload bodies outsideRelated owner before captured after stores sourcePartition partition storage.reservations) accepted
        exact ⟨_, .control (.handledRequest (saved := saved) (around := around) (partition := sourcePartition) sourceFound sourceAccepted),
          ⟨matched.store, rfl, rfl, matched.entry.as_program⟩⟩
  | installHandler | enterProtection | enterRegion | packageOperand | unpackageOperand => cases atRequest

private theorem stateful_reflection_bounded (table : Source.Definitions signature algebra program) (bound : Nat) :
    ∀ {input result} {source : Source.Program signature algebra program input}
      {sourceOutside : Source.Context signature algebra program input result}
      {targetOutside : Target.Stack signature algebra program input result}
      {target : Target.Configuration signature algebra program result}
      {count} {final : Target.State signature algebra program result} {observation},
      count < bound → ProgramRelated source targetOutside target →
      ContextRelated signature algebra program sourceOutside targetOutside →
      ∀ {sourceStore : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program},
      ControlHeapRelated sourceStore targetStore →
      ∀ (storage : Cells signature algebra (Source.Computation signature algebra program)) regions,
      Target.ExecutionSteps (definitions table) ⟨⟨targetStore, target⟩, cells storage, regions⟩ count final →
      Target.HeadObservation final.control.configuration observation →
      ∃ sourceFinal sourceObservation,
        Source.StateObserves table ⟨⟨sourceStore, sourceOutside.plug source⟩, storage, regions⟩ sourceFinal sourceObservation ∧
        StateObservationRelated sourceFinal final sourceObservation observation := by
  induction bound with
  | zero => intros; omega
  | succ bound smaller =>
    intro input result source sourceOutside targetOutside target count final observation counted related outside sourceStore targetStore stores storage regions run head
    have reflectTail {remaining} (sourceAfter : Source.State signature algebra program result)
        (targetAfter : Target.State signature algebra program result)
        (decreased : remaining < bound) (matched : ExecutionStateRelated sourceAfter targetAfter)
        (tail : Target.ExecutionSteps (definitions table) targetAfter remaining final) :
        ∃ sourceFinal sourceObservation, Source.StateObserves table sourceAfter sourceFinal sourceObservation ∧
          StateObservationRelated sourceFinal final sourceObservation observation := by
      rcases sourceAfter with ⟨⟨sourceHeap, sourceProgram⟩, sourceCells, sourceRegions⟩
      rcases targetAfter with ⟨⟨targetHeap, targetProgram⟩, targetCells, targetRegions⟩
      rcases matched with ⟨heaps, sameCells, sameRegions, programs⟩
      dsimp only at sameCells sameRegions programs
      subst targetCells
      subst targetRegions
      exact smaller decreased programs .done heaps sourceCells sourceRegions tail head
    induction related with
    | evaluate body bindings future =>
      obtain ⟨sourceAfter, targetAfter, remaining, decreased, sourceStep, matched, tail⟩ :=
        computation_stateful_step_reflected table body bindings storage regions stores outside run head
      obtain ⟨sourceFinal, sourceObservation, observed, same⟩ := reflectTail sourceAfter targetAfter (by omega) matched tail
      exact ⟨sourceFinal, sourceObservation, observed.prepend (.cons sourceStep .refl), same⟩
    | bind body bindings inner induction =>
      simpa only [Source.Context.plug, Source.Frame.plug, Source.Frame.bindAuthored, Source.Program.bindAuthored] using
        induction (.push (.bind body bindings) outside) run head reflectTail
    | handler effect mode attachment returned clauses bindings inner induction =>
      simpa only [Source.Context.plug, Source.Frame.plug] using
        induction (.push (.handler effect mode attachment returned clauses bindings) outside) run head reflectTail
    | region identity inner induction =>
      simpa only [Source.Context.plug, Source.Frame.plug] using induction (.push (.region identity) outside) run head reflectTail
    | protection identity cleanup bindings inner induction =>
      simpa only [Source.Context.plug, Source.Frame.plug] using induction (.push (.protection identity cleanup bindings) outside) run head reflectTail
    | cleaning identity original exit inner induction =>
      simpa only [Source.Context.plug, Source.Frame.plug] using induction (.push (.cleanupReturn identity original exit) outside) run head reflectTail
    | passthrough bindings inner induction => exact induction (.passthrough bindings outside) run head reflectTail
    | yielded inner induction =>
      cases run with
      | refl => cases head
                exact ⟨_, _, ⟨sourceOutside.length, sourceOutside.forward_yield_state table _ sourceStore storage regions, .yielded⟩,
                  ⟨stores, rfl, rfl, .yielded (outside.close_program inner)⟩⟩
      | cons step tail => exact False.elim (Target.ExecutionStep.no_yielded_step _ targetStore (cells storage) regions step)
    | requested operation attachment payload bodies saved future =>
      cases run with
      | refl =>
        exact stateful_head_observation_reflected table
          (⟨stores, rfl, rfl, outside.close_program (.requested operation attachment payload bodies saved _)⟩ :
            ExecutionStateRelated ⟨⟨sourceStore, sourceOutside.plug (.request operation attachment payload bodies _)⟩, storage, regions⟩ _) head
      | cons step tail =>
        obtain ⟨sourceAfter, sourceStep, matched⟩ := requested_state_step_reflected table operation attachment payload bodies _ sourceOutside
          _ (context_composition saved outside) storage regions stores step
        obtain ⟨sourceFinal, sourceObservation, observed, same⟩ := reflectTail sourceAfter _ (by omega) matched tail
        exact ⟨sourceFinal, sourceObservation, observed.prepend (.cons sourceStep .refl), same⟩
    | returned value future =>
      cases outside with
      | done =>
        have finalAt := Target.ExecutionSteps.returned_done (Defunctionalization.value value) targetStore (cells storage) regions run
        subst final
        cases head
        exact ⟨_, _, ⟨0, .refl, .returned⟩, ⟨stores, rfl, rfl, .returned value⟩⟩
      | passthrough bindings rest =>
        obtain ⟨firstCount, firstEq, firstRun⟩ := Target.ordinary_cancel_stateful_observed Target.CallStep.caller rfl run head
        obtain ⟨remaining, secondEq, tail⟩ := Target.ordinary_cancel_stateful_observed Target.CallStep.returned rfl firstRun head
        exact smaller (by omega) (.returned value _) rest stores storage regions tail head
      | push frame rest =>
        cases frame with
        | bind body bindings =>
          obtain ⟨firstCount, firstEq, firstRun⟩ := Target.ordinary_cancel_stateful_observed Target.CallStep.caller rfl run head
          obtain ⟨remaining, secondEq, tail⟩ := Target.ordinary_cancel_stateful_observed Target.CallStep.enter rfl firstRun head
          obtain ⟨sourceFinal, sourceObservation, observed, same⟩ := smaller (by omega) (.evaluate body (.cons value bindings) _) rest stores storage regions tail head
          exact ⟨sourceFinal, sourceObservation, observed.prepend (.cons (Source.Step.in_state_context .bindValue rfl _ sourceStore storage regions) .refl), same⟩
        | handler effect mode identity returned clauses bindings =>
          obtain ⟨remaining, decreased, tail⟩ := Target.ordinary_cancel_stateful_observed Target.CallStep.handlerReturned rfl run head
          obtain ⟨sourceFinal, sourceObservation, observed, same⟩ := smaller (by omega) (.evaluate returned (.cons value bindings) _) rest stores storage regions tail head
          exact ⟨sourceFinal, sourceObservation, observed.prepend (.cons (Source.Step.in_state_context .handlerValue rfl _ sourceStore storage regions) .refl), same⟩
        | protection identity cleanup bindings =>
          obtain ⟨remaining, decreased, tail⟩ := Target.ordinary_cancel_stateful_observed Target.CallStep.protectionReturn rfl run head
          obtain ⟨sourceFinal, sourceObservation, observed, same⟩ := smaller (by omega)
            (.cleaning identity (some value) ⟨.normal, [], none⟩ (.evaluate cleanup (.cons (.exit ⟨.normal, [], none⟩) bindings) _)) rest stores storage regions tail head
          exact ⟨sourceFinal, sourceObservation, observed.prepend (.cons (Source.Step.in_state_context .protectionReturn rfl _ sourceStore storage regions) .refl), same⟩
        | cleanupReturn identity original exit =>
          cases original with
          | none =>
            cases run with
            | refl => cases head
            | cons step tail =>
              have ordinary := (step.returned_is_ordinary _ _ _ _ _).2.2.2
              cases ordinary
          | some original =>
            cases run with
            | refl => cases head
            | @cons first middle count last step tail =>
              rcases middle with ⟨⟨heap, configuration⟩, targetCells, targetRegions⟩
              obtain ⟨stored, sameCells, sameRegions, ordinary⟩ := step.returned_is_ordinary _ _ _ _ _
              dsimp only at stored sameCells sameRegions ordinary
              subst heap
              subst targetCells
              subst targetRegions
              cases ordinary with
              | cleanupReturn normal =>
                obtain ⟨sourceFinal, sourceObservation, observed, same⟩ := smaller (by omega) (.returned original _) rest stores storage regions tail head
                exact ⟨sourceFinal, sourceObservation, observed.prepend (.cons (Source.Step.in_state_context (.cleaningReturn normal) rfl _ sourceStore storage regions) .refl), same⟩
        | region identity =>
          cases run with
          | refl => cases head
          | cons step tail =>
            have ordinary := (step.returned_is_ordinary _ _ _ _ _).2.2.2
            cases ordinary
    | failed fault future =>
      cases outside with
      | done =>
        have finalAt := Target.ExecutionSteps.failed_done fault _ targetStore (cells storage) regions run
        subst final
        cases head
        exact ⟨_, _, ⟨0, .refl, .failed⟩, ⟨stores, rfl, rfl, .failed fault⟩⟩
      | passthrough bindings rest =>
        obtain ⟨remaining, decreased, tail⟩ := Target.ordinary_cancel_stateful_observed Target.CallStep.callerFault rfl run head
        exact smaller (by omega) (.failed fault _) rest stores storage regions tail head
      | push frame rest =>
        cases frame with
        | bind body bindings =>
          obtain ⟨remaining, decreased, tail⟩ := Target.ordinary_cancel_stateful_observed Target.CallStep.callerFault rfl run head
          obtain ⟨sourceFinal, sourceObservation, observed, same⟩ := smaller (by omega) (.failed fault _) rest stores storage regions tail head
          exact ⟨sourceFinal, sourceObservation, observed.prepend (.cons (Source.Step.in_state_context .bindFault rfl _ sourceStore storage regions) .refl), same⟩
        | handler effect mode identity returned clauses bindings =>
          obtain ⟨remaining, decreased, tail⟩ := Target.ordinary_cancel_stateful_observed Target.CallStep.handlerFault rfl run head
          obtain ⟨sourceFinal, sourceObservation, observed, same⟩ := smaller (by omega) (.failed fault _) rest stores storage regions tail head
          exact ⟨sourceFinal, sourceObservation, observed.prepend (.cons (Source.Step.in_state_context .handlerFault rfl _ sourceStore storage regions) .refl), same⟩
        | region identity | protection identity cleanup bindings | cleanupReturn identity original exit =>
          cases run with
          | refl => cases head
          | cons step tail =>
            have ordinary := (step.failed_is_ordinary _ _ _ _ _).2.2.2
            cases ordinary

/-- Finite reflection for the current shared execution relation, with all four
observations and related current resources. The separate disposal/template/exit
embeddings remain required before this is whole-core D adequacy. -/
theorem stateful_observation_reflected
    (table : Source.Definitions signature algebra program)
    {source : Source.State signature algebra program result} {target : Target.State signature algebra program result}
    (related : ExecutionStateRelated source target)
    (observed : Target.StateObserves (definitions table) target targetFinal observation) :
    ∃ sourceFinal sourceObservation, Source.StateObserves table source sourceFinal sourceObservation ∧
      StateObservationRelated sourceFinal targetFinal sourceObservation observation := by
  rcases source with ⟨⟨sourceStore, sourceProgram⟩, sourceCells, sourceRegions⟩
  rcases target with ⟨⟨targetStore, targetProgram⟩, targetCells, targetRegions⟩
  rcases related with ⟨stores, cellsAt, regionsAt, programs⟩
  dsimp only at cellsAt regionsAt programs
  subst targetCells
  subst targetRegions
  obtain ⟨count, run, head⟩ := observed
  exact stateful_reflection_bounded table (count + 1) (by omega) programs .done stores sourceCells sourceRegions run head

end Defunctionalization
end BoundaryV2.Generalized
