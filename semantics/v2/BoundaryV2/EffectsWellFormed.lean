import BoundaryV2.EffectsActivation
import BoundaryV2.EffectsEvents
import BoundaryV2.EffectsIdentity

namespace BoundaryV2.Effects

open Core Control

mutual
  /-- A dormant template has its own delimiter spine. Its aliases are not
  additional live allocations. -/
  def Frame.Unique : Frame A r a s b → Prop
    | .repeat template _ _ _ _ _ => template.Unique
    | _ => True

  def Stack.Unique : Stack A r a s b → Prop
    | .done => True
    | .push frame rest =>
      frame.Unique ∧ rest.Unique ∧ (Stack.push frame rest).attachments.Nodup
end

/-- Every attachment occurrence, including dormant aliases, is reserved below
the supply. Distinctness applies to delimiter spines, not reference occurrences. -/
def Stack.IdentityWF (stack : Stack A r a s b) (fresh : Nat) : Prop :=
  (∀ identity ∈ stack.references, identity < fresh) ∧ stack.Unique

def Focus.IdentityWF (focus : Focus A r a) (fresh : Nat) : Prop := match focus with
  | .code _ _ capabilities => ∀ identity ∈ capabilities.toList, identity < fresh
  | .value _ => True

def Status.IdentityWF (status : Status A r a) (fresh : Nat) : Prop := match status with
  | .running position => position.focus.IdentityWF fresh ∧ position.stack.IdentityWF fresh
  | .pending request | .transferred request =>
    request.identity < fresh ∧ request.stack.IdentityWF fresh
  | .returned _ | .disposed => True

def Machine.IdentityWF (machine : Machine A r a) : Prop :=
  machine.status.IdentityWF machine.freshAttachment

/-- Types and cell scope are indexed by the actual state constructors. This
small model has no graph resources or cleanup obligations; their richer source
and target machines have separate preservation obligations. -/
def Machine.WellFormed (machine : Machine A r a) : Prop :=
  machine.Valid ∧ machine.IdentityWF

theorem Stack.attachments_append (first : Stack A r a s b) (second : Stack A s b t c) :
    (first.append second).attachments = first.attachments ++ second.attachments := by
  induction first using Stack.spine_induction with
  | done => rfl
  | push frame rest ih => cases frame <;> simp [Stack.append, Stack.attachments, ih]

theorem Stack.references_append (first : Stack A r a s b) (second : Stack A s b t c) :
    (first.append second).references = first.references ++ second.references := by
  induction first using Stack.spine_induction with
  | done => rfl
  | push frame rest ih => simp [Stack.append, Stack.references, ih, List.append_assoc]

theorem Stack.attachments_mem_references (stack : Stack A r a s b)
    (member : identity ∈ stack.attachments) : identity ∈ stack.references := by
  induction stack using Stack.spine_induction with
  | done => simp [Stack.attachments] at member
  | push frame rest ih =>
    cases frame <;> simp_all [Stack.attachments, Stack.references, Frame.references] <;> grind

theorem Stack.Unique.nodup (stack : Stack A r a s b) (unique : stack.Unique) :
    stack.attachments.Nodup := by
  cases stack with
  | done => simp [Stack.attachments]
  | push => exact unique.2.2

theorem Stack.Unique.append_iff (first : Stack A r a s b) (second : Stack A s b t c) :
    (first.append second).Unique ↔ first.Unique ∧ second.Unique ∧
      (∀ left ∈ first.attachments, ∀ right ∈ second.attachments, left ≠ right) := by
  induction first using Stack.spine_induction with
  | done => simp [Stack.append, Stack.Unique, Stack.attachments]
  | push frame rest ih =>
    simp only [Stack.append, Stack.Unique]
    rw [ih, ← Stack.append, Stack.attachments_append, List.nodup_append]
    constructor
    · rintro ⟨frameWF, ⟨restWF, secondWF, _⟩, spineWF, _, apart⟩
      exact ⟨⟨frameWF, restWF, spineWF⟩, secondWF, apart⟩
    · rintro ⟨⟨frameWF, restWF, spineWF⟩, secondWF, apart⟩
      have restApart : ∀ left ∈ rest.attachments, ∀ right ∈ second.attachments, left ≠ right := by
        intro left member right other
        exact apart left (by cases frame <;> simp [Stack.attachments, member]) right other
      exact ⟨frameWF, ⟨restWF, secondWF, restApart⟩, spineWF, Stack.Unique.nodup second secondWF, apart⟩

