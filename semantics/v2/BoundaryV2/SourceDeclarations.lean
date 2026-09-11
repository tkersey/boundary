import BoundaryV2.SourcePrimitives
import BoundaryV2.DeclarationAdmission

namespace BoundaryV2.Profile.Source.Admission

def shape (program : Module) (id : SchemaId .source) : Option (Schema .source) :=
  program.schemas[id.value]?

def resourceDescriptor (program : Module) (id : SchemaId .source) : Option (Resource .source) := do
  let .internal (.abstractResource resource) ← shape program id | none
  program.resources[resource.value]?

def declarationContext (program : Module) : DeclarationAdmission.Context .source where
  schemas := program.schemas
  resources := program.resources
  effects := program.effects
  functionCount := program.functions.length
  regionCount := program.regionCount

abbrev subset := @DeclarationAdmission.subset
abbrev orderedRefs := @DeclarationAdmission.orderedRefs
abbrev evidenceRefs := @DeclarationAdmission.evidenceRefs

def computation (program : Module) := DeclarationAdmission.computation (declarationContext program)
def resumption (program : Module) := DeclarationAdmission.resumption (declarationContext program)
def capability (program : Module) := DeclarationAdmission.capability (declarationContext program)
def schemaExists (program : Module) := DeclarationAdmission.schemaExists (declarationContext program)
def resourceValid (program : Module) := DeclarationAdmission.resourceValid (declarationContext program)
def internalValid (program : Module) := DeclarationAdmission.internalValid (declarationContext program)
def effectValid (program : Module) := DeclarationAdmission.effectValid (declarationContext program)

def functionValid (source : Module) (function : Function) : Bool :=
  schemaExists source function.result && (variableTypes source function.parameters).isSome &&
  orderedRefs source.effects.length function.effects && orderedRefs source.regionCount function.regions

def directValueRows (source : Module) : List Bool :=
  source.values.foldl (fun earlier value => earlier ++ [match value.expression with
    | .variable _ | .literal _ => true
    | .lambda _ => false
    | .primitive opcode operands immediate failures =>
      PrimitiveAdmission.directOperation (⟨opcode, value.schema, immediate, failures⟩ : PrimitiveAdmission.Operation .source) &&
        operands.all (fun operand => earlier[operand.value]?.getD false)]) []

def directTermRows (source : Module) : List Bool :=
  let values := directValueRows source
  source.terms.foldl (fun earlier term => earlier ++ [match term with
    | .value value => values[value.value]?.getD false
    | .bind _ value next => earlier[value.value]?.getD false && earlier[next.value]?.getD false
    | _ => false]) []

def clauseValid (program : Module) (handler : Handler .source) (clause : Clause .source) : Bool := ((do
  let effect ← program.effects[clause.effect.value]?
  let function ← program.functions[clause.function.value]?
  let continuation ← resumption program clause.resumption
  let common := continuation.effect == clause.effect && continuation.mode == handler.mode &&
    continuation.answer == (if handler.mode == .deep then handler.answer else handler.input) &&
    continuation.handled == handler.clauses.map Clause.effect
  if clause.direct then
    let body ← function.body
    return common && handler.mode == .deep && continuation.use == .linear && effect.bodies.isEmpty &&
      function.result == effect.result && variableTypes program function.parameters == some (handler.state ++ [effect.payload]) &&
      function.effects.isEmpty && (directTermRows program)[body.value]?.getD false
  else
    return common && function.result == handler.answer &&
      variableTypes program function.parameters == some (handler.state ++ [effect.payload] ++ effect.bodies ++ [clause.resumption]) &&
      subset function.effects handler.effects) : Option Bool).getD false

def handlerValid (program : Module) (handler : Handler .source) : Bool :=
  schemaExists program handler.input && schemaExists program handler.answer &&
  orderedRefs program.effects.length handler.effects &&
  handler.state.all (fun id => schemaExists program id && Traits.check program.schemas .copy id) &&
  handler.forwardFunction.isNone &&
  (program.functions[handler.returnFunction.value]?).any (fun returns =>
    variableTypes program returns.parameters == some (handler.state ++ [handler.input]) && returns.result == handler.answer &&
      subset returns.effects handler.effects) &&
  decide (handler.clauses.map Clause.effect).Nodup && handler.clauses.all (clauseValid program handler)

def rootsValid (source : Module) : Bool :=
  schemaExists source source.failure && Traits.check source.schemas .external source.failure &&
  (source.functions[source.entry.value]?).any (fun entry =>
    Traits.check source.schemas .external entry.result &&
    (variableTypes source entry.parameters).any (fun types => types.all (Traits.check source.schemas .external)))

def constantsValid (source : Module) (meanings : List (Profile.Value .source)) : Bool :=
  source.constants.length == meanings.length &&
  (source.constants.zip meanings).all (fun (literal, meaning) =>
    Profile.Value.checkExternal source.schemas literal.schema literal.bytes meaning)

/-- All raw declarations are admitted independently of reachability or a target
image. The source formation/capture checker owns the lexical function interface. -/
def declarationsValid (source : Module) (meanings : List (Profile.Value .source)) : Bool :=
  SchemaAdmission.valid source.schemas && rootsValid source && constantsValid source meanings &&
  source.effects.all (effectValid source) && source.functions.all (functionValid source) &&
  source.schemas.all (fun type => match type with | .internal inner => internalValid source inner | _ => true) &&
  source.resources.all (resourceValid source) && source.handlers.all (handlerValid source)

theorem constants_exact (program : Module) (meanings : List (Profile.Value .source))
    (accepted : constantsValid program meanings = true) :
    program.constants.length = meanings.length ∧
    ∀ (index : Nat) (literal : Literal .source) (meaning : Profile.Value .source), program.constants[index]? = some literal → meanings[index]? = some meaning →
      meaning.schema = literal.schema ∧ Profile.Value.externalValid program.schemas meaning = true ∧
        Profile.Value.encode program.schemas meaning = literal.bytes := by
  simp only [constantsValid, Bool.and_eq_true, beq_iff_eq] at accepted
  refine ⟨accepted.1, ?_⟩
  intro index literal meaning literalFound meaningFound
  have member : (literal, meaning) ∈ program.constants.zip meanings :=
    List.mem_iff_getElem?.mpr ⟨index, List.getElem?_zip_eq_some.mpr ⟨literalFound, meaningFound⟩⟩
  exact Profile.Value.checkExternal_sound _ _ _ _ (List.all_eq_true.mp accepted.2 _ member)

end BoundaryV2.Profile.Source.Admission
