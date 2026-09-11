import BoundaryV2.SourceObjectExecution
import BoundaryV2.SourceReferenceState

namespace BoundaryV2.Profile.Source.Machine
namespace ReferenceContracts

/-- Reference compatibility uses stored schema equality, or nominal catalog
identities for capabilities and regions. The stored object's own catalog kind
is governed separately by `ObjectSchemas` and `ClosureContracts`. -/
def Matches (schemas : List (Schema .source)) (schema : SchemaId .source) : Object → Prop
  | .closure stored _ _ | .cell _ stored _ _ | .package stored _ | .resource stored _
    | .borrow stored _ _ _ => stored = schema
  | .oneShot saved | .multiTemplate saved => saved.schema = schema
  | .capability _ effect => schemas[schema.value]? = some (.internal (.capability effect))
  | .region _ descriptor _ _ => schemas[schema.value]? = some (.internal (.region descriptor))

/-- Historical lexical values may retain spent tokens. Token-free references
remain usable; an owned reference is usable only while its token is live. -/
def Usable (book : Custody.Book) : Option CustodyToken → Prop
  | none => True
  | some token => ∃ entry ∈ book.entries, entry.token = token

def ReferenceValid (schemas : List (Schema .source)) (heap : Heap)
    (schema : SchemaId .source) (node : NodeId) (token : Option CustodyToken) : Prop :=
  Usable heap.custody token → ∃ stored, heap.lookup node = some stored ∧ Matches schemas schema stored

def ValueValid (schemas : List (Schema .source)) (heap : Heap) : SemanticValue → Prop :=
  Primitives.ReferencesSatisfy (ReferenceValid schemas heap)

theorem references_mono (value : SemanticValue)
    (first second : SchemaId .source → NodeId → Option CustodyToken → Prop)
    (holds : Primitives.ReferencesSatisfy first value)
    (implies : ∀ schema node token, first schema node token → second schema node token) :
    Primitives.ReferencesSatisfy second value := by
  cases value with
  | scalar _ _ | blob _ _ => simp [Primitives.ReferencesSatisfy]
  | reference schema node token =>
    simp only [Primitives.ReferencesSatisfy] at holds ⊢
    exact implies schema node token holds
  | product _ fields | sequence _ fields =>
    simp only [Primitives.ReferencesSatisfy] at holds ⊢
    exact fun child member => references_mono child first second (holds child member) implies
  | variant _ _ payload =>
    simp only [Primitives.ReferencesSatisfy] at holds ⊢
    exact references_mono payload first second holds implies
termination_by sizeOf value
decreasing_by
  all_goals subst value
  all_goals simp_wf
  all_goals first | omega | exact Nat.lt_trans (List.sizeOf_lt_of_mem member) (by omega)

theorem token_modes_agree (schemas : List (Schema .source)) (first second : SchemaId .source)
    (node : NodeId) (left right : Option CustodyToken) (stored : Object)
    (leftShape : ValueShape schemas (.reference first node left))
    (rightShape : ValueShape schemas (.reference second node right))
    (leftMatches : Matches schemas first stored) (rightMatches : Matches schemas second stored) :
    left.isSome = right.isSome := by
  have sameMode (schema : SchemaId .source) (inner : Internal .source)
      (first : ReferenceOwnership schemas schema inner node left)
      (second : ReferenceOwnership schemas schema inner node right) : left.isSome = right.isSome := by
    cases inner <;> simp only [ReferenceOwnership] at first second <;> grind only []
  cases leftShape with
  | reference leftFound leftOwned =>
    cases rightShape with
    | reference rightFound rightOwned =>
      by_cases equal : first = second
      · subst second
        have sameInner := Option.some.inj (leftFound.symm.trans rightFound)
        injection sameInner with innerSame
        rw [innerSame] at leftOwned
        exact sameMode _ _ leftOwned rightOwned
      · cases stored <;> simp only [Matches] at leftMatches rightMatches
        all_goals first
          | exact False.elim (equal (leftMatches.symm.trans rightMatches))
          | (rw [leftFound] at leftMatches
             rw [rightFound] at rightMatches
             cases leftMatches
             cases rightMatches
             simp only [ReferenceOwnership] at leftOwned rightOwned
             simp [leftOwned, rightOwned])