theorem Stack.IdentityWF.append_iff (first : Stack A r a s b) (second : Stack A s b t c) :
    (first.append second).IdentityWF fresh ↔
      first.IdentityWF fresh ∧ second.IdentityWF fresh ∧
        (∀ left ∈ first.attachments, ∀ right ∈ second.attachments, left ≠ right) := by
  simp only [Stack.IdentityWF, Stack.references_append, List.mem_append,
    Stack.Unique.append_iff]
  grind only

theorem Stack.IdentityWF.mono (stack : Stack A r a s b)
    (valid : stack.IdentityWF before) (larger : before ≤ after) : stack.IdentityWF after :=
  ⟨fun identity member => Nat.lt_of_lt_of_le (valid.1 identity member) larger, valid.2⟩

theorem Stack.attachments_rename (stack : Stack A r a s b) (rename : Nat → Nat) :
    (stack.rename rename).attachments = stack.attachments.map rename := by
  induction stack using Stack.spine_induction with
  | done => rfl
  | push frame rest ih => cases frame <;> simp [Stack.rename, Frame.rename, Stack.attachments, ih]

private theorem nodup_map_below (identities : List Nat) (unique : identities.Nodup)
    (bounded : ∀ identity ∈ identities, identity < fresh) (rename : Nat → Nat)
    (injective : ∀ left < fresh, ∀ right < fresh, rename left = rename right → left = right) :
    (identities.map rename).Nodup := by
  rw [List.Nodup, List.pairwise_map]
  exact List.Pairwise.imp_of_mem (fun leftMem rightMem different same =>
    different (injective _ (bounded _ leftMem) _ (bounded _ rightMem) same)) unique

theorem Stack.Unique.rename_below (stack : Stack A r a s b) (rename : Nat → Nat)
    (injective : ∀ left < fresh, ∀ right < fresh, rename left = rename right → left = right)
    (bounded : ∀ identity ∈ stack.references, identity < fresh) (unique : stack.Unique) :
    (stack.rename rename).Unique := by
  induction stack using Stack.rec
    (motive_1 := fun _ _ _ _ frame =>
      (∀ identity ∈ frame.references, identity < fresh) → frame.Unique → (frame.rename rename).Unique) with
  | bind | delimiter | region | post | done => trivial
  | «repeat» template heap arguments acc fold env ih => apply ih <;> assumption
  | push frame rest frameIH restIH =>
    have frameBound : ∀ identity ∈ frame.references, identity < fresh :=
      fun identity member => bounded identity (List.mem_append_left _ member)
    have restBound : ∀ identity ∈ rest.references, identity < fresh :=
      fun identity member => bounded identity (List.mem_append_right _ member)
    refine ⟨frameIH frameBound unique.1, restIH restBound unique.2.1, ?_⟩
    rw [← Stack.rename, Stack.attachments_rename]
    exact nodup_map_below _ unique.2.2
      (fun identity member => bounded identity (Stack.attachments_mem_references _ member)) rename injective

theorem renameLocal_injective_below (ids : List Nat) (fresh : Nat)
    (leftBound : left < fresh) (rightBound : right < fresh)
    (same : renameLocal ids fresh left = renameLocal ids fresh right) : left = right := by
  by_cases leftLocal : left ∈ ids
  · by_cases rightLocal : right ∈ ids
    · exact renameLocal_injective_on_binders _ _ _ _ leftLocal rightLocal same
    · have lower := (renameLocal_interval ids fresh left leftLocal).1
      rw [renameLocal_outside _ _ _ rightLocal] at same
      omega
  · rw [renameLocal_outside _ _ _ leftLocal] at same
    by_cases rightLocal : right ∈ ids
    · have lower := (renameLocal_interval ids fresh right rightLocal).1
      omega
    · simpa [renameLocal_outside _ _ _ rightLocal] using same

