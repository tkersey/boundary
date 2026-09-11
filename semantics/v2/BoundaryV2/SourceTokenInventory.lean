import BoundaryV2.SourceReferenceInformation
import BoundaryV2.SourceReferenceClone

namespace BoundaryV2.Profile.Source.Machine
namespace TokenInventory

abbrev All (limit : Nat) (machine : State) : Prop :=
  ValueInventory.All (ValueTokensBounded limit) machine

theorem value_mono (before after : Nat) (value : SemanticValue)
    (bounded : ValueTokensBounded before value) (grows : before ≤ after) : ValueTokensBounded after value :=
  fun token member => Nat.lt_of_lt_of_le (bounded token member) grows

theorem all_mono (before after : Nat) (machine : State) (bounded : All before machine)
    (grows : before ≤ after) : All after machine :=
  ValueInventory.all_mono _ _ machine bounded (fun value holds => value_mono before after value holds grows)

theorem allocation_result (before after : Heap) (schema : SchemaId .source) (stored : Object)
    (owner : Custody.Owner) (exclusive : Bool) (result : Located)
    (accepted : allocateObject before schema stored owner exclusive = some (after, result))
    (upper : after.nextCustody ≤ limit) : ValueTokensBounded limit result.value :=
  value_mono _ _ _ (allocation_returns_aligned_reference _ _ _ _ _ _ _ accepted).2 upper

theorem initial_bounded (context : Context) (arguments : List SemanticValue) (machine : State)
    (accepted : initial context arguments = .ok machine) : All limit machine := by
  exact ValueInventory.all_mono _ _ machine (ValueInventory.initial_has_no_runtime_handles _ _ _ accepted)
    (fun value free => by simp [ValueTokensBounded, free.2])

theorem external_preserves (machine : State) (context : Context) (action : External) (after : Transition)
    (accepted : external machine context action = .ok after) (holds : All limit machine) : All limit after.state := by
  apply ValueInventory.external_preserves_all _ _ _ _ accepted _ holds
  intro value checked
  simp [ValueTokensBounded, (external_value_has_no_runtime_handles _ _ checked).2]

theorem instantiate_preserves (machine after : State) (context : Context) (saved instantiated : Capture)
    (accepted : instantiateCapture machine context saved = .ok (after, instantiated))
    (holds : All limit machine)
    (captureHolds : ∀ value ∈ ValueInventory.capture saved, ValueTokensBounded limit value) :
    All limit after ∧ (∀ value ∈ ValueInventory.capture instantiated, ValueTokensBounded limit value) := by
  obtain ⟨mapping, captured, _, inventory⟩ :=
    ReferenceContracts.instantiation_reference_map machine after context saved instantiated accepted
  exact ReferenceContracts.instantiation_values_of_inventory machine after context saved instantiated accepted
    mapping captured _ _ holds captureHolds (fun _ holds => holds)
    (fun value holds => ValueInventory.rename_preserves_token_bounds mapping limit value holds) inventory

theorem cleanupInformation_preserves (context : Context) (schema : SchemaId .source)
    (exit : Cleanup.Exit .source) (information : SemanticValue)
    (accepted : cleanupInformation context schema exit = .ok information)
    (holds : ∀ value ∈ exitValues exit, ValueTokensBounded limit value) : ValueTokensBounded limit information := by
  rw [← referencesSatisfy_token_bounds]
  apply ReferenceContracts.cleanupInformation_preserves_references _ _ _ _ accepted
  intro value member
  exact (referencesSatisfy_token_bounds limit value).mpr (holds value member)

theorem liveOwnedValue_preserves (store : Heap) (owner : Custody.Owner) (original : SemanticValue)
    (bounded : ValueTokensBounded limit original) :
    ∀ value ∈ liveOwnedValue store owner original, ValueTokensBounded limit value.value := by
  cases original with
  | scalar _ _ | blob _ _ => simp [liveOwnedValue]
  | reference schema node token =>
    cases token with
    | none => simp [liveOwnedValue]
    | some token =>
      simp only [liveOwnedValue]
      split
      · intro value member
        cases List.mem_singleton.mp member
        exact bounded
      · simp
  | product schema fields | sequence schema fields =>
    simp only [liveOwnedValue, List.mem_flatMap]
    intro value member
    obtain ⟨child, childMember, member⟩ := member
    apply liveOwnedValue_preserves store owner child ?_ value member
    intro token tokenMember
    apply bounded token
    simpa only [ownedTokens] using List.mem_flatMap.mpr ⟨child, childMember, tokenMember⟩
  | variant schema tag payload =>
    simpa only [liveOwnedValue] using liveOwnedValue_preserves store owner payload (by simpa only [ValueTokensBounded, ownedTokens] using bounded)
termination_by sizeOf original
decreasing_by
  all_goals subst original
  all_goals simp_wf
  all_goals first | omega | exact Nat.lt_trans (List.sizeOf_lt_of_mem childMember) (by omega)

end TokenInventory
end BoundaryV2.Profile.Source.Machine