/-- An owned object cannot simultaneously be named by a well-typed reusable
reference. This is the exclusion used when retirement leaves a tombstone. -/
theorem reusable_reference_differs_from_owned (schemas : List (Schema .source)) (heap : Heap)
    (first second : SchemaId .source) (node ownedNode : NodeId) (token : CustodyToken)
    (reusableShape : ValueShape schemas (.reference first node none))
    (ownedShape : ValueShape schemas (.reference second ownedNode (some token)))
    (reusable : ∃ stored, heap.lookup node = some stored ∧ Matches schemas first stored)
    (owned : ∃ stored, heap.lookup ownedNode = some stored ∧ Matches schemas second stored) :
    node ≠ ownedNode := by
  intro same
  subst ownedNode
  obtain ⟨stored, found, compatible⟩ := reusable
  obtain ⟨other, otherFound, otherMatches⟩ := owned
  have equal : stored = other := Option.some.inj (found.symm.trans otherFound)
  subst other
  have modes := token_modes_agree schemas first second node none (some token) stored
    reusableShape ownedShape compatible otherMatches
  contradiction

theorem primitive_preserves_valid_references (schemas : List (Schema .source)) (heap : Heap)
    (constants : List SemanticValue) (opcode : Opcode) (schema : SchemaId .source) (immediate : Nat)
    (operands : List SemanticValue) (result : SemanticValue)
    (constantsValid : ∀ value ∈ constants, ValueValid schemas heap value)
    (operandsValid : ∀ value ∈ operands, ValueValid schemas heap value)
    (accepted : Primitives.evaluate schemas constants opcode schema immediate operands = .ok (.value result)) :
    ValueValid schemas heap result :=
  Primitives.evaluate_preserves_references _ _ _ _ _ _ _ _ constantsValid operandsValid accepted

private theorem bind_ok (value : Option α) (next : α → Option β) (result : β) :
    value.bind next = some result ↔ ∃ input, value = some input ∧ next input = some result := by
  cases value <;> simp

theorem retire_lookup (before after : Heap) (value : Located)
    (accepted : retireObject before value = some after) :
    ∃ schema node token, value.value = .reference schema node (some token) ∧
      after.lookup node = none ∧
      (∀ other : NodeId, other ≠ node → after.lookup other = before.lookup other) ∧
      after.custody.entries ⊆ before.custody.entries := by
  unfold retireObject at accepted
  split at accepted <;> try contradiction
  rename_i schema node token shape
  simp only [bind, bind_ok, pure, Option.some.injEq] at accepted
  obtain ⟨stored, found, middle, consumed, rfl⟩ := accepted
  simp only [consumeValue, bind, bind_ok, pure, Option.some.injEq] at consumed
  obtain ⟨book, consumed, rfl⟩ := consumed
  unfold Custody.consume at consumed
  split at consumed <;> try contradiction
  cases consumed
  refine ⟨schema, node, token, shape, ?_, ?_, ?_⟩
  · have bound : node.value < before.objects.length := by
      simp only [Heap.lookup, Option.bind_eq_some_iff] at found
      obtain ⟨entry, atNode, _⟩ := found
      exact (List.getElem?_eq_some_iff.mp atNode).choose
    simp [Heap.lookup, List.getElem?_set_self bound]
  · intro other different
    have indices : node.value ≠ other.value := by
      intro same
      apply different
      exact congrArg (fun number => (⟨number⟩ : NodeId)) same.symm
    simp [Heap.lookup, List.getElem?_set_ne indices]
  · exact fun _ member => (List.mem_filter.mp member).1

theorem retire_reference_valid (schemas : List (Schema .source)) (before after : Heap)
    (retired : Located) (schema : SchemaId .source) (node : NodeId) (token : Option CustodyToken)
    (accepted : retireObject before retired = some after)
    (live : before.CustodyLive)
    (retiredShape : ValueShape schemas retired.value)
    (retiredValid : ValueValid schemas before retired.value)
    (retiredAligned : ValueAligned before.custody retired.value)
    (shape : ValueShape schemas (.reference schema node token))
    (valid : ReferenceValid schemas before schema node token)
    (aligned : ValueAligned before.custody (.reference schema node token)) :
    ReferenceValid schemas after schema node token := by
  obtain ⟨ownedSchema, ownedNode, ownedToken, retiredValue, removed, unchanged, retained⟩ :=
    retire_lookup before after retired accepted
  have afterLive := retireObject_preserves_live_objects before after retired accepted live retiredAligned
  have afterAligned := retireObject_preserves_alignment before after retired (.reference schema node token) accepted aligned
  intro usable
  have originalUsable : Usable before.custody token := by
    cases token with
    | none => trivial
    | some token =>
      obtain ⟨entry, member, same⟩ := usable
      exact ⟨entry, retained member, same⟩
  obtain ⟨stored, found, compatible⟩ := valid originalUsable
  have different : node ≠ ownedNode := by
    cases token with
    | none =>
      have ownedUsable : Usable before.custody (some ownedToken) := by
        unfold retireObject at accepted
        simp only [retiredValue, bind, bind_ok, pure, Option.some.injEq] at accepted
        obtain ⟨_, _, middle, consumed, _⟩ := accepted
        simp only [consumeValue, retiredValue, ownedTokens, Option.toList_some,
          bind, bind_ok, pure, Option.some.injEq] at consumed
        obtain ⟨_, consumed, _⟩ := consumed
        unfold Custody.consume at consumed
        split at consumed <;> try contradiction
        rename_i admitted
        have has : Custody.has before.custody ownedToken retired.owner = true := by simpa using admitted
        obtain ⟨entry, member, same, _⟩ : ∃ entry ∈ before.custody.entries,
            entry.token = ownedToken ∧ entry.owner = retired.owner := by
          simpa [Custody.has, List.any_eq_true, Bool.and_eq_true] using has
        exact ⟨entry, member, same⟩
      have retiredReference : ReferenceValid schemas before ownedSchema ownedNode (some ownedToken) := by
        simpa only [ValueValid, retiredValue, Primitives.ReferencesSatisfy] using retiredValid
      exact reusable_reference_differs_from_owned schemas before schema ownedSchema node ownedNode ownedToken
        shape (retiredValue ▸ retiredShape) ⟨stored, found, compatible⟩ (retiredReference ownedUsable)
    | some token =>
      obtain ⟨entry, member, same⟩ := usable
      have atNode : entry.object = node := by
        apply afterAligned (token, node) ?_ entry member same
        simp [ownedReferences]
      have present := afterLive entry member
      rw [atNode] at present
      intro equal
      simp [equal, removed] at present
  exact ⟨stored, (unchanged node different).trans found, compatible⟩

