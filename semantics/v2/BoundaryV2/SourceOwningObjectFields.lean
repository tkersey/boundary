import BoundaryV2.SourceObjectOwnerExecution
import BoundaryV2.SourceOwningFields

namespace BoundaryV2.Profile.Source.Machine
namespace OwningFields

def CellFree : Object → Prop
  | .cell _ _ _ content => ownedTokens content.value = []
  | _ => True

def objectEntries (book : Custody.Book) (stored : Object) : List Custody.Entry :=
  (object stored).flatMap (live book)

theorem live_empty_of_token_free (book : Custody.Book) (field : Located)
    (free : ownedTokens field.value = []) : live book field = [] := by
  have empty : ownedReferences field.value = [] :=
    List.map_eq_nil_iff.mp ((ownedReferences_tokens field.value).trans free)
  simp [live, empty]

theorem closure_owners_unique (node : NodeId) (schema : SchemaId .source)
    (function : FunctionId .source) (bindings : Environment)
    (formed : ObjectOwners.Layout node (.closure schema function bindings)) :
    (bindings.map fun binding => binding.located.owner).Nodup := by
  apply List.pairwise_iff_getElem.mpr
  intro first second firstBound secondBound earlier equal
  have firstIn : first < bindings.length := by simpa using firstBound
  have secondIn : second < bindings.length := by simpa using secondBound
  have firstOwner := formed first bindings[first] (List.getElem?_eq_getElem firstIn)
  have secondOwner := formed second bindings[second] (List.getElem?_eq_getElem secondIn)
  simp only [List.getElem_map, firstOwner, secondOwner, Custody.Owner.closure.injEq] at equal
  omega

theorem object_tokens_unique (book : Custody.Book) (node : NodeId) (stored : Object)
    (formed : ObjectOwners.Layout node stored) (cellFree : CellFree stored)
    (linear : ∀ field ∈ object stored, (ownedTokens field.value).Nodup) :
    ((objectEntries book stored).map Custody.Entry.token).Nodup := by
  cases stored <;> simp only [objectEntries, object, List.flatMap_nil, List.map_nil] <;> try exact List.nodup_nil
  case closure schema function bindings =>
    apply unique_owners_give_unique_live_tokens book _ ?_ linear
    simpa only [object, List.map_map, Function.comp_def] using closure_owners_unique node schema function bindings formed
  case cell identity schema region content =>
    simp only [List.flatMap_cons, List.flatMap_nil, List.append_nil, live_empty_of_token_free book content cellFree]
    exact List.nodup_nil
  all_goals
    apply unique_owners_give_unique_live_tokens book _ (by simp [object]) linear

theorem object_token_owner (book : Custody.Book) (node : NodeId) (stored : Object) (token : CustodyToken)
    (formed : ObjectOwners.Layout node stored) (cellFree : CellFree stored)
    (member : token ∈ (objectEntries book stored).map Custody.Entry.token) :
    ∃ index, Custody.owns book token (.closure node index) := by
  simp only [objectEntries, List.map_flatMap, List.mem_flatMap] at member
  obtain ⟨field, fieldAt, member⟩ := member
  have held := live_token_held book field token member
  cases stored <;> simp only [object, List.not_mem_nil] at fieldAt
  case closure schema function bindings =>
    obtain ⟨binding, bindingAt, rfl⟩ := List.mem_map.mp fieldAt
    obtain ⟨index, atIndex⟩ := List.mem_iff_getElem?.mp bindingAt
    exact ⟨index, (formed index binding atIndex) ▸ held⟩
  case cell identity schema region content =>
    have equal : field = content := List.mem_singleton.mp fieldAt
    subst field
    simp only [live_empty_of_token_free book content cellFree, List.map_nil, List.not_mem_nil] at member
  all_goals
    cases List.mem_singleton.mp fieldAt
    exact ⟨0, formed ▸ held⟩


