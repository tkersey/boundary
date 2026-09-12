import BoundaryV2.SourceOperandTypes

namespace BoundaryV2.Profile.Source.Machine
namespace LexicalCoverage

def variables (facts : Analysis.Facts) (node : Analysis.Node) : List VariableId :=
  (facts.row node).map Prod.fst

def Covers (bindings : Environment) (needed : List VariableId) : Prop :=
  ∀ var ∈ needed, ∃ value, lookupVariable bindings var = some value

theorem lookup_exists_iff (bindings : Environment) (var : VariableId) :
    (∃ value, lookupVariable bindings var = some value) ↔ ∃ binding ∈ bindings, binding.var = var := by
  constructor
  · rintro ⟨value, found⟩
    obtain ⟨binding, selected, _⟩ := Option.map_eq_some_iff.mp found
    exact ⟨binding, List.mem_of_find?_eq_some selected, by simpa using List.find?_some selected⟩
  · rintro ⟨binding, member, same⟩
    cases selected : bindings.find? (fun binding => binding.var == var) with
    | none =>
      have missing := List.find?_eq_none.mp selected binding member
      simp [same] at missing
    | some binding => exact ⟨binding.located, by simp [lookupVariable, selected]⟩

theorem covers_mono (covered : Covers bindings all) (subset : needed ⊆ all) : Covers bindings needed :=
  fun var member => covered var (subset member)

theorem covers_same_keys (covered : Covers before needed)
    (same : after.map Binding.var = before.map Binding.var) : Covers after needed := by
  intro var member
  obtain ⟨binding, bindingMember, key⟩ := (lookup_exists_iff before var).mp (covered var member)
  have original : var ∈ before.map Binding.var := List.mem_map.mpr ⟨binding, bindingMember, key⟩
  rw [← same] at original
  obtain ⟨binding, member, key⟩ := List.mem_map.mp original
  exact (lookup_exists_iff after var).mpr ⟨binding, member, key⟩

theorem renamed_environment_covers (mapping : Renaming) (covered : Covers bindings needed) :
    Covers (renameEnvironment mapping bindings) needed := by
  apply covers_same_keys covered
  simp [renameEnvironment, List.map_map, Function.comp_def]

theorem rank_exists_iff (facts : Analysis.Facts) (node : Analysis.Node) (var : VariableId) :
    (∃ rank, facts.rank node var = some rank) ↔ var ∈ variables facts node := by
  constructor
  · rintro ⟨rank, found⟩
    obtain ⟨binding, selected, _⟩ := Option.map_eq_some_iff.mp found
    exact List.mem_map.mpr ⟨binding, List.mem_of_find?_eq_some selected, by simpa using List.find?_some selected⟩
  · intro member
    obtain ⟨binding, member, same⟩ := List.mem_map.mp member
    cases selected : (facts.row node).find? (fun entry => entry.1 == var) with
    | none =>
      have missing := List.find?_eq_none.mp selected binding member
      simp [same] at missing
    | some binding => exact ⟨binding.2, by simp [Analysis.Facts.rank, selected]⟩

theorem variables_exact (source : Module) (facts : Analysis.Facts) (checked : Analysis.check source facts = true)
    (node : Analysis.Node) (var : VariableId) : var ∈ variables facts node ↔ Analysis.Free source node var :=
  (rank_exists_iff facts node var).symm.trans (Analysis.checked_capture_exact source facts checked node var)

theorem dependency_variables (source : Module) (facts : Analysis.Facts)
    (checked : Analysis.check source facts = true) (node : Analysis.Node) (dependency : Analysis.Dependency)
    (linked : dependency ∈ Analysis.dependencies source node) (var : VariableId)
    (needed : var ∈ variables facts dependency.node) (notBound : var ∉ dependency.excludes) :
    var ∈ variables facts node :=
  (variables_exact _ _ checked _ _).mpr (.through linked notBound ((variables_exact _ _ checked _ _).mp needed))

theorem checked_capture_analysis (context : Context) (typed : context.typingValid = true) :
    Analysis.check context.source context.captures = true := by
  simp only [Context.typingValid, Option.any_eq_true] at typed
  obtain ⟨_, _, admitted⟩ := typed
  simp only [Admission.typed, Analysis.foundationValid, Bool.and_eq_true] at admitted
  grind only []

