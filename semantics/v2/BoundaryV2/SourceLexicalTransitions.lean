import BoundaryV2.SourceLexicalFrames

namespace BoundaryV2.Profile.Source.Machine
namespace LexicalCoverage
namespace SavedFrames

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]






theorem enterTerm_heap (machine : State) (context : Context) (after : Transition)
    (accepted : enterTerm machine context.source = .ok after) (typed : HeapValid context machine.heap) :
    HeapValid context after.state.heap := by
  unfold enterTerm at accepted
  repeat' split at accepted
  all_goals first | contradiction | (cases accepted; exact typed)

theorem enterExpression_heap (machine : State) (context : Context) (after : Transition)
    (accepted : enterExpression machine context = .ok after) (typed : HeapValid context machine.heap) :
    HeapValid context after.state.heap := by
  unfold enterExpression at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨⟨schema, expression⟩, _, accepted⟩ := accepted
  cases expression with
  | «variable» =>
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
    exact typed
  | literal =>
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, _, _, accepted⟩ := accepted
    exact (scopedValue_valid context _ _ _ accepted typed).2.2
  | lambda => exact (makeClosure_shape _ _ _ _ _ _ accepted typed).2.2
  | primitive _ operands => cases operands <;> cases accepted <;> exact typed

theorem deliverOperand_heap (machine : State) (context : Context) (after : Transition)
    (accepted : deliverOperand machine = .ok after) (typed : HeapValid context machine.heap) :
    HeapValid context after.state.heap := by
  unfold deliverOperand at accepted
  repeat' split at accepted
  all_goals first | contradiction | (cases accepted; exact typed)

theorem executePrimitive_plain (machine : State) (context : Context) (after : Transition)
    (accepted : executePrimitive machine context = .ok after) (typed : Plain context machine) :
    Plain context after.state ∧ ControlValid context after.state.control := by
  unfold executePrimitive at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted
  · contradiction
  · have shape := OperandStructure.authoredFailure_shape _ _ _ _ _ accepted
    obtain ⟨exit, unwinding⟩ := shape.1
    exact ⟨plain_of_shape context _ _ typed shape.2.1 (typed.2.of_objects shape.2.2), by simp [ControlValid, unwinding]⟩
  · have shape := commitPure_valid context _ _ _ _ _ accepted typed.2
    obtain ⟨value, delivered⟩ := shape.1
    exact ⟨plain_of_shape context _ _ typed shape.2.1 shape.2.2, by simp [ControlValid, delivered]⟩
  · have shape := heapPrimitive_shape _ _ _ _ _ _ _ accepted typed.2
    obtain ⟨value, delivered⟩ := shape.1
    exact ⟨plain_of_shape context _ _ typed shape.2.1 shape.2.2, by simp [ControlValid, delivered]⟩

end SavedFrames

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]






theorem invokeFunction_control (machine : State) (context : Context) (function : FunctionId .source)
    (bindings : Environment) (arguments : List Located) (after : Transition) (typed : context.typingValid = true)
    (accepted : invokeFunction machine context function bindings arguments = .ok after) : ControlValid context after.state.control := by
  obtain ⟨body, entered, control, bounded, covered⟩ := invokeFunction_establishes_body_bindings _ _ _ _ _ _ typed accepted
  simpa only [ControlValid, control, SiteValid, Analysis.inBounds] using And.intro bounded covered

theorem applyClosure_control (machine : State) (context : Context) (closure : Located)
    (arguments : List Located) (after : Transition) (typed : context.typingValid = true)
    (accepted : applyClosure machine context closure arguments = .ok after) : ControlValid context after.state.control := by
  simp only [applyClosure, bind, except_bind_ok] at accepted
  obtain ⟨⟨node, stored⟩, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  · simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨store, _, accepted⟩ := accepted
    exact invokeFunction_control _ _ _ _ _ _ typed accepted
  · simp only [pure, Except.pure, Except.bind] at accepted
    exact invokeFunction_control _ _ _ _ _ _ typed accepted

theorem handler_return_bound (context : Context) (typed : context.typingValid = true)
    (handler : Handler .source) (member : handler ∈ context.source.handlers) :
    handler.returnFunction.value < context.source.functions.length := by
  simp only [Context.typingValid, Option.any_eq_true] at typed
  obtain ⟨_, _, admitted⟩ := typed
  have roots : Analysis.closureRootsValid context.source context.captures = true := by
    simp only [Admission.typed, Analysis.foundationValid, Bool.and_eq_true] at admitted
    grind only []
  simp only [Analysis.closureRootsValid, Bool.and_eq_true] at roots
  have closed := List.all_eq_true.mp roots.2 handler member
  simp only [Bool.and_eq_true] at closed
  simpa using closed.1.1