theorem Stack.IdentityWF.activate (template : Stack A r a s b)
    (valid : template.IdentityWF fresh) :
    (template.activate fresh).1.IdentityWF (template.activate fresh).2 := by
  refine ⟨?_, Stack.Unique.rename_below template _
    (fun _ left _ right same => renameLocal_injective_below _ _ left right same) valid.1 valid.2⟩
  rw [Stack.activate, renaming_covers_dormant_references]
  intro identity member
  obtain ⟨original, sourceMember, rfl⟩ := List.mem_map.mp member
  by_cases localId : original ∈ template.attachments
  · exact (renameLocal_interval _ _ _ localId).2
  · rw [renameLocal_outside _ _ _ localId]
    exact Nat.lt_of_lt_of_le (valid.1 original sourceMember) (Nat.le_add_right _ _)

theorem Stack.activation_separates_outside (template : Stack A r a s b)
    (outside : Stack A t c u d) (valid : outside.IdentityWF fresh) :
    ∀ left ∈ (template.activate fresh).1.attachments,
      ∀ right ∈ outside.attachments, left ≠ right := by
  simp only [Stack.activate, Stack.attachments_rename, List.mem_map]
  rintro left ⟨original, member, rfl⟩ right other same
  have lower := (renameLocal_interval template.attachments fresh original member).1
  have upper := valid.1 right (outside.attachments_mem_references other)
  omega

@[simp] theorem Stack.identityWF_done : (Stack.done : Stack A r a r a).IdentityWF fresh := by
  simp [Stack.IdentityWF, Stack.references, Stack.Unique]

@[simp] theorem Stack.identityWF_bind (body : Flow A r caps (a :: ctx) b)
    (env : Values ctx) (capabilities : Capabilities caps) (rest : Stack A r b s c) :
    (Stack.push (.bind body env capabilities) rest).IdentityWF fresh ↔
      (∀ identity ∈ capabilities.toList, identity < fresh) ∧ rest.IdentityWF fresh := by
  simp only [Stack.IdentityWF, Stack.references, Frame.references, List.mem_append,
    Stack.Unique, Frame.Unique, Stack.attachments, true_and]
  have spine := Stack.Unique.nodup rest
  grind only

@[simp] theorem Stack.identityWF_delimiter (identity : Nat) (handler : Handler A ctx a b)
    (env : Values ctx) (rest : Stack A r b s c) :
    (Stack.push (.delimiter identity handler env) rest).IdentityWF fresh ↔
      identity < fresh ∧ rest.IdentityWF fresh ∧ identity ∉ rest.attachments := by
  simp only [Stack.IdentityWF, Stack.references, Frame.references, List.singleton_append,
    List.mem_cons, Stack.Unique, Frame.Unique, Stack.attachments, true_and, List.nodup_cons]
  constructor
  · rintro ⟨bounded, unique, absent, _⟩
    exact ⟨bounded identity (.inl rfl), ⟨fun item member => bounded item (.inr member), unique⟩, absent⟩
  · rintro ⟨bound, ⟨bounded, unique⟩, absent⟩
    refine ⟨?_, unique, absent, Stack.Unique.nodup rest unique⟩
    intro item member
    rcases member with rfl | member
    · exact bound
    · exact bounded item member

@[simp] theorem Stack.identityWF_region (rest : Stack A r a s b) :
    (Stack.push .region rest).IdentityWF fresh ↔ rest.IdentityWF fresh := by
  simp only [Stack.IdentityWF, Stack.references, Frame.references, List.nil_append,
    Stack.Unique, Frame.Unique, Stack.attachments, true_and]
  have spine := Stack.Unique.nodup rest
  grind only

