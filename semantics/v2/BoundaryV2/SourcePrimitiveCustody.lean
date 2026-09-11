import BoundaryV2.SourceCustodyAlignment
import BoundaryV2.SourceCloneSafety

namespace BoundaryV2.Profile.Source.Machine

theorem referencesSatisfy_owned (property : CustodyToken → NodeId → Prop) (value : SemanticValue) :
    Primitives.ReferencesSatisfy (fun _ node token => ∀ owned ∈ token.toList, property owned node) value ↔
      ∀ pair ∈ ownedReferences value, property pair.1 pair.2 := by
  cases value with
  | scalar _ _ | blob _ _ => simp [Primitives.ReferencesSatisfy, ownedReferences]
  | reference _ _ token => cases token <;> simp [Primitives.ReferencesSatisfy, ownedReferences]
  | product _ fields | sequence _ fields =>
    simp only [Primitives.ReferencesSatisfy, ownedReferences]
    constructor
    · intro holds pair member
      obtain ⟨child, childMember, pairMember⟩ := List.mem_flatMap.mp member
      exact (referencesSatisfy_owned property child).mp (holds child childMember) pair pairMember
    · intro holds child childMember
      apply (referencesSatisfy_owned property child).mpr
      intro pair member
      exact holds pair (List.mem_flatMap.mpr ⟨child, childMember, member⟩)
  | variant _ _ payload =>
    simpa only [Primitives.ReferencesSatisfy, ownedReferences] using referencesSatisfy_owned property payload
termination_by sizeOf value
decreasing_by
  all_goals subst value
  all_goals simp_wf
  all_goals first | omega | exact Nat.lt_trans (List.sizeOf_lt_of_mem childMember) (by omega)

theorem referencesSatisfy_alignment (book : Custody.Book) (value : SemanticValue) :
    Primitives.ReferencesSatisfy (fun _ node token => ∀ owned ∈ token.toList,
      ∀ entry ∈ book.entries, entry.token = owned → entry.object = node) value ↔ ValueAligned book value :=
  referencesSatisfy_owned (fun token node => ∀ entry ∈ book.entries, entry.token = token → entry.object = node) value

theorem referencesSatisfy_token_bounds (supply : Nat) (value : SemanticValue) :
    Primitives.ReferencesSatisfy (fun _ _ token => ∀ owned ∈ token.toList, owned.value < supply) value ↔
      ValueTokensBounded supply value := by
  rw [referencesSatisfy_owned]
  constructor
  · intro holds token member
    rw [← ownedReferences_tokens] at member
    obtain ⟨pair, pairMember, rfl⟩ := List.mem_map.mp member
    exact holds pair pairMember
  · intro holds pair member
    apply holds pair.1
    rw [← ownedReferences_tokens]
    exact List.mem_map.mpr ⟨pair, member, rfl⟩

/-- All primitive opcodes use the shared dispatch proof, including projections,
optional container results, and mutations of finite value trees. Stateful graph
actions are not successful pure values and are handled by the heap machine. -/
theorem primitive_preserves_alignment (book : Custody.Book) (schemas : List (Schema .source))
    (constants : List SemanticValue) (opcode : Opcode) (schema : SchemaId .source) (immediate : Nat)
    (operands : List SemanticValue) (result : SemanticValue)
    (constantsAligned : ∀ value ∈ constants, ValueAligned book value)
    (operandsAligned : ∀ value ∈ operands, ValueAligned book value)
    (accepted : Primitives.evaluate schemas constants opcode schema immediate operands = .ok (.value result)) :
    ValueAligned book result := by
  apply (referencesSatisfy_alignment book result).mp
  exact Primitives.evaluate_preserves_references _ _ _ _ _ _ _ _
    (fun value member => (referencesSatisfy_alignment book value).mpr (constantsAligned value member))
    (fun value member => (referencesSatisfy_alignment book value).mpr (operandsAligned value member)) accepted

