import BoundaryV2.SourceOperandOutcomes

namespace BoundaryV2.Profile.Source.Machine
namespace OperandSchemas

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem unwindStep_typed (machine : State) (context : Context) (after : Transition)
    (accepted : unwindStep machine context = .ok after) (structural : OperandStructure.Valid machine)
    (running : machine.status = .running) : Typed context.source after.state := by
  have afterStructure := OperandStructure.unwindStep_valid _ _ _ accepted structural
  unfold unwindStep at accepted
  split at accepted <;> try contradiction
  rename_i original unwinding
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  cases stacked : machine.stack with
  | nil =>
    simp only [stacked] at accepted
    split at accepted
    · cases accepted
      exact plain_typed _ _ ⟨OperandStructure.noOperands_nil, structural.2⟩ trivial
    · split at accepted <;> try contradiction
      all_goals cases accepted
      all_goals exact plain_typed _ _ ⟨OperandStructure.noOperands_nil, structural.2⟩ (by simp [NonExecuting, unwinding])
  | cons saved tail =>
    cases saved <;> simp only [stacked] at accepted
    case operands =>
      cases accepted
      exact running_typed _ _ afterStructure (by simp [LocalTypes, unwinding]) running
    all_goals
      have plain := structural.nonoperand stacked (by simp)
      have tailTyped := ((OperandStructure.noOperands_cons _ _).mp (by simpa only [stacked] using plain.1)).2
      have tailPlain : OperandStructure.Plain { machine with stack := tail } := ⟨tailTyped, structural.2⟩
    case invocation =>
      split at accepted
      · cases accepted
        apply plain_typed
        · simpa only [OperandStructure.Plain, stacked] using plain
        · trivial
      · cases accepted
        exact plain_typed _ _ tailPlain (by simp [NonExecuting, unwinding])
    case lexical =>
      split at accepted
      · cases accepted
        apply plain_typed
        · simpa only [OperandStructure.Plain, stacked] using plain
        · trivial
      · simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
        obtain ⟨_, _, _, _, rfl⟩ := accepted
        exact plain_typed _ _ tailPlain (by simp [NonExecuting, unwinding])
    case protection =>
      exact plain_typed _ _ (OperandStructure.beginCleanup_plain _ _ _ _ _ _ _ accepted structural.2 tailTyped)
        (beginCleanup_nonexecuting _ _ _ _ _ _ _ accepted)
    case cleanupReturn =>
      exact plain_typed _ _ (OperandStructure.finishCleanupUnwind_plain _ _ _ _ _ _ _ _ accepted structural.2 tailTyped)
        (finishCleanupUnwind_nonexecuting _ _ _ _ _ _ _ _ accepted)
    case releaseReturn => cases accepted; exact plain_typed _ _ tailPlain trivial
    case disposalReturn =>
      repeat' split at accepted
      all_goals simp only [pure, Except.pure, Except.bind, Except.ok.injEq] at accepted
      all_goals cases accepted
      all_goals apply plain_typed
      all_goals first | exact tailPlain | simpa only [OperandStructure.Plain, stacked] using plain | trivial
    all_goals cases accepted; exact plain_typed _ _ tailPlain (by simp [NonExecuting, unwinding])

theorem cancel_local_types (source : Module) (machine : State) (reason : Protocol.Reason) :
    LocalTypes source { machine with control := cancelControl machine.control reason } := by
  cases executing : machine.control <;> simp only [cancelControl]
  all_goals repeat' split
  all_goals trivial