@[simp] theorem Stack.identityWF_post (expression : A (a :: ctx) b)
    (env : Values ctx) (rest : Stack A r b s c) :
    (Stack.push (.post expression env) rest).IdentityWF fresh ↔ rest.IdentityWF fresh := by
  simp only [Stack.IdentityWF, Stack.references, Frame.references, List.nil_append,
    Stack.Unique, Frame.Unique, Stack.attachments, true_and]
  have spine := Stack.Unique.nodup rest
  grind only

@[simp] theorem Stack.identityWF_repeat (template : Stack A r .number s a)
    (heap : LocalHeap r s) (arguments : List Nat) (acc : Value b)
    (fold : A (a :: b :: ctx) b) (env : Values ctx) (rest : Stack A s b t c) :
    (Stack.push (.repeat template heap arguments acc fold env) rest).IdentityWF fresh ↔
      template.IdentityWF fresh ∧ rest.IdentityWF fresh := by
  simp only [Stack.IdentityWF, Stack.references, Frame.references, List.mem_append,
    Stack.Unique, Frame.Unique, Stack.attachments]
  have spine := Stack.Unique.nodup rest
  grind only

theorem Stack.IdentityWF.activate_append (template : Stack A r a s b)
    (outside : Stack A s b t c) (templateWF : template.IdentityWF fresh)
    (outsideWF : outside.IdentityWF fresh) :
    ((template.activate fresh).1.append outside).IdentityWF (template.activate fresh).2 := by
  exact (Stack.IdentityWF.append_iff _ _).mpr
    ⟨templateWF.activate template, outsideWF.mono outside (Nat.le_add_right _ _),
      template.activation_separates_outside outside outsideWF⟩

theorem Selected.capture_and_outside (selected : Selected A r a s b) (mode : Mode)
    (valid : selected.whole.IdentityWF fresh) :
    (selected.capture mode).IdentityWF fresh ∧ selected.outsideStack.IdentityWF fresh ∧
      (∀ left ∈ (selected.capture mode).attachments,
        ∀ right ∈ selected.outsideStack.attachments, left ≠ right) := by
  obtain ⟨inside, rest, apart⟩ := (Stack.IdentityWF.append_iff _ _).mp valid
  obtain ⟨identityBound, outside, absent⟩ := (Stack.identityWF_delimiter _ _ _ _).mp rest
  cases mode with
  | deep =>
    refine ⟨(Stack.IdentityWF.append_iff _ _).mpr ⟨inside, ?_, ?_⟩, outside, ?_⟩
    · exact (Stack.identityWF_delimiter _ _ _ _).mpr
        ⟨identityBound, Stack.identityWF_done, by simp [Stack.attachments]⟩
    · intro left member right other
      have same : right = selected.identity := by simpa [Stack.attachments] using other
      exact apart left member right (by simp [Stack.attachments, same])
    · intro left member right other
      simp only [Selected.capture, Stack.attachments_append, Stack.attachments,
        List.mem_append, List.mem_cons, List.not_mem_nil, or_false] at member
      rcases member with member | rfl
      · exact apart left member right (by simp [Stack.attachments, other])
      · exact fun same => absent (same ▸ other)
  | shallow =>
    exact ⟨inside, outside,
      fun left member right other => apart left member right (by simp [Stack.attachments, other])⟩

theorem Selected.capture_identityWF (selected : Selected A r a s b) (mode : Mode)
    (valid : selected.whole.IdentityWF fresh) : (selected.capture mode).IdentityWF fresh :=
  (selected.capture_and_outside mode valid).1

theorem Selected.outside_identityWF (selected : Selected A r a s b)
    (valid : selected.whole.IdentityWF fresh) : selected.outsideStack.IdentityWF fresh :=
  (selected.capture_and_outside .shallow valid).2.1

theorem Selected.capture_post {clauseCtx : List Ty} (selected : Selected A r .number s b) (mode : Mode)
    (post : A (mode.result selected.body selected.answer :: clauseCtx) selected.answer) (env : Values clauseCtx)
    (valid : selected.whole.IdentityWF fresh) :
    ((selected.capture mode).append (.push (.post post env) selected.outsideStack)).IdentityWF fresh := by
  obtain ⟨captured, outside, apart⟩ := selected.capture_and_outside mode valid
  exact (Stack.IdentityWF.append_iff _ _).mpr
    ⟨captured, (Stack.identityWF_post _ _ _).mpr outside, apart⟩

