import BoundaryV2.Profile

namespace BoundaryV2.Profile.Target.Canonical

inductive Kind where
  | schema | constant | effect | function | block | handler | capture | region | resource | constructor
  deriving DecidableEq, Repr

def kinds : List Kind := [.schema, .constant, .effect, .function, .block, .handler,
  .capture, .region, .resource, .constructor]

structure Reference where
  kind : Kind
  index : Nat
  deriving DecidableEq, Repr

def references (kind : Kind) (ids : List (Ref .target domain)) : List Reference :=
  ids.map (fun id => ⟨kind, id.value⟩)

def count (program : Program) : Kind → Nat
  | .schema => program.schemas.length
  | .constant => program.constants.length
  | .effect => program.effects.length
  | .function => program.functions.length
  | .block => program.blocks.length
  | .handler => program.handlers.length
  | .capture => program.scopes.captures.length
  | .region => program.scopes.regionCount
  | .resource => program.scopes.resources.length
  | .constructor => program.constructors.length

/-- Non-strict comparison makes mergeSort preserve original order for equal
textual identities. Equal text never interns two nominal effect declarations. -/
def bytesLE : Bytes → Bytes → Bool
  | [], _ => true
  | _ :: _, [] => false
  | a :: as, b :: bs => if a == b then bytesLE as bs else a.toNat < b.toNat

def effectRow (program : Program) (ids : List (EffectId .target)) : List Reference :=
  references .effect (ids.mergeSort (fun a b =>
    bytesLE ((program.effects[a.value]?).map Effect.identity |>.getD [])
      ((program.effects[b.value]?).map Effect.identity |>.getD [])))

def internalReferences (program : Program) : Internal .target → List Reference
  | .computation value => references .schema value.parameters ++ [⟨.schema, value.result.value⟩] ++
    effectRow program value.effects ++ references .schema value.captureBound ++ references .region value.regions
  | .capability effect => [⟨.effect, effect.value⟩]
  | .cell type region => [⟨.schema, type.value⟩, ⟨.region, region.value⟩]
  | .region region => [⟨.region, region.value⟩]
  | .resumption value => [⟨.effect, value.effect.value⟩, ⟨.schema, value.input.value⟩, ⟨.schema, value.answer.value⟩] ++
    effectRow program value.effects ++ references .schema value.captureBound ++ references .effect value.handled ++
    effectRow program value.escaping ++ references .region value.ownedRegions
  | .suspensionPackage type => [⟨.schema, type.value⟩]
  | .abstractResource resource => [⟨.resource, resource.value⟩]
  | .borrowed type region => [⟨.schema, type.value⟩, ⟨.region, region.value⟩]

def schemaReferences (program : Program) : Schema .target → List Reference
  | .product fields | .sum fields => references .schema fields
  | .seq type | .vector type _ | .array type _ => [⟨.schema, type.value⟩]
  | .internal value => internalReferences program value
  | .unit | .boolean | .i8 | .i16 | .i32 | .i64 | .u8 | .u16 | .u32 | .u64
  | .bytes | .text | .boundedBytes _ | .boundedText _ | .enumeration _ => []

def literalReferences (value : Literal .target) : List Reference := [⟨.schema, value.schema.value⟩]

def effectReferences (value : Effect .target) : List Reference :=
  [⟨.schema, value.payload.value⟩, ⟨.schema, value.result.value⟩] ++
    references .effect value.useSiteEffects ++ references .schema value.bodies

def functionReferences (program : Program) (value : Function) : List Reference :=
  [⟨.block, value.entry.value⟩] ++ references .schema value.parameters ++ [⟨.schema, value.result.value⟩] ++
    effectRow program value.effects ++ references .region value.regions

def instructionReferences (value : Instruction) : List Reference :=
  [⟨.schema, value.resultType.value⟩] ++
    (match value.opcode with
    | .constant => [⟨.constant, value.immediate⟩]
    | .computation => [⟨.constructor, value.immediate⟩]
    | _ => []) ++ value.failures.map (fun failure => ⟨.constant, failure.value.value⟩)

