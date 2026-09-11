import BoundaryV2.GraphEdges
import BoundaryV2.ValueCodec
import BoundaryV2.Primitives
import BoundaryV2.GraphValueTypes

namespace BoundaryV2.Profile.Target.Machine

abbrev SemanticValue := Profile.Value .target

inductive Invalid where
  | reference | type | operands | custody | scope | inactive | witness
  deriving DecidableEq, Repr

def require (condition : Bool) (reason : Invalid) : Except Invalid Unit :=
  if condition then .ok () else .error reason

def fromOption (value : Option α) (reason : Invalid) : Except Invalid α :=
  match value with | some value => .ok value | none => .error reason

/-- Byte interpretations are checked data. Runtime certificates can supply the
finite value tree, but its complete bytes and external admission are proved. -/
structure StoredBlob (schemas : List (Schema .target)) where
  raw : Graph.Blob
  meaning : SemanticValue
  checked : Profile.Value.checkExternal schemas raw.schema raw.bytes meaning = true

namespace StoredBlob

def admit (schemas : List (Schema .target)) (raw : Graph.Blob) (meaning : SemanticValue) :
    Option (StoredBlob schemas) :=
  if checked : Profile.Value.checkExternal schemas raw.schema raw.bytes meaning = true then
    some ⟨raw, meaning, checked⟩ else none

theorem meaning_unique (left right : StoredBlob schemas) (same : left.raw = right.raw) :
    left.meaning = right.meaning := by
  apply Profile.Value.checked_candidates_unique schemas left.raw.schema left.raw.bytes
    left.meaning right.meaning left.checked
  simpa [same] using right.checked

theorem exact (blob : StoredBlob schemas) :
    blob.meaning.schema = blob.raw.schema ∧ Profile.Value.externalValid schemas blob.meaning = true ∧
      Profile.Value.encode schemas blob.meaning = blob.raw.bytes :=
  Profile.Value.checkExternal_sound _ _ _ _ blob.checked
end StoredBlob

/-- Stable logical node handles are independent of source variables and source
frames. Raw graph records retain every PST2 field; collection is separate. -/
structure Store (schemas : List (Schema .target)) where
  nodes : List Graph.Node := []
  blobs : List (StoredBlob schemas) := []

namespace Store

def lookup (store : Store schemas) (reference : NodeId) : Option Graph.Node := store.nodes[reference.value]?

def add (store : Store schemas) (node : Graph.Node) : Store schemas × NodeId :=
  ({ store with nodes := store.nodes ++ [node] }, ⟨store.nodes.length⟩)

def replace (store : Store schemas) (reference : NodeId) (node : Graph.Node) : Option (Store schemas) :=
  if reference.value < store.nodes.length then some { store with nodes := store.nodes.set reference.value node }
  else none

def raw (store : Store schemas) (identity : Digest) (status : Graph.Status) (roots : Graph.Roots) : Graph.State :=
  ⟨identity, status, roots, store.nodes, store.blobs.map StoredBlob.raw⟩

def admitBlobs (schemas : List (Schema .target)) : List Graph.Blob → List SemanticValue → Option (List (StoredBlob schemas))
  | [], [] => some []
  | raw :: raws, value :: values => do
    let head ← StoredBlob.admit schemas raw value
    let tail ← admitBlobs schemas raws values
    return head :: tail
  | _, _ => none

def importGraph (schemas : List (Schema .target)) (graph : Graph.State) (meanings : List SemanticValue) :
    Option (Store schemas) := do
  let blobs ← admitBlobs schemas graph.blobs meanings
  return ⟨graph.nodes, blobs⟩

theorem add_fresh (store : Store schemas) (node : Graph.Node) :
    (add store node).2.value = store.nodes.length ∧
    (add store node).1.lookup (add store node).2 = some node := by simp [add, lookup]

theorem add_preserves_old (store : Store schemas) (node : Graph.Node) (reference : NodeId)
    (inside : reference.value < store.nodes.length) :
    (add store node).1.lookup reference = store.lookup reference := by
  simp [add, lookup, List.getElem?_append_left inside]

