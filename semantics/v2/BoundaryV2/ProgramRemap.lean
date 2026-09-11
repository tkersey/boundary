import BoundaryV2.ProgramCanonical

namespace BoundaryV2.Profile.Target.Canonical

abbrev Renaming := Kind → Nat → Nat

def rename (mapping : Renaming) (kind : Kind) (reference : Ref .target domain) : Ref .target domain :=
  ⟨mapping kind reference.value⟩

def renameList (mapping : Renaming) (kind : Kind) (values : List (Ref .target domain)) : List (Ref .target domain) :=
  values.map (rename mapping kind)

def renameSet (mapping : Renaming) (kind : Kind) (values : List (Ref .target domain)) : List (Ref .target domain) :=
  (renameList mapping kind values).mergeSort (fun a b => a.value ≤ b.value)

def remapInternal (mapping : Renaming) : Internal .target → Internal .target
  | .computation value => .computation { value with
      parameters := renameList mapping .schema value.parameters
      result := rename mapping .schema value.result
      effects := renameSet mapping .effect value.effects
      captureBound := renameList mapping .schema value.captureBound
      regions := renameSet mapping .region value.regions }
  | .capability effect => .capability (rename mapping .effect effect)
  | .cell type region => .cell (rename mapping .schema type) (rename mapping .region region)
  | .region region => .region (rename mapping .region region)
  | .resumption value => .resumption { value with
      effect := rename mapping .effect value.effect
      input := rename mapping .schema value.input
      answer := rename mapping .schema value.answer
      effects := renameSet mapping .effect value.effects
      captureBound := renameList mapping .schema value.captureBound
      handled := renameList mapping .effect value.handled
      escaping := renameSet mapping .effect value.escaping
      ownedRegions := renameSet mapping .region value.ownedRegions }
  | .suspensionPackage type => .suspensionPackage (rename mapping .schema type)
  | .abstractResource resource => .abstractResource (rename mapping .resource resource)
  | .borrowed type region => .borrowed (rename mapping .schema type) (rename mapping .region region)

def remapSchema (mapping : Renaming) : Schema .target → Schema .target
  | .product fields => .product (renameList mapping .schema fields)
  | .sum fields => .sum (renameList mapping .schema fields)
  | .seq type => .seq (rename mapping .schema type)
  | .vector type maximum => .vector (rename mapping .schema type) maximum
  | .array type length => .array (rename mapping .schema type) length
  | .internal value => .internal (remapInternal mapping value)
  | value => value

def remapLiteral (mapping : Renaming) (value : Literal .target) : Literal .target :=
  { value with schema := rename mapping .schema value.schema }

def remapEffect (mapping : Renaming) (value : Effect .target) : Effect .target :=
  { value with payload := rename mapping .schema value.payload
               result := rename mapping .schema value.result
               useSiteEffects := renameList mapping .effect value.useSiteEffects
               bodies := renameList mapping .schema value.bodies }

def remapFunction (mapping : Renaming) (value : Function) : Function :=
  { value with entry := rename mapping .block value.entry
               parameters := renameList mapping .schema value.parameters
               result := rename mapping .schema value.result
               effects := renameSet mapping .effect value.effects
               regions := renameSet mapping .region value.regions }

def remapInstruction (mapping : Renaming) (value : Instruction) : Instruction :=
  { value with resultType := rename mapping .schema value.resultType
               immediate := match value.opcode with
                 | .constant => mapping .constant value.immediate
                 | .computation => mapping .constructor value.immediate
                 | _ => value.immediate
               failures := value.failures.map (fun failure =>
                 { failure with value := rename mapping .constant failure.value }) }

def remapEdge (mapping : Renaming) (value : Edge) : Edge :=
  { value with block := rename mapping .block value.block }

def remapPerform (mapping : Renaming) (value : Perform) : Perform :=
  { value with effect := rename mapping .effect value.effect, next := remapEdge mapping value.next }

def remapTerminator (mapping : Renaming) : Terminator → Terminator
  | .returnValue value => .returnValue value
  | .fail value => .fail value
  | .jump next => .jump (remapEdge mapping next)
  | .yieldValue next => .yieldValue (remapEdge mapping next)
  | .branch value yes no => .branch value (remapEdge mapping yes) (remapEdge mapping no)
  | .switchVariant value cases => .switchVariant value (cases.map (remapEdge mapping))
  | .unpackProduct value block arguments => .unpackProduct value (rename mapping .block block) arguments
  | .call function arguments next => .call (rename mapping .function function) arguments (remapEdge mapping next)
  | .perform operation => .perform (remapPerform mapping operation)
  | .forward operation => .forward (remapPerform mapping operation)
  | .apply closure arguments next => .apply closure arguments (remapEdge mapping next)
  | .handle handler body arguments state next =>
    .handle (rename mapping .handler handler) body arguments state (remapEdge mapping next)
  | .resumeValue token argument next => .resumeValue token argument (remapEdge mapping next)
  | .resumeWith token argument handler state next =>
    .resumeWith token argument (rename mapping .handler handler) state (remapEdge mapping next)
  | .resumeComputation token body next => .resumeComputation token body (remapEdge mapping next)
  | .dispose value next => .dispose value (remapEdge mapping next)
  | .protect body cleanup arguments resource region next =>
    .protect body cleanup arguments resource (region.map (rename mapping .region)) (remapEdge mapping next)
  | .withRegion region body arguments next =>
    .withRegion (rename mapping .region region) body arguments (remapEdge mapping next)

