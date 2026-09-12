import BoundaryV2.SourceTokenExecution
import BoundaryV2.SourceValueExecution
import BoundaryV2.SourcePrimitiveLinearity

namespace BoundaryV2.Profile.Source.Machine
namespace ValueLinearity

abbrev Linear (value : SemanticValue) : Prop := (ownedTokens value).Nodup
abbrev All (machine : State) : Prop := ValueInventory.All Linear machine

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

theorem member_linear (values : List SemanticValue) (child : SemanticValue)
    (linear : (values.flatMap ownedTokens).Nodup) (member : child ∈ values) : Linear child := by
  induction values with
  | nil => simp at member
  | cons first rest ih =>
    rw [List.flatMap_cons, List.nodup_append] at linear
    rcases List.mem_cons.mp member with rfl | member
    · exact linear.1
    · exact ih linear.2.1 member

theorem allocation_result (before after : Heap) (schema : SchemaId .source) (stored : Object)
    (owner : Custody.Owner) (exclusive : Bool) (result : Located)
    (accepted : allocateObject before schema stored owner exclusive = some (after, result)) : Linear result.value := by
  rw [ValueInventory.allocateObject_result _ _ _ _ _ _ _ accepted]
  cases exclusive <;> simp [Linear, ownedTokens]

theorem initial_linear (context : Context) (arguments : List SemanticValue) (machine : State)
    (accepted : initial context arguments = .ok machine) : All machine :=
  ValueInventory.all_mono _ _ machine (ValueInventory.initial_has_no_runtime_handles _ _ _ accepted)
    (fun value free => by simp [Linear, free.2])

theorem external_preserves (machine : State) (context : Context) (action : External) (after : Transition)
    (accepted : external machine context action = .ok after) (holds : All machine) : All after.state := by
  apply ValueInventory.external_preserves_all _ _ _ _ accepted _ holds
  intro value checked
  simp [Linear, (external_value_has_no_runtime_handles _ _ checked).2]

theorem instantiate_preserves (machine after : State) (context : Context) (saved instantiated : Capture)
    (accepted : instantiateCapture machine context saved = .ok (after, instantiated))
    (holds : All machine) (captureHolds : ∀ value ∈ ValueInventory.capture saved, Linear value) :
    All after ∧ (∀ value ∈ ValueInventory.capture instantiated, Linear value) := by
  obtain ⟨mapping, captured, _, inventory⟩ :=
    ReferenceContracts.instantiation_reference_map machine after context saved instantiated accepted
  exact ReferenceContracts.instantiation_values_of_inventory machine after context saved instantiated accepted
    mapping captured _ _ holds captureHolds (fun _ holds => holds)
    (fun value holds => by simpa only [Linear, renaming_preserves_owned_tokens] using holds) inventory

theorem liveOwnedValue_preserves (store : Heap) (owner : Custody.Owner) (original : SemanticValue)
    (linear : Linear original) : ∀ value ∈ liveOwnedValue store owner original, Linear value.value := by
  cases original with
  | scalar _ _ | blob _ _ => simp [liveOwnedValue]
  | reference schema node token =>
    cases token with
    | none => simp [liveOwnedValue]
    | some token =>
      simp only [liveOwnedValue]
      split
      · intro value member; cases List.mem_singleton.mp member; exact linear
      · simp
  | product schema fields | sequence schema fields =>
    simp only [liveOwnedValue, List.mem_flatMap]
    intro value member
    obtain ⟨child, childMember, member⟩ := member
    apply liveOwnedValue_preserves store owner child ?_ value member
    exact member_linear fields child (by simpa only [Linear, ownedTokens] using linear) childMember
  | variant schema tag payload =>
    simpa only [liveOwnedValue] using liveOwnedValue_preserves store owner payload (by simpa only [Linear, ownedTokens] using linear)
termination_by sizeOf original
decreasing_by
  all_goals subst original
  all_goals simp_wf
  all_goals first | omega | exact Nat.lt_trans (List.sizeOf_lt_of_mem childMember) (by omega)

theorem external_shape_has_no_tokens (schemas : List (Schema .source)) (value : SemanticValue)
    (shape : ValueShape schemas value) (safe : Traits.Safe schemas (value.schema, .external)) :
    ownedTokens value = [] := by
  have inherited := shape.reference_traits .external safe
  have zero : ValueTokensBounded 0 value := by
    apply (referencesSatisfy_token_bounds 0 value).mp
    apply ReferenceContracts.references_mono value _ _ inherited
    intro schema node token ⟨safe, inner, shape, _⟩
    obtain ⟨children, rule⟩ := safe _ .refl
    simp [Traits.rule, shape, Traits.premises] at rule
  cases tokens : ownedTokens value with
  | nil => rfl
  | cons token tail =>
    have impossible := zero token (by simp [tokens])
    omega