def edgeReferences (value : Edge) : List Reference := [⟨.block, value.block.value⟩]
def performReferences (value : Perform) : List Reference :=
  [⟨.effect, value.effect.value⟩] ++ edgeReferences value.next

/-- Operands and result holes remain block-local positions. Only the catalog
references below participate in program numbering. -/
def terminatorReferences : Terminator → List Reference
  | .returnValue _ | .fail _ => []
  | .jump next | .yieldValue next | .apply _ _ next | .resumeValue _ _ next
  | .resumeComputation _ _ next | .dispose _ next => edgeReferences next
  | .branch _ yes no => edgeReferences yes ++ edgeReferences no
  | .switchVariant _ cases => cases.flatMap edgeReferences
  | .unpackProduct _ block _ => [⟨.block, block.value⟩]
  | .call function _ next => [⟨.function, function.value⟩] ++ edgeReferences next
  | .perform operation | .forward operation => performReferences operation
  | .handle handler _ _ _ next | .resumeWith _ _ handler _ next =>
    [⟨.handler, handler.value⟩] ++ edgeReferences next
  | .protect _ _ _ _ region next => references .region region.toList ++ edgeReferences next
  | .withRegion region _ _ next => [⟨.region, region.value⟩] ++ edgeReferences next

def blockReferences (value : Block) : List Reference :=
  [⟨.function, value.function.value⟩] ++ references .schema value.parameters ++
    value.instructions.flatMap instructionReferences ++ terminatorReferences value.terminator

def clauseReferences (value : Clause .target) : List Reference :=
  [⟨.effect, value.effect.value⟩, ⟨.function, value.function.value⟩, ⟨.schema, value.resumption.value⟩]

def handlerReferences (program : Program) (value : Handler .target) : List Reference :=
  [⟨.schema, value.input.value⟩, ⟨.schema, value.answer.value⟩, ⟨.function, value.returnFunction.value⟩] ++
    value.clauses.flatMap clauseReferences ++ references .function value.forwardFunction.toList ++
    references .schema value.state ++ effectRow program value.effects

def captureReferences (value : Capture) : List Reference :=
  references .schema value.fields ++ references .region value.ownedRegions ++ references .region value.borrowedRegions

def resourceReferences (value : Resource .target) : List Reference :=
  [⟨.schema, value.representation.value⟩] ++ references .function value.introducers ++ references .function value.eliminators

def constructorReferences (value : Constructor) : List Reference :=
  [⟨.function, value.function.value⟩, ⟨.capture, value.capture.value⟩, ⟨.schema, value.schema.value⟩]

def rootReferences (value : Roots) : List Reference :=
  [⟨.function, value.entry.value⟩, ⟨.schema, value.result.value⟩, ⟨.schema, value.failure.value⟩]

def nodeReferences (program : Program) (reference : Reference) : Option (List Reference) :=
  match reference.kind with
  | .schema => (program.schemas[reference.index]?).map (schemaReferences program)
  | .constant => (program.constants[reference.index]?).map literalReferences
  | .effect => (program.effects[reference.index]?).map effectReferences
  | .function => (program.functions[reference.index]?).map (functionReferences program)
  | .block => (program.blocks[reference.index]?).map blockReferences
  | .handler => (program.handlers[reference.index]?).map (handlerReferences program)
  | .capture => (program.scopes.captures[reference.index]?).map captureReferences
  | .region => if reference.index < program.scopes.regionCount then some [] else none
  | .resource => (program.scopes.resources[reference.index]?).map resourceReferences
  | .constructor => (program.constructors[reference.index]?).map constructorReferences

theorem bytesLE_reflexive (bytes : Bytes) : bytesLE bytes bytes = true := by
  induction bytes with
  | nil => rfl
  | cons byte rest ih => simpa [bytesLE] using ih

theorem operand_positions_not_catalog_references (instruction : Instruction) (operands : List Slot) :
    instructionReferences { instruction with operands := operands } = instructionReferences instruction := rfl

theorem result_holes_not_catalog_references (edge : Edge) (arguments : List Argument) :
    edgeReferences { edge with arguments := arguments } = edgeReferences edge := rfl

end BoundaryV2.Profile.Target.Canonical
