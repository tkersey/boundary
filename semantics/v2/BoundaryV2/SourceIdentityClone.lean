import BoundaryV2.SourceIdentityStorage

namespace BoundaryV2.Profile.Source.Machine
namespace IdentitySupport

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

private theorem dedup_length_le [BEq α] [LawfulBEq α] (values : List α) : values.eraseDups.length ≤ values.length := by
  cases values with
  | nil => simp
  | cons head tail =>
    rw [List.eraseDups_cons]
    have smaller := dedup_length_le (tail.filter (fun value => !value == head))
    have filtered := List.length_filter_le (fun value => !value == head) tail
    simp only [List.length_cons]
    omega
termination_by values.length
decreasing_by have := List.length_filter_le (fun value => !value == head) tail; simp only [List.length_cons]; omega

theorem fresh_map_at_limit (domain : Domain) (start : Nat) (identities : List (Ref .runtime domain))
    (identity : Ref .runtime domain) (bounded : Bound limit identity)
    (upper : start + identities.length ≤ limit domain) :
    Bound limit (renamed (freshMap .runtime domain start identities) identity) := by
  by_cases inside : identity ∈ identities
  · have allocated := (source_activation_interval .runtime domain start identities identity inside).2
    have count := dedup_length_le identities
    simp only [Bound]
    omega
  · rw [renamed_outside_fresh_map _ _ _ _ _ inside]
    exact bounded

private theorem mapM_origin (function : α → Except Invalid β) (inputs : List α) (outputs : List β)
    (accepted : inputs.mapM function = .ok outputs) (output : β) (member : output ∈ outputs) :
    ∃ input ∈ inputs, function input = .ok output := by
  induction inputs generalizing outputs with
  | nil => cases accepted; simp at member
  | cons head tail induction =>
    simp only [List.mapM_cons, bind, except_bind_ok] at accepted
    obtain ⟨first, firstAt, rest, restAt, accepted⟩ := accepted
    cases accepted
    rcases List.mem_cons.mp member with rfl | member
    · exact ⟨head, by simp, firstAt⟩
    · obtain ⟨input, inputMember, found⟩ := induction _ restAt member
      exact ⟨input, by simp [inputMember], found⟩

