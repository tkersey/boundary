import BoundaryV2.Effects

namespace BoundaryV2.Effects

open Core Control

/-- Reconstruct both sides of the delimiter selected in the *effectful* stack. -/
def Selected.whole (selected : Selected A r a s b) : Stack A r a s b :=
  selected.inside.append
    (.push (.delimiter selected.identity selected.handler selected.env) selected.outsideStack)

theorem selection_reconstructs_stack (stack : Stack A r a s b) (identity : Nat)
    (selected : Selected A r a s b) (found : select identity stack = some selected) :
    selected.whole = stack := by
  induction stack using Stack.spine_induction with
  | done => simp [select] at found
  | push frame rest ih =>
    cases frame with
    | delimiter actual handler env =>
      simp only [select] at found
      split at found
      · cases found; rfl
      · simp only [Option.map_eq_some_iff] at found
        obtain ⟨inner, found, rfl⟩ := found
        exact congrArg (Stack.push (.delimiter actual handler env)) (ih inner found)
    | bind | region | post | «repeat» =>
      simp only [select, Option.map_eq_some_iff] at found
      obtain ⟨inner, found, rfl⟩ := found
      exact congrArg (Stack.push _) (ih inner found)

theorem selection_uses_identity (stack : Stack A r a s b) (identity : Nat)
    (selected : Selected A r a s b) (found : select identity stack = some selected) :
    selected.identity = identity := by
  induction stack using Stack.spine_induction with
  | done => simp [select] at found
  | push frame rest ih =>
    cases frame with
    | delimiter actual handler env =>
      simp only [select] at found
      split at found
      next same => cases found; exact same.symm
      next =>
        simp only [Option.map_eq_some_iff] at found
        obtain ⟨inner, found, rfl⟩ := found
        exact ih inner found
    | bind | region | post | «repeat» =>
      simp only [select, Option.map_eq_some_iff] at found
      obtain ⟨inner, found, rfl⟩ := found
      exact ih inner found

theorem selection_is_nearest (stack : Stack A r a s b) (identity : Nat)
    (selected : Selected A r a s b) (found : select identity stack = some selected) :
    identity ∉ selected.inside.attachments := by
  induction stack using Stack.spine_induction with
  | done => simp [select] at found
  | push frame rest ih =>
    cases frame with
    | delimiter actual handler env =>
      simp only [select] at found
      split at found
      · cases found; simp [Stack.attachments]
      next different =>
        simp only [Option.map_eq_some_iff] at found
        obtain ⟨inner, found, rfl⟩ := found
        simpa [Selected.prepend, Stack.attachments, different] using ih inner found
    | bind | region | post | «repeat» =>
      simp only [select, Option.map_eq_some_iff] at found
      obtain ⟨inner, found, rfl⟩ := found
      exact ih inner found

theorem selection_absent_iff (stack : Stack A r a s b) (identity : Nat) :
    select identity stack = none ↔ identity ∉ stack.attachments := by
  induction stack using Stack.spine_induction with
  | done => simp [select, Stack.attachments]
  | push frame rest ih =>
    cases frame with
    | delimiter actual handler env =>
      by_cases same : identity = actual
      · simp [select, Stack.attachments, same]
      · simp [select, Stack.attachments, same, ih]
    | bind | region | post | «repeat» => simpa [select, Stack.attachments] using ih

/-- Bounds cover capability aliases as well as delimiter identities, recursively
including dormant templates. Heap numbers and ordinary values are not names. -/
def NamesBelow (fresh : Nat) (names : List Nat) : Prop := ∀ id ∈ names, id < fresh

mutual
  def Frame.Below (fresh : Nat) : Frame A r a s b → Prop
    | .bind _ _ caps => NamesBelow fresh caps.toList
    | .delimiter identity _ _ => identity < fresh
    | .region | .post _ _ => True
    | .repeat template _ _ _ _ _ => template.Below fresh

  def Stack.Below (fresh : Nat) : Stack A r a s b → Prop
    | .done => True
    | .push frame rest => frame.Below fresh ∧ rest.Below fresh
end

theorem reserve_attachments_lower_bound (names : List Nat) (fresh : Nat) :
    fresh ≤ reserveAttachments names fresh := by
  induction names with
  | nil => exact Nat.le_refl fresh
  | cons id rest ih => exact Nat.le_trans ih (Nat.le_max_right _ _)