theorem primitive_preserves_token_bounds (supply : Nat) (schemas : List (Schema .source))
    (constants : List SemanticValue) (opcode : Opcode) (schema : SchemaId .source) (immediate : Nat)
    (operands : List SemanticValue) (result : SemanticValue)
    (constantsBounded : ∀ value ∈ constants, ValueTokensBounded supply value)
    (operandsBounded : ∀ value ∈ operands, ValueTokensBounded supply value)
    (accepted : Primitives.evaluate schemas constants opcode schema immediate operands = .ok (.value result)) :
    ValueTokensBounded supply result := by
  apply (referencesSatisfy_token_bounds supply result).mp
  exact Primitives.evaluate_preserves_references _ _ _ _ _ _ _ _
    (fun value member => (referencesSatisfy_token_bounds supply value).mpr (constantsBounded value member))
    (fun value member => (referencesSatisfy_token_bounds supply value).mpr (operandsBounded value member)) accepted

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β)
    (result : β) : value.bind next = .ok result ↔
      ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem consumeBook_preserves_alignment (before after : Custody.Book) (tokens : List CustodyToken)
    (owner : Custody.Owner) (value : SemanticValue)
    (accepted : Custody.consume before tokens owner = some after) (aligned : ValueAligned before value) :
    ValueAligned after value := by
  unfold Custody.consume at accepted
  split at accepted <;> try contradiction
  cases accepted
  exact alignment_after_removal _ _ _ (fun _ member => (List.mem_filter.mp member).1) aligned

/-- Atomic primitive commit changes owners and consumes discarded tokens. It
does not alter any surviving token's physical object identity. This applies
also to lexical remnants not selected as the primitive's result. -/
theorem commitPure_preserves_alignment (state : State) (opcode : Opcode) (operands : List Located)
    (result value : SemanticValue) (after : Transition)
    (accepted : commitPure state opcode operands result = .ok after)
    (aligned : ValueAligned state.heap.custody value) : ValueAligned after.state.heap.custody value := by
  simp only [commitPure, bind] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → temporary_retains_custody,
    → finishTemporary_retains_custody, → moveValues_preserves_alignment, → consumeBook_preserves_alignment]

theorem commitPure_delivers_result (state : State) (opcode : Opcode) (operands : List Located)
    (result : SemanticValue) (after : Transition)
    (accepted : commitPure state opcode operands result = .ok after) :
    ∃ owner, after.state.control = .delivered ⟨result, owner⟩ := by
  have finish (state : State) (value : Located) (after : Transition)
      (accepted : finishTemporary state value = .ok after) : after.state.control = .delivered value := by
    unfold finishTemporary at accepted
    split at accepted <;> try contradiction
    cases accepted; rfl
  simp only [commitPure, bind] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok]

theorem primitive_commit_delivers_aligned_result (state : State) (context : Context) (opcode : Opcode)
    (schema : SchemaId .source) (immediate : Nat) (operands : List Located)
    (result : SemanticValue) (after : Transition)
    (constantsAligned : ∀ value ∈ context.executionConstants, ValueAligned state.heap.custody value)
    (operandsAligned : ∀ value ∈ operands, ValueAligned state.heap.custody value.value)
    (evaluated : Primitives.evaluate context.source.schemas context.executionConstants opcode schema immediate
      (operands.map Located.value) = .ok (.value result))
    (committed : commitPure state opcode operands result = .ok after) :
    (∃ owner, after.state.control = .delivered ⟨result, owner⟩) ∧
      ValueAligned after.state.heap.custody result := by
  refine ⟨commitPure_delivers_result _ _ _ _ _ committed, ?_⟩
  apply commitPure_preserves_alignment _ _ _ _ _ _ committed
  apply primitive_preserves_alignment _ _ _ _ _ _ _ _ constantsAligned ?_ evaluated
  intro value member
  obtain ⟨located, locatedMember, rfl⟩ := List.mem_map.mp member
  exact operandsAligned located locatedMember

end BoundaryV2.Profile.Source.Machine
