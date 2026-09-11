import BoundaryV2.SourcePrimitives
import BoundaryV2.SourceValues

namespace BoundaryV2.Profile.Source.Admission

theorem variableTypes_member (source : Module) (variables : List VariableId) (types : List (SchemaId .source))
    (accepted : variableTypes source variables = some types) (binder : VariableId) (type : SchemaId .source)
    (member : binder ∈ variables) (found : source.variables[binder.value]? = some type) : type ∈ types := by
  unfold variableTypes at accepted
  induction variables generalizing types with
  | nil => simp at member
  | cons head tail induction =>
    simp only [List.mapM_cons, bind, Option.bind_eq_some_iff, pure, Option.some.injEq] at accepted
    obtain ⟨first, firstFound, rest, restFound, rfl⟩ := accepted
    rcases List.mem_cons.mp member with rfl | member
    · rw [found] at firstFound
      cases firstFound
      exact List.mem_cons_self
    · exact List.mem_cons_of_mem _ (induction rest restFound member)

/-- The source lambda's declared bound includes the actual type of each
lexically captured binder. Capture membership is derived from the checked
function interface, not inferred from the closure's reusable/multi label. -/
theorem lambda_capture_in_bound (source : Module) (facts : Analysis.Facts) (function : FunctionId .source)
    (type : SchemaId .source) (signature : ComputationType .source) (binder : VariableId)
    (capture : SchemaId .source) (accepted : lambdaValid source facts function type = true)
    (shape : source.schemas[type.value]? = some (.internal (.computation signature)))
    (member : binder ∈ Analysis.captures facts function)
    (found : source.variables[binder.value]? = some capture) : capture ∈ signature.captureBound := by
  cases definitionFound : source.functions[function.value]? with
  | none => simp [lambdaValid, shape, definitionFound] at accepted
  | some definition =>
    cases typesFound : variableTypes source (Analysis.captures facts function) with
    | none => simp [lambdaValid, shape, definitionFound, typesFound] at accepted
    | some types =>
      have bounded : types.all signature.captureBound.contains = true := by
        simp only [lambdaValid, shape, definitionFound, typesFound, bind, Option.bind_some,
          pure, Option.getD_some, Bool.and_eq_true] at accepted
        exact accepted.2
      have typeMember := variableTypes_member source _ types typesFound binder capture member found
      simpa using List.all_eq_true.mp bounded capture typeMember

theorem lambda_capture_trait_safe (source : Module) (facts : Analysis.Facts) (function : FunctionId .source)
    (type : SchemaId .source) (signature : ComputationType .source) (binder : VariableId)
    (capture : SchemaId .source) (kind : Traits.Kind) (accepted : lambdaValid source facts function type = true)
    (shape : source.schemas[type.value]? = some (.internal (.computation signature)))
    (trait : Traits.Safe source.schemas (type, kind))
    (member : binder ∈ Analysis.captures facts function)
    (found : source.variables[binder.value]? = some capture) : Traits.Safe source.schemas (capture, kind) :=
  trait.computation_capture source.schemas type signature kind capture shape
    (lambda_capture_in_bound source facts function type signature binder capture accepted shape member found)

end BoundaryV2.Profile.Source.Admission

namespace BoundaryV2.Profile.Source.Machine

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

theorem closure_creation_checks_capture_types (state : State) (context : Context) (schema : SchemaId .source)
    (function : FunctionId .source) (values : List Located) (after : Transition)
    (accepted : makeClosureWithValues state context schema function values = .ok after) :
    (Analysis.captures context.captures function).length = values.length ∧
      ∀ value ∈ values, ∃ binder ∈ Analysis.captures context.captures function,
        context.source.variables[binder.value]? = some value.value.schema := by
  simp only [makeClosureWithValues, bind, except_bind_ok] at accepted
  obtain ⟨_, checked, _⟩ := accepted
  have checkedFields :
      (Analysis.captures context.captures function).length = values.length ∧
      ((Analysis.captures context.captures function).zip values).all
        (fun (binder, value) => context.source.variables[binder.value]? == some value.value.schema) = true := by
    unfold require at checked
    split at checked <;> try contradiction
    have both := Bool.and_eq_true_iff.mp ‹_ = true›
    exact ⟨by simpa using both.1, both.2⟩
  refine ⟨checkedFields.1, ?_⟩
  intro value member
  obtain ⟨index, found⟩ := List.mem_iff_getElem?.mp member
  have bound : index < (Analysis.captures context.captures function).length := by
    rw [checkedFields.1]
    exact (List.getElem?_eq_some_iff.mp found).choose
  let binder := (Analysis.captures context.captures function)[index]
  have binderFound : (Analysis.captures context.captures function)[index]? = some binder :=
    List.getElem?_eq_getElem bound
  refine ⟨binder, List.mem_of_getElem? binderFound, ?_⟩
  have pairMember : (binder, value) ∈ (Analysis.captures context.captures function).zip values :=
    List.mem_iff_getElem?.mpr ⟨index, List.getElem?_zip_eq_some.mpr ⟨binderFound, found⟩⟩
  simpa using List.all_eq_true.mp checkedFields.2 _ pairMember

theorem created_closure_capture_traits (state : State) (context : Context) (schema : SchemaId .source)
    (function : FunctionId .source) (values : List Located) (after : Transition)
    (signature : ComputationType .source) (kind : Traits.Kind)
    (accepted : makeClosureWithValues state context schema function values = .ok after)
    (admitted : Admission.lambdaValid context.source context.captures function schema = true)
    (shape : context.source.schemas[schema.value]? = some (.internal (.computation signature)))
    (trait : Traits.Safe context.source.schemas (schema, kind)) :
    ∀ value ∈ values, Traits.Safe context.source.schemas (value.value.schema, kind) := by
  intro value member
  obtain ⟨binder, captured, typed⟩ := (closure_creation_checks_capture_types _ _ _ _ _ _ accepted).2 value member
  exact Admission.lambda_capture_trait_safe _ _ _ _ _ _ _ _ admitted shape trait captured typed

end BoundaryV2.Profile.Source.Machine