theorem external_typed (machine : State) (context : Context) (action : External) (after : Transition)
    (accepted : external machine context action = .ok after) (typed : Typed context.source machine) : Typed context.source after.state := by
  have running : Typed context.source { machine with status := .running } := running_typed _ _ typed.1 typed.2.1 rfl
  have cancelled (reason : Protocol.Reason) : Typed context.source
      { machine with status := .running, control := cancelControl machine.control reason, cancellation := some reason } :=
    running_typed _ _ ⟨OperandStructure.cancel_fits _ _ _ typed.1.1, typed.1.2⟩ (cancel_local_types _ _ _) rfl
  have cancellationOnly (reason : Protocol.Reason) : Typed context.source { machine with cancellation := some reason } := typed
  have scopedResult (request : Request) (value : SemanticValue) (transition : Transition)
      (parked : machine.status = .parked request)
      (checked : scopedValue { machine with status := .running } value = .ok transition) : Typed context.source transition.state := by
    have plain : OperandStructure.Plain { machine with status := .running } := ⟨typed.2.2 request parked, typed.1.2⟩
    have afterPlain := OperandStructure.scopedValue_plain _ _ _ checked plain
    obtain ⟨result, delivered, _⟩ := scopedValue_delivers _ _ _ checked
    exact plain_typed _ _ afterPlain (by simp only [NonExecuting, delivered])
  cases phase : machine.status <;> cases action <;>
    simp only [external, phase, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw,
      Except.bind] at accepted <;> try contradiction
  all_goals grind (gen := 32) only []