def remapBlock (mapping : Renaming) (value : Block) : Block :=
  { function := rename mapping .function value.function
    parameters := renameList mapping .schema value.parameters
    instructions := value.instructions.map (remapInstruction mapping)
    terminator := remapTerminator mapping value.terminator }

def remapClause (mapping : Renaming) (value : Clause .target) : Clause .target :=
  { value with effect := rename mapping .effect value.effect
               function := rename mapping .function value.function
               resumption := rename mapping .schema value.resumption }

def remapHandler (mapping : Renaming) (value : Handler .target) : Handler .target :=
  { value with input := rename mapping .schema value.input
               answer := rename mapping .schema value.answer
               returnFunction := rename mapping .function value.returnFunction
               clauses := value.clauses.map (remapClause mapping)
               forwardFunction := value.forwardFunction.map (rename mapping .function)
               state := renameList mapping .schema value.state
               effects := renameSet mapping .effect value.effects }

def remapCapture (mapping : Renaming) (value : Capture) : Capture :=
  { value with fields := renameList mapping .schema value.fields
               ownedRegions := renameSet mapping .region value.ownedRegions
               borrowedRegions := renameSet mapping .region value.borrowedRegions }

def remapResource (mapping : Renaming) (value : Resource .target) : Resource .target :=
  { representation := rename mapping .schema value.representation
    introducers := renameSet mapping .function value.introducers
    eliminators := renameSet mapping .function value.eliminators }

def remapConstructor (mapping : Renaming) (value : Constructor) : Constructor :=
  { function := rename mapping .function value.function
    capture := rename mapping .capture value.capture
    schema := rename mapping .schema value.schema }

def remapRoots (mapping : Renaming) (value : Roots) : Roots :=
  { value with entry := rename mapping .function value.entry
               result := rename mapping .schema value.result
               failure := rename mapping .schema value.failure }

/-- Reindex every retained record. The order tables decide catalog placement;
the renaming decides embedded references. Nominal catalogs are never interned. -/
def materialize (program : Program) (order : Kind → List Nat) (mapping : Renaming) : Option Program := do
  let catalog := fun {α : Type} (kind : Kind) (values : List α) (rewrite : α → α) =>
    (order kind).mapM (fun index => (values[index]?).map rewrite)
  return {
    roots := remapRoots mapping program.roots
    schemas := ← catalog .schema program.schemas (remapSchema mapping)
    constants := ← catalog .constant program.constants (remapLiteral mapping)
    effects := ← catalog .effect program.effects (remapEffect mapping)
    functions := ← catalog .function program.functions (remapFunction mapping)
    blocks := ← catalog .block program.blocks (remapBlock mapping)
    handlers := ← catalog .handler program.handlers (remapHandler mapping)
    scopes := {
      captures := ← catalog .capture program.scopes.captures (remapCapture mapping)
      regionCount := (order .region).length
      resources := ← catalog .resource program.scopes.resources (remapResource mapping) }
    constructors := ← catalog .constructor program.constructors (remapConstructor mapping) }

def catalogMap (program : Program) (order : List Reference) : Renaming := fun kind index =>
  if kind == .constant then
    ((orderOf order .constant).findIdx? (fun old => program.constants[old]? == program.constants[index]?)).getD
      (orderOf order .constant).length
  else (orderOf order kind).idxOf index

/-- Structural normalization only. The public program operation checks full
admission before pruning and rechecks the reindexed result. -/
def normalizeRecords (program : Program) : Option Program := do
  let order ← discover program
  materialize program (orderOf order) (catalogMap program order)

theorem remap_preserves_literal_bytes (mapping : Renaming) (literal : Literal .target) :
    (remapLiteral mapping literal).bytes = literal.bytes := rfl

theorem remap_preserves_effect_identity (mapping : Renaming) (effect : Effect .target) :
    (remapEffect mapping effect).identity = effect.identity := rfl

theorem remap_preserves_operand_order (mapping : Renaming) (instruction : Instruction) :
    (remapInstruction mapping instruction).operands = instruction.operands := rfl

theorem remap_preserves_edge_arguments (mapping : Renaming) (edge : Edge) :
    (remapEdge mapping edge).arguments = edge.arguments := rfl

theorem remap_preserves_capture_order (mapping : Renaming) (capture : Capture) :
    (remapCapture mapping capture).fields = capture.fields.map (rename mapping .schema) := rfl

theorem remap_preserves_handled_order (mapping : Renaming) (signature : ResumptionType .target) :
    remapInternal mapping (.resumption signature) = .resumption { signature with
      effect := rename mapping .effect signature.effect, input := rename mapping .schema signature.input
      answer := rename mapping .schema signature.answer, effects := renameSet mapping .effect signature.effects
      captureBound := renameList mapping .schema signature.captureBound
      handled := signature.handled.map (rename mapping .effect)
      escaping := renameSet mapping .effect signature.escaping
      ownedRegions := renameSet mapping .region signature.ownedRegions } := rfl

end BoundaryV2.Profile.Target.Canonical
