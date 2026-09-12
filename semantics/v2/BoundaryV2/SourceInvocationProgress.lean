import BoundaryV2.SourceClosureProgress
import BoundaryV2.SourceResultContracts
import BoundaryV2.SourceInternalProgress

namespace BoundaryV2.Profile.Source.Machine
namespace InvocationProgress

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

private theorem require_ok (condition : Bool) (reason : Invalid) (result : Unit)
    (accepted : require condition reason = .ok result) : condition = true := by
  unfold require at accepted
  split at accepted <;> first | assumption | contradiction

theorem createScope_token_free (machine : State) (context : Context) (invocation : InvocationId)
    (parent : Option LexicalScopeId) (vars : List VariableId) (values : List Located) (environment : Environment)
    (bound : bindArguments context vars values = true)
    (supply : machine.heap.nextScope = machine.heap.scopes.length)
    (free : ∀ value ∈ values, ownedTokens value.value = []) :
    ∃ after bindings, createScope machine context invocation parent vars values environment = .ok (after, bindings) := by
  have moved := ClosureProgress.move_token_free machine.heap values
    (Custody.Owner.lexical ⟨machine.heap.nextScope⟩) free
  simp only [createScope, bound, require, ↓reduceIte, bind, Except.bind]
  split
  · exact ⟨_, _, rfl⟩
  · rw [supply] at moved
    simp [supply, moved, fromOption, pure, Except.pure]

/-- Initial admission discharges the first real invocation's guards. The step
enters the source entry body and changes state, without a successful-tick premise. -/
theorem initialized_enters_body (context : Context) (arguments : List SemanticValue) (machine : State)
    (initialized : initial context arguments = .ok machine) :
    ∃ declaration body bindings after,
      context.source.functions[context.source.entry.value]? = some declaration ∧
      declaration.body = some body ∧
      tick machine context = .ok after ∧ after.state.control = .term body bindings ∧ after.state ≠ machine := by
  obtain ⟨results, inferred, admitted⟩ := initial_checks_typing _ _ _ initialized
  have typed : context.typingValid = true := by simp [Context.typingValid, inferred, admitted]
  have noHandles := (initialization_excludes_hidden_handles _ _ _ initialized).1
  unfold initial at initialized
  simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at initialized
  obtain ⟨_, _, _, _, _, _, entry, entryAt, _, capturesOk, _, _, _, argumentsOk, rfl⟩ := initialized
  have noCaptures : Analysis.captures context.captures context.source.entry = [] := by
    simpa only [List.isEmpty_iff] using require_ok _ _ _ capturesOk
  have argumentTypes := require_ok _ _ _ argumentsOk
  obtain ⟨body, result, bodyAt, _, _⟩ :=
    ResultContracts.checked_function_result context results typed inferred context.source.entry entry entryAt
  let values := arguments.mapIdx (fun index value => Located.mk value (.receiver 0 index))
  have free : ∀ value ∈ values, ownedTokens value.value = [] := by
    intro value member
    simp only [values, List.mapIdx_eq_zipIdx_map, List.mem_map] at member
    obtain ⟨⟨argument, index⟩, present, rfl⟩ := member
    exact (noHandles _ (List.fst_mem_of_mem_zipIdx present)).2
  have count : values.length = entry.parameters.length := by
    have bound := argumentTypes
    simp only [bindArguments, Bool.and_eq_true, beq_iff_eq] at bound
    exact bound.1.1.symm
  let start : State := {
    control := .invoke context.source.entry [] values
    stack := []
    heap := {
      scopes := [⟨0, 0, none, 0, []⟩]
      invocations := [⟨0, context.source.entry, [], []⟩]
      nextInvocation := 1
      nextScope := 1 }
    scope := 0
    invocation := 0 }
  obtain ⟨entered, bindings, enteredOk⟩ := createScope_token_free start
    context ⟨1⟩ none entry.parameters values [] argumentTypes rfl free
  let after : Transition := ⟨{ entered with
    control := .term body bindings
    stack := [.invocation 0 0]
    invocation := ⟨1⟩
    heap := { entered.heap with
      invocations := entered.heap.invocations ++ [⟨⟨1⟩, context.source.entry, [], []⟩]
      nextInvocation := entered.heap.nextInvocation + 1 } }, []⟩
  have tickOk : tick start context = .ok after := by
    simp only [start, tick, tickRunning, enterInvocation, invokeFunction, entryAt, fromOption, noCaptures,
      List.mapM_nil, count, List.nil_append, beq_self_eq_true, require,
      ↓reduceIte, bind, Except.bind, bodyAt, enteredOk, pure, Except.pure, activeAttachments, activeRegions]
    rfl
  exact ⟨entry, body, bindings, after, entryAt, bodyAt, tickOk, rfl,
    InternalProgress.running_tick_changes _ context after rfl tickOk⟩

end InvocationProgress
end BoundaryV2.Profile.Source.Machine
