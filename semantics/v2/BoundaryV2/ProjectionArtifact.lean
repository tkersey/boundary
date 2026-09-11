import Std

/- First production-artifact slice. This module covers scalar projections and
constants, not the full Boundary language. Its source serializer writes a
complete staged Module; its target serializer writes all nine BPI2 sections.
Certificates bind entire byte arrays and quantify over every admitted argument.
Neither compiler execution nor a supplied native Boolean is proof authority. -/
namespace BoundaryV2.ProjectionArtifact

abbrev Bytes := List UInt8
def limit : Nat := 2 ^ 64

inductive Selection where
  | parameter : Nat → Selection
  | literal : Nat → Selection
  deriving DecidableEq, Repr

structure Source where
  arity : Nat
  selection : Selection
  deriving DecidableEq, Repr

def Source.Valid (source : Source) : Prop :=
  source.arity < limit ∧ match source.selection with
    | .parameter index => index < source.arity
    | .literal value => value < limit

instance (source : Source) : Decidable source.Valid := by
  unfold Source.Valid
  cases source.selection <;> infer_instance

def AdmittedArguments (arity : Nat) (arguments : List Nat) : Prop :=
  arguments.length = arity ∧ ∀ value ∈ arguments, value < limit

instance (arity : Nat) (arguments : List Nat) : Decidable (AdmittedArguments arity arguments) :=
  inferInstanceAs (Decidable (arguments.length = arity ∧ ∀ value ∈ arguments, value < limit))

/-- Source variable lookup and source literal evaluation; no target code is
consulted in the definition of source meaning. -/
def sourceMeaning (source : Source) (arguments : List Nat) : Option Nat :=
  if AdmittedArguments source.arity arguments then
    match source.selection with
    | .parameter index => arguments[index]?
    | .literal value => some value
  else none

inductive Instruction where
  | constant : Nat → Instruction
  | move : Nat → Instruction
  deriving DecidableEq, Repr

structure Target where
  arity : Nat
  entryArguments : List Nat
  constants : List Nat
  instructions : List Instruction
  returned : Nat
  deriving DecidableEq, Repr

def orderedSlots (constantCount : Nat) : Nat → List Instruction → Prop
  | _, [] => True
  | available, .constant index :: rest => index < constantCount ∧ orderedSlots constantCount (available + 1) rest
  | available, .move index :: rest => index < available ∧ orderedSlots constantCount (available + 1) rest

def Target.Valid (target : Target) : Prop :=
  target.arity < limit ∧ (∀ index ∈ target.entryArguments, index < target.arity) ∧
  (∀ value ∈ target.constants, value < limit) ∧
  orderedSlots target.constants.length target.entryArguments.length target.instructions ∧
  target.returned < target.entryArguments.length + target.instructions.length

/-- Independent target slot execution: parameters precede appended instruction
results, and a return names a slot. Missing references reject. -/
def runInstructions (constants : List Nat) : List Instruction → List Nat → Option (List Nat)
  | [], slots => some slots
  | instruction :: rest, slots => do
    let value ← match instruction with
      | .constant index => constants[index]?
      | .move index => slots[index]?
    runInstructions constants rest (slots ++ [value])

def targetMeaning (target : Target) (arguments : List Nat) : Option Nat :=
  if AdmittedArguments target.arity arguments then do
    let parameters ← target.entryArguments.mapM fun index => arguments[index]?
    let slots ← runInstructions target.constants target.instructions parameters
    slots[target.returned]?
  else none

def targetFor (source : Source) : Target :=
  match source.selection with
  | .parameter index => ⟨source.arity, [index], [], [], 0⟩
  | .literal value => ⟨source.arity, [], [value], [.constant 0], 0⟩

theorem projection_target_is_well_formed (source : Source) (valid : source.Valid) :
    (targetFor source).Valid := by
  rcases source with ⟨arity, selection⟩
  cases selection <;> simpa [Source.Valid, Target.Valid, targetFor, orderedSlots] using valid

theorem all_input_correspondence (source : Source) (arguments : List Nat) :
    sourceMeaning source arguments = targetMeaning (targetFor source) arguments := by
  rcases source with ⟨arity, selection⟩
  cases selection with
  | parameter index =>
    cases lookup : arguments[index]? <;>
      simp [sourceMeaning, targetMeaning, targetFor, runInstructions, lookup]
  | literal value =>
    simp [sourceMeaning, targetMeaning, targetFor, runInstructions]

theorem admitted_inputs_nonempty (arity : Nat) :
    ∃ arguments, AdmittedArguments arity arguments := by
  refine ⟨List.replicate arity 0, ?_⟩
  simp [AdmittedArguments, limit]

def text (value : String) : Bytes := value.toUTF8.data.toList
def fixed (width value : Nat) : Bytes :=
  (List.range width).map fun index => UInt8.ofNat (value / 256 ^ index % 256)

def natural (value : Nat) : Bytes :=
  if value < 128 then [UInt8.ofNat value]
  else UInt8.ofNat (value % 128 + 128) :: natural (value / 128)