theorem return_preserves_identity (eval : Evaluator A) (machine : Machine A outside result)
    (value : Value a) (heap : Heap regions) (stack : Stack A regions a outside result)
    (valid : stack.IdentityWF machine.freshAttachment) :
    (returnValue eval machine value heap stack).IdentityWF := by
  cases stack with
  | done => trivial
  | push frame rest =>
    cases frame with
    | bind body env caps =>
      exact (Stack.identityWF_bind _ _ _ _).mp valid
    | delimiter identity handler env =>
      exact ⟨True.intro, ((Stack.identityWF_delimiter _ _ _ _).mp valid).2.1⟩
    | region =>
      cases heap
      exact ⟨True.intro, (Stack.identityWF_region _).mp valid⟩
    | post expression env => exact ⟨True.intro, (Stack.identityWF_post _ _ _).mp valid⟩
    | «repeat» template frozen arguments acc fold env =>
      have both := (Stack.identityWF_repeat _ _ _ _ _ _ _).mp valid
      cases arguments with
      | nil => exact ⟨True.intro, both.2⟩
      | cons argument arguments =>
        exact ⟨True.intro, Stack.IdentityWF.activate_append template _ both.1
          ((Stack.identityWF_repeat _ _ _ _ _ _ _).mpr both)⟩

theorem dispatch_preserves_identity (eval : Evaluator A) (machine : Machine A outside result)
    (payload : Nat) (heap : Heap regions) (selected : Selected A regions .number outside result)
    (valid : selected.whole.IdentityWF machine.freshAttachment) :
    (dispatch eval machine payload heap selected).IdentityWF := by
  cases clause : selected.handler.clause with
  | dispose expression =>
    simp only [dispatch, clause, Machine.IdentityWF, Status.IdentityWF, Focus.IdentityWF, true_and]
    exact selected.outside_identityWF valid
  | once mode argument post =>
    simp only [dispatch, clause, Machine.IdentityWF, Status.IdentityWF, Focus.IdentityWF, true_and]
    exact selected.capture_post mode post _ valid
  | multi mode arguments seed fold =>
    simp only [dispatch, clause]
    split
    · exact ⟨True.intro, selected.outside_identityWF valid⟩
    · exact ⟨True.intro, Stack.IdentityWF.activate_append (selected.capture mode) _
        (selected.capture_identityWF mode valid)
        ((Stack.identityWF_repeat _ _ _ _ _ _ _).mpr
          ⟨selected.capture_identityWF mode valid, selected.outside_identityWF valid⟩)⟩

