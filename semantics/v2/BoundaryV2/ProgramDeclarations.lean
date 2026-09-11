import BoundaryV2.InstructionAdmission
import BoundaryV2.DeclarationAdmission
import BoundaryV2.SchemaAdmission
import BoundaryV2.ValueCodec

namespace BoundaryV2.Profile.Target.Admission

def declarationContext (program : Program) : DeclarationAdmission.Context .target :=
  ⟨program.schemas, program.scopes.resources, program.effects, program.functions.length, program.scopes.regionCount⟩

abbrev subset := @DeclarationAdmission.subset
abbrev orderedRefs := @DeclarationAdmission.orderedRefs
abbrev evidenceRefs := @DeclarationAdmission.evidenceRefs

def computation (program : Program) := DeclarationAdmission.computation (declarationContext program)
def resumption (program : Program) := DeclarationAdmission.resumption (declarationContext program)
def capability (program : Program) := DeclarationAdmission.capability (declarationContext program)
def schemaExists (program : Program) := DeclarationAdmission.schemaExists (declarationContext program)
def resourceValid (program : Program) := DeclarationAdmission.resourceValid (declarationContext program)
def internalValid (program : Program) := DeclarationAdmission.internalValid (declarationContext program)
def effectValid (program : Program) := DeclarationAdmission.effectValid (declarationContext program)

def functionValid (program : Program) (index : Nat) (function : Function) : Bool :=
  schemaExists program function.result && function.parameters.all (schemaExists program) &&
  orderedRefs program.effects.length function.effects &&
  orderedRefs program.scopes.regionCount function.regions &&
  (program.blocks[function.entry.value]?).any (fun entry =>
    entry.function.value == index && entry.parameters == function.parameters)

def captureValid (program : Program) (capture : Capture) : Bool :=
  capture.fields.all (schemaExists program) && capture.ownedRegions.isEmpty && capture.borrowedRegions.isEmpty

def constructorValid (program : Program) (constructor : Constructor) : Bool := ((do
  let signature ← computation program constructor.schema
  let function ← program.functions[constructor.function.value]?
  let capture ← program.scopes.captures[constructor.capture.value]?
  return function.parameters == capture.fields ++ signature.parameters &&
    function.result == signature.result && capture.use == signature.use &&
    subset function.effects signature.effects && function.regions == signature.regions &&
    subset capture.fields signature.captureBound) : Option Bool).getD false

def directInstruction (instruction : Instruction) : Bool :=
  PrimitiveAdmission.directOperation (primitiveOperation instruction)

def directBlock (block : Block) : Bool :=
  (match block.terminator with | .returnValue _ => true | _ => false) &&
    block.instructions.all directInstruction

def clauseValid (program : Program) (handler : Handler .target) (clause : Clause .target) : Bool := ((do
  let effect ← program.effects[clause.effect.value]?
  let function ← program.functions[clause.function.value]?
  let continuation ← resumption program clause.resumption
  let common := continuation.effect == clause.effect && continuation.mode == handler.mode &&
    continuation.answer == (if handler.mode == .deep then handler.answer else handler.input) &&
    continuation.handled == handler.clauses.map Clause.effect
  if clause.direct then
    let entry ← program.blocks[function.entry.value]?
    return common && handler.mode == .deep && continuation.use == .linear && effect.bodies.isEmpty &&
      function.result == effect.result && function.parameters == handler.state ++ [effect.payload] &&
      function.effects.isEmpty && directBlock entry
  else
    return common && function.result == handler.answer &&
      function.parameters == handler.state ++ [effect.payload] ++ effect.bodies ++ [clause.resumption] &&
      subset function.effects handler.effects) : Option Bool).getD false

def handlerValid (program : Program) (handler : Handler .target) : Bool :=
  schemaExists program handler.input && schemaExists program handler.answer &&
  orderedRefs program.effects.length handler.effects &&
  handler.state.all (fun id => schemaExists program id && Traits.check program.schemas .copy id) &&
  handler.forwardFunction.isNone &&
  (program.functions[handler.returnFunction.value]?).any (fun returns =>
    returns.parameters == handler.state ++ [handler.input] && returns.result == handler.answer &&
      subset returns.effects handler.effects) &&
  decide (handler.clauses.map Clause.effect).Nodup && handler.clauses.all (clauseValid program handler)