theorem admitted_blob_inventory (schemas : List (Schema .target)) (raws : List Graph.Blob)
    (meanings : List SemanticValue) (blobs : List (StoredBlob schemas))
    (accepted : admitBlobs schemas raws meanings = some blobs) :
    blobs.map StoredBlob.raw = raws ∧ blobs.map StoredBlob.meaning = meanings := by
  induction raws generalizing meanings blobs with
  | nil => cases meanings <;> simp_all [admitBlobs]
  | cons raw raws ih =>
    cases meanings with
    | nil => simp [admitBlobs] at accepted
    | cons meaning meanings =>
      cases head : StoredBlob.admit schemas raw meaning with
      | none => simp [admitBlobs, head] at accepted
      | some checked =>
        cases tail : admitBlobs schemas raws meanings with
        | none => simp [admitBlobs, head, tail] at accepted
        | some rest =>
          have prior := ih meanings rest tail
          have fields : checked.raw = raw ∧ checked.meaning = meaning := by
            unfold StoredBlob.admit at head
            split at head
            · cases head; exact ⟨rfl, rfl⟩
            · cases head
          simp [admitBlobs, head, tail] at accepted
          cases accepted
          simp [prior.1, prior.2, fields.1, fields.2]

theorem import_preserves_exact_graph (schemas : List (Schema .target)) (graph : Graph.State)
    (meanings : List SemanticValue) (store : Store schemas)
    (accepted : importGraph schemas graph meanings = some store) :
    store.raw graph.programIdentity graph.status graph.roots = graph := by
  cases admitted : admitBlobs schemas graph.blobs meanings with
  | none => simp [importGraph, admitted] at accepted
  | some blobs =>
    have inventory := (admitted_blob_inventory schemas graph.blobs meanings blobs admitted).1
    simp [importGraph, admitted] at accepted
    cases accepted
    cases graph
    simp_all [raw]
end Store

/-- External scalars occupy an eight-byte graph field with zero high padding.
Aggregates use their complete canonical blob, even when their encoding is empty. -/
abbrev scalarWidth := Profile.Value.scalarWidth (space := .target)

def reference (schemas : List (Schema .target)) (schema : SchemaId .target) (node : NodeId) : Graph.Value :=
  ⟨schema, if Traits.check schemas .copy schema then .reference node else .owned ⟨node⟩⟩

/-- Canonical external allocation performs no evaluation. Interning equality
is over the complete schema and byte string, never a digest assumption. -/
def storeExternal (store : Store schemas) (value : SemanticValue) : Except Invalid (Store schemas × Graph.Value) := do
  if valid : Profile.Value.externalValid schemas value = true then
    let bytes := Profile.Value.encode schemas value
    let shape ← fromOption schemas[value.schema.value]? .type
    match scalarWidth shape with
    | some width =>
      require (bytes.length == width && width ≤ 8) .type
      let padded := (bytes ++ List.replicate 8 0).take 8
      if size : padded.length = 8 then
        return (store, ⟨value.schema, .scalar ⟨padded.toArray, by simpa using size⟩⟩)
      else throw .type
    | none =>
      let raw : Graph.Blob := ⟨value.schema, bytes⟩
      match store.blobs.findIdx? (fun blob => blob.raw == raw) with
      | some index => return (store, ⟨value.schema, .blob ⟨index⟩⟩)
      | none =>
        let blob : StoredBlob schemas := ⟨raw, value, by
          simp [Profile.Value.checkExternal, raw, bytes, valid]⟩
        return ({ store with blobs := store.blobs ++ [blob] }, ⟨value.schema, .blob ⟨store.blobs.length⟩⟩)
  else throw .type