theorem reserve_attachments_above (names : List Nat) (fresh : Nat) :
    NamesBelow (reserveAttachments names fresh) names := by
  induction names with
  | nil => simp [NamesBelow]
  | cons id rest ih =>
    intro name member
    rcases List.mem_cons.mp member with rfl | member
    · simp only [reserveAttachments]; omega
    · have := ih name member
      simp only [reserveAttachments]; omega

theorem reserve_attachments_unchanged (names : List Nat) (fresh : Nat)
    (bound : NamesBelow fresh names) : reserveAttachments names fresh = fresh := by
  induction names with
  | nil => rfl
  | cons id rest ih =>
    have head := bound id (by simp)
    have tail : NamesBelow fresh rest := fun n h => bound n (List.mem_cons_of_mem id h)
    simp only [reserveAttachments, ih tail]
    omega

theorem rename_local_shared (ids : List Nat) (fresh identity : Nat)
    (shared : identity ∉ ids) : renameLocal ids fresh identity = identity := by
  simp [renameLocal, shared]

theorem rename_local_fresh (ids : List Nat) (fresh identity : Nat)
    (captured : identity ∈ ids) :
    fresh ≤ renameLocal ids fresh identity ∧ renameLocal ids fresh identity < fresh + ids.length := by
  have := List.idxOf_lt_length_of_mem captured
  simp only [renameLocal, if_pos captured]
  omega

theorem rename_local_bounded (ids : List Nat) (fresh identity : Nat) (old : identity < fresh) :
    renameLocal ids fresh identity < fresh + ids.length := by
  by_cases captured : identity ∈ ids
  · exact (rename_local_fresh ids fresh identity captured).2
  · rw [rename_local_shared ids fresh identity captured]; omega

/-- Finite substitution need not be injective on all Nat. It is injective on the
reachable old names below the reserved supply, which is the required domain. -/
theorem rename_local_injective_below (ids : List Nat) (fresh a b : Nat)
    (ha : a < fresh) (hb : b < fresh)
    (same : renameLocal ids fresh a = renameLocal ids fresh b) : a = b := by
  by_cases ca : a ∈ ids <;> by_cases cb : b ∈ ids
  · have index : ids.idxOf a = ids.idxOf b := by simpa [renameLocal, ca, cb] using same
    have ia := List.idxOf_lt_length_of_mem ca
    have ib := List.idxOf_lt_length_of_mem cb
    have ea := List.getElem_idxOf ia
    have eb := List.getElem_idxOf ib
    have ea' : ids[ids.idxOf b] = a := by simpa only [index] using ea
    exact ea'.symm.trans eb
  · have := (rename_local_fresh ids fresh a ca).1
    rw [rename_local_shared ids fresh b cb] at same
    omega
  · have := (rename_local_fresh ids fresh b cb).1
    rw [rename_local_shared ids fresh a ca] at same
    omega
  · simpa [renameLocal, ca, cb] using same

/-- Different activation intervals cannot share a freshly renamed delimiter. -/
theorem activation_intervals_are_disjoint (template : Stack A r a s b) (fresh a b : Nat)
    (ca : a ∈ template.attachments) (cb : b ∈ template.attachments) :
    renameLocal template.attachments fresh a ≠
      renameLocal template.attachments (template.activate fresh).2 b := by
  have left := (rename_local_fresh template.attachments fresh a ca).2
  have right := (rename_local_fresh template.attachments (template.activate fresh).2 b cb).1
  simp only [Stack.activate] at right ⊢
  omega

theorem stack_below_append (first : Stack A r a s b) (after : Stack A s b t c) (fresh : Nat) :
    (first.append after).Below fresh ↔ first.Below fresh ∧ after.Below fresh := by
  induction first using Stack.spine_induction with
  | done => simp [Stack.append, Stack.Below]
  | push frame rest ih => simp [Stack.append, Stack.Below, ih, and_assoc]

theorem stack_below_mono (stack : Stack A r a s b) (bound : stack.Below before)
    (grow : before ≤ after) : stack.Below after := by
  induction stack using Stack.rec
    (motive_1 := fun _ _ _ _ frame => frame.Below before → frame.Below after) with
  | bind body env caps => rename_i h; exact fun id member => Nat.lt_of_lt_of_le (h id member) grow
  | delimiter identity handler env => rename_i h; exact Nat.lt_of_lt_of_le h grow
  | region | post => trivial
  | «repeat» template heap arguments acc fold env ih => rename_i h; exact ih h
  | done => trivial
  | push frame rest ihFrame ihRest => exact ⟨ihFrame bound.1, ihRest bound.2⟩