def rootsValid (program : Program) : Bool :=
  program.roots.profile == 1 && schemaExists program program.roots.result &&
  schemaExists program program.roots.failure &&
  Traits.check program.schemas .external program.roots.result &&
  Traits.check program.schemas .external program.roots.failure &&
  (program.functions[program.roots.entry.value]?).any (fun entry =>
    entry.result == program.roots.result && entry.parameters.all (fun parameter =>
      schemaExists program parameter && Traits.check program.schemas .external parameter))

def constantsValid (program : Program) (meanings : List (Profile.Value .target)) : Bool :=
  program.constants.length == meanings.length &&
  (program.constants.zip meanings).all (fun (literal, meaning) =>
    Profile.Value.checkExternal program.schemas literal.schema literal.bytes meaning)

/-- Global declaration admission. Block control, use, region-flow and borrowed
value escape checks are separate obligations and are not implied by this predicate. -/
def declarationsValid (program : Program) (meanings : List (Profile.Value .target)) : Bool :=
  SchemaAdmission.valid program.schemas && rootsValid program && constantsValid program meanings &&
  program.effects.all (effectValid program) &&
  program.functions.zipIdx.all (fun (function, index) => functionValid program index function) &&
  program.schemas.all (fun type => match type with | .internal inner => internalValid program inner | _ => true) &&
  program.scopes.resources.all (resourceValid program) &&
  program.scopes.captures.all (captureValid program) &&
  program.constructors.all (constructorValid program) && program.handlers.all (handlerValid program)

theorem constants_exact (program : Program) (meanings : List (Profile.Value .target))
    (accepted : constantsValid program meanings = true) :
    program.constants.length = meanings.length ∧
    ∀ (index : Nat) (literal : Literal .target) (meaning : Profile.Value .target), program.constants[index]? = some literal → meanings[index]? = some meaning →
      meaning.schema = literal.schema ∧ Profile.Value.externalValid program.schemas meaning = true ∧
        Profile.Value.encode program.schemas meaning = literal.bytes := by
  simp only [constantsValid, Bool.and_eq_true, beq_iff_eq] at accepted
  refine ⟨accepted.1, ?_⟩
  intro index literal meaning literalFound meaningFound
  have member : (literal, meaning) ∈ program.constants.zip meanings :=
    List.mem_iff_getElem?.mpr ⟨index, List.getElem?_zip_eq_some.mpr ⟨literalFound, meaningFound⟩⟩
  exact Profile.Value.checkExternal_sound _ _ _ _ (List.all_eq_true.mp accepted.2 _ member)

theorem constructor_interface (program : Program) (constructor : Constructor)
    (accepted : constructorValid program constructor = true) :
    ∃ signature function capture,
      computation program constructor.schema = some signature ∧
      program.functions[constructor.function.value]? = some function ∧
      program.scopes.captures[constructor.capture.value]? = some capture ∧
      function.parameters = capture.fields ++ signature.parameters ∧
      function.result = signature.result ∧ capture.use = signature.use ∧
      subset function.effects signature.effects = true ∧ function.regions = signature.regions ∧
      subset capture.fields signature.captureBound = true := by
  unfold constructorValid at accepted
  cases signature : computation program constructor.schema with
  | none => simp [signature] at accepted
  | some signatureValue =>
    cases function : program.functions[constructor.function.value]? with
    | none => simp [signature, function] at accepted
    | some functionValue =>
      cases capture : program.scopes.captures[constructor.capture.value]? with
      | none => simp [signature, function, capture] at accepted
      | some captureValue =>
        simp [signature, function, capture, Bool.and_eq_true] at accepted
        exact ⟨signatureValue, functionValue, captureValue, rfl, rfl, rfl,
          accepted.1.1.1.1.1, accepted.1.1.1.1.2, accepted.1.1.1.2,
          accepted.1.1.2, accepted.1.2, accepted.2⟩

end BoundaryV2.Profile.Target.Admission
