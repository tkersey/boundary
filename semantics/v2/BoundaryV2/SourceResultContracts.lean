import BoundaryV2.SourceOperandSchemas

namespace BoundaryV2.Profile.Source.Analysis

private theorem foldlM_congr (values : List α) (first second : β → α → Option β)
    (initial : β) (same : ∀ value ∈ values, ∀ before, first before value = second before value) :
    values.foldlM first initial = values.foldlM second initial := by
  induction values generalizing initial with
  | nil => rfl
  | cons value rest induction =>
    simp only [List.foldlM_cons, same value (by simp)]
    cases found : second initial value <;> simp only [bind, Option.bind]
    exact induction _ (fun item member before => same item (by simp [member]) before)

/-- A result equation observes only its explicit syntax children. Appending
later rows cannot alter the types of already formed terms. -/
theorem resultType_congr (source : Module) (left right : List ResultType) (authored : Term)
    (same : ∀ child excluded, (child, excluded) ∈ termChildren authored →
      left[child.value]? = right[child.value]?) :
    resultType source left authored = resultType source right authored := by
  cases authored <;> try rfl
  case bind binder value next =>
    simp only [resultType, same value [] (by simp [termChildren]), same next [binder] (by simp [termChildren])]
  case conditional condition yes no =>
    simp only [resultType, same yes [] (by simp [termChildren]), same no [] (by simp [termChildren])]
  case yieldThen next => exact same next [] (by simp [termChildren])
  case unpackProduct value variables body =>
    simp only [resultType, same body variables (by simp [termChildren])]
  case matchSum value branches =>
    simp only [resultType]
    cases found : valueShape source value with
    | none => rfl
    | some shape =>
      simp only [bind, Option.bind]
      cases shape <;> try rfl
      rename_i fields
      dsimp only
      split <;> try rfl
      apply foldlM_congr
      intro pair member before
      rcases pair with ⟨⟨binder, body⟩, schema⟩
      have present : (body, [binder]) ∈ termChildren (.matchSum value branches) := by
        simp only [termChildren, List.mem_map]
        exact ⟨(binder, body), List.of_mem_zip member |>.1, rfl⟩
      simp only [same body [binder] present]

theorem formed_resultType_full (source : Module) (results : List ResultType)
    (index : Nat) (authored : Term) (formed : formedTerm source index authored = true) :
    resultType source (results.take index) authored = resultType source results authored := by
  apply resultType_congr
  intro child excluded member
  have bounded := term_children_strictly_earlier source index authored formed member
  simp [bounded]

theorem resultsValid_full_row (source : Module) (results : List ResultType)
    (valid : resultsValid source results = true) (index : Nat) (authored : Term)
    (formed : formedTerm source index authored = true) (found : source.terms[index]? = some authored) :
    ∃ result, results[index]? = some result ∧ resultType source results authored = some result := by
  have length : results.length = source.terms.length := by
    have both := valid
    simp only [resultsValid, Bool.and_eq_true, beq_iff_eq] at both
    exact both.1
  have bounded : index < results.length := length ▸ (List.getElem?_eq_some_iff.mp found).1
  have resultAt := List.getElem?_eq_getElem bounded
  refine ⟨results[index], resultAt, ?_⟩
  rw [← formed_resultType_full source results index authored formed]
  exact resultsValid_row _ _ valid _ _ _ found resultAt

theorem compatible_left_result (left right result : ResultType) (schema : SchemaId .source)
    (accepted : compatible left right = some result) (returns : left = some schema) : result = some schema := by
  subst left
  obtain ⟨same, union⟩ := (compatible_exact _ _ _).mp accepted
  exact union.symm

theorem compatible_right_result (left right result : ResultType) (schema : SchemaId .source)
    (accepted : compatible left right = some result) (returns : right = some schema) : result = some schema := by
  subst right
  obtain ⟨same, union⟩ := (compatible_exact _ _ _).mp accepted
  cases left with
  | none => exact union.symm
  | some left => simpa only [same left schema rfl rfl, Option.or] using union.symm

theorem bind_result_contract (source : Module) (results : List ResultType)
    (binder : VariableId) (value next : TermId) (result : ResultType)
    (accepted : resultType source results (.bind binder value next) = some result) :
    ∃ valueResult nextResult schema,
      results[value.value]? = some valueResult ∧ results[next.value]? = some nextResult ∧
      source.variables[binder.value]? = some schema ∧
      (valueResult = none → result = none) ∧
      (∀ valueSchema, valueResult = some valueSchema → valueSchema = schema ∧ result = nextResult) := by
  simp only [resultType, bind, Option.bind_eq_some_iff, pure, Option.some.injEq] at accepted
  obtain ⟨valueResult, valueAt, schema, schemaAt, joined, joinedOk, nextResult, nextAt, resultEq⟩ := accepted
  refine ⟨valueResult, nextResult, schema, valueAt, nextAt, schemaAt, ?_, ?_⟩
  · intro abrupt
    simpa only [abrupt, Option.isNone_none, ↓reduceIte] using resultEq.symm
  · intro valueSchema returns
    have same := (compatible_exact _ _ _).mp joinedOk |>.1 _ _ returns rfl
    exact ⟨same, by simpa only [returns, Option.isNone_some, Bool.false_eq_true, ↓reduceIte] using resultEq.symm⟩

