import BoundaryV2.SourceObligationExecution

namespace BoundaryV2.Profile.Source.Machine
namespace BorrowRegistry

/-- A borrow names the protected resource of the exact loan selected by the
machine. Completed records may remain as historical storage; use checks its phase. -/
def Registered (heap : Heap) (resource : NodeId) (region : RegionInstanceId) : Prop :=
  ∃ id obligation schema token,
    (heap.loans.find? (fun entry => entry.1 == region)).map Prod.snd = some id ∧
    heap.obligations[id.value]? = some obligation ∧
    obligation.resource = some (.reference schema resource (some token))

def ObjectValid (heap : Heap) : Object → Prop
  | .borrow _ resource region _ => Registered heap resource region
  | _ => True

def Valid (heap : Heap) : Prop := ∀ entry ∈ heap.objects, ∀ stored ∈ entry, ObjectValid heap stored

def Tables (before after : Heap) : Prop :=
  (∀ region id, (before.loans.find? (fun entry => entry.1 == region)).map Prod.snd = some id →
    (after.loans.find? (fun entry => entry.1 == region)).map Prod.snd = some id) ∧
  (∀ (index : Nat) (obligation : Cleanup.Obligation .source), before.obligations[index]? = some obligation →
    ∃ next, after.obligations[index]? = some next ∧ next.resource = obligation.resource)

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

theorem Tables.refl (heap : Heap) : Tables heap heap :=
  ⟨fun _ _ found => found, fun _ obligation found => ⟨obligation, found, rfl⟩⟩

theorem Tables.trans (first : Tables before middle) (last : Tables middle after) : Tables before after := by
  refine ⟨fun region id found => last.1 _ _ (first.1 region id found), ?_⟩
  intro index obligation found
  obtain ⟨mid, midAt, same⟩ := first.2 index obligation found
  obtain ⟨next, nextAt, nextSame⟩ := last.2 index mid midAt
  exact ⟨next, nextAt, nextSame.trans same⟩

theorem Registered.mono (tables : Tables before after) (registered : Registered before resource region) :
    Registered after resource region := by
  obtain ⟨id, obligation, schema, token, loan, found, reference⟩ := registered
  obtain ⟨next, nextAt, same⟩ := tables.2 _ _ found
  exact ⟨id, next, schema, token, tables.1 _ _ loan, nextAt, same.trans reference⟩

theorem ObjectValid.mono (tables : Tables before after) (valid : ObjectValid before stored) : ObjectValid after stored := by
  cases stored <;> try trivial
  exact Registered.mono tables valid

theorem Valid.mono (before after : Heap) (valid : Valid before) (tables : Tables before after)
    (included : ∀ entry ∈ after.objects, ∀ stored ∈ entry, some stored ∈ before.objects) : Valid after := by
  intro entry member stored present
  exact (valid (some stored) (included entry member stored present) stored rfl).mono tables

theorem same_valid (before after : Heap) (valid : Valid before) (objects : after.objects = before.objects)
    (loans : after.loans = before.loans) (obligations : after.obligations = before.obligations) : Valid after := by
  simpa only [Valid, ObjectValid, Registered, objects, loans, obligations] using valid

theorem tables_same (before after : Heap) (loans : after.loans = before.loans)
    (obligations : after.obligations = before.obligations) : Tables before after := by
  simpa only [Tables, loans, obligations] using Tables.refl before

theorem append_obligation_tables (heap : Heap) (obligation : Cleanup.Obligation .source) :
    Tables heap {heap with obligations := heap.obligations ++ [obligation]} := by
  refine ⟨fun _ _ found => found, ?_⟩
  intro index original found
  exact ⟨original, by simpa [List.getElem?_append_left (List.getElem?_eq_some_iff.mp found).1] using found, rfl⟩

theorem append_loan_tables (heap : Heap) (loan : RegionInstanceId × ObligationId) :
    Tables heap {heap with loans := heap.loans ++ [loan]} := by
  refine ⟨?_, fun _ obligation found => ⟨obligation, found, rfl⟩⟩
  intro region id found
  obtain ⟨pair, present, rfl⟩ := Option.map_eq_some_iff.mp found
  simp only [List.find?_append, present]
  rfl

theorem replace_obligation_tables (heap : Heap) (index : Nat) (before after : Cleanup.Obligation .source)
    (found : heap.obligations[index]? = some before) (same : after.resource = before.resource) :
    Tables heap {heap with obligations := heap.obligations.set index after} := by
  refine ⟨fun _ _ found => found, ?_⟩
  intro other obligation atOther
  by_cases equal : other = index
  · subst other
    cases atOther.symm.trans found
    exact ⟨after, by simp [List.getElem?_eq_some_iff.mp found |>.1], same⟩
  · exact ⟨obligation, by simpa [List.getElem?_set, equal, Ne.symm equal] using atOther, rfl⟩