theorem completeHandler_control (machine : State) (context : Context) (after : Transition)
    (typed : context.typingValid = true) (accepted : completeHandler machine context = .ok after) :
    ControlValid context after.state.control := by
  unfold completeHandler at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨definition, found, _, _, rfl⟩ := accepted
  have member := List.mem_of_getElem? found
  refine ⟨handler_return_bound _ typed _ member, ?_⟩
  have closed := (handler_functions_closed _ typed _ member).1
  change Covers _ (Analysis.captures context.captures definition.returnFunction)
  rw [closed]
  simp [Covers]

theorem installHandler_control (machine : State) (context : Context) (handler : HandlerId .source)
    (body : Located) (arguments stored : List Located) (bindings : Environment) (after : Transition)
    (typed : context.typingValid = true)
    (accepted : installHandler machine context handler body arguments stored bindings = .ok after) :
    ControlValid context after.state.control := by
  simp only [installHandler, bind, except_bind_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, ⟨_, _⟩, _, applied⟩ := accepted
  exact applyClosure_control _ _ _ _ _ typed applied

theorem enterRegion_control (machine : State) (context : Context) (descriptor : RegionId .source)
    (body : Located) (arguments : List Located) (after : Transition) (typed : context.typingValid = true)
    (accepted : enterRegion machine context descriptor body arguments = .ok after) : ControlValid context after.state.control := by
  simp only [enterRegion, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, ⟨_, _⟩, _, applied⟩ := accepted
  exact applyClosure_control _ _ _ _ _ typed applied

theorem openRequest_control (machine : State) (context : Context) (operation : Operation) (operands : List Located)
    (after : Transition) (typed : context.typingValid = true) (covered : ControlValid context machine.control)
    (accepted : openRequest machine context operation operands = .ok after) : ControlValid context after.state.control := by
  simp only [openRequest, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, accepted⟩ := accepted
  split at accepted
  · simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, rfl⟩ := accepted
    exact covered
  · simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, stored⟩, _, accepted⟩ := accepted
    cases stored <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, _, _, _, _, accepted⟩ := accepted
    split at accepted
    · simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, _, _, _, _, invoked⟩ := accepted
      exact invokeFunction_control _ _ _ _ _ _ typed invoked
    · simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
      split at accepted
      all_goals
        simp only [except_bind_ok, fromOption_ok] at accepted
        try
          obtain ⟨gate, guard, rest⟩ := accepted
          have _ : Unit := gate
          clear guard
          have accepted := rest
        obtain ⟨⟨_, _⟩, _, ⟨_, _⟩, _, _, _, invoked⟩ := accepted
        exact invokeFunction_control _ _ _ _ _ _ typed invoked

theorem resumeValue_control (machine : State) (context : Context) (token argument : Located)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : Transition)
    (accepted : resumeValue machine context token argument successor = .ok after) : ControlValid context after.state.control := by
  simp only [resumeValue, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨⟨_, _⟩, _, _, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  simp only [except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, _, _, ⟨_, _⟩, _, _, _, finished⟩ := accepted
  have delivered := (OperandStructure.finishTemporary_shape _ _ _ finished).1
  simp [ControlValid, delivered]

theorem resumeComputation_control (machine : State) (context : Context) (token computation : Located) (after : Transition)
    (typed : context.typingValid = true) (accepted : resumeComputation machine context token computation = .ok after) :
    ControlValid context after.state.control := by
  simp only [resumeComputation, bind, except_bind_ok] at accepted
  obtain ⟨⟨_, _⟩, _, _, _, applied⟩ := accepted
  exact applyClosure_control _ _ _ _ _ typed applied

theorem executeEffectTerm_control (machine : State) (context : Context) (after : Transition)
    (typed : context.typingValid = true) (covered : ControlValid context machine.control)
    (accepted : executeEffectTerm machine context = .ok after) : ControlValid context after.state.control := by
  unfold executeEffectTerm at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · exact openRequest_control _ _ _ _ _ typed covered accepted
  all_goals split at accepted <;> try contradiction
  all_goals first
    | exact installHandler_control _ _ _ _ _ _ _ _ typed accepted
    | exact resumeValue_control _ _ _ _ _ _ accepted
    | exact resumeComputation_control _ _ _ _ _ typed accepted
    | exact enterRegion_control _ _ _ _ _ _ typed accepted

end LexicalCoverage
end BoundaryV2.Profile.Source.Machine
