import BoundaryV2.SourceResults
import BoundaryV2.PrimitiveAdmission
import BoundaryV2.EarlierRows

namespace BoundaryV2.Profile.Source.Admission

def variableTypes (source : Module) (variables : List VariableId) : Option (List (SchemaId .source)) :=
  variables.mapM (fun binder => source.variables[binder.value]?)

def valueTypes (source : Module) (values : List SourceValueId) : Option (List (SchemaId .source)) :=
  values.mapM (Analysis.valueType source)

def executionLiterals (source : Module) : List (Literal .source) :=
  match Analysis.firstUnit source with
  | none => source.constants
  | some type =>
    if Analysis.hasDisposal source && !source.constants.any
        (fun literal => literal.schema == type && literal.bytes.isEmpty) then
      source.constants ++ [⟨type, []⟩]
    else source.constants

/-- Constructor indices are derived from source syntax and checked lexical
captures. This adapter never consumes target blocks or a lowering witness. -/
def primitiveContext (source : Module) (facts : Analysis.Facts) : PrimitiveAdmission.Context .source where
  schemas := source.schemas
  constants := executionLiterals source
  failure := source.failure
  resources := source.resources
  constructor index := do
    let (function, schema) ← (Analysis.constructors source)[index]?
    let fields ← variableTypes source (Analysis.captures facts function)
    return (schema, fields)

def lambdaValid (source : Module) (facts : Analysis.Facts) (function : FunctionId .source)
    (type : SchemaId .source) : Bool := ((do
  let .internal (.computation signature) ← source.schemas[type.value]? | none
  let definition ← source.functions[function.value]?
  let fields ← variableTypes source (Analysis.captures facts function)
  return variableTypes source definition.parameters == some signature.parameters &&
    definition.result == signature.result && definition.effects.all signature.effects.contains &&
    definition.regions == signature.regions && fields.all signature.captureBound.contains) : Option Bool).getD false

def primitiveValid (source : Module) (facts : Analysis.Facts) (value : Source.Value) : Bool :=
  match value.expression with
  | .variable binder => source.variables[binder.value]? == some value.schema
  | .literal constant => (source.constants[constant.value]?).map Literal.schema == some value.schema
  | .lambda function => lambdaValid source facts function value.schema
  | .primitive opcode operands immediate failures =>
    (valueTypes source operands).any (fun types =>
      let context := primitiveContext source facts
      let operation : PrimitiveAdmission.Operation .source := ⟨opcode, value.schema, immediate, failures⟩
      PrimitiveAdmission.failuresValid context operation types &&
      if opcode == .resourcePack || opcode == .resourceUnpack then
        (PrimitiveAdmission.resourceOperation context opcode value.schema types immediate).isSome
      else PrimitiveAdmission.operationType context ⟨0⟩ operation types)

/-- A raw resource expression has a type before it has an enclosing function.
Every occurrence additionally checks the authority of its actual function.
Entering a lambda or a call does not lend the caller's authority to its body. -/
def resourceAuthority (source : Module) (facts : Analysis.Facts) (owner : FunctionId .source)
    (value : Source.Value) : Bool := match value.expression with
  | .primitive opcode operands immediate _ =>
    if opcode == .resourcePack || opcode == .resourceUnpack then
      (valueTypes source operands).any (fun types => PrimitiveAdmission.resourceInstruction
        (primitiveContext source facts) owner opcode value.schema types immediate)
    else true
  | _ => true

def valueChildren (source : Module) (index : Nat) : List Nat :=
  match source.values[index]? with
  | some ⟨_, .primitive _ operands _ _⟩ => operands.map Ref.value
  | _ => []

def termChildren (source : Module) (index : Nat) : List Nat :=
  ((source.terms[index]?).map (fun term => (Analysis.termChildren term).map (fun (child, _) => child.value))).getD []

def authorityValueRows (source : Module) (facts : Analysis.Facts) (owner : FunctionId .source) : List Bool :=
  EarlierRows.compute (fun index => (source.values[index]?).any (resourceAuthority source facts owner))
    (valueChildren source) source.values.length

def termValuesAuthorized (source : Module) (values : List Bool) (index : Nat) : Bool :=
  (source.terms[index]?).any (fun term =>
    (Analysis.termValues term).all (fun value => values[value.value]?.getD false))

def authorityTermCheck (source : Module) (facts : Analysis.Facts) (owner : FunctionId .source) (index : Nat) : Bool :=
  termValuesAuthorized source (authorityValueRows source facts owner) index

def authorityTermRows (source : Module) (facts : Analysis.Facts) (owner : FunctionId .source) : List Bool :=
  let values := authorityValueRows source facts owner
  EarlierRows.compute (termValuesAuthorized source values) (termChildren source) source.terms.length

/-- Sharing the immutable value table changes no row, including rejection of
forward references and uses outside this function's resource authority. -/
theorem authorityTermRows_exact (source : Module) (facts : Analysis.Facts) (owner : FunctionId .source) :
    authorityTermRows source facts owner =
      EarlierRows.compute (authorityTermCheck source facts owner) (termChildren source) source.terms.length := rfl

