import BoundaryV2.SourceFrozenStorage

namespace BoundaryV2.Profile.Source.Machine
namespace ObjectSchemas

/-- Stored object tags and payload schemas agree with the admitted source
catalog. Reference-to-object agreement is a separate heap relation. -/
def ObjectValid (source : Module) : Object → Prop
  | .cell _ schema _ content =>
    ∃ region, source.schemas[schema.value]? = some (.internal (.cell content.value.schema region))
  | .package schema content =>
    source.schemas[schema.value]? = some (.internal (.suspensionPackage content.value.schema))
  | .resource schema content =>
    ∃ id resource, source.schemas[schema.value]? = some (.internal (.abstractResource id)) ∧
      source.resources[id.value]? = some resource ∧ resource.representation = content.value.schema ∧
      Traits.check source.schemas .external content.value.schema = true
  | .oneShot capture =>
    ∃ signature, source.schemas[capture.schema.value]? = some (.internal (.resumption signature)) ∧ signature.use ≠ .multi
  | .multiTemplate capture =>
    ∃ signature, source.schemas[capture.schema.value]? = some (.internal (.resumption signature)) ∧ signature.use = .multi
  | .borrow schema _ _ _ =>
    ∃ resource region, source.schemas[schema.value]? = some (.internal (.borrowed resource region)) ∧ region.value < source.regionCount
  | .region _ descriptor _ _ => descriptor.value < source.regionCount
  | .capability _ effect => ∃ schema : SchemaId .source, source.schemas[schema.value]? = some (.internal (.capability effect))
  | .closure .. => True

def Valid (source : Module) (objects : List (Option Object)) : Prop :=
  ∀ entry ∈ objects, ∀ stored ∈ entry, ObjectValid source stored

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

private theorem require_ok (condition : Bool) (reason : Invalid) (result : Unit)
    (accepted : require condition reason = .ok result) : condition = true := by
  unfold require at accepted
  split at accepted <;> first | assumption | contradiction

theorem rename_object (source : Module) (mapping : Renaming) (stored : Object)
    (valid : ObjectValid source stored) : ObjectValid source (renameObject mapping stored) := by
  cases stored <;> simp_all only [ObjectValid, renameObject, renameLocated, renameCapture, renaming_preserves_value_schema]

theorem frozen_object (source : Module) (heap : Heap) (capture : Capture) (dormant : List Capture)
    (valid : FrozenContracts.Valid heap capture)
    (dormantValid : ∀ inner ∈ dormant, FrozenContracts.Valid heap inner)
    (node : NodeId) (stored : Object) (found : heap.lookup node = some stored)
    (typed : ObjectValid source stored) : ObjectValid source (frozenObject capture dormant node stored) := by
  have same := FrozenContracts.frozenObject_preserves_signature heap capture dormant valid dormantValid node stored found
  cases stored <;> try exact typed
  rename_i identity schema region current
  have projected := congrArg (fun value => value.map CellStability.Signature.contentSchema) same
  simp only [frozenObject, CellStability.signature, Option.map_some, Option.some.injEq] at projected
  simpa only [frozenObject, ObjectValid, projected] using typed

theorem heap_lookup (source : Module) (heap : Heap) (node : NodeId) (stored : Object)
    (found : heap.lookup node = some stored) (valid : Valid source heap.objects) : ObjectValid source stored := by
  simp only [Heap.lookup, Option.bind_eq_some_iff] at found
  obtain ⟨entry, atNode, present⟩ := found
  cases entry <;> simp [id] at present
  cases present
  exact valid _ (List.mem_of_getElem? atNode) _ rfl

theorem allocate_valid (source : Module) (before after : Heap) (schema : SchemaId .source)
    (stored : Object) (owner : Custody.Owner) (exclusive : Bool) (value : Located)
    (accepted : allocateObject before schema stored owner exclusive = some (after, value))
    (typed : Valid source before.objects) (storedTyped : ObjectValid source stored) : Valid source after.objects := by
  cases exclusive <;> simp [allocateObject, Option.bind_eq_some_iff] at accepted
  · obtain ⟨rfl, _⟩ := accepted
    simp only [Valid, List.mem_append, List.mem_singleton] at typed ⊢
    grind only [Option.mem_def, Option.some.inj]
  · obtain ⟨_, _, rfl, _⟩ := accepted
    simp only [Valid, List.mem_append, List.mem_singleton] at typed ⊢
    grind only [Option.mem_def, Option.some.inj]

theorem replace_valid (source : Module) (before after : Heap) (node : NodeId) (stored : Object)
    (accepted : replaceObject before node stored = some after) (typed : Valid source before.objects)
    (storedTyped : ObjectValid source stored) : Valid source after.objects := by
  unfold replaceObject at accepted
  split at accepted <;> try contradiction
  cases accepted
  intro entry member value present
  rcases List.mem_or_eq_of_mem_set member with old | rfl
  · exact typed _ old _ present
  · cases present; exact storedTyped

theorem retire_valid (source : Module) (before after : Heap) (value : Located)
    (accepted : retireObject before value = some after) (typed : Valid source before.objects) : Valid source after.objects := by
  unfold retireObject at accepted
  split at accepted <;> try contradiction
  simp only [bind, Option.bind_eq_some_iff, consumeValue, pure, Option.some.injEq] at accepted
  obtain ⟨_, _, _, ⟨_, _, rfl⟩, rfl⟩ := accepted
  intro entry member value present
  rcases List.mem_or_eq_of_mem_set member with old | rfl
  · exact typed _ old _ present
  · cases present

theorem instantiate_valid (machine after : State) (context : Context) (capture instantiated : Capture)
    (accepted : instantiateCapture machine context capture = .ok (after, instantiated))
    (typed : Valid context.source machine.heap.objects)
    (frozen : FrozenContracts.HeapValid machine.heap) (captureValid : FrozenContracts.Valid machine.heap capture) :
    Valid context.source after.heap.objects := by
  let dormant := (cloneSupport machine.heap capture).filterMap (fun node => match machine.heap.lookup node with
    | some (.multiTemplate inner) => some inner | _ => none)
  have allDormant : ∀ inner ∈ dormant, FrozenContracts.Valid machine.heap inner := by
    intro inner member
    obtain ⟨node, _, selected⟩ := List.mem_filterMap.mp member
    split at selected <;> try contradiction
    rename_i saved found
    cases selected
    exact FrozenContracts.heap_lookup _ _ _ found frozen
  obtain ⟨mapping, _, _, _, inventory⟩ := instantiation_inventory machine after context capture instantiated accepted
  intro entry member stored present
  rcases inventory entry member with old | new
  · exact typed entry old stored present
  · obtain ⟨node, _, object, found, rfl⟩ := new
    cases present
    exact rename_object _ _ _ (frozen_object _ _ _ _ captureValid allDormant _ _ found
      (heap_lookup _ _ _ _ found typed))

end ObjectSchemas
end BoundaryV2.Profile.Source.Machine
