import BoundaryV2.SourceLexicalCoverage

namespace BoundaryV2.Profile.Source.Machine
namespace LexicalCoverage

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]


theorem checked_term_formed (context : Context) (typed : context.typingValid = true)
    (reference : TermId) (term : Source.Term) (found : context.source.terms[reference.value]? = some term) :
    Analysis.formedTerm context.source reference.value term = true := by
  have formed := OperandSchemas.checked_context_formation context typed
  simp only [Analysis.formation, Bool.and_eq_true] at formed
  exact List.all_eq_true.mp formed.1.1.2 (term, reference.value) (List.mem_iff_getElem?.mpr ⟨reference.value, by simp [found]⟩)

theorem checked_value_formed (context : Context) (typed : context.typingValid = true)
    (reference : SourceValueId) (value : Source.Value) (found : context.source.values[reference.value]? = some value) :
    Analysis.formedValue context.source reference.value value = true := by
  have formed := OperandSchemas.checked_context_formation context typed
  simp only [Analysis.formation, Bool.and_eq_true] at formed
  exact List.all_eq_true.mp formed.1.1.1.2 (value, reference.value) (List.mem_iff_getElem?.mpr ⟨reference.value, by simp [found]⟩)

theorem term_operand_bound (context : Context) (typed : context.typingValid = true)
    (reference : TermId) (term : Source.Term) (found : context.source.terms[reference.value]? = some term)
    (operand : SourceValueId) (member : operand ∈ Analysis.termValues term) :
    operand.value < context.source.values.length := by
  have formed := checked_term_formed _ typed _ _ found
  simp only [Analysis.formedTerm, Bool.and_eq_true] at formed
  exact of_decide_eq_true (List.all_eq_true.mp formed.1.1.1 operand member)

theorem term_child_bound (context : Context) (typed : context.typingValid = true)
    (reference : TermId) (term : Source.Term) (found : context.source.terms[reference.value]? = some term)
    (child : TermId) (bound : List VariableId) (member : (child, bound) ∈ Analysis.termChildren term) :
    child.value < context.source.terms.length := by
  have earlier := Analysis.term_children_strictly_earlier _ _ _ (checked_term_formed _ typed _ _ found) member
  have present := (List.getElem?_eq_some_iff.mp found).1
  omega

theorem value_operand_bound (context : Context) (typed : context.typingValid = true)
    (reference : SourceValueId) (schema : SchemaId .source) (opcode : Opcode) (operands : List SourceValueId)
    (immediate : Nat) (failures : List (InstructionFailure .source))
    (found : context.source.values[reference.value]? = some ⟨schema, .primitive opcode operands immediate failures⟩)
    (operand : SourceValueId) (member : operand ∈ operands) : operand.value < context.source.values.length := by
  have earlier := Analysis.primitive_children_strictly_earlier _ _ _ _ _ _ _ (checked_value_formed _ typed _ _ found) member
  have present := (List.getElem?_eq_some_iff.mp found).1
  omega

theorem term_operand_valid (context : Context) (typed : context.typingValid = true)
    (reference : TermId) (term : Source.Term) (found : context.source.terms[reference.value]? = some term)
    (bindings : Environment) (covered : Covers bindings (variables context.captures (.term reference)))
    (operand : SourceValueId) (member : operand ∈ Analysis.termValues term) :
    SiteValid context (.value operand) bindings :=
  ⟨term_operand_bound _ typed _ _ found _ member,
    covers_mono covered (term_operand_variables _ typed _ _ found _ member)⟩

theorem term_intent_valid (context : Context) (typed : context.typingValid = true)
    (reference : TermId) (term : Source.Term) (found : context.source.terms[reference.value]? = some term)
    (bindings : Environment) (covered : Covers bindings (variables context.captures (.term reference))) :
    IntentValid context (.term term) bindings :=
  ⟨List.mem_of_getElem? found, covers_mono covered (term_continuation_variables _ typed _ _ found)⟩