theorem tick_preserves_identity (eval : Evaluator A) (machine : Machine A outside result)
    (valid : machine.IdentityWF) : (tick eval machine).IdentityWF := by
  cases state : machine.status with
  | pending | returned | disposed | transferred => simpa [tick, state] using valid
  | running position =>
    rcases position with ⟨regions, input, focus, heap, stack⟩
    change machine.status.IdentityWF machine.freshAttachment at valid
    rw [state] at valid
    cases focus with
    | value value =>
      simpa [tick, state] using return_preserves_identity eval machine value heap stack valid.2
    | code expression env caps =>
      have capBound : ∀ identity ∈ caps.toList, identity < machine.freshAttachment := valid.1
      have stackWF : stack.IdentityWF machine.freshAttachment := valid.2
      cases expression with
      | pure | read | write =>
        simp only [tick, state, Machine.IdentityWF, Status.IdentityWF, Focus.IdentityWF, true_and]
        exact stackWF
      | bind =>
        simp only [tick, state, Machine.IdentityWF, Status.IdentityWF, Focus.IdentityWF]
        exact ⟨capBound, (Stack.identityWF_bind _ _ _ _).mpr ⟨capBound, stackWF⟩⟩
      | branch =>
        simp only [tick, state, Machine.IdentityWF, Status.IdentityWF, Focus.IdentityWF]
        exact ⟨capBound, stackWF⟩
      | region =>
        simp only [tick, state, Machine.IdentityWF, Status.IdentityWF, Focus.IdentityWF]
        exact ⟨capBound, (Stack.identityWF_region _).mpr stackWF⟩
      | handle handler body =>
        simp only [tick, state, Machine.IdentityWF, Status.IdentityWF, Focus.IdentityWF]
        refine ⟨?_, (Stack.identityWF_delimiter _ _ _ _).mpr ⟨Nat.lt_succ_self _,
          stackWF.mono stack (Nat.le_succ _), ?_⟩⟩
        · intro identity member
          simp only [Vector.toList_cast, Vector.toList_append] at member
          change identity ∈ machine.freshAttachment :: caps.toList at member
          rcases List.mem_cons.mp member with rfl | member
          · exact Nat.lt_succ_self _
          · exact Nat.lt_succ_of_lt (capBound identity member)
        · intro member
          exact Nat.lt_irrefl _ (stackWF.1 _ (stack.attachments_mem_references member))
      | perform index payload =>
        simp only [tick, state]
        split
        · exact ⟨capBound caps[index] (by simp), stackWF⟩
        next selected found =>
          apply dispatch_preserves_identity
          rwa [selection_reconstructs_effectful_stack stack caps[index] selected found]

theorem transition_preserves_identity (eval : Evaluator A) (machine next : Machine A outside result)
    (input : Input) (valid : machine.IdentityWF) (step : transition eval machine input = some next) :
    next.IdentityWF := by
  cases input with
  | internal =>
    have equal : tick eval machine = next := Option.some.inj step
    exact equal ▸ tick_preserves_identity eval machine valid
  | resume value | dispose | transfer =>
    cases state : machine.status <;> try simp [transition, state] at step
    next request =>
      simp only [Machine.IdentityWF, state, Status.IdentityWF] at valid
      simp only [Option.bind_eq_some_iff, Option.some.injEq] at step
      obtain ⟨_, _, rfl⟩ := step
      first | exact ⟨True.intro, valid.2⟩ | trivial | exact valid

theorem tick_preserves_well_formedness (eval : Evaluator A) (machine : Machine A outside result)
    (valid : machine.WellFormed) : (tick eval machine).WellFormed :=
  ⟨tick_preserves_invariants eval machine valid.1, tick_preserves_identity eval machine valid.2⟩

theorem transition_preserves_well_formedness (eval : Evaluator A)
    (machine next : Machine A outside result) (input : Input)
    (valid : machine.WellFormed) (step : transition eval machine input = some next) : next.WellFormed :=
  ⟨transition_preserves_invariants eval machine next input valid.1 step,
    transition_preserves_identity eval machine next input valid.2 step⟩

theorem initialization_establishes_well_formedness (body : Flow A 0 caps [] result)
    (capabilities : Capabilities caps) : (initial body capabilities).WellFormed := by
  refine ⟨initial_is_well_owned _ _, ?_⟩
  exact ⟨fun identity member => freshAbove_reserves_every_identity _ identity member,
    Stack.identityWF_done⟩

theorem checked_initialization_establishes_well_formedness (body : Flow A 0 caps [] result)
    (capabilities : Capabilities caps) (fresh : Nat) (machine : Machine A 0 result)
    (accepted : initialWithSupply? body capabilities fresh = some machine) : machine.WellFormed := by
  unfold initialWithSupply? at accepted
  split at accepted <;> try contradiction
  next reserved =>
    cases accepted
    refine ⟨raw_initial_is_well_owned _ _ _, ?_⟩
    exact ⟨reserved, Stack.identityWF_done⟩

theorem attempt_preserves_well_formedness (eval : Evaluator A) (machine : Machine A outside result)
    (input : Input) (valid : machine.WellFormed) : (attempt eval machine input).state.WellFormed := by
  unfold attempt
  split
  · exact valid
  next next accepted => exact transition_preserves_well_formedness eval machine next input valid accepted

