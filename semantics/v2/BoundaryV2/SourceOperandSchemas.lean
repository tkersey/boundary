import BoundaryV2.SourceOperandExecution
import BoundaryV2.SourcePrimitiveTypes

namespace BoundaryV2.Profile.Source.Machine
namespace OperandSchemas

abbrev Schemas := List (SchemaId .source)

def schemas (values : List Located) : Schemas := values.map (fun value => value.value.schema)

inductive Signature (source : Module) : Intent → Schemas → Prop where
  | primitive (member : Source.Value.mk schema (.primitive opcode operands immediate failures) ∈ source.values)
      (types : Admission.valueTypes source operands = some expected) :
      Signature source (.primitive schema opcode immediate failures) expected
  | term (member : authored ∈ source.terms)
      (types : Admission.valueTypes source (Analysis.termValues authored) = some expected) :
      Signature source (.term authored) expected

inductive Spine (source : Module) : Option (SchemaId .source) → List Frame → Prop where
  | plain (empty : OperandStructure.NoOperands frames) : Spine source input frames
  | primitive (signature : Signature source (.primitive schema opcode immediate failures)
        (schemas evaluated ++ input :: remainingTypes))
      (remainingTyped : Admission.valueTypes source remaining = some remainingTypes)
      (tailTyped : Spine source (some schema) tail) :
      Spine source (some input) (.operands (.primitive schema opcode immediate failures) bindings remaining evaluated :: tail)
  | term (signature : Signature source (.term authored) (schemas evaluated ++ input :: remainingTypes))
      (remainingTyped : Admission.valueTypes source remaining = some remainingTypes)
      (tailTyped : OperandStructure.NoOperands tail) :
      Spine source (some input) (.operands (.term authored) bindings remaining evaluated :: tail)

def LocalTypes (source : Module) (machine : State) : Prop := match machine.control with
  | .expression reference _ => Spine source (Analysis.valueType source reference) machine.stack
  | .delivered value => Spine source (some value.value.schema) machine.stack
  | .execute intent _ values =>
    Signature source intent (schemas values) ∧ match intent with
      | .primitive schema .. => Spine source (some schema) machine.stack
      | .term _ => OperandStructure.NoOperands machine.stack
  | _ => True

def ParkedPlain (machine : State) : Prop := ∀ request, machine.status = .parked request → OperandStructure.NoOperands machine.stack

def Typed (source : Module) (machine : State) : Prop :=
  OperandStructure.Valid machine ∧ LocalTypes source machine ∧ ParkedPlain machine

theorem Spine.layout {source : Module} {input : Option (SchemaId .source)} {frames : List Frame}
    (typed : Spine source input frames) : OperandStructure.Layout frames := by
  induction typed with
  | plain empty => exact .plain empty
  | primitive _ _ _ induction => exact .primitive induction
  | term _ _ empty => exact .term empty

theorem valueTypes_nil (source : Module) : Admission.valueTypes source [] = some [] := rfl

theorem valueTypes_cons (source : Module) (first : SourceValueId) (rest : List SourceValueId) (expected : Schemas)
    (typed : Admission.valueTypes source (first :: rest) = some expected) :
    ∃ schema tail, Analysis.valueType source first = some schema ∧ Admission.valueTypes source rest = some tail ∧
      expected = schema :: tail := by
  simp only [Admission.valueTypes, List.mapM_cons, bind, Option.bind_eq_some_iff, pure, Option.some.injEq] at typed
  obtain ⟨schema, firstAt, tail, restAt, rfl⟩ := typed
  exact ⟨schema, tail, firstAt, restAt, rfl⟩

theorem valueTypes_total (source : Module) (references : List SourceValueId)
    (bounded : ∀ reference ∈ references, reference.value < source.values.length) :
    ∃ types, Admission.valueTypes source references = some types := by
  induction references with
  | nil => exact ⟨[], rfl⟩
  | cons reference rest induction =>
    obtain ⟨types, restAt⟩ := induction (fun child member => bounded child (by simp [member]))
    have indexBound := bounded reference (by simp)
    have found := List.getElem?_eq_getElem indexBound
    exact ⟨source.values[reference.value].schema :: types, by simp [Admission.valueTypes, List.mapM_cons, Analysis.valueType, found,
      show rest.mapM (Analysis.valueType source) = some types from restAt]⟩