theorem conditional_result_contract (source : Module) (results : List ResultType)
    (condition : SourceValueId) (yes no : TermId) (result : ResultType)
    (accepted : resultType source results (.conditional condition yes no) = some result) :
    ∃ left right, results[yes.value]? = some left ∧ results[no.value]? = some right ∧
      (∀ schema, left = some schema → result = some schema) ∧
      (∀ schema, right = some schema → result = some schema) := by
  simp only [resultType, bind, Option.bind_eq_some_iff] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  simp only [Option.bind_eq_some_iff] at accepted
  obtain ⟨left, leftAt, right, rightAt, joined⟩ := accepted
  exact ⟨left, right, leftAt, rightAt,
    fun schema returns => compatible_left_result _ _ _ _ joined returns,
    fun schema returns => compatible_right_result _ _ _ _ joined returns⟩

end BoundaryV2.Profile.Source.Analysis

namespace BoundaryV2.Profile.Source.Machine
namespace ResultContracts

/-- The table is derived from the actual source in Context, and every row is
checked against the same source before it can type a running term. -/
theorem checked_term_result (context : Context) (results : List Analysis.ResultType)
    (typed : context.typingValid = true) (inferred : Analysis.inferResults context.source = some results)
    (reference : TermId) (authored : Term) (found : context.source.terms[reference.value]? = some authored) :
    ∃ result, results[reference.value]? = some result ∧
      Analysis.resultType context.source results authored = some result := by
  have formed := OperandSchemas.checked_context_formation _ typed
  simp only [Analysis.formation, Bool.and_eq_true] at formed
  have member : (authored, reference.value) ∈ context.source.terms.zipIdx :=
    List.mem_iff_getElem?.mpr ⟨reference.value, by simp [found]⟩
  exact Analysis.resultsValid_full_row _ _ (Analysis.inferResults_sound _ _ inferred) _ _
    (List.all_eq_true.mp formed.1.1.2 _ member) found

/-- A function body may be abrupt. Any normal body result has exactly the
function's declared schema, including for recursively called functions. -/
theorem checked_function_result (context : Context) (results : List Analysis.ResultType)
    (typed : context.typingValid = true) (inferred : Analysis.inferResults context.source = some results)
    (function : FunctionId .source) (declaration : Function)
    (found : context.source.functions[function.value]? = some declaration) :
    ∃ body result, declaration.body = some body ∧ results[body.value]? = some result ∧
      (∀ schema, result = some schema → schema = declaration.result) := by
  simp only [Context.typingValid, inferred, Option.any_some, Admission.typed,
    Analysis.foundationValid, Bool.and_eq_true] at typed
  have checked : Analysis.functionResultsValid context.source results = true := typed.1.1.1.1.1.2
  have member := List.mem_of_getElem? found
  have bodyTyped := List.all_eq_true.mp checked declaration member
  simp only [Option.any_eq_true, bind, Option.bind_eq_some_iff] at bodyTyped
  obtain ⟨result, ⟨body, bodyAt, resultAt⟩, compatible⟩ := bodyTyped
  refine ⟨body, result, bodyAt, resultAt, ?_⟩
  intro schema returns
  cases joined : Analysis.compatible result (some declaration.result) with
  | none => simp [joined] at compatible
  | some joinedResult => exact (Analysis.compatible_exact _ _ _).mp joined |>.1 _ _ returns rfl

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

/-- Successful invocation enters the declared source body with a result
compatible with that exact function, without assuming its normal termination. -/
theorem invoked_body_result (machine : State) (context : Context) (results : List Analysis.ResultType)
    (function : FunctionId .source) (bindings : Environment) (arguments : List Located) (after : Transition)
    (typed : context.typingValid = true) (inferred : Analysis.inferResults context.source = some results)
    (accepted : invokeFunction machine context function bindings arguments = .ok after) :
    ∃ declaration body environment result,
      context.source.functions[function.value]? = some declaration ∧ declaration.body = some body ∧
      after.state.control = .term body environment ∧ results[body.value]? = some result ∧
      (∀ schema, result = some schema → schema = declaration.result) := by
  simp only [invokeFunction, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨declaration, definitionAt, body, bodyAt, _, _, _, _, _, _, ⟨middle, entered⟩, _, rfl⟩ := accepted
  obtain ⟨checkedBody, result, checkedAt, resultAt, compatible⟩ :=
    checked_function_result _ _ typed inferred function declaration definitionAt
  have equal : checkedBody = body := Option.some.inj (checkedAt.symm.trans bodyAt)
  subst checkedBody
  exact ⟨declaration, body, entered, result, definitionAt, bodyAt, rfl, resultAt, compatible⟩

end ResultContracts
end BoundaryV2.Profile.Source.Machine