theorem handler_functions_closed (context : Context) (typed : context.typingValid = true)
    (handler : Handler .source) (member : handler ∈ context.source.handlers) :
    Analysis.captures context.captures handler.returnFunction = [] ∧
    ∀ clause ∈ handler.clauses, Analysis.captures context.captures clause.function = [] := by
  simp only [Context.typingValid, Option.any_eq_true] at typed
  obtain ⟨_, _, admitted⟩ := typed
  have roots : Analysis.closureRootsValid context.source context.captures = true := by
    simp only [Admission.typed, Analysis.foundationValid, Bool.and_eq_true] at admitted
    grind only []
  simp only [Analysis.closureRootsValid, Bool.and_eq_true] at roots
  have closed := List.all_eq_true.mp roots.2 handler member
  simp only [Bool.and_eq_true] at closed
  refine ⟨by simpa using closed.1.2, ?_⟩
  intro clause member
  have selected := List.all_eq_true.mp closed.2 clause member
  exact by simpa using (Bool.and_eq_true_iff.mp selected).2

/-- Baseline handler callbacks are closed source roots. Handler state is passed
through explicit parameters; no hidden lexical callback captures are required. -/
theorem handler_environment_empty (context : Context) (typed : context.typingValid = true)
    (handler : Handler .source) (member : handler ∈ context.source.handlers) (bindings : Environment) :
    handlerEnvironment context handler bindings = [] := by
  have closed := handler_functions_closed _ typed _ member
  have empty : (handler.returnFunction :: handler.clauses.map Clause.function).flatMap
      (Analysis.captures context.captures) = [] := by
    apply List.flatMap_eq_nil_iff.mpr
    intro function found
    rcases List.mem_cons.mp found with same | found
    · cases same; exact closed.1
    · obtain ⟨clause, member, rfl⟩ := List.mem_map.mp found
      exact closed.2 clause member
  simp [handlerEnvironment, empty, restrictEnvironment]

end LexicalCoverage
end BoundaryV2.Profile.Source.Machine

namespace BoundaryV2.Profile.Source.Machine
namespace LexicalCoverage

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem covers_iff_subset (bindings : Environment) (needed : List VariableId) :
    Covers bindings needed ↔ needed ⊆ bindings.map Binding.var := by
  constructor
  · intro covered var member
    obtain ⟨binding, member, same⟩ := (lookup_exists_iff _ _).mp (covered var member)
    exact List.mem_map.mpr ⟨binding, member, same⟩
  · intro subset var member
    obtain ⟨binding, member, same⟩ := List.mem_map.mp (subset member)
    exact (lookup_exists_iff _ _).mpr ⟨binding, member, same⟩

theorem restrict_covers (covered : Covers bindings needed) (retained : needed ⊆ kept) :
    Covers (restrictEnvironment bindings kept) needed := by
  intro var member
  obtain ⟨binding, bindingMember, same⟩ := (lookup_exists_iff _ _).mp (covered var member)
  apply (lookup_exists_iff _ _).mpr
  refine ⟨binding, ?_, same⟩
  exact List.mem_filter.mpr ⟨bindingMember, by simpa [same] using retained member⟩

theorem createScope_keys (machine : State) (context : Context) (invocation : InvocationId)
    (parent : Option LexicalScopeId) (vars : List VariableId) (values : List Located) (bindings : Environment)
    (after : State) (entered : Environment)
    (accepted : createScope machine context invocation parent vars values bindings = .ok (after, entered)) :
    entered.map Binding.var = vars ++ (bindings.filter (fun binding => !vars.contains binding.var)).map Binding.var := by
  simp only [createScope, bind, except_bind_ok] at accepted
  obtain ⟨_, checked, accepted⟩ := accepted
  have lengths : vars.length = values.length := by
    unfold require at checked
    split at checked <;> try contradiction
    rename_i valid
    simpa [bindArguments, Bool.and_eq_true] using (show (vars.length == values.length) = true from
      (Bool.and_eq_true_iff.mp (Bool.and_eq_true_iff.mp valid).1).1)
  split at accepted
  · cases accepted
    simp [List.map_map, Function.comp_def, List.map_fst_zip, lengths]
  · simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq, Prod.mk.injEq] at accepted
    obtain ⟨_, _, _, _, rfl, rfl⟩ := accepted
    simp [List.map_map, Function.comp_def, List.map_fst_zip, lengths]

theorem createScope_covers (machine : State) (context : Context) (invocation : InvocationId)
    (parent : Option LexicalScopeId) (vars : List VariableId) (values : List Located) (bindings : Environment)
    (after : State) (entered : Environment) (covered : Covers bindings needed)
    (accepted : createScope machine context invocation parent vars values bindings = .ok (after, entered)) :
    Covers entered (vars ++ needed) := by
  rw [covers_iff_subset, createScope_keys _ _ _ _ _ _ _ _ _ accepted]
  intro var member
  by_cases introduced : var ∈ vars
  · exact List.mem_append_left _ introduced
  · have needed := (List.mem_append.mp member).resolve_left introduced
    obtain ⟨binding, member, same⟩ := (lookup_exists_iff _ _).mp (covered var needed)
    apply List.mem_append_right
    apply List.mem_map.mpr
    exact ⟨binding, List.mem_filter.mpr ⟨member, by simpa [same] using introduced⟩, same⟩