termination_by value
decreasing_by omega

def vector (values : List Bytes) : Bytes := natural values.length ++ values.flatten
def blob (value : Bytes) : Bytes := natural value.length ++ value
def ids (values : List Nat) : Bytes := vector (values.map natural)

def jsonArray (values : List String) : String := "[" ++ String.intercalate "," values ++ "]"
def jsonIds (values : List Nat) : String := jsonArray (values.map toString)
def literalJson (value : Nat) : String :=
  "{\"schema\":0,\"bytes\":" ++ jsonIds ((fixed 8 value).map UInt8.toNat) ++ "}"

/-- Exact complete JSON shape used by the staged source emitter, including its
final newline. Other source shapes require a different admitted proof rule. -/
def encodeSource (source : Source) : Bytes := text <|
  "{\"entry\":0,\"failure\":1,\"schemas\":[{\"u64\":{}},{\"unit\":{}}],\"constants\":" ++
  (match source.selection with | .parameter _ => "[]" | .literal value => jsonArray [literalJson value]) ++
  ",\"effects\":[],\"handlers\":[],\"region_count\":0,\"resources\":[],\"variables\":" ++
  jsonIds (List.replicate source.arity 0) ++ ",\"values\":[{\"schema\":0,\"expression\":" ++
  (match source.selection with
    | .parameter index => "{\"variable\":" ++ toString index ++ "}"
    | .literal _ => "{\"literal\":0}") ++
  "}],\"terms\":[{\"value\":0}],\"functions\":[{\"parameters\":" ++
  jsonIds (List.range source.arity) ++
  ",\"result\":0,\"effects\":[],\"regions\":[],\"body\":0}]}\n"

def encodeInstruction : Instruction → Bytes
  | .constant index => natural 0 ++ natural 0 ++ ids [] ++ natural index ++ vector []
  | .move slot => natural 1 ++ natural 0 ++ ids [slot] ++ natural 0 ++ vector []

def targetBlocks (target : Target) : List Bytes := Id.run do
  let code := natural 0 ++ ids (List.replicate target.entryArguments.length 0) ++
    vector (target.instructions.map encodeInstruction) ++ natural 0 ++ natural target.returned
  if target.entryArguments == List.range target.arity then return [code]
  let entry := natural 0 ++ ids (List.replicate target.arity 0) ++ vector [] ++
    natural 1 ++ natural 1 ++ vector (target.entryArguments.map fun index => natural 0 ++ natural index)
  return [entry, code]

/-- The real BPI2 catalog order and record fields. This slice has one function
and one block; unused catalog families still have their required encodings. -/
def sections (target : Target) : List Bytes := [
  idsRaw [1, 0, 0, 1],
  vector [natural 9, natural 0],
  vector (target.constants.map fun value => natural 0 ++ blob (fixed 8 value)),
  vector [],
  vector [natural 0 ++ ids (List.replicate target.arity 0) ++ natural 0 ++ ids [] ++ ids []],
  vector (targetBlocks target),
  vector [],
  vector [] ++ natural 0 ++ vector [],
  vector []]
where idsRaw (values : List Nat) := (values.map natural).flatten

def directory : List Bytes → Nat → Nat → Bytes
  | [], _, _ => []
  | bytes :: rest, index, offset =>
    natural index ++ natural offset ++ natural bytes.length ++
      directory rest (index + 1) (offset + bytes.length)

def body (target : Target) : Bytes :=
  let contents := sections target
  natural 9 ++ directory contents 1 0 ++ contents.flatten

def encodeImage (target : Target) : Bytes :=
  let contents := body target
  text "ABL_BPI2" ++ fixed 2 2 ++ fixed 2 0 ++ fixed 8 contents.length ++ contents

/-- This is deliberately a projection-artifact claim, not CertifiedProgram for
the complete Boundary profile. The all-input relation is derived below. -/
def Certified (sourceBytes imageBytes : Bytes) : Prop :=
  ∃ source : Source, source.Valid ∧ (body (targetFor source)).length < limit ∧
    encodeSource source = sourceBytes ∧ encodeImage (targetFor source) = imageBytes ∧
    (targetFor source).Valid ∧
    ∀ arguments, sourceMeaning source arguments = targetMeaning (targetFor source) arguments

def check (sourceBytes imageBytes : Bytes) (source : Source) : Bool :=
  decide source.Valid && decide ((body (targetFor source)).length < limit) &&
    decide (encodeSource source = sourceBytes) && decide (encodeImage (targetFor source) = imageBytes)

theorem check_sound (sourceBytes imageBytes : Bytes) (source : Source)
    (accepted : check sourceBytes imageBytes source = true) : Certified sourceBytes imageBytes := by
  simp only [check, Bool.and_eq_true, decide_eq_true_eq] at accepted
  exact ⟨source, accepted.1.1.1, accepted.1.1.2, accepted.1.2, accepted.2,
    projection_target_is_well_formed source accepted.1.1.1, all_input_correspondence source⟩

end BoundaryV2.ProjectionArtifact
