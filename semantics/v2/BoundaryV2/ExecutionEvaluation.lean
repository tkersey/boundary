import BoundaryV2.ExecutionCertificate
import BoundaryV2.SnapshotCertificate
import BoundaryV2.SchemaClasses

namespace BoundaryV2.Profile.Target.Boundary

/-- A checked evaluation fragment of the existing internal dispatcher. A
fragment may end between rules; only `completeInternal` certifies a complete
segment ending at a real observable or terminal boundary. -/
def internalPrefix (context : Machine.Context) : Nat → Machine.State context.program →
    Except Machine.Invalid (Machine.Transition context.program)
  | 0, state => .ok ⟨state, []⟩
  | count + 1, state => do
    Machine.require (!stopped state) .witness
    let next ← Machine.tick context state
    let rest ← internalPrefix context count next.state
    pure ⟨rest.state, next.events ++ rest.events⟩

/-- Prefix composition retains the final stopping check of the original
complete evaluator and concatenates every actual event in order. -/
theorem completeInternal_prepend (context : Machine.Context) (count rest : Nat)
    (state : Machine.State context.program) (first last : Machine.Transition context.program)
    (prefixChecked : internalPrefix context count state = .ok first)
    (suffix : completeInternal context rest first.state = .ok last) :
    completeInternal context (count + rest) state = .ok ⟨last.state, first.events ++ last.events⟩ := by
  induction count generalizing state first with
  | zero =>
    cases prefixChecked
    simpa using suffix
  | succ count induction =>
    cases active : stopped state with
    | true => simp [internalPrefix, active, Machine.require, bind, Except.bind] at prefixChecked
    | false =>
      simp only [internalPrefix, active, Bool.not_false, Machine.require, ↓reduceIte, bind, Except.bind] at prefixChecked
      cases ticked : Machine.tick context state with
      | error error => simp [ticked] at prefixChecked
      | ok next =>
        simp only [ticked] at prefixChecked
        cases advanced : internalPrefix context count next.state with
        | error error => simp [advanced] at prefixChecked
        | ok middle =>
          simp only [advanced] at prefixChecked
          cases prefixChecked
          have combined := induction next.state middle advanced suffix
          simp [Nat.succ_add, completeInternal, active, Machine.require, bind, Except.bind,
            ticked, combined, List.append_assoc]
          rfl

theorem completeInternal_of_prefix (context : Machine.Context) (count : Nat)
    (state : Machine.State context.program) (result : Machine.Transition context.program)
    (prefixChecked : internalPrefix context count state = .ok result)
    (final : stopped result.state = true) : completeInternal context count state = .ok result := by
  have suffix : completeInternal context 0 result.state = .ok ⟨result.state, []⟩ := by
    simp [completeInternal, final, Machine.require, bind, Except.bind]
    rfl
  have combined := completeInternal_prepend context count 0 state result ⟨result.state, []⟩ prefixChecked suffix
  simpa using combined

end BoundaryV2.Profile.Target.Boundary


namespace BoundaryV2.Profile.SchemaDescriptor

private theorem mapChildren_leaf (shape : Schema .target)
    (leaf : SchemaAdmission.structuralChildren shape = []) (rename : SchemaId .target → SchemaId .target) :
    SchemaEquivalence.mapChildren rename shape = shape := by
  cases shape <;> simp_all [SchemaAdmission.structuralChildren, SchemaEquivalence.mapChildren]

private theorem label_leaf (shape other : Schema .target)
    (leaf : SchemaAdmission.structuralChildren shape = [])
    (same : SchemaEquivalence.label shape = SchemaEquivalence.label other) : other = shape := by
  cases shape <;> cases other <;>
    simp_all [SchemaAdmission.structuralChildren, SchemaEquivalence.label, SchemaEquivalence.mapChildren]

/-- Canonicalizing an external childless schema yields its complete one-node
shape, irrespective of the other (possibly recursive) schemas in the program. -/
theorem canonicalize_leaf (descriptor : Descriptor) (shape : Schema .target)
    (valid : SchemaAdmission.valid descriptor.types = true)
    (found : descriptor.types[descriptor.root.value]? = some shape)
    (leaf : SchemaAdmission.structuralChildren shape = [])
    (external : ∀ internal, shape ≠ .internal internal) :
    canonicalize descriptor = some ⟨0, [shape]⟩ := by
  have bounded := SchemaEquivalence.valid_has_bounded_children descriptor.types valid
  have related := classes_related descriptor.types bounded descriptor.root (List.getElem?_eq_some_iff.mp found).1
  obtain ⟨original, other, originalFound, otherFound, same, _⟩ :=
    SchemaEquivalence.bisimilar_is_bisimulation descriptor.types descriptor.root _ related.2
  have originalSame := Option.some.inj (found.symm.trans originalFound)
  subst original
  have otherSame := label_leaf shape other leaf same
  subst other
  have member : classes descriptor.types descriptor.root ∈
      (List.range descriptor.types.length).map (fun index => (⟨index⟩ : SchemaId .target)) := by
    exact List.mem_map.mpr ⟨_, List.mem_range.mpr related.1, rfl⟩
  have walked : walk descriptor.types (classes descriptor.types)
      ((List.range descriptor.types.length).map (fun index => ⟨index⟩))
      [classes descriptor.types descriptor.root] [] = some [classes descriptor.types descriptor.root] := by
    rw [walk]
    simp only [otherFound]
    cases shape <;> simp_all [SchemaAdmission.structuralChildren, walk]
  simp only [canonicalize, valid, Bool.not_true, Bool.false_eq_true, ↓reduceIte,
    walked, List.mapM_cons, List.mapM_nil, otherFound,
    mapChildren_leaf _ leaf, bind, Option.bind, pure]

