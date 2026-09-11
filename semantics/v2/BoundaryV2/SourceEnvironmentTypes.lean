import BoundaryV2.SourceValueTypes

namespace BoundaryV2.Profile.Source.Machine

/-- Lexical binder IDs retain their declared schema. Value contents and live
heap references have separate shape and custody components. -/
def Environment.Types (source : Module) (bindings : Environment) : Prop :=
  ∀ binding ∈ bindings, source.variables[binding.var.value]? = some binding.located.value.schema

theorem Environment.Types.lookup (typed : Environment.Types source bindings)
    (binder : VariableId) (value : Located) (found : lookupVariable bindings binder = some value) :
    source.variables[binder.value]? = some value.value.schema := by
  simp only [lookupVariable, Option.map_eq_some_iff] at found
  obtain ⟨binding, found, rfl⟩ := found
  have member := List.mem_of_find?_eq_some found
  have same : binding.var = binder := by simpa using List.find?_some found
  simpa only [same] using typed binding member

theorem Environment.Types.append (leftTyped : Environment.Types source left)
    (rightTyped : Environment.Types source right) : Environment.Types source (left ++ right) := by
  intro binding member
  rcases List.mem_append.mp member with member | member
  · exact leftTyped binding member
  · exact rightTyped binding member

theorem Environment.Types.filter (typed : Environment.Types source bindings) (keep : Binding → Bool) :
    Environment.Types source (bindings.filter keep) :=
  fun binding member => typed binding (List.mem_filter.mp member).1

theorem Environment.Types.rename (source : Module) (bindings : Environment) (mapping : Renaming)
    (typed : Environment.Types source bindings) : Environment.Types source (renameEnvironment mapping bindings) := by
  intro binding member
  obtain ⟨original, originalMember, rfl⟩ := List.mem_map.mp member
  simpa only [renameLocated, renaming_preserves_value_schema] using typed original originalMember

theorem checked_arguments_have_declared_types (context : Context) (vars : List VariableId) (values : List Located)
    (checked : bindArguments context vars values = true) :
    Environment.Types context.source ((vars.zip values).map (fun (binder, value) => Binding.mk binder value)) := by
  intro binding member
  obtain ⟨⟨binder, value⟩, pairMember, rfl⟩ := List.mem_map.mp member
  have fields : (vars.zip values).all (fun (binder, value) =>
      context.source.variables[binder.value]? == some value.value.schema) = true :=
    (Bool.and_eq_true_iff.mp checked).2
  simpa using List.all_eq_true.mp fields (binder, value) pairMember

theorem checked_arguments_after_relocation (context : Context) (vars : List VariableId) (values : List Located)
    (receiver : Nat → Custody.Owner) (checked : bindArguments context vars values = true) :
    Environment.Types context.source ((vars.zip (values.mapIdx (fun index value => retainAt value (receiver index)))).map
      (fun (binder, value) => Binding.mk binder value)) := by
  have fields := checked_arguments_have_declared_types context vars values checked
  intro binding member
  obtain ⟨⟨binder, value⟩, pairMember, rfl⟩ := List.mem_map.mp member
  obtain ⟨index, pairAt⟩ := List.mem_iff_getElem?.mp pairMember
  obtain ⟨binderAt, valueAt⟩ := List.getElem?_zip_eq_some.mp pairAt
  rw [List.getElem?_mapIdx] at valueAt
  obtain ⟨original, originalAt, same⟩ := Option.map_eq_some_iff.mp valueAt
  have originalMember : (binder, original) ∈ vars.zip values :=
    List.mem_iff_getElem?.mpr ⟨index, List.getElem?_zip_eq_some.mpr ⟨binderAt, originalAt⟩⟩
  have declaration := fields ⟨binder, original⟩ (List.mem_map.mpr ⟨(binder, original), originalMember, rfl⟩)
  cases same
  exact declaration

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

