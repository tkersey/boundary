import BoundaryV2.SourceObligationEffects

namespace BoundaryV2.Profile.Source.Machine
namespace ObligationLocations

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

private theorem commute_prefixes (first second tail : List α) :
    (first ++ (second ++ tail)).Perm (second ++ (first ++ tail)) := by
  simpa only [List.append_assoc] using (List.perm_append_comm (l₁ := first) (l₂ := second)).append_right tail

private theorem flatMap_slot (values : List α) (index : Nat) (original replacement : α) (f : α → List β)
    (found : values[index]? = some original) :
    ∃ remainder, (values.flatMap f).Perm (f original ++ remainder) ∧
      ((values.set index replacement).flatMap f).Perm (f replacement ++ remainder) := by
  induction values generalizing index with
  | nil => simp at found
  | cons value values induction =>
    cases index with
    | zero =>
      cases found
      exact ⟨values.flatMap f, .refl _, .refl _⟩
    | succ index =>
      obtain ⟨remainder, before, after⟩ := induction index found
      exact ⟨f value ++ remainder,
        (before.append_left (f value)).trans (commute_prefixes _ _ _),
        (after.append_left (f value)).trans (commute_prefixes _ _ _)⟩

theorem replace_record_frame (records : List (Cleanup.Obligation .source)) (index : Nat)
    (original replacement : Cleanup.Obligation .source) (prior : Entry) (next tail : List Entry)
    (found : records[index]? = some original) (originalEntry : record original = [prior])
    (replacementEntries : record replacement = next)
    (valid : (prior :: tail).Perm (records.flatMap record)) :
    (next ++ tail).Perm ((records.set index replacement).flatMap record) := by
  obtain ⟨remainder, before, after⟩ := flatMap_slot records index original replacement record found
  have cancelled : tail.Perm remainder := List.Perm.cons_inv (by
    simpa only [originalEntry, List.singleton_append] using valid.trans before)
  exact (cancelled.append_left next).trans (by simpa only [replacementEntries] using after.symm)

theorem begin_frame (machine : State) (id : ObligationId) (invocation : InvocationId)
    (exit : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame)
    (before after : Cleanup.Obligation .source) (events : List Cleanup.Event)
    (found : machine.heap.obligations[id.value]? = some before)
    (identity : before.id = id) (accepted : Cleanup.begin before invocation = some (after, events))
    (stacked : machine.stack = .protection id :: tail) (valid : Valid machine) :
    Valid {machine with heap := {machine.heap with obligations := machine.heap.obligations.set id.value after}, stack := .cleanupReturn id invocation exit normal :: tail} := by
  unfold Cleanup.begin at accepted
  split at accepted <;> try contradiction
  rename_i pending
  cases accepted
  have next := replace_record_frame machine.heap.obligations id.value before {before with phase := .running invocation} ⟨id, none⟩
    [⟨id, some invocation⟩] (fields {machine with stack := tail}) found
    (by simp [record, pending, identity]) (by simp [record, identity]) (by
      simpa only [Valid, fields, stacked, List.flatMap_cons, frame, List.singleton_append, List.cons_append, List.nil_append, expected] using valid)
  simpa only [Valid, fields, frame, List.flatMap_cons, List.singleton_append, List.cons_append, List.nil_append, expected] using next

theorem complete_frame (machine : State) (id : ObligationId) (invocation : InvocationId)
    (exit : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame)
    (before after : Cleanup.Obligation .source) (events : List Cleanup.Event) (result : Except SemanticValue Unit)
    (found : machine.heap.obligations[id.value]? = some before)
    (identity : before.id = id) (accepted : Cleanup.complete before invocation result = some (after, events))
    (stacked : machine.stack = .cleanupReturn id invocation exit normal :: tail) (valid : Valid machine) :
    Valid {machine with heap := {machine.heap with obligations := machine.heap.obligations.set id.value after}, stack := tail} := by
  unfold Cleanup.complete at accepted
  split at accepted <;> try contradiction
  rename_i active phase
  split at accepted <;> try contradiction
  rename_i matched
  have same : active = invocation := by simpa using matched
  subst active
  cases result with
  | ok value =>
    cases value
    cases accepted
    have next := replace_record_frame machine.heap.obligations id.value before {before with phase := .completed} ⟨id, some invocation⟩ []
      (fields {machine with stack := tail}) found
      (by simp [record, phase, identity]) rfl (by
        simpa only [Valid, fields, stacked, List.flatMap_cons, frame, List.singleton_append, List.cons_append, List.nil_append, expected] using valid)
    simpa only [List.nil_append, Valid, fields, expected] using next
  | error failure =>
    cases accepted
    have next := replace_record_frame machine.heap.obligations id.value before {before with phase := .failed failure} ⟨id, some invocation⟩ []
      (fields {machine with stack := tail}) found
      (by simp [record, phase, identity]) rfl (by
        simpa only [Valid, fields, stacked, List.flatMap_cons, frame, List.singleton_append, List.cons_append, List.nil_append, expected] using valid)
    simpa only [List.nil_append, Valid, fields, expected] using next