def primitivesValid (source : Module) (facts : Analysis.Facts) : Bool :=
  source.values.all (primitiveValid source facts) &&
  source.functions.zipIdx.all (fun (function, index) =>
    (function.body >>= fun body => (authorityTermRows source facts ⟨index⟩)[body.value]?).getD false)

theorem primitive_faults_exact (source : Module) (facts : Analysis.Facts)
    (type : SchemaId .source) (opcode : Opcode) (operands : List SourceValueId)
    (immediate : Nat) (failures : List (InstructionFailure .source))
    (accepted : primitiveValid source facts ⟨type, .primitive opcode operands immediate failures⟩ = true) :
    ∃ types, valueTypes source operands = some types ∧
      failures.map InstructionFailure.kind =
        PrimitiveAdmission.requiredFaults (primitiveContext source facts) opcode type types ∧
      ∀ failure ∈ failures, ∃ literal,
        (executionLiterals source)[failure.value.value]? = some literal ∧ literal.schema = source.failure := by
  obtain ⟨types, found, checked⟩ := (Option.any_eq_true _ _).mp accepted
  dsimp only at checked
  simp only [Bool.and_eq_true] at checked
  have faults := checked.1
  refine ⟨types, found, ?_⟩
  simpa [PrimitiveAdmission.failuresValid, primitiveContext, Bool.and_eq_true,
    List.all_eq_true, Option.any_eq_true] using faults

theorem primitives_checks_unreachable_value (source : Module) (facts : Analysis.Facts)
    (accepted : primitivesValid source facts = true) (value : Source.Value)
    (member : value ∈ source.values) : primitiveValid source facts value = true := by
  simp only [primitivesValid, Bool.and_eq_true] at accepted
  exact List.all_eq_true.mp accepted.1 value member

theorem resource_occurrence_authorized (source : Module) (facts : Analysis.Facts)
    (owner : FunctionId .source) (type : SchemaId .source) (opcode : Opcode)
    (operands : List SourceValueId) (immediate : Nat) (failures : List (InstructionFailure .source))
    (resource : opcode = .resourcePack ∨ opcode = .resourceUnpack)
    (accepted : resourceAuthority source facts owner ⟨type, .primitive opcode operands immediate failures⟩ = true) :
    ∃ types descriptor, valueTypes source operands = some types ∧
      PrimitiveAdmission.resourceOperation (primitiveContext source facts) opcode type types immediate = some descriptor ∧
      owner ∈ (if opcode == .resourcePack then descriptor.introducers else descriptor.eliminators) := by
  have isResource : (opcode == .resourcePack || opcode == .resourceUnpack) = true := by
    rcases resource with rfl | rfl <;> decide
  simp only [resourceAuthority, isResource, ite_true, Option.any_eq_true,
    PrimitiveAdmission.resourceInstruction] at accepted
  obtain ⟨types, found, descriptor, lookup, authorized⟩ := accepted
  exact ⟨types, descriptor, found, lookup, List.contains_iff_mem.mp authorized⟩

theorem authority_reaches_operand (source : Module) (facts : Analysis.Facts) (owner : FunctionId .source)
    (body term : TermId) (authored : Term) (value operand : SourceValueId) (expression : Source.Value)
    (accepted : (authorityTermRows source facts owner)[body.value]? = some true)
    (termReach : EarlierRows.Reach (termChildren source) body.value term.value)
    (atTerm : source.terms[term.value]? = some authored) (supplied : value ∈ Analysis.termValues authored)
    (valueReach : EarlierRows.Reach (valueChildren source) value.value operand.value)
    (atValue : source.values[operand.value]? = some expression) :
    resourceAuthority source facts owner expression = true := by
  have termChecked := EarlierRows.descendants_checked _ _ _ _ accepted termReach
  simp only [termValuesAuthorized, atTerm, Option.any_some, List.all_eq_true] at termChecked
  have valueChecked := EarlierRows.getD_true _ |>.mp (termChecked value supplied)
  have checked := EarlierRows.descendants_checked _ _ _ _ valueChecked valueReach
  simpa only [atValue, Option.any_some] using checked

theorem function_authority_root (source : Module) (facts : Analysis.Facts) (owner : FunctionId .source)
    (function : Function) (body : TermId) (accepted : primitivesValid source facts = true)
    (atFunction : source.functions[owner.value]? = some function) (atBody : function.body = some body) :
    (authorityTermRows source facts owner)[body.value]? = some true := by
  simp only [primitivesValid, Bool.and_eq_true] at accepted
  have member : (function, owner.value) ∈ source.functions.zipIdx :=
    List.mem_iff_getElem?.mpr ⟨owner.value, by simp [atFunction]⟩
  have checked := List.all_eq_true.mp accepted.2 _ member
  simpa [atBody, EarlierRows.getD_true] using checked

end BoundaryV2.Profile.Source.Admission