theorem heap_object_tokens_unique (store : Heap) (formed : ObjectOwners.Valid store)
    (cellFree : ∀ node stored, store.lookup node = some stored → CellFree stored)
    (linear : ∀ node stored, store.lookup node = some stored →
      ∀ field ∈ object stored, (ownedTokens field.value).Nodup) :
    ((store.objects.flatMap fun entry => entry.toList.flatMap (objectEntries store.custody)).map Custody.Entry.token).Nodup := by
  let tokens (entry : Option Object) := entry.toList.flatMap (fun stored => (objectEntries store.custody stored).map Custody.Entry.token)
  have indexed : (store.objects.zipIdx.flatMap fun pair => tokens pair.1).Nodup := by
    apply List.pairwise_flatMap.mpr
    refine ⟨?_, ?_⟩
    · rintro ⟨entry, index⟩ member
      have atIndex := List.mk_mem_zipIdx_iff_getElem?.mp member
      cases entry with
      | none => exact List.nodup_nil
      | some stored =>
        have found : store.lookup ⟨index⟩ = some stored := by simp [Heap.lookup, atIndex]
        simpa only [List.Nodup, tokens, Option.toList_some, List.flatMap_cons, List.flatMap_nil, List.append_nil] using
          object_tokens_unique store.custody ⟨index⟩ stored (formed _ _ found) (cellFree _ _ found) (linear _ _ found)
    · have positions : List.Pairwise (fun (first second : Option Object × Nat) => first.2 ≠ second.2) store.objects.zipIdx := by
        apply List.pairwise_iff_getElem.mpr
        intro first second firstBound secondBound earlier equal
        simp only [List.getElem_zipIdx, Nat.zero_add] at equal
        omega
      apply positions.imp_of_mem
      rintro ⟨firstEntry, firstIndex⟩ ⟨secondEntry, secondIndex⟩ firstAt secondAt distinct firstToken firstTokenAt secondToken secondTokenAt equal
      have firstPosition := List.mk_mem_zipIdx_iff_getElem?.mp firstAt
      have secondPosition := List.mk_mem_zipIdx_iff_getElem?.mp secondAt
      cases firstEntry with
      | none => contradiction
      | some firstStored =>
        cases secondEntry with
        | none => contradiction
        | some secondStored =>
          have firstFound : store.lookup ⟨firstIndex⟩ = some firstStored := by simp [Heap.lookup, firstPosition]
          have secondFound : store.lookup ⟨secondIndex⟩ = some secondStored := by simp [Heap.lookup, secondPosition]
          obtain ⟨firstSlot, firstOwned⟩ := object_token_owner store.custody ⟨firstIndex⟩ firstStored firstToken
            (formed _ _ firstFound) (cellFree _ _ firstFound) (by simpa [tokens] using firstTokenAt)
          obtain ⟨secondSlot, secondOwned⟩ := object_token_owner store.custody ⟨secondIndex⟩ secondStored firstToken
            (formed _ _ secondFound) (cellFree _ _ secondFound) (by simpa [tokens, equal] using secondTokenAt)
          have owners := Custody.unique_custodian store.custody firstToken _ _ firstOwned secondOwned
          apply distinct
          exact congrArg Ref.value (Custody.Owner.closure.inj owners).1
  have projected : store.objects.zipIdx.map Prod.fst = store.objects := by simp
  have same : (store.objects.zipIdx.flatMap fun pair => tokens pair.1) = store.objects.flatMap tokens := by
    simpa only [List.flatMap_map] using congrArg (List.flatMap tokens) projected
  rw [same] at indexed
  simpa only [tokens, List.map_flatMap] using indexed

/-- Every heap object's live owning-field tokens are globally distinct.
The proof combines actual object addresses, per-value uniqueness, and the
copy-only cell declaration rule; no token set erases multiplicity. -/
theorem reachable_object_entries_are_unique (context : Context) (arguments : List SemanticValue)
    (before after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) :
    ((after.heap.objects.flatMap fun entry => entry.toList.flatMap (objectEntries after.heap.custody)).map Custody.Entry.token).Nodup := by
  apply heap_object_tokens_unique after.heap
    (ObjectOwners.initialized_execution_preserves_object_owners _ _ _ _ _ initialized steps)
  · intro node stored found
    cases stored <;> try trivial
    exact ObjectOwners.reachable_cell_contents_have_no_tokens _ _ _ _ _ initialized steps _ _ _ _ _ found
  · intro node stored found field member
    have values := ValueLinearity.initialized_execution_preserves_linearity _ _ _ _ _ initialized steps
    have fields := ValueInventory.lookup_preserves_all after node stored found _ values
    exact fields field.value (object_subset stored field member)