/-- Primitive aggregate results are materialized as canonical external blobs
or as graph nodes containing the actual ordered internal fields. -/
def storeValue (store : Store schemas) (value : SemanticValue) : Except Invalid (Store schemas × Graph.Value) := do
  if Profile.Value.externalValid schemas value then storeExternal store value
  else
    let shape ← fromOption schemas[value.schema.value]? .type
    require (!Traits.check schemas .external value.schema) .type
    match value with
    | .reference type node token =>
      let .internal _ := shape | throw .type
      require token.isNone .custody
      let _ ← fromOption (store.lookup node) .reference
      return (store, reference schemas type node)
    | .product type fields | .sequence type fields =>
      match value, shape with
      | .product _ _, .product types => require (fields.map Profile.Value.schema == types) .type
      | .sequence _ _, _ =>
        require (Profile.Value.sequenceLengthValid shape fields.length && fields.all
          (fun field => Profile.Value.sequenceElement shape == some field.schema)) .type
      | _, _ => throw .type
      let (store, fields) ← fields.attach.foldlM (fun (store, prior) field => do
        let (store, field) ← storeValue store field.val
        pure (store, prior ++ [field])) (store, [])
      let (store, node) := store.add (.aggregate type 0 fields)
      return (store, reference schemas type node)
    | .variant type tag payload =>
      let .sum cases := shape | throw .type
      require (tag < wordLimit && cases[tag]? == some payload.schema) .type
      let (store, field) ← storeValue store payload
      let (store, node) := store.add (.aggregate type tag [field])
      return (store, reference schemas type node)
    | .scalar .. | .blob .. => throw .type
termination_by sizeOf value
decreasing_by
  all_goals simp_wf
  all_goals first | omega | exact Nat.lt_trans (List.sizeOf_lt_of_mem field.property) (by omega)

/-- Expansion follows only immutable aggregate fields. Internal handles remain
handles; they do not recursively expose cells, closures, or captured control.
The finite graph bounds this data walk, independently of program recursion. -/
def expandValue (store : Store schemas) : Nat → Graph.Value → Except Invalid SemanticValue
  | 0, _ => .error .reference
  | depth + 1, value => do
    let shape ← fromOption schemas[value.schema.value]? .type
    match value.body with
    | .scalar bytes =>
      let width ← fromOption (scalarWidth shape) .type
      let (number, rest) ← fromOption (Profile.Value.readScalar shape (bytes.toList.take width)) .type
      require (rest.isEmpty && (bytes.toList.drop width).all (· == 0)) .type
      let result : SemanticValue := .scalar value.schema number
      require (Profile.Value.checkExternal schemas value.schema (bytes.toList.take width) result) .type
      return result
    | .blob reference =>
      let blob ← fromOption store.blobs[reference.value]? .reference
      require (blob.raw.schema == value.schema && (scalarWidth shape).isNone) .type
      return blob.meaning
    | .reference node | .owned ⟨node⟩ =>
      require (!Traits.check schemas .external value.schema) .type
      require ((match value.body with | .reference _ => true | _ => false) == Traits.check schemas .copy value.schema) .custody
      let record ← fromOption (store.lookup node) .reference
      match shape, record with
      | .product types, .aggregate type tag fields =>
        require (type == value.schema && tag == 0 && fields.map Graph.Value.schema == types) .type
        return .product value.schema (← fields.mapM (expandValue store depth))
      | .sum types, .aggregate type tag fields =>
        require (type == value.schema && tag < wordLimit) .type
        let [field] := fields | throw .type
        require (types[tag]? == some field.schema) .type
        return .variant value.schema tag (← expandValue store depth field)
      | .seq element, .aggregate type tag fields | .vector element _, .aggregate type tag fields
      | .array element _, .aggregate type tag fields =>
        require (type == value.schema && tag == 0 && Profile.Value.sequenceLengthValid shape fields.length &&
          fields.all (fun field => field.schema == element)) .type
        return .sequence value.schema (← fields.mapM (expandValue store depth))
      | .internal _, _ => return .reference value.schema node none
      | _, _ => throw .type

def loadValue (store : Store schemas) (value : Graph.Value) : Except Invalid SemanticValue :=
  expandValue store (store.nodes.length + 1) value

end BoundaryV2.Profile.Target.Machine