theorem append_pending (machine : State) (id : ObligationId) (cleanup : SemanticValue)
    (resource : Option SemanticValue) (valid : Valid machine) :
    Valid {machine with heap := {machine.heap with obligations := machine.heap.obligations ++
      [⟨id, machine.scope, id.value, cleanup, resource, .pending⟩]}, stack := .protection id :: machine.stack} := by
  have next := (valid.cons ⟨id, none⟩).trans (List.perm_append_comm (l₁ := ([⟨id, none⟩] : List Entry)))
  simpa only [Valid, fields, expected, List.flatMap_cons, List.flatMap_append, List.flatMap_nil,
    frame, record, List.append_nil, List.singleton_append, List.cons_append, List.nil_append] using next

theorem installProtection_valid (machine : State) (context : Context) (body cleanup : Located)
    (arguments : List Located) (resource : Option Located) (loan : Option (RegionId .source)) (after : Transition)
    (accepted : installProtection machine context body cleanup arguments resource loan = .ok after) (valid : Valid machine) : Valid after.state := by
  simp only [installProtection, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, store, moved, accepted⟩ := accepted
  let identity : ObligationId := ⟨machine.heap.nextObligation⟩
  let obligation : Cleanup.Obligation .source := ⟨identity, machine.scope, identity.value,
    cleanup.value, resource.map Located.value, .pending⟩
  let kept := {store with obligations := store.obligations ++ [obligation], nextObligation := store.nextObligation + 1}
  have movedValid := move_valid _ _ _ _ moved valid
  have next : Valid {machine with heap := kept, stack := .protection identity :: machine.stack} :=
    append_pending {machine with heap := store} identity cleanup.value (resource.map Located.value) movedValid
  cases resource with
  | none =>
    cases loan <;> try contradiction
    simp only [pure, Except.pure, Except.bind] at accepted
    exact applyClosure_valid _ _ _ _ _ accepted next
  | some value =>
    cases loan with
    | none => contradiction
    | some descriptor =>
      simp only [except_bind_ok] at accepted
      obtain ⟨_, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
      obtain ⟨_, _, _, _, ⟨afterStore, borrowed⟩, allocated, _, rfl, applied⟩ := accepted
      let seedHeap : Heap := {kept with nextRegion := kept.nextRegion + 1, loans := kept.loans ++ [(⟨kept.nextRegion⟩, identity)]}
      have seed : Valid {machine with heap := seedHeap, stack := .region ⟨kept.nextRegion⟩ :: .protection identity :: machine.stack} := next
      have created := allocate_empty_valid _ _ _ _ _ _ _ allocated seed rfl
      exact applyClosure_valid _ _ _ _ _ applied created

theorem beginCleanup_valid (machine : State) (context : Context) (id : ObligationId)
    (exit : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (after : Transition)
    (accepted : beginCleanup machine context id exit normal tail = .ok after) (valid : Valid machine)
    (stacked : machine.stack = .protection id :: tail) : Valid after.state := by
  simp only [beginCleanup, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨original, originalAt, _, identity, ⟨record, events⟩, begun, _, _, _, _, _, _, result, applied, rfl⟩ := accepted
  have same : original.id = id := by simpa using (require_ok _ _ _ identity)
  have next := begin_frame _ _ _ (observedExit machine exit) normal _ _ _ _ originalAt same begun stacked valid
  exact applyClosure_valid _ _ _ _ result applied next

theorem indexed_obligation_id (heap : Heap) (id : ObligationId) (obligation : Cleanup.Obligation .source)
    (indexed : heap.Indexed) (found : heap.obligations[id.value]? = some obligation) : obligation.id = id := by
  have same := indexed.obligation_identity found
  cases identity : obligation.id
  cases id
  simp_all only

theorem resumeRelease_valid (machine : State) (released : AfterRelease) (valid : Valid machine) :
    Valid (resumeRelease machine released).state := by
  cases released <;> exact valid

theorem finishCleanup_valid (machine : State) (context : Context) (after : Transition)
    (accepted : finishCleanup machine context = .ok after) (valid : Valid machine)
    (indexed : machine.heap.Indexed) : Valid after.state := by
  unfold finishCleanup at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i id invocation exit normal tail stacked
  simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, original, originalAt, ⟨record, events⟩, completed, released, _, rfl⟩ := accepted
  have next := complete_frame _ _ _ _ _ _ _ _ _ _ originalAt
    (indexed_obligation_id _ _ _ indexed originalAt) completed stacked valid
  exact resumeRelease_valid _ _ next

theorem cleanupFailed_valid (machine : State) (id : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame)
    (inner : Cleanup.Exit .source) (after : Transition)
    (accepted : cleanupFailed machine id invocation outer normal tail inner = .ok after) (valid : Valid machine)
    (indexed : machine.heap.Indexed) (stacked : machine.stack = .cleanupReturn id invocation outer normal :: tail) : Valid after.state := by
  unfold cleanupFailed at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨original, originalAt, ⟨record, events⟩, completed, rfl⟩ := accepted
  have next := complete_frame _ _ _ _ _ _ _ _ _ _ originalAt
    (indexed_obligation_id _ _ _ indexed originalAt) completed stacked valid
  exact next

theorem cleanupAbandoned_valid (machine : State) (id : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame)
    (inner : Cleanup.Exit .source) (after : Transition)
    (accepted : cleanupAbandoned machine id invocation outer normal tail inner = .ok after) (valid : Valid machine)
    (indexed : machine.heap.Indexed) (stacked : machine.stack = .cleanupReturn id invocation outer normal :: tail) : Valid after.state := by
  simp only [cleanupAbandoned, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, original, originalAt, ⟨record, events⟩, completed, rfl⟩ := accepted
  have next := complete_frame _ _ _ _ _ _ _ _ _ _ originalAt
    (indexed_obligation_id _ _ _ indexed originalAt) completed stacked valid
  exact next

theorem finishCleanupUnwind_valid (machine : State) (id : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame)
    (inner : Cleanup.Exit .source) (after : Transition)
    (accepted : finishCleanupUnwind machine id invocation outer normal tail inner = .ok after) (valid : Valid machine)
    (indexed : machine.heap.Indexed) (stacked : machine.stack = .cleanupReturn id invocation outer normal :: tail) : Valid after.state := by
  unfold finishCleanupUnwind at accepted
  split at accepted <;> first
    | exact cleanupFailed_valid _ _ _ _ _ _ _ _ accepted valid indexed stacked
    | exact cleanupAbandoned_valid _ _ _ _ _ _ _ _ accepted valid indexed stacked
    | contradiction

theorem unwindStep_valid (machine : State) (context : Context) (after : Transition)
    (original : Cleanup.Exit .source) (unwinding : machine.control = .unwind original)
    (accepted : unwindStep machine context = .ok after) (valid : Valid machine)
    (indexed : machine.heap.Indexed) : Valid after.state := by
  simp only [unwindStep, unwinding, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨scope, _, accepted⟩ := accepted
  have pendingValid : Valid {machine with control := .discard (scope.holdings.flatMap (liveOwned machine.heap)) (.unwind (observedExit machine original))} :=
    valid
  cases stacked : machine.stack with
  | nil =>
    simp only [stacked] at accepted
    split at accepted
    · cases accepted
      simpa only [Valid, fields, stacked] using pendingValid
    · split at accepted <;> try contradiction
      all_goals cases accepted
      all_goals simpa only [Valid, fields, unwinding, stacked] using valid
  | cons saved tail =>
    have same (free : frame saved = []) :
        tail.flatMap frame = machine.stack.flatMap frame := by
      simp only [stacked, List.flatMap_cons, free, List.nil_append]
    have tailValid (free : frame saved = []) : Valid {machine with stack := tail} :=
      stack_valid machine tail valid (same free)
    cases saved <;> simp only [stacked] at accepted
    case invocation invocation parent =>
      split at accepted
      · cases accepted
        simpa only [Valid, fields, stacked] using pendingValid
      · cases accepted
        simpa only [Valid, fields] using tailValid rfl
    case lexical identity =>
      split at accepted
      · cases accepted
        simpa only [Valid, fields, stacked] using pendingValid
      · simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
        obtain ⟨_, _, parent, _, rfl⟩ := accepted
        simpa only [Valid, fields] using tailValid rfl
    case restore invocation parent =>
      cases accepted
      simpa only [Valid, fields] using tailValid rfl
    case binding binder body bindings parent =>
      cases accepted
      simpa only [Valid, fields] using tailValid rfl
    case operands intent bindings remaining evaluated =>
      cases accepted
      simpa only [Valid, fields] using tailValid rfl
    case handler active =>
      cases accepted
      simpa only [Valid, fields] using tailValid rfl
    case region region =>
      cases accepted
      simpa only [Valid, fields] using tailValid rfl
    case injection values =>
      cases accepted
      simpa only [Valid, fields] using tailValid rfl
    case protection identity =>
      exact beginCleanup_valid _ _ _ _ _ _ _ accepted valid stacked
    case cleanupReturn identity invocation outer normal =>
      exact finishCleanupUnwind_valid _ _ _ _ _ _ _ _ accepted valid indexed stacked
    case releaseReturn scope afterRelease =>
      cases accepted
      exact tailValid rfl
    case disposalReturn remaining afterRelease invocation parent =>
      cases primaryIs : (observedExit machine original).primary <;> simp only [primaryIs] at accepted
      all_goals cases afterRelease <;> simp only [pure, Except.pure, Except.bind] at accepted
      all_goals cases accepted
      all_goals simpa only [Valid, fields, frame, stacked, List.flatMap_cons, List.nil_append] using valid


theorem executeCleanupTerm_valid (machine : State) (context : Context) (after : Transition)
    (accepted : executeCleanupTerm machine context = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold executeCleanupTerm at accepted
  split at accepted <;> try contradiction
  rename_i term bindings operands executing
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    exact installProtection_valid _ _ _ _ _ _ _ _ accepted valid
  · split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, unitIndex, _, ⟨middle, owner⟩, reserved, rfl⟩ := accepted
    have next := temporary_valid _ _ _ reserved valid
    exact next

end ObligationLocations
end BoundaryV2.Profile.Source.Machine
