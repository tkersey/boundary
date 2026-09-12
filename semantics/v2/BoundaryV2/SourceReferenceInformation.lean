import BoundaryV2.SourceReferenceContracts
import BoundaryV2.SourceCleanupValueTypes

namespace BoundaryV2.Profile.Source.Machine
namespace ReferenceContracts

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem cleanupInformation_preserves_references (context : Context) (schema : SchemaId .source)
    (exit : Cleanup.Exit .source) (information : SemanticValue)
    (accepted : cleanupInformation context schema exit = .ok information)
    (property : SchemaId .source → NodeId → Option CustodyToken → Prop)
    (holds : ∀ value ∈ exitValues exit, Primitives.ReferencesSatisfy property value) :
    Primitives.ReferencesSatisfy property information := by
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
  have failuresHold : ∀ value ∈ exit.failures, Primitives.ReferencesSatisfy property value := by
    intro value member
    apply holds
    unfold exitValues
    split <;> simp_all
  have cancelledHold : ∀ value, (exit.cancellation.map fun cancellation => match cancellation with
      | .text data => Profile.Value.variant reason 0 (.blob textSchema data)
      | .bytes data => Profile.Value.variant reason 1 (.blob bytesSchema data)) = some value →
      Primitives.ReferencesSatisfy property value := by
    intro value found
    obtain ⟨cancellation, _, rfl⟩ := Option.map_eq_some_iff.mp found
    cases cancellation <;> simp [Primitives.ReferencesSatisfy]
  cases primaryIs : exit.primary <;> simp only [primaryIs] at accepted
  case normal =>
    simp only [pure, Except.pure, Except.bind, Except.ok.injEq] at accepted
    cases accepted
    simp [Primitives.ReferencesSatisfy]
    constructor
    · split
      · simp [Primitives.ReferencesSatisfy]
      · rename_i _ child found
        simpa only [Primitives.ReferencesSatisfy] using cancelledHold child found
    · exact failuresHold
  case failure value =>
    simp only [pure, Except.pure, Except.bind, Except.ok.injEq] at accepted
    cases accepted
    have valueHolds := holds value (by simp [exitValues, primaryIs])
    simp [Primitives.ReferencesSatisfy]
    refine ⟨valueHolds, ?_, failuresHold⟩
    split
    · simp [Primitives.ReferencesSatisfy]
    · rename_i _ child found
      simpa only [Primitives.ReferencesSatisfy] using cancelledHold child found
  case cancellation =>
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨value, found, _, rfl, rfl⟩ := accepted
    simp [Primitives.ReferencesSatisfy]
    refine ⟨cancelledHold value found, ?_, failuresHold⟩
    split
    · simp [Primitives.ReferencesSatisfy]
    · rename_i _ child found
      simpa only [Primitives.ReferencesSatisfy] using cancelledHold child found
  case abandoned =>
    simp only [pure, Except.pure, Except.bind, Except.ok.injEq] at accepted
    cases accepted
    simp [Primitives.ReferencesSatisfy]
    constructor
    · split
      · simp [Primitives.ReferencesSatisfy]
      · rename_i _ child found
        simpa only [Primitives.ReferencesSatisfy] using cancelledHold child found
    · exact failuresHold

end ReferenceContracts
end BoundaryV2.Profile.Source.Machine
