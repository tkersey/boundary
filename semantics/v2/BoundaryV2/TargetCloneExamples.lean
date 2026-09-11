import BoundaryV2.TargetClone

namespace BoundaryV2.Profile.Target.Machine.Clone

private def nestedStore : Store [] := ⟨[
  .region 0 none [],
  .handler 0 [] none (some 0),
  .attachment 1 none none .suspended (some 0),
  .region 1 (some 0) [],
  .regionScope 0 3 (some 2),
  .handler 0 [] (some 2) (some 3),
  .attachment 5 (some 2) none .suspended (some 3),
  .continuation ⟨0, [], some 6, some 6, some 3⟩,
  .multiTemplate ⟨0, some 7, 6, some 6, []⟩,
  .continuation ⟨0, [some ⟨0, .reference 8⟩, some ⟨0, .reference 8⟩], some 4, some 2, some 3⟩
], []⟩

private def nestedCapture : Graph.Capture := ⟨0, some 9, 2, some 2, []⟩

private def nestedObservation : Except Invalid (List NodeId) := do
  let (store, capture) ← instantiate nestedStore nestedCapture
  let .continuation position ← fromOption (store.lookup (← fromOption capture.capture .reference)) .reference | throw .type
  let [some left, some right] := position.arguments | throw .type
  let left ← valueReference left
  let right ← valueReference right
  let .multiTemplate inner ← fromOption (store.lookup left) .reference | throw .type
  let .attachment handler outer _ _ _ ← fromOption (store.lookup inner.delimiter) .reference | throw .type
  let .handler _ _ _ region ← fromOption (store.lookup handler) .reference | throw .type
  let .region _ outside _ ← fromOption (store.lookup (← fromOption region .scope)) .reference | throw .type
  let .attachment originalHandler _ _ _ _ ← fromOption (store.lookup capture.delimiter) .reference | throw .type
  return [left, right, ← fromOption outer .scope, capture.delimiter, ← fromOption region .scope,
    ← fromOption position.region .scope, ← fromOption outside .scope, originalHandler]

/-- Both aliases acquire the same fresh nested template; its borrowed local
region and attachment change together, while the outside region and selected
handler activation keep their original identities. -/
theorem dormant_nested_template_and_aliases_are_rebased :
    nestedObservation = .ok [14, 14, 13, 13, 12, 12, 0, 1] := by rfl

private def cellStore : Store [] := ⟨[
  .region 0 none [],
  .handler 0 [] none (some 0),
  .attachment 1 none none .suspended (some 0),
  .region 1 (some 0) [],
  .regionScope 0 3 (some 2),
  .cell 0 0 (some ⟨0, .scalar (Vector.replicate 8 0)⟩),
  .cell 0 3 (some ⟨0, .scalar (Vector.replicate 8 0)⟩),
  .aggregate 0 0 [⟨0, .reference 5⟩, ⟨0, .reference 6⟩, ⟨0, .reference 6⟩],
  .continuation ⟨0, [some ⟨0, .reference 7⟩], some 4, some 2, some 3⟩
], []⟩

private def cellObservation : Except Invalid (List NodeId) := do
  let (store, capture) ← instantiate cellStore ⟨0, some 8, 2, some 2, []⟩
  let .continuation saved ← fromOption (store.lookup (← fromOption capture.capture .reference)) .reference | throw .type
  let [some aggregate] := saved.arguments | throw .type
  let aggregate ← valueReference aggregate
  let .aggregate _ _ fields ← fromOption (store.lookup aggregate) .reference | throw .type
  return aggregate :: (← fields.mapM valueReference)

theorem cloning_copies_local_cells_and_preserves_outside_cells :
    cellObservation = .ok [14, 5, 13, 13] := by rfl

end BoundaryV2.Profile.Target.Machine.Clone