theorem heap_object_token_owner (store : Heap) (token : CustodyToken)
    (formed : ObjectOwners.Valid store)
    (cellFree : ∀ node stored, store.lookup node = some stored → CellFree stored)
    (member : token ∈ (store.objects.flatMap fun entry => entry.toList.flatMap
      (objectEntries store.custody)).map Custody.Entry.token) :
    ∃ node index stored, store.lookup node = some stored ∧ Custody.owns store.custody token (.closure node index) := by
  simp only [List.map_flatMap, List.mem_flatMap] at member
  obtain ⟨entry, entryAt, stored, storedAt, member⟩ := member
  obtain ⟨position, atPosition⟩ := List.mem_iff_getElem?.mp entryAt
  cases entry with
  | none => contradiction
  | some actual =>
    have equal : stored = actual := by simpa using storedAt
    subst stored
    have found : store.lookup ⟨position⟩ = some actual := by simp [Heap.lookup, atPosition]
    obtain ⟨index, owned⟩ := object_token_owner store.custody ⟨position⟩ actual token
      (formed _ _ found) (cellFree _ _ found) member
    exact ⟨⟨position⟩, index, actual, found, owned⟩

theorem scope_token_owner (store : Heap) (token : CustodyToken) (formed : HoldingOwners.Valid store)
    (member : token ∈ ((store.scopes.flatMap Scope.holdings).flatMap (live store.custody)).map Custody.Entry.token) :
    ∃ scope index, Custody.owns store.custody token (.lexical scope index) ∨
      Custody.owns store.custody token (.temporary scope index) := by
  simp only [List.map_flatMap, List.mem_flatMap] at member
  obtain ⟨field, ⟨scope, scopeAt, fieldAt⟩, member⟩ := member
  have owned := live_token_held store.custody field token member
  obtain ⟨index, _, location⟩ := (formed scope scopeAt).2 field fieldAt
  refine ⟨scope.id, index, ?_⟩
  rcases location with lexical | temporary
  · exact Or.inl (lexical ▸ owned)
  · exact Or.inr (temporary ▸ owned)

/-- Heap object fields and scope holdings cannot independently hold the same
live token. Their actual owner constructors separate the physical locations. -/
theorem reachable_object_and_scope_entries_are_unique (context : Context) (arguments : List SemanticValue)
    (before after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) :
    (((after.heap.objects.flatMap fun entry => entry.toList.flatMap (objectEntries after.heap.custody)) ++
      (after.heap.scopes.flatMap Scope.holdings).flatMap (live after.heap.custody)).map Custody.Entry.token).Nodup := by
  simp only [List.map_append]
  apply List.nodup_append.mpr
  refine ⟨reachable_object_entries_are_unique _ _ _ _ _ initialized steps,
    reachable_scope_entries_are_unique _ _ _ _ _ initialized steps, ?_⟩
  intro first firstAt second secondAt equal
  have formed := ObjectOwners.initialized_execution_preserves_object_owners _ _ _ _ _ initialized steps
  have free : ∀ node stored, after.heap.lookup node = some stored → CellFree stored := by
    intro node stored found
    cases stored <;> try trivial
    exact ObjectOwners.reachable_cell_contents_have_no_tokens _ _ _ _ _ initialized steps _ _ _ _ _ found
  obtain ⟨node, index, stored, _, objectOwner⟩ := heap_object_token_owner after.heap first formed free firstAt
  obtain ⟨scope, slot, scopeOwner⟩ := scope_token_owner after.heap first
    (HoldingOwners.initialized_execution_preserves_holding_owners _ _ _ _ _ initialized steps) (equal ▸ secondAt)
  rcases scopeOwner with lexical | temporary
  · have impossible := Custody.unique_custodian after.heap.custody first _ _ objectOwner lexical
    cases impossible
  · have impossible := Custody.unique_custodian after.heap.custody first _ _ objectOwner temporary
    cases impossible

end OwningFields
end BoundaryV2.Profile.Source.Machine