end BoundaryV2.Profile.SchemaDescriptor


namespace BoundaryV2.Profile.Target.Boundary
open Machine (require fromOption)
/-- Compose the exact saved-state checks without repeating their reductions
inside the public boundary operation. -/
theorem finish_yielded_of_parts (image : Machine.ImageContext imageBytes programWitness)
    (state : Machine.State image.context.program) (witness : Graph.Admission.Witness)
    (normalized : Graph.State) (bytes : Bytes)
    (identityChecked : (state.identity == image.identity) = true)
    (clockChecked : (clock state).valid state.status = true)
    (noResult : state.result = none)
    (canonical : Graph.Snapshot.canonicalize state.raw = some normalized)
    (rawChecked : Images.rawState.valid normalized = true)
    (graphChecked : Graph.Admission.check image.context.program programWitness.borrows normalized witness = true)
    (yielded : state.status = .yielded)
    (encoded : Images.rawState.encode normalized = bytes) :
    finish image state witness = .ok (.yielded bytes) := by
  unfold finish
  rw [identityChecked, clockChecked, noResult]
  simp only [require, fromOption, bind, Except.bind, ↓reduceIte]
  rw [canonical]
  dsimp only
  rw [rawChecked, graphChecked, yielded, encoded]
  rfl
end BoundaryV2.Profile.Target.Boundary

namespace BoundaryV2.Profile.Target.Boundary
open Machine (require fromOption)
theorem finish_progressed_of_parts (image : Machine.ImageContext imageBytes programWitness)
    (state : Machine.State image.context.program) (witness : Graph.Admission.Witness)
    (normalized : Graph.State) (bytes : Bytes)
    (identityChecked : (state.identity == image.identity) = true)
    (clockChecked : (clock state).valid state.status = true)
    (noResult : state.result = none)
    (canonical : Graph.Snapshot.canonicalize state.raw = some normalized)
    (rawChecked : Images.rawState.valid normalized = true)
    (graphChecked : Graph.Admission.check image.context.program programWitness.borrows normalized witness = true)
    (progressed : state.status = .active ∨ state.status = .unwinding)
    (encoded : Images.rawState.encode normalized = bytes) :
    finish image state witness = .ok (.progressed bytes) := by
  unfold finish
  rw [identityChecked, clockChecked, noResult]
  simp only [require, fromOption, bind, Except.bind, ↓reduceIte]
  rw [canonical]
  dsimp only
  rw [rawChecked, graphChecked, encoded]
  rcases progressed with phase | phase
  all_goals rw [phase]; rfl

theorem finish_requested_of_parts (image : Machine.ImageContext imageBytes programWitness)
    (state : Machine.State image.context.program) (witness : Graph.Admission.Witness)
    (normalized : Graph.State) (bytes : Bytes) (pending : Protocol.Request)
    (identityChecked : (state.identity == image.identity) = true)
    (clockChecked : (clock state).valid state.status = true)
    (noResult : state.result = none)
    (canonical : Graph.Snapshot.canonicalize state.raw = some normalized)
    (rawChecked : Images.rawState.valid normalized = true)
    (graphChecked : Graph.Admission.check image.context.program programWitness.borrows normalized witness = true)
    (parked : state.status = .parked)
    (encoded : Images.rawState.encode normalized = bytes)
    (requested : request image.context.program normalized bytes = .ok pending)
    (requestChecked : (Images.rawRequest.valid pending && Protocol.requestHeaderValid pending) = true) :
    finish image state witness = .ok (.requested bytes (Images.rawRequest.encode pending)) := by
  unfold finish
  rw [identityChecked, clockChecked, noResult]
  simp only [require, fromOption, bind, Except.bind, ↓reduceIte]
  rw [canonical]
  dsimp only
  rw [rawChecked, graphChecked, parked, encoded]
  simp only [↓reduceIte, requested, requestChecked]
  rfl

theorem finish_terminal_of_parts (image : Machine.ImageContext imageBytes programWitness)
    (state : Machine.State image.context.program) (witness : Graph.Admission.Witness)
    (result : Machine.Result) (outcome : Protocol.Outcome)
    (identityChecked : (state.identity == image.identity) = true)
    (clockChecked : (clock state).valid state.status = true)
    (resultKnown : state.result = some result)
    (terminalKnown : terminal image.context.program result = .ok outcome) :
    finish image state witness = .ok outcome := by
  simp [finish, identityChecked, clockChecked, resultKnown, terminalKnown, require, bind, Except.bind]
end BoundaryV2.Profile.Target.Boundary