theorem function_body_variables (source : Module) (facts : Analysis.Facts)
    (checked : Analysis.check source facts = true) (function : FunctionId .source) (definition : Source.Function)
    (body : TermId) (found : source.functions[function.value]? = some definition) (atBody : definition.body = some body)
    (var : VariableId) (needed : var ∈ variables facts (.term body)) :
    var ∈ Analysis.captures facts function ++ definition.parameters := by
  by_cases parameter : var ∈ definition.parameters
  · exact List.mem_append_right _ parameter
  · apply List.mem_append_left
    exact dependency_variables _ _ checked (.function function) ⟨.term body, definition.parameters⟩
      (by simp [Analysis.dependencies, found, atBody]) var needed parameter

end LexicalCoverage
end BoundaryV2.Profile.Source.Machine

namespace BoundaryV2.Profile.Source.Machine
namespace LexicalCoverage

theorem checked_function_body_bound (context : Context) (typed : context.typingValid = true)
    (function : FunctionId .source) (definition : Source.Function) (body : TermId)
    (found : context.source.functions[function.value]? = some definition) (atBody : definition.body = some body) :
    body.value < context.source.terms.length := by
  have formed := OperandSchemas.checked_context_formation context typed
  simp only [Analysis.formation, Bool.and_eq_true] at formed
  have checked := List.all_eq_true.mp formed.2 definition (List.mem_of_getElem? found)
  simp only [Bool.and_eq_true] at checked
  simpa [atBody] using checked.2