theorem instantiateCapture_valid (machine : State) (context : Context) (saved : Capture) (after : State × Capture)
    (bounded : ValidAt limit machine) (captureBounded : CaptureValid limit saved)
    (upper : Upper limit after.1.heap)
    (accepted : instantiateCapture machine context saved = .ok after) :
    ValidAt limit after.1 ∧ CaptureValid limit after.2 := by
  let support := cloneSupport machine.heap saved
  let dormant := support.filterMap (fun node => match machine.heap.lookup node with
    | some (.multiTemplate inner) => some inner | _ => none)
  let scopeIds := (captureScopes saved ++ dormant.flatMap captureScopes).eraseDups
  let invocationIds := (captureInvocations saved ++ dormant.flatMap captureInvocations).eraseDups
  let regions := (saved.localRegions ++ dormant.flatMap Capture.localRegions).eraseDups
  let attachments := (saved.delimiter.identity :: activeAttachments saved.frames ++
    dormant.flatMap (fun inner => inner.delimiter.identity :: activeAttachments inner.frames)).eraseDups
  let copyNodes := support.filter fun node => match machine.heap.lookup node with
    | some (.cell _ _ region _) | some (.region region _ _ _) => regions.contains region
    | some (.capability identity _) => attachments.contains identity
    | some (.closure ..) | some (.multiTemplate _) => true
    | _ => false
  let cells := copyNodes.filterMap (fun node => match machine.heap.lookup node with
    | some (.cell identity _ _ _) => some identity | _ => none)
  let mapping : Renaming := {
    nodes := freshMap .runtime .node machine.heap.objects.length copyNodes
    attachments := freshMap .runtime .attachment machine.heap.nextAttachment attachments
    regions := freshMap .runtime .regionInstance machine.heap.nextRegion regions
    cells := freshMap .runtime .cell machine.heap.nextCell cells
    scopes := freshMap .runtime .lexicalScope machine.heap.nextScope scopeIds
    invocations := freshMap .runtime .invocation machine.heap.nextInvocation invocationIds }
  unfold instantiateCapture at accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨objects, objectsAt, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨scopes, scopesAt, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨invocations, invocationsAt, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  cases accepted
  have attachmentUpper : machine.heap.nextAttachment + attachments.length ≤ limit .attachment := upper .attachment
  have regionUpper : machine.heap.nextRegion + regions.length ≤ limit .regionInstance := upper .regionInstance
  have cellUpper : machine.heap.nextCell + cells.length ≤ limit .cell := upper .cell
  have scopeUpper : machine.heap.nextScope + scopeIds.length ≤ limit .lexicalScope := upper .lexicalScope
  have invocationUpper : machine.heap.nextInvocation + invocationIds.length ≤ limit .invocation := upper .invocation
  have renames : Renames limit limit mapping := {
    attachments := fun identity formed => fresh_map_at_limit _ _ _ _ formed attachmentUpper
    regions := fun identity formed => fresh_map_at_limit _ _ _ _ formed regionUpper
    cells := fun identity formed => fresh_map_at_limit _ _ _ _ formed cellUpper
    scopes := fun identity formed => fresh_map_at_limit _ _ _ _ formed scopeUpper
    invocations := fun identity formed => fresh_map_at_limit _ _ _ _ formed invocationUpper
    obligations := fun _ formed => formed }
  have objectsBounded : ∀ entry ∈ objects, ∀ object ∈ entry, ObjectValid limit object := by
    intro entry member present presentAt
    obtain ⟨node, _, checked⟩ := mapM_origin _ _ _ objectsAt entry member
    simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at checked
    obtain ⟨object, found, rfl⟩ := checked
    cases presentAt
    apply rename_object renames
    have original := heap_lookup bounded.heap found
    cases object <;> exact original
  have scopesBounded : ∀ scope ∈ scopes, ScopeValid limit scope := by
    intro scope member
    obtain ⟨identity, identityMember, checked⟩ := mapM_origin _ _ _ scopesAt scope member
    simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at checked
    obtain ⟨original, found, rfl⟩ := checked
    have originalBound := bounded.heap.scopes original (List.mem_of_getElem? found)
    refine ⟨?_, renames.invocations _ originalBound.2.1, ?_⟩
    · have allocated := (source_activation_interval .runtime .lexicalScope machine.heap.nextScope scopeIds identity identityMember).2
      have count := dedup_length_le scopeIds
      change (renamed (freshMap .runtime .lexicalScope machine.heap.nextScope scopeIds) identity).value < limit .lexicalScope
      omega
    · intro parent member
      obtain ⟨old, oldMember, rfl⟩ := Option.map_eq_some_iff.mp member
      exact renames.scopes _ (originalBound.2.2 old oldMember)
  have invocationsBounded : ∀ invocation ∈ invocations, InvocationValid limit invocation := by
    intro invocation member
    obtain ⟨identity, identityMember, checked⟩ := mapM_origin _ _ _ invocationsAt invocation member
    simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at checked
    obtain ⟨original, found, rfl⟩ := checked
    have originalBound := bounded.heap.invocations original (List.mem_of_getElem? found)
    refine ⟨?_, ?_, ?_⟩
    · have allocated := (source_activation_interval .runtime .invocation machine.heap.nextInvocation invocationIds identity identityMember).2
      have count := dedup_length_le invocationIds
      change (renamed (freshMap .runtime .invocation machine.heap.nextInvocation invocationIds) identity).value < limit .invocation
      omega
    · intro parent member
      obtain ⟨old, oldMember, rfl⟩ := List.mem_map.mp member
      exact renames.attachments _ (originalBound.2.1 old oldMember)
    · intro parent member
      obtain ⟨old, oldMember, rfl⟩ := List.mem_map.mp member
      exact renames.regions _ (originalBound.2.2 old oldMember)
  refine ⟨⟨⟨?_, ?_, ?_, bounded.heap.obligations, bounded.heap.loans⟩,
    bounded.frames, bounded.control, bounded.scope, bounded.invocation⟩, rename_capture renames captureBounded⟩
  · intro entry member object present
    exact (List.mem_append.mp member).elim (fun old => bounded.heap.objects entry old object present)
      (fun fresh => objectsBounded entry fresh object present)
  · intro scope member
    exact (List.mem_append.mp member).elim (bounded.heap.scopes scope) (scopesBounded scope)
  · intro invocation member
    exact (List.mem_append.mp member).elim (bounded.heap.invocations invocation) (invocationsBounded invocation)