/-- Reference kind and ownership mode do not require a wire-size bound on
unrelated scalar, blob, or aggregate data. Full value typing stays separate. -/
def ValueModes (schemas : List (Schema .source)) : SemanticValue → Prop :=
  Primitives.ReferencesSatisfy (fun schema node token => ValueShape schemas (.reference schema node token))

theorem typed_has_reference_modes (schemas : List (Schema .source)) (value : SemanticValue)
    (shape : ValueShape schemas value) : ValueModes schemas value := by
  induction shape with
  | scalar found checked | blob found checked => simp [ValueModes, Primitives.ReferencesSatisfy]
  | product found exactTypes children induction | sequence found bounded exactTypes children induction =>
    simpa only [ValueModes, Primitives.ReferencesSatisfy] using induction
  | variant found bounded exactType child induction =>
    simpa only [ValueModes, Primitives.ReferencesSatisfy] using induction
  | reference found owned =>
    simpa only [ValueModes, Primitives.ReferencesSatisfy, ValueShape] using Profile.Value.Typed.reference found owned

theorem references_transport₂ (value : SemanticValue)
    (first second result : SchemaId .source → NodeId → Option CustodyToken → Prop)
    (left : Primitives.ReferencesSatisfy first value)
    (right : Primitives.ReferencesSatisfy second value)
    (transport : ∀ schema node token, first schema node token → second schema node token → result schema node token) :
    Primitives.ReferencesSatisfy result value := by
  cases value with
  | scalar _ _ | blob _ _ => simp [Primitives.ReferencesSatisfy]
  | reference schema node token =>
    simp only [Primitives.ReferencesSatisfy] at left right ⊢
    exact transport schema node token left right
  | product _ fields | sequence _ fields =>
    simp only [Primitives.ReferencesSatisfy] at left right ⊢
    exact fun child member => references_transport₂ child first second result (left child member) (right child member) transport
  | variant _ _ payload =>
    simp only [Primitives.ReferencesSatisfy] at left right ⊢
    exact references_transport₂ payload first second result left right transport
termination_by sizeOf value
decreasing_by
  all_goals subst value
  all_goals simp_wf
  all_goals first | omega | exact Nat.lt_trans (List.sizeOf_lt_of_mem member) (by omega)

theorem typed_references_transport (schemas : List (Schema .source)) (value : SemanticValue)
    (first second result : SchemaId .source → NodeId → Option CustodyToken → Prop)
    (shape : ValueShape schemas value)
    (left : Primitives.ReferencesSatisfy first value)
    (right : Primitives.ReferencesSatisfy second value)
    (transport : ∀ schema node token, ValueShape schemas (.reference schema node token) →
      first schema node token → second schema node token → result schema node token) :
    Primitives.ReferencesSatisfy result value := by
  induction shape with
  | scalar found checked | blob found checked => simp [Primitives.ReferencesSatisfy]
  | product found exactTypes children induction | sequence found bounded exactTypes children induction =>
    simp only [Primitives.ReferencesSatisfy] at left right ⊢
    exact fun child member => induction child member (left child member) (right child member)
  | variant found bounded exactType child induction =>
    simp only [Primitives.ReferencesSatisfy] at left right ⊢
    exact induction left right
  | reference found owned =>
    simp only [Primitives.ReferencesSatisfy] at left right ⊢
    exact transport _ _ _ (.reference found owned) left right