/-- Both the reusable fast path and the allocated lexical scope bind exactly
the checked argument types and preserve the surviving outer bindings. -/
theorem createScope_preserves_environment_types (state : State) (context : Context)
    (invocation : InvocationId) (parent : Option LexicalScopeId) (vars : List VariableId)
    (values : List Located) (bindings : Environment) (after : State) (entered : Environment)
    (typed : Environment.Types context.source bindings)
    (accepted : createScope state context invocation parent vars values bindings = .ok (after, entered)) :
    Environment.Types context.source entered := by
  simp only [createScope, bind, except_bind_ok] at accepted
  obtain ⟨_, checked, accepted⟩ := accepted
  have argumentsChecked : bindArguments context vars values = true := by
    unfold require at checked
    split at checked <;> first | assumption | contradiction
  split at accepted
  · cases accepted
    exact (checked_arguments_have_declared_types context vars values argumentsChecked).append (typed.filter _)
  · simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, heap, _, equal⟩ := accepted
    cases equal
    exact (checked_arguments_after_relocation context vars values _ argumentsChecked).append (typed.filter _)

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem ValueInventory.createScope_preserves_all (state : State) (context : Context)
    (invocation : InvocationId) (parent : Option LexicalScopeId) (vars : List VariableId)
    (values : List Located) (bindings : Environment) (after : State) (entered : Environment)
    (accepted : createScope state context invocation parent vars values bindings = .ok (after, entered))
    (property : SemanticValue → Prop) (holds : All property state)
    (inputs : ∀ value ∈ values, property value.value) : All property after := by
  simp only [createScope, bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted
  · cases accepted; exact holds
  · simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, moved, movedOk, equal⟩ := accepted
    have movedHolds := ValueInventory.moveValues_preserves_all _ _ _ _ movedOk property holds
    have relocated : ∀ value ∈ values.mapIdx (fun index value => retainAt value (.lexical ⟨state.heap.nextScope⟩ index)),
        property value.value := by
      intro value member
      simp only [List.mapIdx_eq_zipIdx_map, List.mem_map] at member
      obtain ⟨⟨original, index⟩, originalMember, rfl⟩ := member
      exact inputs original (List.fst_mem_of_mem_zipIdx originalMember)
    cases equal
    simp only [All, ValueInventory.state, ValueInventory.heap, List.flatMap_append, List.flatMap_cons,
      List.flatMap_nil, List.append_nil, List.mem_append, List.mem_map] at movedHolds ⊢
    grind only []

theorem invokeFunction_enters_typed_environment (state : State) (context : Context)
    (function : FunctionId .source) (bindings : Environment) (arguments : List Located) (after : Transition)
    (accepted : invokeFunction state context function bindings arguments = .ok after) :
    ∃ body entered, after.state.control = .term body entered ∧ Environment.Types context.source entered := by
  simp only [invokeFunction, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨definition, _, body, _, captured, _, _, _, _, _, ⟨middle, entered⟩, scopeOk, rfl⟩ := accepted
  exact ⟨body, entered, rfl,
    createScope_preserves_environment_types _ _ _ _ _ _ _ _ _ (by simp [Environment.Types]) scopeOk⟩

theorem binding_enters_typed_environment (state : State) (context : Context) (value : Located)
    (binder : VariableId) (body : TermId) (bindings : Environment) (parent : LexicalScopeId)
    (tail : List Frame) (after : Transition)
    (control : state.control = .delivered value)
    (stack : state.stack = .binding binder body bindings parent :: tail)
    (typed : Environment.Types context.source bindings)
    (accepted : enterBinding state context = .ok after) :
    ∃ entered, after.state.control = .term body entered ∧ Environment.Types context.source entered := by
  simp only [enterBinding, control, stack, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, entered⟩, scopeOk, rfl⟩ := accepted
  exact ⟨entered, rfl, createScope_preserves_environment_types _ _ _ _ _ _ _ _ _ typed scopeOk⟩

end BoundaryV2.Profile.Source.Machine
