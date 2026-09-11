import BoundaryV2.GraphReferences

namespace BoundaryV2.Profile.Graph

private def Agree (n₁ n₂ : NodeId → NodeId) (b₁ b₂ : BlobId → BlobId) (refs : List Reference) : Prop :=
  ∀ reference ∈ refs, reference.map n₁ b₁ = reference.map n₂ b₂

private theorem agree_append : Agree n₁ n₂ b₁ b₂ (left ++ right) ↔
    Agree n₁ n₂ b₁ b₂ left ∧ Agree n₁ n₂ b₁ b₂ right := by
  simp only [Agree, List.mem_append, or_imp, forall_and]

private theorem agree_cons : Agree n₁ n₂ b₁ b₂ (head :: tail) ↔
    head.map n₁ b₁ = head.map n₂ b₂ ∧ Agree n₁ n₂ b₁ b₂ tail := by simp [Agree]

private theorem agree_nil : Agree n₁ n₂ b₁ b₂ [] := by simp [Agree]

private theorem value_congr (value : Value) (same : Agree n₁ n₂ b₁ b₂ (valueReferences value)) :
    mapValue n₁ (mapBlobValue b₁ value) = mapValue n₂ (mapBlobValue b₂ value) := by
  cases value with | mk schema body =>
    cases body <;> simp_all [Agree, valueReferences, Reference.map, mapValue, mapBlobValue]

private theorem values_congr (values : List Value) (same : Agree n₁ n₂ b₁ b₂ (valuesReferences values)) :
    (values.map (mapBlobValue b₁)).map (mapValue n₁) =
      (values.map (mapBlobValue b₂)).map (mapValue n₂) := by
  simp only [List.map_map, List.map_inj_left]
  intro value member
  apply value_congr
  intro reference edge
  exact same reference (List.mem_flatMap.mpr ⟨value, member, edge⟩)

private theorem optional_congr (value : Option NodeId)
    (same : Agree n₁ n₂ b₁ b₂ (optionalReferences value)) : value.map n₁ = value.map n₂ := by
  cases value <;> simp_all [Agree, optionalReferences, Reference.map]

private theorem optional_value_congr (value : Option Value)
    (same : Agree n₁ n₂ b₁ b₂ (valuesReferences value.toList)) :
    (value.map (mapBlobValue b₁)).map (mapValue n₁) =
      (value.map (mapBlobValue b₂)).map (mapValue n₂) := by
  cases value with
  | none => rfl
  | some value =>
    have h : Agree n₁ n₂ b₁ b₂ (valueReferences value) := by simpa [valuesReferences] using same
    exact congrArg some (value_congr value h)

private theorem saved_congr (values : List (Option Value))
    (same : Agree n₁ n₂ b₁ b₂ (valuesReferences (values.filterMap id))) :
    (values.map (Option.map (mapBlobValue b₁))).map (Option.map (mapValue n₁)) =
      (values.map (Option.map (mapBlobValue b₂))).map (Option.map (mapValue n₂)) := by
  simp only [List.map_map, List.map_inj_left]
  intro value member
  apply optional_value_congr
  intro reference edge
  rcases List.mem_flatMap.mp edge with ⟨actual, atValue, actualEdge⟩
  apply same reference
  apply List.mem_flatMap.mpr
  exact ⟨actual, List.mem_filterMap.mpr ⟨value, member, by simpa using atValue⟩, actualEdge⟩

private theorem capture_congr (capture : Capture)
    (same : Agree n₁ n₂ b₁ b₂ (captureReferences capture)) :
    mapCapture n₁ (mapBlobCapture b₁ capture) = mapCapture n₂ (mapBlobCapture b₂ capture) := by
  simp only [captureReferences, agree_append, agree_cons, Reference.map, Reference.node.injEq] at same
  simp only [mapCapture, mapBlobCapture]
  rw [optional_congr capture.capture same.1.1.1, same.1.1.2.1,
    optional_congr capture.evidence same.1.2, values_congr capture.useSiteCapabilities same.2]

private theorem exit_congr (exit : Exit)
    (same : Agree n₁ n₂ b₁ b₂ (exitReferences exit)) :
    mapExit n₁ (mapBlobExit b₁ exit) = mapExit n₂ (mapBlobExit b₂ exit) := by
  cases exit with | mk reason failures failure stop outer discarded =>
    cases reason <;>
      simp only [exitReferences, agree_append] at same <;>
      simp only [mapExit, mapBlobExit]
    all_goals rw [values_congr failures same.1.1.1.2, optional_congr stop same.1.1.2,
      optional_congr outer same.1.2, values_congr discarded same.2]
    all_goals try rw [value_congr _ same.1.1.1.1]