theorem term_unbound_child_valid (context : Context) (typed : context.typingValid = true)
    (reference : TermId) (term : Source.Term) (found : context.source.terms[reference.value]? = some term)
    (bindings : Environment) (covered : Covers bindings (variables context.captures (.term reference)))
    (child : TermId) (member : (child, []) ∈ Analysis.termChildren term) : SiteValid context (.term child) bindings := by
  refine ⟨term_child_bound _ typed _ _ found _ _ member, covers_mono covered ?_⟩
  intro var needed
  exact term_child_variables _ typed _ _ found _ _ member (List.mem_filter.mpr ⟨needed, by simp⟩)

/-- One source term step retains lexical lookup availability in the active
control and every newly saved frame, including the binder's continuation. -/
theorem enterTerm_valid (machine : State) (context : Context) (after : Transition)
    (typed : context.typingValid = true) (accepted : enterTerm machine context.source = .ok after)
    (control : ControlValid context machine.control)
    (stack : ∀ frame ∈ machine.stack, FrameValid context frame) :
    ControlValid context after.state.control ∧ ∀ frame ∈ after.state.stack, FrameValid context frame := by
  unfold enterTerm at accepted
  split at accepted <;> try contradiction
  rename_i reference bindings executing
  split at accepted <;> try contradiction
  rename_i term found
  have covered : Covers bindings (variables context.captures (.term reference)) :=
    (show SiteValid context (.term reference) bindings from by simpa only [ControlValid, executing] using control).2
  have operandValid := term_operand_valid context typed reference term found bindings covered
  have intentValid := term_intent_valid context typed reference term found bindings covered
  have childValid := term_unbound_child_valid context typed reference term found bindings covered
  cases term <;> simp only at accepted
  case bind var value next =>
    cases accepted
    refine ⟨childValid value (by simp [Analysis.termChildren]), ?_⟩
    intro frame member
    rcases List.mem_cons.mp member with rfl | member
    · refine ⟨term_child_bound _ typed _ _ found _ [var] (by simp [Analysis.termChildren]), covers_mono covered ?_⟩
      intro wanted needed
      have selected := List.mem_filter.mp needed
      apply term_child_variables context typed reference (.bind var value next) found next [var] (by simp [Analysis.termChildren])
      exact List.mem_filter.mpr ⟨selected.1, by simpa using selected.2⟩
    · exact stack frame member
  case yieldThen next => cases accepted; exact ⟨childValid next (by simp [Analysis.termChildren]), stack⟩
  case value value => cases accepted; exact ⟨operandValid value (by simp [Analysis.termValues]), stack⟩
  all_goals split at accepted
  all_goals first
    | (cases accepted; exact ⟨intentValid, stack⟩)
    | (rename_i first rest operands; cases accepted
       refine ⟨operandValid first (by rw [operands]; simp), ?_⟩
       intro frame member
       rcases List.mem_cons.mp member with rfl | member
       · exact ⟨intentValid, fun child member => operandValid child (by rw [operands]; simp [member])⟩
       · exact stack frame member)

/-- Sequential operand delivery only discards satisfied dependencies. -/
theorem deliverOperand_valid (machine : State) (context : Context) (after : Transition)
    (accepted : deliverOperand machine = .ok after)
    (stack : ∀ frame ∈ machine.stack, FrameValid context frame) :
    ControlValid context after.state.control ∧ ∀ frame ∈ after.state.stack, FrameValid context frame := by
  unfold deliverOperand at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i intent bindings remaining evaluated tail stacked
  have saved := stack _ (by rw [stacked]; exact List.mem_cons_self)
  change IntentValid context intent bindings ∧ (∀ reference ∈ remaining, SiteValid context (.value reference) bindings) at saved
  have tailValid : ∀ frame ∈ tail, FrameValid context frame := fun frame member => stack frame (by rw [stacked]; simp [member])
  cases remaining with
  | nil => cases accepted; exact ⟨saved.1, tailValid⟩
  | cons next rest =>
    cases accepted
    refine ⟨saved.2 next (by simp), ?_⟩
    intro frame member
    rcases List.mem_cons.mp member with rfl | member
    · exact ⟨saved.1, fun child member => saved.2 child (by simp [member])⟩
    · exact tailValid frame member

