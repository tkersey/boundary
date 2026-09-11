import BoundaryV2.GraphEdges
import BoundaryV2.ValueCodec

namespace BoundaryV2.Profile.Value

/-- The fixed-width part of a PST2 value. External aggregates use blobs even
when their canonical byte encoding is empty. -/
def scalarWidth : Schema space → Option Nat
  | .unit => some 0
  | .boolean | .i8 | .u8 => some 1
  | .i16 | .u16 => some 2
  | .i32 | .u32 | .enumeration _ => some 4
  | .i64 | .u64 => some 8
  | _ => none

end BoundaryV2.Profile.Value

namespace BoundaryV2.Profile.Graph.Admission

def node (state : State) (reference : NodeId) : Option Node := state.nodes[reference.value]?

def handler (program : Target.Program) (state : State) (reference : NodeId) : Option (Handler .target) := do
  let .handler definition _ _ _ ← node state reference | none
  program.handlers[definition.value]?

def internalValue (program : Target.Program) (state : State) (expected : SchemaId .target)
    (shape : Internal .target) (record : Node) : Bool :=
  match shape, record with
  | .capability effect, .attachment activation _ _ _ _ =>
    (handler program state activation).any (fun definition => definition.clauses.any (fun clause => clause.effect == effect))
  | .computation _, .computation constructor _ =>
    program.constructors[constructor.value]?.any (fun definition => definition.schema == expected)
  | .resumption signature, .multiTemplate token => signature.use == .multi && token.schema == expected
  | .resumption signature, .oneShot token => signature.use != .multi && token.schema == expected
  | .region descriptor, .region actual _ _ => descriptor == actual
  | .cell _ _, .cell actual _ _ | .suspensionPackage _, .package actual _
  | .abstractResource _, .resource actual _ | .borrowed _ _, .borrow actual _ _ => actual == expected
  | _, _ => false

def referencedValue (program : Target.Program) (state : State) (expected : SchemaId .target)
    (shape : Schema .target) (reference : NodeId) : Bool :=
  (node state reference).any fun record => match shape with
    | .internal internal => internalValue program state expected internal record
    | _ => !Traits.check program.schemas .external expected &&
      match record with | .aggregate actual _ _ => actual == expected | _ => false

/-- The scalar decoder checks both canonical payload bytes and the unused
high-byte padding. It never interprets a node index as an integer payload. -/
def scalarValue (schemas : List (Schema .target)) (expected : SchemaId .target)
    (shape : Schema .target) (bytes : Vector UInt8 8) : Bool :=
  (Profile.Value.scalarWidth shape).any fun width =>
    (Profile.Value.readScalar shape (bytes.toList.take width)).any fun (number, rest) =>
      rest.isEmpty && (bytes.toList.drop width).all (· == 0) &&
        Profile.Value.checkExternal schemas expected (bytes.toList.take width) (.scalar expected number)

def valueValid (program : Target.Program) (state : State) (item : Value) (expected : SchemaId .target) : Bool :=
  item.schema == expected && program.schemas[expected.value]?.any fun shape =>
    match item.body with
    | .scalar bytes => scalarValue program.schemas expected shape bytes
    | .blob reference => (Profile.Value.scalarWidth shape).isNone &&
      Traits.check program.schemas .external expected &&
      state.blobs[reference.value]?.any (fun blob => blob.schema == expected)
    | .reference reference => Traits.check program.schemas .copy expected &&
      referencedValue program state expected shape reference
    | .owned reference => !Traits.check program.schemas .copy expected &&
      referencedValue program state expected shape reference.node

def valuesValid (program : Target.Program) (state : State) (items : List Value)
    (expected : List (SchemaId .target)) : Bool :=
  items.length == expected.length && (items.zip expected).all (fun (item, type) => valueValid program state item type)

def blobsValid (program : Target.Program) (state : State) (meanings : List (Profile.Value .target)) : Bool :=
  state.blobs.length == meanings.length && (state.blobs.zip meanings).all
    (fun (blob, meaning) => Profile.Value.checkExternal program.schemas blob.schema blob.bytes meaning)

theorem value_schema_exact (program : Target.Program) (state : State) (item : Value)
    (expected : SchemaId .target) (accepted : valueValid program state item expected = true) : item.schema = expected := by
  simp only [valueValid, Bool.and_eq_true, beq_iff_eq] at accepted
  exact accepted.1

theorem scalar_padding_zero (schemas : List (Schema .target)) (expected : SchemaId .target)
    (shape : Schema .target) (bytes : Vector UInt8 8)
    (accepted : scalarValue schemas expected shape bytes = true) :
    ∃ width, Profile.Value.scalarWidth shape = some width ∧
      ∀ byte ∈ bytes.toList.drop width, byte = 0 := by
  obtain ⟨width, found, checked⟩ := (Option.any_eq_true _ _).mp accepted
  obtain ⟨⟨number, rest⟩, _, checked⟩ := (Option.any_eq_true _ _).mp checked
  simp only [Bool.and_eq_true] at checked
  exact ⟨width, found, by simpa using List.all_eq_true.mp checked.1.2⟩

theorem capability_uses_nominal_effect (program : Target.Program) (state : State)
    (expected : SchemaId .target) (effect : EffectId .target) (record : Node)
    (accepted : internalValue program state expected (.capability effect) record = true) :
    ∃ activation outer parent phase region definition clause,
      record = .attachment activation outer parent phase region ∧
      handler program state activation = some definition ∧ clause ∈ definition.clauses ∧ clause.effect = effect := by
  cases record <;> simp only [internalValue, Bool.false_eq_true] at accepted
  rename_i activation outer parent phase region
  obtain ⟨definition, found, accepted⟩ := (Option.any_eq_true _ _).mp accepted
  obtain ⟨clause, member, same⟩ := List.any_eq_true.mp accepted
  exact ⟨activation, outer, parent, phase, region, definition, clause, rfl, found, member, by simpa using same⟩

theorem blobs_exact (program : Target.Program) (state : State) (meanings : List (Profile.Value .target))
    (accepted : blobsValid program state meanings = true) :
    state.blobs.length = meanings.length ∧ ∀ pair ∈ state.blobs.zip meanings,
      pair.2.schema = pair.1.schema ∧ Profile.Value.externalValid program.schemas pair.2 = true ∧
        Profile.Value.encode program.schemas pair.2 = pair.1.bytes := by
  simp only [blobsValid, Bool.and_eq_true] at accepted
  obtain ⟨length, checked⟩ := accepted
  refine ⟨by simpa using length, fun pair member => ?_⟩
  exact Profile.Value.checkExternal_sound _ _ _ _ (List.all_eq_true.mp checked pair member)

end BoundaryV2.Profile.Graph.Admission
