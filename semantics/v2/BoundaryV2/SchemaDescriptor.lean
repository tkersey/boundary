import BoundaryV2.SchemaBisimulation

namespace BoundaryV2.Profile.SchemaDescriptor

structure Descriptor where
  root : SchemaId .target := 0
  types : List (Schema .target)
  deriving DecidableEq, Repr

def rawCodec : Wire.Codec Descriptor :=
  ((Wire.NonemptyCodec.reference .target .schema).toCodec.pair
    (Codecs.schema .target).list.toCodec).iso
    (fun (root, types) => ⟨root, types⟩) (fun descriptor => (descriptor.root, descriptor.types))
    (by intro descriptor; cases descriptor; rfl) (by intro pair; cases pair; rfl)

def representative (count : Nat) (pairs : List (SchemaEquivalence.Pair .target))
    (id : SchemaId .target) : SchemaId .target :=
  ⟨((List.range count).find? (fun index => pairs.contains (id, ⟨index⟩))).getD count⟩

def classes (types : List (Schema .target)) : SchemaId .target → SchemaId .target :=
  representative types.length (SchemaEquivalence.bisimilar types)

/-- Traverse the quotient graph in first-occurrence depth-first order. Internal
handles are rejected on every reachable alternative, even when a supplied
payload happens to choose a public alternative. -/
def walk (types : List (Schema .target)) (classOf : SchemaId .target → SchemaId .target)
    (remaining : List (SchemaId .target)) (pending order : List (SchemaId .target)) :
    Option (List (SchemaId .target)) :=
  match pending with
  | [] => some order
  | id :: tail =>
    match types[id.value]? with
    | none | some (.internal _) => none
    | some shape =>
      if _fresh : id ∈ remaining then
        walk types classOf (remaining.erase id)
          ((SchemaAdmission.structuralChildren shape).map classOf ++ tail) (order ++ [id])
      else walk types classOf remaining tail order
termination_by (remaining.length, pending.length)
decreasing_by
  all_goals simp_wf
  all_goals first
    | have size := List.length_erase_of_mem _fresh
      have positive := List.length_pos_of_mem _fresh
      omega
    | exact Prod.Lex.right _ (by omega)

def canonicalize (descriptor : Descriptor) : Option Descriptor := do
  if !SchemaAdmission.valid descriptor.types then none else do
    let classOf := classes descriptor.types
    let order ← walk descriptor.types classOf
      ((List.range descriptor.types.length).map (fun index => ⟨index⟩)) [classOf descriptor.root] []
    let types ← order.mapM (fun id => do
      let shape ← descriptor.types[id.value]?
      return SchemaEquivalence.mapChildren (fun child => ⟨order.idxOf (classOf child)⟩) shape)
    return ⟨0, types⟩

/-- Decode exhausts the raw descriptor, canonicalizes the complete recursive
shape, then requires exact record equality. The raw codec's uniqueness theorem
binds that equality to the full original bytes. -/
def decode (input : Bytes) : Option Descriptor := do
  let descriptor ← rawCodec.decode input
  let normalized ← canonicalize descriptor
  if normalized = descriptor then some descriptor else none

def encode (descriptor : Descriptor) : Option Bytes := do
  let normalized ← canonicalize descriptor
  if rawCodec.valid normalized then some (rawCodec.encode normalized) else none

theorem canonical_root (descriptor normalized : Descriptor)
    (accepted : canonicalize descriptor = some normalized) : normalized.root = 0 := by
  unfold canonicalize at accepted
  split at accepted
  · cases accepted
  · dsimp only [Bind.bind] at accepted
    obtain ⟨_, _, rest⟩ := Option.bind_eq_some_iff.mp accepted
    obtain ⟨_, _, equal⟩ := Option.bind_eq_some_iff.mp rest
    cases equal
    rfl

theorem decode_exact (input : Bytes) (descriptor : Descriptor)
    (accepted : decode input = some descriptor) :
    rawCodec.valid descriptor = true ∧ rawCodec.encode descriptor = input ∧
      descriptor.root = 0 ∧ canonicalize descriptor = some descriptor := by
  unfold decode at accepted
  cases raw : rawCodec.decode input with
  | none => simp [raw] at accepted
  | some original =>
    cases normal : canonicalize original with
    | none => simp [raw, normal] at accepted
    | some normalized =>
      simp [raw, normal] at accepted
      rcases accepted with ⟨equal, rfl⟩
      subst normalized
      have exactBytes := rawCodec.decode_exact input original raw
      exact ⟨exactBytes.1, exactBytes.2, canonical_root original original normal, normal⟩

end BoundaryV2.Profile.SchemaDescriptor