/-- Actual function entry supplies every free body variable through the ordered
capture fields or the declared parameters, and chooses an existing source term. -/
theorem invokeFunction_establishes_body_bindings (machine : State) (context : Context)
    (function : FunctionId .source) (bindings : Environment) (arguments : List Located) (after : Transition)
    (typed : context.typingValid = true)
    (accepted : invokeFunction machine context function bindings arguments = .ok after) :
    ∃ body entered, after.state.control = .term body entered ∧ body.value < context.source.terms.length ∧
      Covers entered (variables context.captures (.term body)) := by
  simp only [invokeFunction, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨definition, found, body, atBody, _, _, _, _, _, _, ⟨middle, entered⟩, created, rfl⟩ := accepted
  refine ⟨body, entered, rfl, checked_function_body_bound context typed function definition body found atBody, ?_⟩
  have covered := createScope_covers _ _ _ _ _ _ _ _ _ (needed := []) (by simp [Covers]) created
  apply covers_mono covered
  intro var needed
  simpa only [List.append_nil] using function_body_variables context.source context.captures
    (checked_capture_analysis context typed) function definition body found atBody var needed

end LexicalCoverage
end BoundaryV2.Profile.Source.Machine

namespace BoundaryV2.Profile.Source.Machine
namespace LexicalCoverage

def SiteValid (context : Context) (node : Analysis.Node) (bindings : Environment) : Prop :=
  Analysis.inBounds context.source node ∧ Covers bindings (variables context.captures node)

def IntentValid (context : Context) (intent : Intent) (bindings : Environment) : Prop := match intent with
  | .term term => term ∈ context.source.terms ∧ Covers bindings (continuationVariables context intent)
  | .primitive .. => True

def FrameValid (context : Context) : Frame → Prop
  | .binding var body bindings _ => body.value < context.source.terms.length ∧
      Covers bindings ((variables context.captures (.term body)).filter (· != var))
  | .operands intent bindings remaining _ => IntentValid context intent bindings ∧
      ∀ reference ∈ remaining, SiteValid context (.value reference) bindings
  | _ => True

def ControlValid (context : Context) : Control → Prop
  | .term body bindings => SiteValid context (.term body) bindings
  | .expression reference bindings => SiteValid context (.value reference) bindings
  | .invoke function bindings _ => SiteValid context (.function function) bindings
  | .execute intent bindings _ => IntentValid context intent bindings
  | _ => True

theorem covers_append (bindings : Environment) (left right : List VariableId) :
    Covers bindings (left ++ right) ↔ Covers bindings left ∧ Covers bindings right := by
  simp [Covers, List.mem_append, or_imp, forall_and]

theorem site_rename (context : Context) (node : Analysis.Node) (bindings : Environment) (mapping : Renaming)
    (covered : SiteValid context node bindings) : SiteValid context node (renameEnvironment mapping bindings) :=
  ⟨covered.1, renamed_environment_covers mapping covered.2⟩

theorem intent_rename (context : Context) (intent : Intent) (bindings : Environment) (mapping : Renaming)
    (covered : IntentValid context intent bindings) : IntentValid context intent (renameEnvironment mapping bindings) := by
  cases intent with
  | term => exact ⟨covered.1, renamed_environment_covers mapping covered.2⟩
  | primitive => trivial

theorem frame_rename (context : Context) (frame : Frame) (mapping : Renaming)
    (covered : FrameValid context frame) : FrameValid context (renameFrame mapping frame) := by
  cases frame with
  | binding => exact ⟨covered.1, renamed_environment_covers mapping covered.2⟩
  | operands intent bindings remaining evaluated =>
    exact ⟨intent_rename _ _ _ _ covered.1, fun reference member => site_rename _ _ _ _ (covered.2 reference member)⟩
  | _ => trivial

theorem frame_trim (context : Context) (frame : Frame) (covered : FrameValid context frame) :
    FrameValid context (trimFrame context frame) := by
  cases frame with
  | binding => exact ⟨covered.1, restrict_covers covered.2 (List.Subset.refl _)⟩
  | operands intent bindings remaining evaluated =>
    refine ⟨?_, ?_⟩
    · cases intent with
      | term => exact ⟨covered.1.1, restrict_covers covered.1.2 (fun _ member => List.mem_append_right _ member)⟩
      | primitive => trivial
    · intro reference member
      refine ⟨(covered.2 reference member).1, restrict_covers (covered.2 reference member).2 ?_⟩
      intro var needed
      exact List.mem_append_left _ (List.mem_flatMap.mpr ⟨reference, member, needed⟩)
  | _ => exact covered

theorem value_operand_variables (context : Context) (typed : context.typingValid = true)
    (reference : SourceValueId) (schema : SchemaId .source) (opcode : Opcode) (operands : List SourceValueId)
    (immediate : Nat) (failures : List (InstructionFailure .source))
    (found : context.source.values[reference.value]? = some ⟨schema, .primitive opcode operands immediate failures⟩)
    (operand : SourceValueId) (member : operand ∈ operands) :
    variables context.captures (.value operand) ⊆ variables context.captures (.value reference) := by
  intro var needed
  exact dependency_variables _ _ (checked_capture_analysis _ typed) (.value reference) ⟨.value operand, []⟩
    (by simpa [Analysis.dependencies, found] using member) var needed (by simp)

theorem term_operand_variables (context : Context) (typed : context.typingValid = true)
    (reference : TermId) (term : Source.Term) (found : context.source.terms[reference.value]? = some term)
    (operand : SourceValueId) (member : operand ∈ Analysis.termValues term) :
    variables context.captures (.value operand) ⊆ variables context.captures (.term reference) := by
  intro var needed
  apply dependency_variables _ _ (checked_capture_analysis _ typed) (.term reference) ⟨.value operand, []⟩ _ var needed (by simp)
  simp only [Analysis.dependencies, found, List.mem_append]
  exact Or.inl (Or.inl (List.mem_map.mpr ⟨operand, member, rfl⟩))

theorem term_child_variables (context : Context) (typed : context.typingValid = true)
    (reference : TermId) (term : Source.Term) (found : context.source.terms[reference.value]? = some term)
    (child : TermId) (bound : List VariableId) (member : (child, bound) ∈ Analysis.termChildren term) :
    ((variables context.captures (.term child)).filter (fun var => !bound.contains var)) ⊆
      variables context.captures (.term reference) := by
  intro var needed
  have selected := List.mem_filter.mp needed
  apply dependency_variables _ _ (checked_capture_analysis _ typed) (.term reference) ⟨.term child, bound⟩ _ var selected.1 (by simpa using selected.2)
  simp only [Analysis.dependencies, found, List.mem_append]
  exact Or.inl (Or.inr (List.mem_map.mpr ⟨(child, bound), member, rfl⟩))

theorem term_continuation_variables (context : Context) (typed : context.typingValid = true)
    (reference : TermId) (term : Source.Term) (found : context.source.terms[reference.value]? = some term) :
    continuationVariables context (.term term) ⊆ variables context.captures (.term reference) := by
  intro var needed
  simp only [continuationVariables, List.mem_append] at needed
  rcases needed with child | call
  · obtain ⟨⟨child, bound⟩, member, needed⟩ := List.mem_flatMap.mp child
    exact term_child_variables _ typed _ _ found child bound member needed
  · cases term <;> try cases call
    rename_i function arguments
    exact dependency_variables _ _ (checked_capture_analysis _ typed) (.term reference) ⟨.function function, []⟩
      (by simp [Analysis.dependencies, found]) var call (by simp)

end LexicalCoverage
end BoundaryV2.Profile.Source.Machine