theorem remapNode_congr (node : Node)
    (same : ∀ reference ∈ nodeReferences node, reference.map n₁ b₁ = reference.map n₂ b₂) :
    remapNode n₁ b₁ node = remapNode n₂ b₂ node := by
  change Agree n₁ n₂ b₁ b₂ (nodeReferences node) at same
  cases node <;> simp only [nodeReferences, agree_append, agree_cons, Reference.map,
    Reference.node.injEq] at same <;> simp only [remapNode, mapNode, mapBlobNode]
  all_goals first
    | exact congrArg _ (capture_congr _ same)
    | exact congrArg _ (exit_congr _ same)
    | congr 1
  all_goals try simp only [Control.mk.injEq, Continuation.mk.injEq, OwnedRef.mk.injEq]
  all_goals repeat first | apply And.intro
  all_goals try solve
    | apply values_congr; simp_all
    | apply value_congr; simp_all
    | apply optional_congr (b₁ := b₁) (b₂ := b₂); simp_all
    | apply optional_value_congr; simp_all
    | apply saved_congr; simp_all
    | simp_all
  · exact ⟨values_congr _ same.1.1.1, optional_congr _ same.1.1.2,
      optional_congr _ same.1.2, optional_congr _ same.2⟩
  · exact ⟨saved_congr _ same.1.1.1, optional_congr _ same.1.1.2,
      optional_congr _ same.1.2, optional_congr _ same.2⟩
  · apply List.map_inj_left.mpr
    intro owned member
    apply congrArg OwnedRef.mk
    exact Reference.node.inj (same.2 _ (List.mem_map.mpr ⟨owned, member, rfl⟩))
  · apply List.map_inj_left.mpr
    intro pair member
    apply Prod.ext
    · exact Reference.node.inj (same.2 (.node pair.1) (List.mem_flatMap.mpr ⟨pair, member, by simp⟩))
    · exact Reference.node.inj (same.2 (.node pair.2) (List.mem_flatMap.mpr ⟨pair, member, by simp⟩))
  · rename_i block cleanup resource status
    cases status <;> simp only at same ⊢
    · rename_i position
      exact congrArg ObligationStatus.running (Reference.node.inj (same.2 (.node position) (by simp)))
    · exact congrArg ObligationStatus.failed (value_congr _ same.2)

private theorem mapValue_id (value : Value) : mapValue id value = value := by
  cases value with | mk schema body => cases body <;> rfl

private theorem mapBlobValue_id (value : Value) : mapBlobValue id value = value := by
  cases value with | mk schema body => cases body <;> rfl

theorem remapNode_id (node : Node) : remapNode id id node = node := by
  cases node <;> simp [remapNode, mapNode, mapBlobNode, mapCapture, mapBlobCapture,
    mapExit, mapBlobExit, Function.comp_def, mapValue_id, mapBlobValue_id]
  · rename_i block cleanup resource status
    cases status <;> rfl
  · rename_i exit
    cases exit with | mk reason failures cancellation stop outer discarded =>
      cases reason <;> rfl

theorem remapNode_identity_on_references (node : Node)
    (fixed : ∀ reference ∈ nodeReferences node, reference.map nodes blobs = reference) :
    remapNode nodes blobs node = node := by
  apply Eq.trans (b := remapNode id id node) _ (remapNode_id node)
  apply remapNode_congr
  intro reference member
  have unchanged : reference.map id id = reference := by cases reference <;> rfl
  exact (fixed reference member).trans unchanged.symm

theorem remapRoots_congr (roots : Roots)
    (same : ∀ reference ∈ rootReferences roots, reference.map n₁ b₁ = reference.map n₂ b₂) :
    remapRoots n₁ roots = remapRoots n₂ roots := by
  change Agree n₁ n₂ b₁ b₂ (rootReferences roots) at same
  simp only [rootReferences, agree_append] at same
  simp only [remapRoots]
  rw [optional_congr _ same.1.1.1.1, optional_congr _ same.1.1.1.2,
    optional_congr _ same.1.2, optional_congr _ same.2]
  congr 1
  apply List.map_inj_left.mpr
  intro owned member
  apply congrArg OwnedRef.mk
  exact Reference.node.inj (same.1.1.2 (.node owned.node) (List.mem_map.mpr ⟨owned, member, rfl⟩))

theorem remapRoots_id (roots : Roots) : remapRoots id roots = roots := by simp [remapRoots]

theorem remapRoots_identity_on_references (roots : Roots)
    (fixed : ∀ reference ∈ rootReferences roots, reference.map nodes blobs = reference) :
    remapRoots nodes roots = roots := by
  apply Eq.trans (b := remapRoots id roots) _ (remapRoots_id roots)
  apply remapRoots_congr (b₁ := blobs) (b₂ := id)
  intro reference member
  have unchanged : reference.map id id = reference := by cases reference <;> rfl
  exact (fixed reference member).trans unchanged.symm

private theorem value_compose (value : Value) :
    mapValue n₂ (mapBlobValue b₂ (mapValue n₁ (mapBlobValue b₁ value))) =
      mapValue (n₂ ∘ n₁) (mapBlobValue (b₂ ∘ b₁) value) := by
  cases value with | mk schema body => cases body <;> rfl

theorem remapNode_compose (node : Node) :
    remapNode n₂ b₂ (remapNode n₁ b₁ node) = remapNode (n₂ ∘ n₁) (b₂ ∘ b₁) node := by
  cases node <;> simp [remapNode, mapNode, mapBlobNode, mapCapture, mapBlobCapture,
    mapExit, mapBlobExit, List.map_map, Option.map_map, Function.comp_def,
    value_compose (n₁ := n₁) (n₂ := n₂) (b₁ := b₁) (b₂ := b₂)]
  · rename_i block cleanup resource status
    cases status <;> simp only [value_compose, Function.comp_def]
  · rename_i exit
    cases exit with | mk reason failures cancellation stop outer discarded =>
      cases reason <;> simp only [value_compose, Function.comp_def]

theorem remapRoots_compose (roots : Roots) :
    remapRoots n₂ (remapRoots n₁ roots) = remapRoots (n₂ ∘ n₁) roots := by
  simp [remapRoots, Function.comp_def]

end BoundaryV2.Profile.Graph
