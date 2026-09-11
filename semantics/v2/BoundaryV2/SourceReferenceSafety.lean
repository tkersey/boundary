import BoundaryV2.SourceCloneOwnership
import BoundaryV2.SourceTokenExecution

namespace BoundaryV2.Profile.Source.Machine
namespace ReferenceSafety
open ReferenceContracts

/-- Usable references agree with their objects; retained owning tokens keep
that physical identity and remain below the allocation supply. -/
def ValueGood (schemas : List (Schema .source)) (heap : Heap) (value : SemanticValue) : Prop :=
  ValueValid schemas heap value ∧ ValueAligned heap.custody value ∧ ValueTokensBounded heap.nextCustody value

structure Valid (schemas : List (Schema .source)) (machine : State) : Prop where
  values : ValueInventory.All (ValueGood schemas machine.heap) machine
  live : machine.heap.CustodyLive

theorem values_valid (good : Valid schemas machine) : ValueInventory.All (ValueValid schemas machine.heap) machine :=
  fun value member => (good.values value member).1

theorem values_aligned (good : Valid schemas machine) : ValueInventory.All (ValueAligned machine.heap.custody) machine :=
  fun value member => (good.values value member).2.1

theorem values_bounded (good : Valid schemas machine) : TokenInventory.All machine.heap.nextCustody machine :=
  fun value member => (good.values value member).2.2

theorem initial_valid (context : Context) (arguments : List SemanticValue) (machine : State)
    (accepted : initial context arguments = .ok machine) : Valid context.source.schemas machine := by
  have valid := initial_references_valid _ _ _ accepted
  have owned := initial_owned_reference_wf _ _ _ accepted
  exact ⟨fun value member => ⟨valid value member, owned.aligned value member, owned.tokens value member⟩, owned.live⟩

theorem external_valid (machine : State) (context : Context) (action : External) (after : Transition)
    (accepted : external machine context action = .ok after) (good : Valid context.source.schemas machine) :
    Valid context.source.schemas after.state := by
  have refValid := external_references_valid _ _ _ _ accepted (values_valid good)
  obtain ⟨objects, custody, supply⟩ := external_retains_reference_custody _ _ _ _ accepted
  have aligned : ValueInventory.All (ValueAligned after.state.heap.custody) after.state := by
    rw [custody]
    apply ValueInventory.external_preserves_all _ _ _ _ accepted _ (values_aligned good)
    intro value admitted
    exact token_free_aligned _ _ (external_value_has_no_runtime_handles _ _ admitted).2
  have bounded : TokenInventory.All after.state.heap.nextCustody after.state := by
    rw [supply]
    exact TokenInventory.external_preserves _ _ _ _ accepted (values_bounded good)
  refine ⟨fun value member => ⟨refValid value member, aligned value member, bounded value member⟩, ?_⟩
  intro entry member
  simpa only [Heap.lookup, objects] using good.live entry (custody ▸ member)

theorem move_value (before after : Heap) (values : List Located) (receiver : Nat → Custody.Owner)
    (value : SemanticValue) (accepted : moveValues before values receiver = some after)
    (good : ValueGood schemas before value) : ValueGood schemas after value :=
  ⟨moveValues_value_valid _ _ _ _ _ _ accepted good.1,
    moveValues_preserves_alignment _ _ _ _ _ accepted good.2.1,
    TokenInventory.value_mono _ _ _ good.2.2 (moveValues_allocation _ _ _ _ accepted).custody⟩

theorem move_valid (machine : State) (after : Heap) (values : List Located) (receiver : Nat → Custody.Owner)
    (accepted : moveValues machine.heap values receiver = some after) (good : Valid schemas machine) :
    Valid schemas {machine with heap := after} := by
  have moved := ValueInventory.all_mono _ _ machine good.values (fun value holds => move_value _ _ _ _ value accepted holds)
  exact ⟨ValueInventory.moveValues_preserves_all _ _ _ _ accepted _ moved,
    moveValues_preserves_live_objects _ _ _ _ accepted good.live⟩

theorem allocation_value (before after : Heap) (schema : SchemaId .source) (stored : Object)
    (owner : Custody.Owner) (exclusive : Bool) (result : Located) (value : SemanticValue)
    (accepted : allocateObject before schema stored owner exclusive = some (after, result))
    (good : ValueGood schemas before value) : ValueGood schemas after value :=
  ⟨allocation_value_valid _ _ _ _ _ _ _ _ _ accepted good.2.2 good.1,
    allocation_preserves_prior_alignment _ _ _ _ _ _ _ _ accepted good.2.2 good.2.1,
    TokenInventory.value_mono _ _ _ good.2.2 (allocateObject_allocation _ _ _ _ _ _ _ accepted).custody⟩