theorem cleanupInformation_token_free (context : Context) (schema : SchemaId .source)
    (exit : Cleanup.Exit .source) (information : SemanticValue)
    (accepted : cleanupInformation context schema exit = .ok information)
    (failuresFree : ∀ value ∈ exit.failures, ownedTokens value = [])
    (primaryFree : ∀ value, exit.primary = .failure value → ownedTokens value = []) :
    ownedTokens information = [] := by
  simp only [cleanupInformation, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, _, _, shape, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  rename_i primary optional failures productAt
  simp only [except_bind_ok, fromOption_ok] at accepted
  obtain ⟨shape, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  rename_i unit failure reason abandoned primaryAt
  simp only [except_bind_ok, fromOption_ok] at accepted
  obtain ⟨shape, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  rename_i absent present optionalAt
  simp only [except_bind_ok, fromOption_ok] at accepted
  obtain ⟨shape, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  rename_i textSchema bytesSchema reasonAt
  simp only [except_bind_ok] at accepted
  obtain ⟨_, _, _, _, accepted⟩ := accepted
  have failureTokens : exit.failures.flatMap ownedTokens = [] := List.flatMap_eq_nil_iff.mpr failuresFree
  have cancelledFree : ∀ value, (exit.cancellation.map fun cancellation => match cancellation with
      | .text data => Profile.Value.variant reason 0 (.blob textSchema data)
      | .bytes data => Profile.Value.variant reason 1 (.blob bytesSchema data)) = some value →
      ownedTokens value = [] := by
    intro value found
    obtain ⟨cancellation, _, rfl⟩ := Option.map_eq_some_iff.mp found
    cases cancellation <;> simp [ownedTokens]
  cases primaryIs : exit.primary <;> simp only [primaryIs] at accepted
  case normal =>
    simp only [pure, Except.pure, Except.bind, Except.ok.injEq] at accepted
    cases accepted
    simp only [ownedTokens, List.flatMap_cons, List.flatMap_nil, List.append_nil, failureTokens, List.nil_append]
    split
    · simp [ownedTokens]
    · rename_i _ child found
      simpa only [ownedTokens] using cancelledFree child found
  case failure value =>
    simp only [pure, Except.pure, Except.bind, Except.ok.injEq] at accepted
    cases accepted
    simp only [ownedTokens, List.flatMap_cons, List.flatMap_nil, List.append_nil, failureTokens, primaryFree value primaryIs, List.nil_append]
    split
    · simp [ownedTokens]
    · rename_i _ child found
      simpa only [ownedTokens] using cancelledFree child found
  case cancellation =>
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨value, found, _, rfl, rfl⟩ := accepted
    simp only [ownedTokens, List.flatMap_cons, List.flatMap_nil, List.append_nil, failureTokens, cancelledFree value found, List.nil_append]
    split
    · simp [ownedTokens]
    · rename_i _ child found
      simpa only [ownedTokens] using cancelledFree child found
  case abandoned =>
    simp only [pure, Except.pure, Except.bind, Except.ok.injEq] at accepted
    cases accepted
    simp only [ownedTokens, List.flatMap_cons, List.flatMap_nil, List.append_nil, failureTokens, List.nil_append]
    split
    · simp [ownedTokens]
    · rename_i _ child found
      simpa only [ownedTokens] using cancelledFree child found

def ExitFree (exit : Cleanup.Exit .source) : Prop :=
  (∀ value ∈ exit.failures, ownedTokens value = []) ∧
  (∀ value, exit.primary = .failure value → ownedTokens value = [])

theorem observed_exit_free (machine : State) (exit : Cleanup.Exit .source) (free : ExitFree exit) :
    ExitFree (observedExit machine exit) := by
  cases exit with
  | mk primary failures cancellation =>
    cases primary <;> cases observed : machine.cancellation <;>
      simp_all [ExitFree, observedExit, Cleanup.cancel]

theorem checked_failure_is_external (context : Context) (checked : context.typingValid = true) :
    Traits.Safe context.source.schemas (context.source.failure, .external) := by
  simp only [Context.typingValid, Option.any_eq_true] at checked
  obtain ⟨results, _, admitted⟩ := checked
  have declarations := (Admission.typed_checks_all_declarations _ _ _ _ admitted).1
  simp only [Admission.declarationsValid, Admission.rootsValid, Bool.and_eq_true] at declarations
  exact Traits.check_sound _ _ _ (by grind only [])

theorem typed_exit_free (context : Context) (exit : Cleanup.Exit .source)
    (checked : context.typingValid = true)
    (shapes : ∀ value ∈ exitValues exit, ValueShape context.source.schemas value)
    (failures : FailureSchemas.Types context.source (FailureSchemas.exit exit)) : ExitFree exit := by
  have safe := checked_failure_is_external context checked
  have free : ∀ value ∈ exitValues exit, value.schema = context.source.failure → ownedTokens value = [] := by
    intro value member same
    exact external_shape_has_no_tokens _ _ (shapes value member) (by simpa only [same] using safe)
  constructor
  · intro value member
    apply free value (by unfold exitValues; split <;> simp_all)
    apply failures
    exact List.mem_append_right _ (List.mem_map.mpr ⟨value, member, rfl⟩)
  · intro value failed
    apply free value (by simp [exitValues, failed])
    apply failures
    simp [FailureSchemas.exit, failed]

end ValueLinearity
end BoundaryV2.Profile.Source.Machine