theorem retire_valid (bounded : ValidAt limit machine)
    (accepted : retireObject machine.heap value = some heap) : ValidAt limit { machine with heap := heap } :=
  ⟨retire_heap bounded.heap accepted, bounded.frames, bounded.control, bounded.scope, bounded.invocation⟩

theorem lookupObject_bound (bounded : ValidAt limit machine)
    (accepted : lookupObject machine value = .ok (node, object)) : ObjectValid limit object :=
  heap_lookup bounded.heap (CellStability.lookupObject_reference _ _ _ _ accepted).2

theorem applyClosure_valid (machine : State) (context : Context) (closure : Located)
    (arguments : List Located) (after : Transition) (bounded : ValidAt limit machine)
    (upper : Upper limit after.state.heap)
    (accepted : applyClosure machine context closure arguments = .ok after) : ValidAt limit after.state := by
  simp only [applyClosure, bind, except_bind_ok] at accepted
  obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
  cases stored <;> try contradiction
  obtain ⟨⟨schema, token, reference⟩, _⟩ := CellStability.lookupObject_reference _ _ _ _ looked
  rw [reference] at accepted
  cases token with
  | none =>
    simp only [pure, Except.pure, Except.bind] at accepted
    exact invokeFunction_valid _ _ _ _ _ _ bounded upper accepted
  | some token =>
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨store, retired, accepted⟩ := accepted
    exact invokeFunction_valid _ _ _ _ _ _ (retire_valid bounded retired) upper accepted

theorem takeCapture_valid (machine : State) (context : Context) (token : Located) (after : State × Capture)
    (bounded : ValidAt limit machine) (upper : Upper limit after.1.heap)
    (accepted : takeCapture machine context token = .ok after) : ValidAt limit after.1 ∧ CaptureValid limit after.2 := by
  simp only [takeCapture, bind, except_bind_ok] at accepted
  obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
  have captureBounded := lookupObject_bound bounded looked
  cases stored <;> try contradiction
  · simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨heap, retired, rfl⟩ := accepted
    exact ⟨retire_valid bounded retired, captureBounded⟩
  · exact instantiateCapture_valid _ _ _ _ bounded captureBounded upper accepted

theorem activateCapture_valid (machine : State) (context : Context) (saved : Capture)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : State)
    (bounded : ValidAt limit machine) (captureBounded : CaptureValid limit saved)
    (accepted : activateCapture machine context saved successor = .ok after) : ValidAt limit after := by
  have assemble (delimiter : Activation) (reinstall : Bool) (delimiterBounded : ActivationValid limit delimiter) :
      ValidAt limit { machine with
        stack := saved.frames ++ (if reinstall then [Frame.handler delimiter] else []) ++
          [Frame.restore machine.invocation machine.scope] ++ machine.stack
        scope := saved.scope, invocation := saved.invocation } := by
    refine ⟨bounded.heap, ?_, bounded.control, captureBounded.2.2.2.2.1, captureBounded.2.2.2.2.2⟩
    have delimiterFrame : ∀ frame ∈ (if reinstall then [Frame.handler delimiter] else []), FrameValid limit frame := by
      split
      · intro frame member
        cases List.mem_singleton.mp member
        exact delimiterBounded
      · simp
    intro frame member
    simp only [List.mem_append, List.mem_singleton] at member
    rcases member with ((inside | selected) | caller) | outside
    · exact captureBounded.1 frame inside
    · exact delimiterFrame frame selected
    · cases caller
      exact ⟨bounded.invocation, bounded.scope⟩
    · exact bounded.frames frame outside
  simp only [activateCapture, bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  cases successor with
  | none => cases accepted; exact assemble _ _ captureBounded.2.1
  | some successor =>
    rcases successor with ⟨handler, stored, environment⟩
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, _, _, _, rfl, rfl⟩ := accepted
    apply assemble
    refine ⟨captureBounded.2.1.1, bounded.scope, bounded.invocation, ?_⟩
    intro parent member
    exact active_attachments bounded.frames (List.mem_of_head? member)

end IdentitySupport
end BoundaryV2.Profile.Source.Machine
