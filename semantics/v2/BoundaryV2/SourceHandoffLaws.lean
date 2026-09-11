import BoundaryV2.SourceEnvironmentTypes
import BoundaryV2.SourceOperandLaws

namespace BoundaryV2.Profile.Source.Machine

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

private theorem require_ok (value : Bool) (reason : Invalid) (result : Unit)
    (accepted : require value reason = .ok result) : value = true := by
  cases value <;> simp_all [require]

/-- Function entry commits every owned argument into the newly entered lexical
scope. The holding and the custody book agree before the transition returns. -/
theorem invocation_commits_owned_argument (state : State) (context : Context)
    (function : FunctionId .source) (environment : Environment) (arguments : List Located) (after : Transition)
    (accepted : invokeFunction state context function environment arguments = .ok after)
    (index : Nat) (inBounds : index < arguments.length) (token : CustodyToken)
    (member : token ∈ ownedTokens arguments[index].value) :
    ∃ scope, after.state.heap.scopes[after.state.scope.value]? = some scope ∧
      scope.id = after.state.scope ∧ scope.invocation = after.state.invocation ∧
      ∃ holding ∈ scope.holdings, holding.value = arguments[index].value ∧
        Custody.owns after.state.heap.custody token holding.owner := by
  simp only [invokeFunction, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨definition, _, body, _, captured, _, _, _, _, _, ⟨middle, entered⟩, scopeOk, rfl⟩ := accepted
  simp only [createScope, Option.isSome_none, Bool.false_and, Bool.false_eq_true, ↓reduceIte,
    bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq, Prod.mk.injEq] at scopeOk
  obtain ⟨_, _, _, nextScope, heap, moved, rfl, rfl⟩ := scopeOk
  have scopeSize : state.heap.nextScope = state.heap.scopes.length := by
    simpa using require_ok _ _ _ nextScope
  have heapScopes : heap.scopes = state.heap.scopes := by
    simp only [moveValues, bind, pure, Option.bind_eq_some_iff, Option.some.injEq] at moved
    obtain ⟨book, _, rfl⟩ := moved
    rfl
  dsimp only at *
  refine ⟨⟨⟨state.heap.nextScope⟩, ⟨state.heap.nextInvocation⟩, none,
    (Analysis.captures context.captures function ++ definition.parameters).length,
    (captured ++ arguments).mapIdx (fun index value => retainAt value (.lexical ⟨state.heap.nextScope⟩ index))⟩,
    ?_, rfl, rfl, ?_⟩
  · simp [heapScopes, scopeSize]
  · have combinedBound : captured.length + index < (captured ++ arguments).length := by simp; omega
    have combinedValue : (captured ++ arguments)[captured.length + index] = arguments[index] := by
      simp [List.getElem_append_right]
    have transferred := (move_values_transfers_each_operand _ _ _ _ (captured.length + index)
      combinedBound token (combinedValue ▸ member) moved).2
    refine ⟨retainAt arguments[index] (.lexical ⟨state.heap.nextScope⟩ (captured.length + index)), ?_, rfl, ?_⟩
    · apply List.mem_mapIdx.mpr
      exact ⟨captured.length + index, combinedBound, by rw [combinedValue]⟩
    · exact transferred

theorem invocation_commits_owned_value (state : State) (context : Context)
    (function : FunctionId .source) (environment : Environment) (arguments : List Located) (after : Transition)
    (accepted : invokeFunction state context function environment arguments = .ok after)
    (value : Located) (input : value ∈ arguments) (token : CustodyToken)
    (member : token ∈ ownedTokens value.value) :
    ∃ scope, after.state.heap.scopes[after.state.scope.value]? = some scope ∧
      scope.id = after.state.scope ∧ scope.invocation = after.state.invocation ∧
      ∃ holding ∈ scope.holdings, holding.value = value.value ∧
        Custody.owns after.state.heap.custody token holding.owner := by
  obtain ⟨index, inBounds, atIndex⟩ := List.mem_iff_getElem.mp input
  simpa only [atIndex] using invocation_commits_owned_argument _ _ _ _ _ _ accepted index inBounds token
    (by simpa only [atIndex] using member)

/-- A handled request enters clause code in the same transition as its custody
handoff. There is no observable deferred-invocation state between those steps. -/
theorem handled_request_enters_clause (state : State) (context : Context)
    (operation : Operation) (operands : List Located) (capability : Located) (after : Transition)
    (supplied : (if operation.capability.isSome then operands.head? else none) = some capability)
    (accepted : openRequest state context operation operands = .ok after) :
    ∃ body environment, after.state.control = .term body environment ∧
      Environment.Types context.source environment := by
  simp only [openRequest, bind, except_bind_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, accepted⟩ := accepted
  simp only [supplied, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  simp only [except_bind_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, accepted⟩ := accepted
  split at accepted
  · simp only [except_bind_ok] at accepted
    obtain ⟨_, _, _, _, _, _, invoked⟩ := accepted
    exact invokeFunction_enters_typed_environment _ _ _ _ _ _ invoked
  · simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
    split at accepted
    all_goals
      simp only [except_bind_ok] at accepted
      try
        obtain ⟨gate, guard, rest⟩ := accepted
        have _ : Unit := gate
        clear guard
        have accepted := rest
      obtain ⟨_, _, _, _, _, _, invoked⟩ := accepted
      exact invokeFunction_enters_typed_environment _ _ _ _ _ _ invoked

/-- Every owned body passed to a handled operation has a concrete holding in
its clause's entered scope. Cancellation can reach that holding using ordinary
lexical unwind; a future receiver is never the committed owner. -/
theorem handled_request_commits_owned_body (state : State) (context : Context)
    (operation : Operation) (operands : List Located) (capability value : Located) (after : Transition)
    (supplied : (if operation.capability.isSome then operands.head? else none) = some capability)
    (input : value ∈ ((operands.drop operation.capability.toList.length).drop 1).take operation.bodies.length)
    (token : CustodyToken) (member : token ∈ ownedTokens value.value)
    (accepted : openRequest state context operation operands = .ok after) :
    ∃ scope, after.state.heap.scopes[after.state.scope.value]? = some scope ∧
      scope.id = after.state.scope ∧ scope.invocation = after.state.invocation ∧
      ∃ holding ∈ scope.holdings, holding.value = value.value ∧
        Custody.owns after.state.heap.custody token holding.owner := by
  simp only [openRequest, bind, except_bind_ok] at accepted
  obtain ⟨_, _, _, _, payload, _, _, _, accepted⟩ := accepted
  simp only [supplied, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  simp only [except_bind_ok] at accepted
  obtain ⟨_, _, selected, _, _, _, clause, _, accepted⟩ := accepted
  split at accepted
  · simp only [except_bind_ok] at accepted
    obtain ⟨_, empty, _⟩ := accepted
    have empty := require_ok _ _ _ empty
    have empty : ((operands.drop operation.capability.toList.length).drop 1).take operation.bodies.length = [] := by
      simpa using empty
    simp only [empty, List.not_mem_nil] at input
  · simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
    split at accepted
    all_goals
      simp only [except_bind_ok] at accepted
      try
        obtain ⟨gate, guard, rest⟩ := accepted
        have _ : Unit := gate
        clear guard
        have accepted := rest
      obtain ⟨_, _, _, _, _, _, invoked⟩ := accepted
      obtain ⟨index, inBounds, atIndex⟩ := List.mem_iff_getElem.mp input
      let outgoing := retainAt value (.receiver ⟨state.heap.nextInvocation⟩ (index + 1))
      apply invocation_commits_owned_value _ _ _ _ _ _ invoked outgoing ?_ token member
      apply List.mem_append_left
      apply List.mem_append_right
      apply List.mem_mapIdx.mpr
      refine ⟨index + 1, by simpa using inBounds, ?_⟩
      simp only [List.getElem_cons_succ, atIndex, outgoing]

end BoundaryV2.Profile.Source.Machine