theorem stack_rename_bounded (stack : Stack A r a s b) (rename : Nat → Nat)
    (bound : stack.Below before) (maps : ∀ id, id < before → rename id < after) :
    (stack.rename rename).Below after := by
  induction stack using Stack.rec
    (motive_1 := fun _ _ _ _ frame => frame.Below before → (frame.rename rename).Below after) with
  | bind body env caps =>
    rename_i h
    intro id member
    simp only [Vector.toList_map] at member
    obtain ⟨original, present, rfl⟩ := List.mem_map.mp member
    exact maps original (h original present)
  | delimiter identity handler env => rename_i h; exact maps identity h
  | region | post => trivial
  | «repeat» template heap arguments acc fold env ih => rename_i h; exact ih h
  | done => trivial
  | push frame rest ihFrame ihRest => exact ⟨ihFrame bound.1, ihRest bound.2⟩

theorem activation_preserves_attachment_bound (template : Stack A r a s b)
    (bound : template.Below fresh) : (template.activate fresh).1.Below (template.activate fresh).2 :=
  stack_rename_bounded template _ bound (rename_local_bounded template.attachments fresh)

theorem capture_preserves_attachment_bound (selected : Selected A r a s b) (mode : Mode)
    (bound : selected.whole.Below fresh) : (selected.capture mode).Below fresh := by
  have parts : selected.inside.Below fresh ∧ selected.identity < fresh ∧ selected.outsideStack.Below fresh := by
    simpa [Selected.whole, stack_below_append, Stack.Below, Frame.Below] using bound
  cases mode with
  | deep => simpa [Selected.capture, stack_below_append, Stack.Below, Frame.Below] using And.intro parts.1 parts.2.1
  | shallow => exact parts.1

def Focus.Below (fresh : Nat) : Focus A regions a → Prop
  | .code _ _ caps => NamesBelow fresh caps.toList
  | .value _ => True

def Status.Below (fresh : Nat) : Status A outside result → Prop
  | .running position => position.focus.Below fresh ∧ position.stack.Below fresh
  | .pending item => item.identity < fresh ∧ item.stack.Below fresh
  | .transferred item => item.identity < fresh ∧ item.stack.Below fresh
  | .returned _ | .disposed => True

/-- Separate from linear custody: the next allocation supply is above all
reachable attachment names, including aliases inside reusable templates. This
is not a complete serialized-graph admission or delimiter-uniqueness predicate. -/
def Machine.AttachmentsBounded (machine : Machine A outside result) : Prop :=
  machine.status.Below machine.freshAttachment

theorem initial_reserves_attachments (body : Flow A 0 caps [] result)
    (capabilities : Capabilities caps) (fresh : Nat) :
    (initial body capabilities fresh).AttachmentsBounded :=
  ⟨reserve_attachments_above capabilities.toList fresh, True.intro⟩

theorem return_preserves_attachment_bound (eval : Evaluator A) (machine : Machine A outside result)
    (value : Value a) (heap : Heap regions) (stack : Stack A regions a outside result)
    (bound : stack.Below machine.freshAttachment) :
    (returnValue eval machine value heap stack).AttachmentsBounded := by
  cases stack with
  | done => trivial
  | push frame rest =>
    cases frame with
    | bind => exact bound
    | delimiter | post => exact ⟨True.intro, bound.2⟩
    | region => cases heap; exact ⟨True.intro, bound.2⟩
    | «repeat» template frozen arguments acc fold env =>
      cases arguments with
      | nil => exact ⟨True.intro, bound.2⟩
      | cons argument arguments =>
        have grow : machine.freshAttachment ≤ (template.activate machine.freshAttachment).2 := by
          simp [Stack.activate]
        exact ⟨True.intro, (stack_below_append _ _ _).mpr
          ⟨activation_preserves_attachment_bound template bound.1,
            stack_below_mono template bound.1 grow, stack_below_mono rest bound.2 grow⟩⟩