theorem same_objects_valid (before after : Heap) (valid : Valid before) (tables : Tables before after)
    (same : after.objects = before.objects) : Valid after := by
  apply Valid.mono before after valid tables
  intro entry member stored present
  cases entry <;> try contradiction
  cases present
  simpa only [same] using member

theorem lookup_valid (heap : Heap) (node : NodeId) (stored : Object) (valid : Valid heap)
    (found : heap.lookup node = some stored) : ObjectValid heap stored := by
  simp only [Heap.lookup, Option.bind_eq_some_iff] at found
  obtain ⟨entry, present, selected⟩ := found
  cases entry <;> try contradiction
  cases selected
  exact valid _ (List.mem_of_getElem? present) _ rfl

theorem move_valid (before after : Heap) (values : List Located) (receiver : Nat → Custody.Owner)
    (accepted : moveValues before values receiver = some after) (valid : Valid before) : Valid after := by
  simp only [moveValues, bind, pure, Option.bind_eq_some_iff, Option.some.injEq] at accepted
  obtain ⟨_, _, rfl⟩ := accepted
  exact valid

theorem consume_valid (before after : Heap) (value : Located)
    (accepted : consumeValue before value = some after) (valid : Valid before) : Valid after := by
  simp only [consumeValue, bind, pure, Option.bind_eq_some_iff, Option.some.injEq] at accepted
  obtain ⟨_, _, rfl⟩ := accepted
  exact valid

theorem temporary_valid (machine after : State) (owner : Custody.Owner)
    (accepted : temporary machine = .ok (after, owner)) (valid : Valid machine.heap) : Valid after.heap := by
  unfold temporary at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  cases accepted
  exact valid

theorem finishTemporary_valid (machine : State) (value : Located) (after : Transition)
    (accepted : finishTemporary machine value = .ok after) (valid : Valid machine.heap) : Valid after.state.heap := by
  unfold finishTemporary at accepted
  split at accepted <;> try contradiction
  cases accepted
  exact valid

theorem scopedValue_valid (machine : State) (value : SemanticValue) (after : Transition)
    (accepted : scopedValue machine value = .ok after) (valid : Valid machine.heap) : Valid after.state.heap := by
  simp only [scopedValue, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, owner⟩, reserved, finished⟩ := accepted
  exact finishTemporary_valid _ _ _ finished (temporary_valid _ _ _ reserved valid)

theorem allocate_valid (before after : Heap) (schema : SchemaId .source) (stored : Object)
    (owner : Custody.Owner) (exclusive : Bool) (value : Located)
    (accepted : allocateObject before schema stored owner exclusive = some (after, value))
    (valid : Valid before) (new : ObjectValid before stored) : Valid after := by
  cases exclusive <;> simp [allocateObject, Option.bind_eq_some_iff] at accepted
  all_goals first | obtain ⟨rfl, _⟩ := accepted | obtain ⟨_, _, rfl, _⟩ := accepted
  all_goals intro entry member value present
  all_goals rcases List.mem_append.mp member with old | added
  all_goals first
    | exact valid entry old value present
    | (cases List.mem_singleton.mp added; cases present; exact new)

theorem replace_valid (before after : Heap) (node : NodeId) (stored : Object)
    (accepted : replaceObject before node stored = some after) (valid : Valid before) (new : ObjectValid before stored) : Valid after := by
  unfold replaceObject at accepted
  split at accepted <;> try contradiction
  cases accepted
  intro entry member value present
  rcases List.mem_or_eq_of_mem_set member with old | equal
  · exact valid entry old value present
  · cases entry <;> try contradiction
    cases present
    cases Option.some.inj equal
    exact new

theorem retire_valid (before after : Heap) (value : Located)
    (accepted : retireObject before value = some after) (valid : Valid before) : Valid after := by
  unfold retireObject at accepted
  split at accepted <;> try contradiction
  simp only [bind, pure, Option.bind_eq_some_iff, Option.some.injEq] at accepted
  obtain ⟨_, _, middle, consumed, rfl⟩ := accepted
  have next := consume_valid _ _ _ consumed valid
  intro entry member stored present
  rcases List.mem_or_eq_of_mem_set member with old | equal
  · exact next entry old stored present
  · subst entry; contradiction

end BorrowRegistry
end BoundaryV2.Profile.Source.Machine