theorem allocation_result (before after : Heap) (schema : SchemaId .source) (stored : Object)
    (owner : Custody.Owner) (exclusive : Bool) (result : Located)
    (accepted : allocateObject before schema stored owner exclusive = some (after, result))
    (compatible : Matches schemas schema stored) : ValueGood schemas after result.value :=
  ⟨allocateObject_reference_valid _ _ _ _ _ _ _ _ accepted compatible,
    allocation_returns_aligned_reference _ _ _ _ _ _ _ accepted⟩

theorem allocation_valid (machine : State) (after : Heap) (schema : SchemaId .source) (stored : Object)
    (owner : Custody.Owner) (exclusive : Bool) (result : Located)
    (accepted : allocateObject machine.heap schema stored owner exclusive = some (after, result))
    (good : Valid schemas machine)
    (storedGood : ∀ value ∈ ValueInventory.object stored, ValueGood schemas machine.heap value) :
    Valid schemas {machine with heap := after} := by
  have moved := ValueInventory.all_mono _ _ machine good.values (fun value holds => allocation_value _ _ _ _ _ _ _ value accepted holds)
  exact ⟨ValueInventory.allocateObject_preserves_all _ _ _ _ _ _ _ accepted _ moved
      (fun value member => allocation_value _ _ _ _ _ _ _ value accepted (storedGood value member)),
    allocateObject_preserves_live_objects _ _ _ _ _ _ _ accepted good.live⟩

theorem retirement_value (before after : Heap) (retired : Located) (value : SemanticValue)
    (accepted : retireObject before retired = some after) (live : before.CustodyLive)
    (retiredShape : ValueShape schemas retired.value) (retiredGood : ValueGood schemas before retired.value)
    (modes : ValueModes schemas value) (good : ValueGood schemas before value) : ValueGood schemas after value :=
  ⟨retire_value_valid_from_modes _ _ _ _ _ accepted live retiredShape retiredGood.1 retiredGood.2.1 modes good.1 good.2.1,
    retireObject_preserves_alignment _ _ _ _ accepted good.2.1,
    TokenInventory.value_mono _ _ _ good.2.2 (retireObject_allocation _ _ _ accepted).custody⟩

theorem retirement_valid (machine : State) (after : Heap) (retired : Located)
    (accepted : retireObject machine.heap retired = some after) (good : Valid schemas machine)
    (retiredShape : ValueShape schemas retired.value) (retiredGood : ValueGood schemas machine.heap retired.value)
    (modes : ValueInventory.All (ValueModes schemas) machine) : Valid schemas {machine with heap := after} := by
  have moved : ValueInventory.All (ValueGood schemas after) machine := fun value member =>
    retirement_value _ _ _ _ accepted good.live retiredShape retiredGood (modes value member) (good.values value member)
  exact ⟨ValueInventory.retireObject_preserves_all _ _ _ accepted _ moved,
    retireObject_preserves_live_objects _ _ _ accepted good.live retiredGood.2.1⟩

theorem replacement_value (before after : Heap) (node : NodeId) (stored original : Object) (value : SemanticValue)
    (found : before.lookup node = some original) (accepted : replaceObject before node stored = some after)
    (compatible : ∀ schema, Matches schemas schema original → Matches schemas schema stored)
    (good : ValueGood schemas before value) : ValueGood schemas after value := by
  have sameBook : after.custody = before.custody := by
    unfold replaceObject at accepted
    split at accepted <;> try contradiction
    cases accepted; rfl
  exact ⟨replaceObject_value_valid _ _ _ _ _ _ _ found accepted compatible good.1,
    sameBook ▸ good.2.1,
    TokenInventory.value_mono _ _ _ good.2.2 (replaceObject_allocation _ _ _ _ accepted).custody⟩

theorem replacement_valid (machine : State) (after : Heap) (node : NodeId) (stored original : Object)
    (found : machine.heap.lookup node = some original) (accepted : replaceObject machine.heap node stored = some after)
    (compatible : ∀ schema, Matches schemas schema original → Matches schemas schema stored)
    (good : Valid schemas machine)
    (storedGood : ∀ value ∈ ValueInventory.object stored, ValueGood schemas machine.heap value) :
    Valid schemas {machine with heap := after} := by
  have moved := ValueInventory.all_mono _ _ machine good.values (fun value holds => replacement_value _ _ _ _ _ value found accepted compatible holds)
  exact ⟨ValueInventory.replaceObject_preserves_all _ _ _ _ accepted _ moved
      (fun value member => replacement_value _ _ _ _ _ value found accepted compatible (storedGood value member)),
    replaceObject_preserves_live_objects _ _ _ _ accepted good.live⟩

end ReferenceSafety
end BoundaryV2.Profile.Source.Machine