theorem checked_context_formation (context : Context) (typed : context.typingValid = true) :
    Analysis.formation context.source = true := by
  simp only [Context.typingValid, Option.any_eq_true] at typed
  obtain ⟨_, _, admitted⟩ := typed
  simp only [Admission.typed, Analysis.foundationValid, Bool.and_eq_true] at admitted
  grind only []

theorem checked_term_operand_types (context : Context) (index : Nat) (authored : Term)
    (typed : context.typingValid = true) (found : context.source.terms[index]? = some authored) :
    ∃ types, Admission.valueTypes context.source (Analysis.termValues authored) = some types := by
  have formed := checked_context_formation context typed
  simp only [Analysis.formation, Bool.and_eq_true] at formed
  have member : (authored, index) ∈ context.source.terms.zipIdx :=
    List.mem_iff_getElem?.mpr ⟨index, by simp [found]⟩
  have termFormed := List.all_eq_true.mp formed.1.1.2 _ member
  simp only [Analysis.formedTerm, Bool.and_eq_true] at termFormed
  apply valueTypes_total
  intro reference member
  exact of_decide_eq_true (List.all_eq_true.mp termFormed.1.1.1 reference member)

theorem checked_primitive_signature (context : Context) (index : Nat) (schema : SchemaId .source)
    (opcode : Opcode) (operands : List SourceValueId) (immediate : Nat) (failures : List (InstructionFailure .source))
    (typed : context.typingValid = true)
    (found : context.source.values[index]? = some ⟨schema, .primitive opcode operands immediate failures⟩) :
    ∃ types, Admission.valueTypes context.source operands = some types ∧
      Signature context.source (.primitive schema opcode immediate failures) types := by
  have admitted := checked_context_checks_value context ⟨index⟩ _ typed found
  obtain ⟨types, typesAt, _⟩ := (Option.any_eq_true _ _).mp admitted
  exact ⟨types, typesAt, .primitive (List.mem_of_getElem? found) typesAt⟩

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem deliverOperand_types (source : Module) (machine : State) (after : Transition)
    (accepted : deliverOperand machine = .ok after) (typed : LocalTypes source machine) : LocalTypes source after.state := by
  unfold deliverOperand at accepted
  split at accepted <;> try contradiction
  rename_i value delivered
  split at accepted <;> try contradiction
  rename_i intent bindings remaining evaluated tail stacked
  have spine : Spine source (some value.value.schema) (.operands intent bindings remaining evaluated :: tail) := by
    simpa only [LocalTypes, delivered, stacked] using typed
  cases spine with
  | plain empty => exact False.elim (empty _ List.mem_cons_self _ _ _ _ rfl)
  | primitive signature remainingTyped tailTyped =>
    cases remaining with
    | nil =>
      cases accepted
      have empty : _ = [] := Option.some.inj remainingTyped.symm
      subst empty
      exact ⟨by simpa only [schemas, List.map_append, List.map_cons, List.map_nil] using signature, tailTyped⟩
    | cons next rest =>
      obtain ⟨nextSchema, restSchemas, firstAt, restAt, rfl⟩ := valueTypes_cons source next rest _ remainingTyped
      cases accepted
      simp only [LocalTypes, firstAt]
      exact .primitive (by simpa only [schemas, List.map_append, List.map_cons, List.map_nil,
        List.append_assoc, List.singleton_append] using signature) restAt tailTyped
  | term signature remainingTyped tailTyped =>
    cases remaining with
    | nil =>
      cases accepted
      have empty : _ = [] := Option.some.inj remainingTyped.symm
      subst empty
      exact ⟨by simpa only [schemas, List.map_append, List.map_cons, List.map_nil] using signature, tailTyped⟩
    | cons next rest =>
      obtain ⟨nextSchema, restSchemas, firstAt, restAt, rfl⟩ := valueTypes_cons source next rest _ remainingTyped
      cases accepted
      simp only [LocalTypes, firstAt]
      exact .term (by simpa only [schemas, List.map_append, List.map_cons, List.map_nil,
        List.append_assoc, List.singleton_append] using signature) restAt tailTyped


private theorem require_ok (condition : Bool) (reason : Invalid) (result : Unit)
    (accepted : require condition reason = .ok result) : condition = true := by
  unfold require at accepted
  split at accepted <;> first | assumption | contradiction