theorem value_leaf_alignment (book : Custody.Book) (value : SemanticValue)
    (aligned : ValueAligned book value) :
    Primitives.ReferencesSatisfy (fun schema node token =>
      ValueAligned book (.reference schema node token)) value := by
  apply references_mono value _ _ ((referencesSatisfy_alignment book value).mpr aligned)
  intro schema node token checked pair member
  simp only [ownedReferences] at member
  obtain ⟨owned, tokenMember, rfl⟩ := List.mem_map.mp member
  exact checked owned tokenMember

theorem retire_value_valid_from_modes (schemas : List (Schema .source)) (before after : Heap)
    (retired : Located) (value : SemanticValue)
    (accepted : retireObject before retired = some after) (live : before.CustodyLive)
    (retiredShape : ValueShape schemas retired.value)
    (retiredValid : ValueValid schemas before retired.value)
    (retiredAligned : ValueAligned before.custody retired.value)
    (modes : ValueModes schemas value) (valid : ValueValid schemas before value)
    (aligned : ValueAligned before.custody value) : ValueValid schemas after value := by
  have both := references_transport₂ value _ _ _ valid (value_leaf_alignment _ _ aligned)
    (fun _ _ _ valid aligned => And.intro valid aligned)
  apply references_transport₂ value _ _ _ modes both
  intro schema node token shape ⟨valid, aligned⟩
  exact retire_reference_valid schemas before after retired schema node token accepted live
    retiredShape retiredValid retiredAligned shape valid aligned

theorem retire_value_valid (schemas : List (Schema .source)) (before after : Heap)
    (retired : Located) (value : SemanticValue)
    (accepted : retireObject before retired = some after) (live : before.CustodyLive)
    (retiredShape : ValueShape schemas retired.value)
    (retiredValid : ValueValid schemas before retired.value)
    (retiredAligned : ValueAligned before.custody retired.value)
    (shape : ValueShape schemas value) (valid : ValueValid schemas before value)
    (aligned : ValueAligned before.custody value) : ValueValid schemas after value := by
  exact retire_value_valid_from_modes schemas before after retired value accepted live
    retiredShape retiredValid retiredAligned (typed_has_reference_modes _ _ shape) valid aligned

theorem reference_free_valid (schemas : List (Schema .source)) (heap : Heap) (value : SemanticValue)
    (free : valueReferences value = []) : ValueValid schemas heap value := by
  cases value with
  | scalar _ _ | blob _ _ => simp [ValueValid, Primitives.ReferencesSatisfy]
  | reference _ _ _ => simp [valueReferences] at free
  | product _ fields | sequence _ fields =>
    simp only [valueReferences, List.flatMap_eq_nil_iff] at free
    simp only [ValueValid, Primitives.ReferencesSatisfy]
    exact fun child member => reference_free_valid schemas heap child (free child member)
  | variant _ _ payload =>
    simp only [valueReferences] at free
    simpa only [ValueValid, Primitives.ReferencesSatisfy] using reference_free_valid schemas heap payload free
termination_by sizeOf value
decreasing_by
  all_goals subst value
  all_goals simp_wf
  all_goals first | omega | exact Nat.lt_trans (List.sizeOf_lt_of_mem member) (by omega)

theorem initial_references_valid (context : Context) (arguments : List SemanticValue) (machine : State)
    (accepted : initial context arguments = .ok machine) :
    ValueInventory.All (ValueValid context.source.schemas machine.heap) machine := by
  have free := ValueInventory.initial_has_no_runtime_handles context arguments machine accepted
  exact fun value member => reference_free_valid _ _ value (free value member).1

theorem external_references_valid (machine : State) (context : Context) (action : External)
    (after : Transition) (accepted : external machine context action = .ok after)
    (valid : ValueInventory.All (ValueValid context.source.schemas machine.heap) machine) :
    ValueInventory.All (ValueValid context.source.schemas after.state.heap) after.state := by
  obtain ⟨objects, custody, _⟩ := external_retains_reference_custody machine context action after accepted
  have same (value : SemanticValue) (holds : ValueValid context.source.schemas machine.heap value) :
      ValueValid context.source.schemas after.state.heap value := by
    apply references_mono value _ _ holds
    intro schema node token checked
    simpa only [ReferenceValid, Heap.lookup, objects, custody] using checked
  apply ValueInventory.external_preserves_all machine context action after accepted _
    (ValueInventory.all_mono _ _ machine valid same)
  intro value admitted
  exact reference_free_valid _ _ value (external_value_has_no_runtime_handles _ _ admitted).1

end ReferenceContracts
end BoundaryV2.Profile.Source.Machine