theorem dispatch_preserves_attachment_bound (eval : Evaluator A) (machine : Machine A outside result)
    (payload : Nat) (heap : Heap regions) (selected : Selected A regions .number outside result)
    (bound : selected.whole.Below machine.freshAttachment) :
    (dispatch eval machine payload heap selected).AttachmentsBounded := by
  have parts : selected.inside.Below machine.freshAttachment ∧ selected.identity < machine.freshAttachment ∧
      selected.outsideStack.Below machine.freshAttachment := by
    simpa [Selected.whole, stack_below_append, Stack.Below, Frame.Below] using bound
  cases clause : selected.handler.clause with
  | dispose => simpa only [dispatch, clause, Machine.AttachmentsBounded, Status.Below, Focus.Below] using And.intro True.intro parts.2.2
  | once mode argument post =>
    simp only [dispatch, clause, Machine.AttachmentsBounded, Status.Below, Focus.Below]
    exact ⟨True.intro, (stack_below_append _ _ _).mpr
      ⟨capture_preserves_attachment_bound selected mode bound, True.intro, parts.2.2⟩⟩
  | multi mode arguments seed fold =>
    have captured := capture_preserves_attachment_bound selected mode bound
    simp only [dispatch, clause]
    split
    · exact ⟨True.intro, parts.2.2⟩
    · have grow : machine.freshAttachment ≤ ((selected.capture mode).activate machine.freshAttachment).2 := by
        simp [Stack.activate]
      exact ⟨True.intro, (stack_below_append _ _ _).mpr
        ⟨activation_preserves_attachment_bound (selected.capture mode) captured,
          stack_below_mono _ captured grow, stack_below_mono _ parts.2.2 grow⟩⟩

theorem tick_preserves_attachment_bound (eval : Evaluator A) (machine : Machine A outside result)
    (bound : machine.AttachmentsBounded) : (tick eval machine).AttachmentsBounded := by
  cases state : machine.status with
  | pending | returned | disposed | transferred => simpa [tick, state] using bound
  | running position =>
    have parts : position.focus.Below machine.freshAttachment ∧ position.stack.Below machine.freshAttachment := by
      simpa [Machine.AttachmentsBounded, state, Status.Below] using bound
    rcases position with ⟨regions, input, focus, heap, stack⟩
    cases focus with
    | value value =>
      simpa [tick, state] using return_preserves_attachment_bound eval machine value heap stack parts.2
    | code expression env caps =>
      cases expression with
      | pure | read | write =>
        simpa [tick, state, Machine.AttachmentsBounded, Status.Below, Focus.Below] using parts.2
      | bind =>
        simpa [tick, state, Machine.AttachmentsBounded, Status.Below, Focus.Below, Stack.Below, Frame.Below] using
          And.intro parts.1 (And.intro parts.1 parts.2)
      | branch condition yes no =>
        simpa only [tick, state, Machine.AttachmentsBounded, Status.Below, Focus.Below] using parts
      | region =>
        simpa only [tick, state, Machine.AttachmentsBounded, Status.Below, Focus.Below, Stack.Below, Frame.Below] using
          And.intro parts.1 (And.intro True.intro parts.2)
      | handle handler body =>
        have capsBound : NamesBelow (machine.freshAttachment + 1) caps.toList :=
          fun id member => Nat.lt_succ_of_lt (parts.1 id member)
        simp only [tick, state, Machine.AttachmentsBounded, Status.Below, Focus.Below, Stack.Below, Frame.Below]
        refine ⟨?_, Nat.lt_succ_self _, stack_below_mono stack parts.2 (by omega)⟩
        simpa [NamesBelow] using And.intro (Nat.lt_succ_self machine.freshAttachment) capsBound
      | perform index payload =>
        have capability : caps[index] < machine.freshAttachment := parts.1 _ (by simp)
        simp only [tick, state]
        split
        · exact ⟨capability, parts.2⟩
        next selected found =>
          apply dispatch_preserves_attachment_bound
          rw [selection_reconstructs_stack stack caps[index] selected found]
          exact parts.2

theorem transition_preserves_attachment_bound (eval : Evaluator A) (machine next : Machine A outside result)
    (input : Input) (bound : machine.AttachmentsBounded)
    (step : transition eval machine input = some next) : next.AttachmentsBounded := by
  cases input with
  | internal =>
    have equal : tick eval machine = next := Option.some.inj step
    exact equal ▸ tick_preserves_attachment_bound eval machine bound
  | resume value | dispose | transfer =>
    cases state : machine.status <;> try simp [transition, state] at step
    next pending =>
      have parts : pending.identity < machine.freshAttachment ∧ pending.stack.Below machine.freshAttachment := by
        simpa [Machine.AttachmentsBounded, state, Status.Below] using bound
      cases consumed : machine.ownership.consume pending.token with
      | none => simp [consumed] at step
      | some after =>
        simp [consumed] at step
        subst next
        first | exact ⟨True.intro, parts.2⟩ | exact True.intro | exact parts

end BoundaryV2.Effects