theorem tickRunning_typed (machine : State) (context : Context) (after : Transition)
    (accepted : tickRunning machine context = .ok after) (contextTyped : context.typingValid = true)
    (typed : Typed context.source machine) (running : machine.status = .running) : Typed context.source after.state := by
  have afterStructure := OperandStructure.tickRunning_valid _ _ _ accepted typed.1
  cases executing : machine.control <;> simp only [tickRunning, executing] at accepted
  case expression =>
    exact running_typed _ _ afterStructure (enterExpression_types _ _ _ accepted contextTyped typed.1.2 typed.2.1)
      ((enterExpression_status _ _ _ accepted).trans running)
  case unwind => exact unwindStep_typed _ _ _ accepted typed.1 running
  case term =>
    have plain : OperandStructure.Plain machine := ⟨by simpa only [OperandStructure.Fits, executing] using typed.1.1, typed.1.2⟩
    exact ⟨afterStructure, enterTerm_types _ _ _ accepted contextTyped plain, enterTerm_parked _ _ _ accepted running⟩
  case execute intent bindings operands =>
    cases intent with
    | primitive =>
      exact running_typed _ _ afterStructure (executePrimitive_types _ _ _ accepted typed.1.2 typed.2.1)
        ((executePrimitive_status _ _ _ accepted).trans running)
    | term authored =>
      have plain : OperandStructure.Plain machine := ⟨by simpa only [OperandStructure.Fits, executing] using typed.1.1, typed.1.2⟩
      cases authored <;> first
        | (have afterPlain := OperandStructure.executeEffectTerm_plain _ _ _ accepted plain
           exact ⟨afterPlain.valid, executeEffectTerm_types _ _ _ accepted typed.2.1 plain, fun _ _ => afterPlain.1⟩)
        | exact plain_typed _ _ (OperandStructure.executeCleanupTerm_plain _ _ _ accepted plain) (executeCleanupTerm_nonexecuting _ _ _ accepted)
        | exact plain_typed _ _ (OperandStructure.executeControlTerm_plain _ _ _ accepted plain) (executeControlTerm_nonexecuting _ _ _ accepted)
  case delivered value =>
    cases stacked : machine.stack with
    | nil =>
      simp only [stacked, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
      obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
      exact plain_typed _ _ ⟨OperandStructure.noOperands_nil, typed.1.2⟩ trivial
    | cons saved tail =>
      cases saved <;> simp only [stacked] at accepted
      case operands =>
        exact running_typed _ _ afterStructure (deliverOperand_types _ _ _ accepted typed.2.1)
          ((deliverOperand_status _ _ accepted).trans running)
      all_goals
        have plain := typed.1.nonoperand stacked (by simp)
        have tailTyped := ((OperandStructure.noOperands_cons _ _).mp (by simpa only [stacked] using plain.1)).2
        have tailPlain : OperandStructure.Plain { machine with stack := tail } := ⟨tailTyped, typed.1.2⟩
      all_goals first
        | exact plain_typed _ _ (OperandStructure.enterBinding_plain _ _ _ accepted plain) (enterBinding_nonexecuting _ _ _ accepted)
        | exact plain_typed _ _ (OperandStructure.leaveInvocation_plain _ _ accepted plain) (leaveInvocation_nonexecuting _ _ accepted)
        | exact plain_typed _ _ (OperandStructure.leaveLexical_plain _ _ accepted plain) (leaveLexical_nonexecuting _ _ accepted)
        | exact plain_typed _ _ (OperandStructure.restoreResumeCaller_plain _ _ accepted plain) (restoreResumeCaller_nonexecuting _ _ accepted)
        | exact plain_typed _ _ (OperandStructure.completeHandler_plain _ _ _ accepted plain) (completeHandler_nonexecuting _ _ _ accepted)
        | exact plain_typed _ _ (OperandStructure.beginCleanup_plain _ _ _ _ _ _ _ accepted typed.1.2 tailTyped) (beginCleanup_nonexecuting _ _ _ _ _ _ _ accepted)
        | exact plain_typed _ _ (OperandStructure.finishCleanup_plain _ _ _ accepted plain) (finishCleanup_nonexecuting _ _ _ accepted)
        | exact plain_typed _ _ (OperandStructure.finishDisposal_plain _ _ accepted plain) (finishDisposal_nonexecuting _ _ accepted)
        | (cases accepted; exact plain_typed _ _ tailPlain (by simp [NonExecuting]))
        | contradiction
  all_goals
    have plain : OperandStructure.Plain machine := ⟨by simpa only [OperandStructure.Fits, executing] using typed.1.1, typed.1.2⟩
  all_goals first
    | exact plain_typed _ _ (OperandStructure.enterInvocation_plain _ _ _ accepted plain) (enterInvocation_nonexecuting _ _ _ accepted)
    | exact plain_typed _ _ (OperandStructure.releaseScope_plain _ _ accepted plain) (releaseScope_nonexecuting _ _ accepted)
    | exact plain_typed _ _ (OperandStructure.discardValues_plain _ _ _ accepted plain) (discardValues_nonexecuting _ _ _ accepted)

theorem tick_typed (machine : State) (context : Context) (after : Transition)
    (accepted : tick machine context = .ok after) (contextTyped : context.typingValid = true)
    (typed : Typed context.source machine) : Typed context.source after.state := by
  cases phase : machine.status <;> simp only [tick, phase] at accepted
  · exact tickRunning_typed _ _ _ accepted contextTyped typed phase
  all_goals cases accepted; exact typed

theorem step_typed (context : Context) (before after : State) (events : List Event)
    (step : Step context before events after) (contextTyped : context.typingValid = true)
    (typed : Typed context.source before) : Typed context.source after := by
  cases step with
  | internal accepted => exact tick_typed _ _ _ accepted contextTyped typed
  | external accepted => exact external_typed _ _ _ _ accepted typed

theorem steps_typed (context : Context) (before after : State) (events : List Event)
    (steps : Steps context before events after) (contextTyped : context.typingValid = true)
    (typed : Typed context.source before) : Typed context.source after := by
  induction steps with
  | refl => exact typed
  | cons step _ induction => exact induction (step_typed _ _ _ _ step contextTyped typed)

theorem initial_typed (context : Context) (arguments : List SemanticValue) (machine : State)
    (accepted : initial context arguments = .ok machine) : Typed context.source machine := by
  simp only [initial, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, _, rfl⟩ := accepted
  apply plain_typed
  · simp [OperandStructure.Plain, OperandStructure.NoOperands, OperandStructure.HeapValid]
  · trivial

theorem initialized_execution_preserves_operand_schemas (context : Context) (arguments : List SemanticValue)
    (before after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) : Typed context.source after := by
  have contextTyped : context.typingValid = true := by
    simpa only [Context.typingValid, Option.any_eq_true] using initial_checks_typing _ _ _ initialized
  exact steps_typed _ _ _ _ steps contextTyped (initial_typed _ _ _ initialized)

theorem reachable_primitive_signature (context : Context) (arguments : List SemanticValue) (before machine : State)
    (events : List Event) (initialized : initial context arguments = .ok before) (steps : Steps context before events machine)
    (schema : SchemaId .source) (opcode : Opcode) (immediate : Nat) (failures : List (InstructionFailure .source))
    (bindings : Environment) (operands : List Located)
    (executing : machine.control = .execute (.primitive schema opcode immediate failures) bindings operands) :
    Signature context.source (.primitive schema opcode immediate failures) (schemas operands) := by
  have typed := (initialized_execution_preserves_operand_schemas _ _ _ _ _ initialized steps).2.1
  exact (show Signature context.source (.primitive schema opcode immediate failures) (schemas operands) ∧
    Spine context.source (some schema) machine.stack from by simpa only [LocalTypes, executing] using typed).1


theorem signature_admits_nonresource (context : Context) (schema : SchemaId .source) (opcode : Opcode)
    (immediate : Nat) (failures : List (InstructionFailure .source)) (types : Schemas)
    (contextTyped : context.typingValid = true)
    (signature : Signature context.source (.primitive schema opcode immediate failures) types)
    (notPack : opcode ≠ .resourcePack) (notUnpack : opcode ≠ .resourceUnpack) :
    PrimitiveAdmission.operationType (Admission.primitiveContext context.source context.captures) ⟨0⟩
      ⟨opcode, schema, immediate, failures⟩ types = true := by
  cases signature with
  | primitive member typesAt =>
    obtain ⟨index, found⟩ := List.mem_iff_getElem?.mp member
    have admitted := checked_context_checks_value context ⟨index⟩ _ contextTyped found
    simp only [Admission.primitiveValid, typesAt, Option.any_some, Bool.and_eq_true] at admitted
    simpa only [Bool.or_eq_true, beq_iff_eq, notPack, notUnpack, or_self, if_false] using admitted.2

theorem value_result_is_nonresource (context : Context) (schema : SchemaId .source) (opcode : Opcode)
    (immediate : Nat) (operands : List Located) (value : SemanticValue)
    (evaluated : Primitives.evaluate context.source.schemas context.executionConstants opcode schema immediate
      (operands.map Located.value) = .ok (.value value)) : opcode ≠ .resourcePack ∧ opcode ≠ .resourceUnpack := by
  constructor
  all_goals intro equal; subst opcode
  all_goals simp only [Primitives.evaluate, Primitives.graphArity] at evaluated
  all_goals split at evaluated <;> cases evaluated

/-- The primitive's actual operands acquire their source declaration through
initialized execution. No premise asks the caller to assume instruction
admission for these runtime values. Finite value typing is the predecessor
component consumed by this preservation lemma. -/
theorem reachable_primitive_preserves_value_shapes (context : Context) (arguments : List SemanticValue)
    (before machine : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events machine) (after : Transition)
    (accepted : executePrimitive machine context = .ok after)
    (typed : ValueInventory.All (ValueShape context.source.schemas) machine) :
    ValueInventory.All (ValueShape context.source.schemas) after.state := by
  have contextTyped : context.typingValid = true := by
    simpa only [Context.typingValid, Option.any_eq_true] using initial_checks_typing _ _ _ initialized
  unfold executePrimitive at accepted
  split at accepted <;> try contradiction
  rename_i schema opcode immediate failures bindings operands executing
  have signature := reachable_primitive_signature _ _ _ _ _ initialized steps _ _ _ _ _ _ executing
  have inputs : ∀ value ∈ operands, ValueShape context.source.schemas value.value := by
    intro value member
    apply typed
    simp only [ValueInventory.state, executing, ValueInventory.control, List.mem_append, List.mem_map]
    exact Or.inl (Or.inl (Or.inl (Or.inr ⟨value, member, rfl⟩)))
  have constantsTyped := checked_execution_constants_have_value_shapes context contextTyped
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted
  · contradiction
  · exact ValueInventory.authoredFailure_preserves_all _ _ _ _ _ accepted _ typed constantsTyped
  · rename_i value evaluated
    have nonresource := value_result_is_nonresource _ _ _ _ _ _ evaluated
    have admitted := signature_admits_nonresource _ _ _ _ _ _ contextTyped signature nonresource.1 nonresource.2
    have valueTyped := Primitives.evaluate_preserves_types
      (Admission.primitiveContext context.source context.captures) ⟨0⟩ (ReferenceOwnership context.source.schemas)
      context.executionConstants ⟨opcode, schema, immediate, failures⟩ (operands.map Located.value) value
      (checked_context_schemas_valid context contextTyped) constantsTyped
      (by
        intro child member
        obtain ⟨located, belongs, rfl⟩ := List.mem_map.mp member
        exact inputs located belongs)
      (by simpa only [schemas, List.map_map, Function.comp_def] using admitted) evaluated
    exact ValueInventory.commitPure_preserves_all _ _ _ _ _ accepted _ typed valueTyped
  · exact heapPrimitive_preserves_value_shapes _ _ _ _ _ _ _ accepted contextTyped typed inputs

theorem reachable_pop_has_resizable_input (context : Context) (arguments : List SemanticValue)
    (before machine : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events machine) (schema : SchemaId .source) (opcode : Opcode) (immediate : Nat)
    (failures : List (InstructionFailure .source)) (bindings : Environment) (value : Located)
    (executing : machine.control = .execute (.primitive schema opcode immediate failures) bindings [value])
    (pop : opcode = .sequencePop ∨ opcode = .sequencePopLast) :
    ∃ element, context.source.schemas[value.value.schema.value]? = some (.seq element) ∨
      ∃ bound, context.source.schemas[value.value.schema.value]? = some (.vector element bound) := by
  have contextTyped : context.typingValid = true := by
    simpa only [Context.typingValid, Option.any_eq_true] using initial_checks_typing _ _ _ initialized
  have signature := reachable_primitive_signature _ _ _ _ _ initialized steps _ _ _ _ _ _ executing
  have admitted := signature_admits_nonresource _ _ _ _ _ _ contextTyped signature
    (by rcases pop with rfl | rfl <;> simp) (by rcases pop with rfl | rfl <;> simp)
  exact PrimitiveAdmission.pop_input_shape (Admission.primitiveContext context.source context.captures) ⟨0⟩
    ⟨opcode, schema, immediate, failures⟩ value.value.schema pop admitted


theorem reachable_term_operand_schemas (context : Context) (arguments : List SemanticValue) (before machine : State)
    (events : List Event) (initialized : initial context arguments = .ok before) (steps : Steps context before events machine)
    (authored : Term) (bindings : Environment) (operands : List Located)
    (executing : machine.control = .execute (.term authored) bindings operands) :
    authored ∈ context.source.terms ∧ Admission.valueTypes context.source (Analysis.termValues authored) = some (schemas operands) := by
  have typed := (initialized_execution_preserves_operand_schemas _ _ _ _ _ initialized steps).2.1
  have signature := (show Signature context.source (.term authored) (schemas operands) ∧ OperandStructure.NoOperands machine.stack from
    by simpa only [LocalTypes, executing] using typed).1
  cases signature with | term member types => exact ⟨member, types⟩

end OperandSchemas
end BoundaryV2.Profile.Source.Machine