theorem makeClosure_result_schema (machine : State) (context : Context) (schema : SchemaId .source)
    (function : FunctionId .source) (bindings : Environment) (after : Transition)
    (accepted : makeClosure machine context schema function bindings = .ok after) (value : Located)
    (delivered : after.state.control = .delivered value) : value.value.schema = schema := by
  simp only [makeClosure, bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  exact makeClosureWithValues_result_schema _ _ _ _ _ _ accepted _ delivered

theorem enterExpression_types (machine : State) (context : Context) (after : Transition)
    (accepted : enterExpression machine context = .ok after) (contextTyped : context.typingValid = true)
    (heapTyped : OperandStructure.HeapValid machine.heap) (typed : LocalTypes context.source machine) :
    LocalTypes context.source after.state := by
  unfold enterExpression at accepted
  split at accepted <;> try contradiction
  rename_i reference bindings executing
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨⟨schema, expression⟩, found, accepted⟩ := accepted
  have spine : Spine context.source (some schema) machine.stack := by
    simpa only [LocalTypes, executing, Analysis.valueType, found, Option.map_some] using typed
  cases expression with
  | «variable» binder =>
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨value, _, _, checked, _, _, rfl⟩ := accepted
    have same : value.value.schema = schema := by simpa using require_ok _ _ _ checked
    simpa only [LocalTypes, finishValue, same] using spine
  | literal constant =>
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨value, _, _, checked, accepted⟩ := accepted
    have same : value.schema = schema := by simpa using require_ok _ _ _ checked
    obtain ⟨⟨result, delivered⟩, stacked, _⟩ := OperandStructure.scopedValue_shape _ _ _ accepted
    have resultSchema := scopedValue_result_schema _ _ _ accepted _ delivered
    simpa only [LocalTypes, delivered, stacked, resultSchema, same] using spine
  | lambda function =>
    obtain ⟨⟨result, delivered⟩, stacked, _⟩ := OperandStructure.makeClosure_shape _ _ _ _ _ _ accepted heapTyped
    have same := makeClosure_result_schema _ _ _ _ _ _ accepted _ delivered
    simpa only [LocalTypes, delivered, stacked, same] using spine
  | primitive opcode operands immediate failures =>
    obtain ⟨types, typesAt, signature⟩ := checked_primitive_signature context reference.value schema opcode operands immediate failures contextTyped found
    cases operands with
    | nil =>
      cases accepted
      have empty : types = [] := Option.some.inj typesAt.symm
      subst types
      exact ⟨signature, spine⟩
    | cons first rest =>
      obtain ⟨input, remainingTypes, firstAt, restAt, rfl⟩ := valueTypes_cons context.source first rest types typesAt
      cases accepted
      simp only [LocalTypes, firstAt]
      exact .primitive signature restAt spine

theorem executePrimitive_types (machine : State) (context : Context) (after : Transition)
    (accepted : executePrimitive machine context = .ok after) (heapTyped : OperandStructure.HeapValid machine.heap)
    (typed : LocalTypes context.source machine) : LocalTypes context.source after.state := by
  have original := accepted
  unfold executePrimitive at accepted
  split at accepted <;> try contradiction
  rename_i schema opcode immediate failures bindings operands executing
  have spine : Spine context.source (some schema) machine.stack := by
    exact (show Signature context.source (.primitive schema opcode immediate failures) (schemas operands) ∧
      Spine context.source (some schema) machine.stack from by simpa only [LocalTypes, executing] using typed).2
  have deliveredTypes (value : Located) (delivered : after.state.control = .delivered value)
      (stacked : after.state.stack = machine.stack) : LocalTypes context.source after.state := by
    have same := executePrimitive_result_schema _ _ _ _ _ _ _ _ _ _ executing original delivered
    simpa only [LocalTypes, delivered, stacked, same] using spine
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted
  · contradiction
  · obtain ⟨⟨exit, unwinding⟩, _, _⟩ := OperandStructure.authoredFailure_shape _ _ _ _ _ accepted
    simp only [LocalTypes, unwinding]
  · obtain ⟨⟨value, delivered⟩, stacked, _⟩ := OperandStructure.commitPure_shape _ _ _ _ _ accepted
    exact deliveredTypes _ delivered stacked
  · obtain ⟨⟨value, delivered⟩, stacked, _⟩ := OperandStructure.heapPrimitive_shape _ _ _ _ _ _ _ accepted heapTyped
    exact deliveredTypes _ delivered stacked

end OperandSchemas
end BoundaryV2.Profile.Source.Machine