theorem driveEvents_preserves_well_formedness (eval : Evaluator A)
    (machine last : Machine A outside result) (inputs : List Input) (events : List (Event result))
    (valid : machine.WellFormed) (accepted : driveEvents eval machine inputs = some (last, events)) :
    last.WellFormed := by
  induction inputs generalizing machine events with
  | nil => cases accepted; exact valid
  | cons input inputs ih =>
    simp only [driveEvents] at accepted
    split at accepted <;> try contradiction
    cases run : driveEvents eval (attempt eval machine input).state inputs with
    | none => simp [run] at accepted
    | some pair =>
      rcases pair with ⟨middle, middleEvents⟩
      simp [run] at accepted
      obtain ⟨rfl, _⟩ := accepted
      exact ih _ _ (attempt_preserves_well_formedness eval machine input valid) run

theorem drive_preserves_well_formedness (eval : Evaluator A) (machine last : Machine A outside result)
    (inputs : List Input) (trace : List (Observation result)) (valid : machine.WellFormed)
    (run : drive eval machine inputs = some (last, trace)) : last.WellFormed := by
  induction inputs generalizing machine last trace with
  | nil => simp [drive] at run; exact run.1 ▸ valid
  | cons input inputs ih =>
    cases step : transition eval machine input with
    | none => simp [drive, step] at run
    | some next =>
      cases later : drive eval next inputs with
      | none => simp [drive, step, later] at run
      | some pair =>
        rcases pair with ⟨finalState, finalTrace⟩
        simp [drive, step, later] at run
        exact run.1 ▸ ih next finalState finalTrace
          (transition_preserves_well_formedness eval machine next input valid step) later

/-- The supply is disjoint from every current alias, not merely from the
active delimiter spine. This directly excludes accidental ambient interception
when the next handler is installed. -/
theorem next_handler_cannot_intercept_reserved_capability (stack : Stack A r a s b)
    (handler : Handler A ctx c a) (env : Values ctx) (reserved : requested < fresh) :
    select requested (.push (.delimiter fresh handler env) stack) =
      (select requested stack).map (fun selected => selected.prepend (.delimiter fresh handler env)) := by
  simp [select, Nat.ne_of_lt reserved]

theorem colliding_raw_state_is_not_well_formed :
    ¬ (rawInitial ambientCollisionBody #[0].toVector 0).WellFormed := by
  intro valid
  have bound := valid.2.1 0 (by simp)
  exact Nat.lt_irrefl 0 bound

theorem dormant_aliases_are_admitted : (nestedAliasTemplate 0 7).IdentityWF 10 := by
  simp [nestedAliasTemplate, Stack.IdentityWF, Stack.references, Frame.references,
    Stack.Unique, Frame.Unique, Stack.attachments]

theorem dormant_alias_at_supply_is_rejected : ¬ (nestedAliasTemplate 0 10).IdentityWF 10 := by
  simp [nestedAliasTemplate, Stack.IdentityWF, Stack.references, Frame.references,
    Stack.Unique, Frame.Unique, Stack.attachments]

private def duplicateDormantSpine : Stack Expr 0 .number 0 .number :=
  .push (.repeat
    (.push (.delimiter 0 ⟨.ref .here, .dispose (.literal (.number 0))⟩ .nil)
      (.push (.delimiter 0 ⟨.ref .here, .dispose (.literal (.number 0))⟩ .nil) .done))
    .done [] (.number 0) (.ref .here) .nil) .done

/-- The active spine is empty and every name is below the supply, but a
dormant template still cannot contain two distinct delimiters with one name. -/
theorem duplicate_dormant_delimiters_rejected :
    duplicateDormantSpine.attachments = [] ∧ ¬ duplicateDormantSpine.IdentityWF 1 := by
  simp [duplicateDormantSpine, Stack.IdentityWF, Stack.references, Frame.references,
    Stack.Unique, Frame.Unique, Stack.attachments]

end BoundaryV2.Effects