end LexicalCoverage
end BoundaryV2.Profile.Source.Machine

namespace BoundaryV2.Profile.Source.Machine
namespace LexicalCoverage

theorem makeClosure_control_stack (machine : State) (context : Context) (schema : SchemaId .source)
    (function : FunctionId .source) (bindings : Environment) (after : Transition)
    (accepted : makeClosure machine context schema function bindings = .ok after) :
    (∃ value, after.state.control = .delivered value) ∧ after.state.stack = machine.stack := by
  simp only [makeClosure, makeClosureWithValues, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, _, _, ⟨middle, owner⟩, temporaryOk, _, _, ⟨store, result⟩, _, finished⟩ := accepted
  have first := OperandStructure.temporary_shape _ _ _ temporaryOk
  have last := OperandStructure.finishTemporary_shape _ _ _ finished
  exact ⟨⟨_, last.1⟩, last.2.1.trans first.2.1⟩

theorem enterExpression_valid (machine : State) (context : Context) (after : Transition)
    (typed : context.typingValid = true) (accepted : enterExpression machine context = .ok after)
    (control : ControlValid context machine.control)
    (stack : ∀ frame ∈ machine.stack, FrameValid context frame) :
    ControlValid context after.state.control ∧ ∀ frame ∈ after.state.stack, FrameValid context frame := by
  unfold enterExpression at accepted
  split at accepted <;> try contradiction
  rename_i reference bindings executing
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨⟨schema, expression⟩, found, accepted⟩ := accepted
  have covered : Covers bindings (variables context.captures (.value reference)) :=
    (show SiteValid context (.value reference) bindings from by simpa only [ControlValid, executing] using control).2
  cases expression with
  | «variable» =>
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
    exact ⟨trivial, stack⟩
  | literal =>
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, _, _, accepted⟩ := accepted
    have shape := OperandStructure.scopedValue_shape _ _ _ accepted
    obtain ⟨value, delivered⟩ := shape.1
    exact ⟨by simp [ControlValid, delivered], by simpa only [shape.2.1] using stack⟩
  | lambda =>
    have shape := makeClosure_control_stack _ _ _ _ _ _ accepted
    obtain ⟨value, delivered⟩ := shape.1
    exact ⟨by simp [ControlValid, delivered], by simpa only [shape.2] using stack⟩
  | primitive opcode operands immediate failures =>
    have children (operand : SourceValueId) (member : operand ∈ operands) : SiteValid context (.value operand) bindings :=
      ⟨value_operand_bound _ typed _ _ _ _ _ _ found _ member,
        covers_mono covered (value_operand_variables _ typed _ _ _ _ _ _ found _ member)⟩
    cases operands with
    | nil => cases accepted; exact ⟨trivial, stack⟩
    | cons first rest =>
      cases accepted
      refine ⟨children first (by simp), ?_⟩
      intro frame member
      rcases List.mem_cons.mp member with rfl | member
      · exact ⟨trivial, fun operand member => children operand (by simp [member])⟩
      · exact stack frame member

theorem invokeFunction_valid (machine : State) (context : Context) (function : FunctionId .source)
    (bindings : Environment) (arguments : List Located) (after : Transition)
    (typed : context.typingValid = true)
    (accepted : invokeFunction machine context function bindings arguments = .ok after)
    (stack : ∀ frame ∈ machine.stack, FrameValid context frame) :
    ControlValid context after.state.control ∧ ∀ frame ∈ after.state.stack, FrameValid context frame := by
  have entered := invokeFunction_establishes_body_bindings _ _ _ _ _ _ typed accepted
  obtain ⟨body, bindings, executing, bounded, covered⟩ := entered
  refine ⟨by simpa only [ControlValid, executing, SiteValid, Analysis.inBounds] using And.intro bounded covered, ?_⟩
  simp only [invokeFunction, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, ⟨middle, entered⟩, created, rfl⟩ := accepted
  have same := (OperandStructure.createScope_shape _ _ _ _ _ _ _ _ _ created).2.1
  intro frame member
  rcases List.mem_cons.mp member with rfl | member
  · trivial
  · exact stack frame (by simpa only [same] using member)

theorem applyClosure_valid (machine : State) (context : Context) (closure : Located)
    (arguments : List Located) (after : Transition) (typed : context.typingValid = true)
    (accepted : applyClosure machine context closure arguments = .ok after)
    (stack : ∀ frame ∈ machine.stack, FrameValid context frame) :
    ControlValid context after.state.control ∧ ∀ frame ∈ after.state.stack, FrameValid context frame := by
  simp only [applyClosure, bind, except_bind_ok] at accepted
  obtain ⟨⟨node, stored⟩, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  · simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨store, _, accepted⟩ := accepted
    exact invokeFunction_valid _ _ _ _ _ _ typed accepted stack
  · simp only [pure, Except.pure, Except.bind] at accepted
    exact invokeFunction_valid _ _ _ _ _ _ typed accepted stack

theorem enterInvocation_valid (machine : State) (context : Context) (after : Transition)
    (typed : context.typingValid = true) (accepted : enterInvocation machine context = .ok after)
    (stack : ∀ frame ∈ machine.stack, FrameValid context frame) :
    ControlValid context after.state.control ∧ ∀ frame ∈ after.state.stack, FrameValid context frame := by
  unfold enterInvocation at accepted
  split at accepted <;> try contradiction
  exact invokeFunction_valid _ _ _ _ _ _ typed accepted stack

theorem enterBinding_valid (machine : State) (context : Context) (after : Transition)
    (accepted : enterBinding machine context = .ok after)
    (stack : ∀ frame ∈ machine.stack, FrameValid context frame) :
    ControlValid context after.state.control ∧ ∀ frame ∈ after.state.stack, FrameValid context frame := by
  unfold enterBinding at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i var body bindings parent tail stacked
  have saved := stack _ (by rw [stacked]; exact List.mem_cons_self)
  change body.value < context.source.terms.length ∧ Covers bindings ((variables context.captures (.term body)).filter (· != var)) at saved
  have tailValid : ∀ frame ∈ tail, FrameValid context frame := fun frame member => stack frame (by rw [stacked]; simp [member])
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, entered⟩, created, rfl⟩ := accepted
  have enteredCovers := createScope_covers _ _ _ _ _ _ _ _ _ saved.2 created
  refine ⟨⟨saved.1, covers_mono enteredCovers ?_⟩, ?_⟩
  · intro wanted needed
    by_cases same : wanted = var
    · simp [same]
    · exact List.mem_append_right _ (List.mem_filter.mpr ⟨needed, by simpa using same⟩)
  · split
    · exact tailValid
    · intro frame member
      rcases List.mem_cons.mp member with rfl | member
      · trivial
      · exact tailValid frame member

theorem intent_child_valid (context : Context) (typed : context.typingValid = true)
    (term : Source.Term) (bindings : Environment) (covered : IntentValid context (.term term) bindings)
    (body : TermId) (bound : List VariableId) (member : (body, bound) ∈ Analysis.termChildren term) :
    body.value < context.source.terms.length ∧
      Covers bindings ((variables context.captures (.term body)).filter (fun var => !bound.contains var)) := by
  obtain ⟨index, found⟩ := List.mem_iff_getElem?.mp covered.1
  refine ⟨term_child_bound context typed ⟨index⟩ term found body bound member, covers_mono covered.2 ?_⟩
  intro var needed
  exact List.mem_append_left _ (List.mem_flatMap.mpr ⟨(body, bound), member, needed⟩)

theorem enterPattern_valid (machine : State) (context : Context) (vars : List VariableId)
    (parts : List SemanticValue) (owner : Custody.Owner) (body : TermId) (bindings : Environment)
    (after : Transition) (accepted : enterPattern machine context vars parts owner body bindings = .ok after)
    (bounded : body.value < context.source.terms.length)
    (covered : Covers bindings ((variables context.captures (.term body)).filter (fun var => !vars.contains var)))
    (stack : ∀ frame ∈ machine.stack, FrameValid context frame) :
    ControlValid context after.state.control ∧ ∀ frame ∈ after.state.stack, FrameValid context frame := by
  simp only [enterPattern, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, entered⟩, created, rfl⟩ := accepted
  have enteredCovers := createScope_covers _ _ _ _ _ _ _ _ _ covered created
  have same := (OperandStructure.createScope_shape _ _ _ _ _ _ _ _ _ created).2.1
  refine ⟨⟨bounded, covers_mono enteredCovers ?_⟩, ?_⟩
  · intro var needed
    by_cases introduced : var ∈ vars
    · exact List.mem_append_left _ introduced
    · exact List.mem_append_right _ (List.mem_filter.mpr ⟨needed, by simpa using introduced⟩)
  · split
    · exact stack
    · intro frame member
      rcases List.mem_cons.mp member with rfl | member
      · trivial
      · exact stack frame member

theorem executeControlTerm_valid (machine : State) (context : Context) (after : Transition)
    (typed : context.typingValid = true) (accepted : executeControlTerm machine context = .ok after)
    (control : ControlValid context machine.control)
    (stack : ∀ frame ∈ machine.stack, FrameValid context frame) :
    ControlValid context after.state.control ∧ ∀ frame ∈ after.state.stack, FrameValid context frame := by
  unfold executeControlTerm at accepted
  split at accepted <;> try contradiction
  rename_i term bindings operands executing
  have covered : IntentValid context (.term term) bindings := by simpa only [ControlValid, executing] using control
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  cases term <;> simp only at accepted <;> try contradiction
  case conditional condition yes no =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, rfl⟩ := accepted
    refine ⟨?_, stack⟩
    split
    · have child := intent_child_valid context typed _ bindings covered yes [] (by simp [Analysis.termChildren])
      refine ⟨child.1, covers_mono child.2 ?_⟩
      intro var member; exact List.mem_filter.mpr ⟨member, by simp⟩
    · have child := intent_child_valid context typed _ bindings covered no [] (by simp [Analysis.termChildren])
      refine ⟨child.1, covers_mono child.2 ?_⟩
      intro var member; exact List.mem_filter.mpr ⟨member, by simp⟩
  case call function arguments =>
    cases accepted
    obtain ⟨index, found⟩ := List.mem_iff_getElem?.mp covered.1
    have formed := checked_term_formed context typed ⟨index⟩ _ found
    simp only [Analysis.formedTerm, Bool.and_eq_true] at formed
    refine ⟨⟨of_decide_eq_true formed.2, ?_⟩, stack⟩
    apply covers_mono covered.2
    intro var needed
    exact List.mem_append_right _ needed
  case apply =>
    split at accepted <;> try contradiction
    exact applyClosure_valid _ _ _ _ _ typed accepted stack
  case fail =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, rfl⟩ := accepted
    exact ⟨trivial, stack⟩
  case matchSum value cases =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨⟨var, body⟩, found, accepted⟩ := accepted
    have member : (body, [var]) ∈ Analysis.termChildren (.matchSum value cases) :=
      List.mem_map.mpr ⟨(var, body), List.mem_of_getElem? found, rfl⟩
    have child := intent_child_valid context typed _ bindings covered _ _ member
    exact enterPattern_valid _ _ _ _ _ _ _ _ accepted child.1 child.2 stack
  case unpackProduct value vars body =>
    split at accepted <;> try contradiction
    have child := intent_child_valid context typed _ bindings covered body vars (by simp [Analysis.termChildren])
    exact enterPattern_valid _ _ _ _ _ _ _ _ accepted child.1 child.2 stack

end LexicalCoverage
end BoundaryV2.Profile.Source.Machine
