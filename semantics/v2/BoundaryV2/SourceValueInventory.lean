import BoundaryV2.SourcePrimitiveCustody

namespace BoundaryV2.Profile.Source.Machine

/- Every stored semantic value, including inactive control and cleanup data.
This is a finite inventory of state fields; it does not follow heap references
recursively or discard stale lexical values. -/
namespace ValueInventory

def environment (bindings : Environment) : List SemanticValue :=
  bindings.map (fun binding => binding.located.value)

def activation (active : Activation) : List SemanticValue :=
  environment active.environment ++ active.state.map Located.value

def afterRelease : AfterRelease → List SemanticValue
  | .deliver value => [value.value]
  | .unwind exit => exitValues exit

def frame : Frame → List SemanticValue
  | .binding _ _ bindings _ => environment bindings
  | .operands _ bindings _ evaluated => environment bindings ++ evaluated.map Located.value
  | .handler active => activation active
  | .cleanupReturn _ _ exit normal => exitValues exit ++ normal.toList.map Located.value
  | .disposalReturn pending after _ _ => pending.map Located.value ++ afterRelease after
  | .injection values => values.map Located.value
  | .releaseReturn _ after => afterRelease after
  | .invocation .. | .restore .. | .lexical _ | .region _ | .protection _ => []

def capture (saved : Capture) : List SemanticValue :=
  saved.frames.flatMap frame ++ activation saved.delimiter ++
    saved.useSiteCapabilities.map Located.value ++ saved.frozenCells.map (fun cell => cell.content.value)

def object : Object → List SemanticValue
  | .closure _ _ bindings => environment bindings
  | .cell _ _ _ content | .package _ content | .resource _ content => [content.value]
  | .oneShot saved | .multiTemplate saved => capture saved
  | .capability .. | .region .. | .borrow .. => []

def obligation (record : Cleanup.Obligation .source) : List SemanticValue :=
  record.cleanup :: record.resource.toList ++
    (match record.phase with | .failed value => [value] | _ => [])

def heap (store : Heap) : List SemanticValue :=
  store.objects.flatMap (fun entry => entry.toList.flatMap object) ++
    store.obligations.flatMap obligation ++ store.scopes.flatMap (fun scope => scope.holdings.map Located.value)

def control : Control → List SemanticValue
  | .term _ bindings | .expression _ bindings => environment bindings
  | .delivered value => [value.value]
  | .execute _ bindings operands | .invoke _ bindings operands => environment bindings ++ operands.map Located.value
  | .unwind exit => exitValues exit
  | .release _ after => afterRelease after
  | .discard pending after => pending.map Located.value ++ afterRelease after

def status : Status → List SemanticValue
  | .running | .yielded => []
  | .parked request => request.payload :: (request.bodies ++ request.useSiteCapabilities).map Located.value
  | .completed value => [value]
  | .failed exit | .cancelled exit => exitValues exit

def state (machine : State) : List SemanticValue :=
  control machine.control ++ machine.stack.flatMap frame ++ heap machine.heap ++ status machine.status

def All (property : SemanticValue → Prop) (machine : State) : Prop :=
  ∀ value ∈ state machine, property value

theorem all_mono (before after : SemanticValue → Prop) (machine : State)
    (holds : All before machine) (implies : ∀ value, before value → after value) : All after machine :=
  fun value member => implies value (holds value member)

theorem rename_environment (mapping : Renaming) (bindings : Environment) :
    environment (renameEnvironment mapping bindings) = (environment bindings).map (renameValue mapping) := by
  simp [environment, renameEnvironment, renameLocated, List.map_map, Function.comp_def]

theorem rename_exit (mapping : Renaming) (exit : Cleanup.Exit .source) :
    exitValues (renameExit mapping exit) = (exitValues exit).map (renameValue mapping) := by
  cases exit with
  | mk primary failures cancellation => cases primary <;> simp [renameExit, exitValues]

theorem rename_after_release (mapping : Renaming) (after : AfterRelease) :
    afterRelease (renameAfter mapping after) = (afterRelease after).map (renameValue mapping) := by
  cases after with
  | deliver value => rfl
  | unwind exit => exact rename_exit mapping exit

theorem rename_activation (mapping : Renaming) (active : Activation) :
    activation (renameActivation mapping active) = (activation active).map (renameValue mapping) := by
  simp [activation, renameActivation, rename_environment, renameLocated, List.map_map, Function.comp_def]

theorem rename_frame (mapping : Renaming) (saved : Frame) :
    frame (renameFrame mapping saved) = (frame saved).map (renameValue mapping) := by
  cases saved <;> simp [frame, renameFrame, rename_environment, rename_activation, rename_exit,
    rename_after_release, renameLocated, List.map_map, Function.comp_def]
  rename_i normal
  cases normal <;> rfl

theorem rename_capture (mapping : Renaming) (saved : Capture) :
    capture (renameCapture mapping saved) = (capture saved).map (renameValue mapping) := by
  simp [capture, renameCapture, rename_frame, rename_activation, renameLocated,
    List.flatMap_map, List.map_flatMap, List.map_map, Function.comp_def]

theorem rename_object (mapping : Renaming) (stored : Object) :
    object (renameObject mapping stored) = (object stored).map (renameValue mapping) := by
  cases stored <;> simp [object, renameObject, rename_environment, rename_capture, renameLocated]

theorem rename_preserves_token_bounds (mapping : Renaming) (supply : Nat) (value : SemanticValue)
    (bounded : ValueTokensBounded supply value) : ValueTokensBounded supply (renameValue mapping value) := by
  simpa only [ValueTokensBounded, renaming_preserves_owned_tokens] using bounded

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

theorem initial_inventory (context : Context) (arguments : List SemanticValue) (machine : State)
    (accepted : initial context arguments = .ok machine) : state machine = arguments := by
  unfold initial at accepted
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, _, rfl⟩ := accepted
  simp [state, control, environment, heap, status, List.mapIdx_eq_zipIdx_map, List.map_map, Function.comp_def]

theorem initial_all (context : Context) (arguments : List SemanticValue) (machine : State)
    (accepted : initial context arguments = .ok machine) (property : SemanticValue → Prop)
    (argumentsHold : ∀ value ∈ arguments, property value) : All property machine := by
  simpa only [All, initial_inventory context arguments machine accepted] using argumentsHold

theorem initial_has_no_runtime_handles (context : Context) (arguments : List SemanticValue) (machine : State)
    (accepted : initial context arguments = .ok machine) :
    All (fun value => valueReferences value = [] ∧ ownedTokens value = []) machine :=
  initial_all context arguments machine accepted _ (initialization_excludes_hidden_handles _ _ _ accepted).1

theorem cancel_exit_subset (exit : Cleanup.Exit .source) (reason : Protocol.Reason) :
    exitValues (Cleanup.cancel exit reason) ⊆ exitValues exit := by
  cases exit with
  | mk primary failures cancellation =>
    cases primary <;> simp [Cleanup.cancel, exitValues, List.subset_def]
    exact fun member => Or.inr member

theorem cancel_control_subset (before : Control) (reason : Protocol.Reason) :
    control (cancelControl before reason) ⊆ control before := by
  cases before with
  | release scope after =>
    cases after with
    | deliver value => exact List.nil_subset _
    | unwind exit => exact cancel_exit_subset exit reason
  | discard pending after =>
    cases after with
    | deliver value => simp [cancelControl, control, afterRelease, exitValues]
    | unwind exit =>
      intro value member
      rcases List.mem_append.mp member with member | member
      · exact List.mem_append_left _ member
      · exact List.mem_append_right _ (cancel_exit_subset exit reason member)
  | unwind exit => exact cancel_exit_subset exit reason
  | term _ _ | expression _ _ | delivered _ | execute _ _ _ | invoke _ _ _ => exact List.nil_subset _

private theorem scope_member (machine : State) (scope : Scope)
    (found : machine.heap.scopes[machine.scope.value]? = some scope) : scope ∈ machine.heap.scopes :=
  List.mem_of_getElem? found

theorem temporary_preserves_all (machine after : State) (owner : Custody.Owner)
    (accepted : temporary machine = .ok (after, owner)) (property : SemanticValue → Prop)
    (holds : All property machine) : All property after := by
  unfold temporary at accepted
  split at accepted <;> try contradiction
  rename_i scope found
  split at accepted <;> try contradiction
  cases accepted
  have member := scope_member machine scope found
  simp only [All, state, heap, List.mem_append, List.mem_flatMap, List.mem_map] at holds ⊢
  grind only [→ List.mem_or_eq_of_mem_set]

theorem finishTemporary_preserves_all (machine : State) (value : Located) (after : Transition)
    (accepted : finishTemporary machine value = .ok after) (property : SemanticValue → Prop)
    (holds : All property machine) (valueHolds : property value.value) : All property after.state := by
  unfold finishTemporary at accepted
  split at accepted <;> try contradiction
  rename_i scope found
  cases accepted
  have member := scope_member machine scope found
  simp only [finishValue, All, state, heap, control, List.mem_append, List.mem_flatMap,
    List.mem_map, List.mem_singleton] at holds ⊢
  grind only [→ List.mem_or_eq_of_mem_set, List.mem_append, List.mem_singleton]

theorem scopedValue_preserves_all (machine : State) (value : SemanticValue) (after : Transition)
    (accepted : scopedValue machine value = .ok after) (property : SemanticValue → Prop)
    (holds : All property machine) (valueHolds : property value) : All property after.state := by
  simp only [scopedValue, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryAccepted, finishAccepted⟩ := accepted
  exact finishTemporary_preserves_all _ _ _ finishAccepted property
    (temporary_preserves_all _ _ _ temporaryAccepted property holds) valueHolds

theorem moveValues_preserves_all (machine : State) (store : Heap) (values : List Located)
    (receiver : Nat → Custody.Owner) (accepted : moveValues machine.heap values receiver = some store)
    (property : SemanticValue → Prop) (holds : All property machine) : All property { machine with heap := store } := by
  simp [moveValues, Option.bind_eq_some_iff] at accepted
  obtain ⟨_, _, rfl⟩ := accepted
  exact holds

theorem allocateObject_preserves_all (machine : State) (store : Heap) (schema : SchemaId .source)
    (stored : Object) (owner : Custody.Owner) (exclusive : Bool) (value : Located)
    (accepted : allocateObject machine.heap schema stored owner exclusive = some (store, value))
    (property : SemanticValue → Prop) (holds : All property machine)
    (objectHolds : ∀ child ∈ object stored, property child) : All property { machine with heap := store } := by
  cases exclusive <;> simp [allocateObject, Option.bind_eq_some_iff] at accepted
  · obtain ⟨rfl, _⟩ := accepted
    simp only [All, state, heap, List.flatMap_append, List.flatMap_cons, List.flatMap_nil,
      Option.toList_some, List.append_nil, List.mem_append] at holds ⊢
    grind only []
  · obtain ⟨_, _, rfl, _⟩ := accepted
    simp only [All, state, heap, List.flatMap_append, List.flatMap_cons, List.flatMap_nil,
      Option.toList_some, List.append_nil, List.mem_append] at holds ⊢
    grind only []

theorem commitPure_preserves_all (machine : State) (opcode : Opcode) (operands : List Located)
    (result : SemanticValue) (after : Transition) (accepted : commitPure machine opcode operands result = .ok after)
    (property : SemanticValue → Prop) (holds : All property machine) (resultHolds : property result) :
    All property after.state := by
  simp only [commitPure, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, owner⟩, first, accepted⟩ := accepted
  have middleHolds := temporary_preserves_all _ _ _ first property holds
  split at accepted
  all_goals simp only [except_bind_ok] at accepted
  · obtain ⟨_, _, _, _, accepted⟩ := accepted
    exact finishTemporary_preserves_all _ _ _ accepted property middleHolds resultHolds
  · obtain ⟨heap, moved, _, _, book, _, accepted⟩ := accepted
    have movedSome : moveValues middle.heap operands (fun _ => owner) = some heap := by
      cases value : moveValues middle.heap operands (fun _ => owner) <;> simp [fromOption, value] at moved ⊢
      exact moved
    have heapHolds := moveValues_preserves_all middle heap operands (fun _ => owner) movedSome property middleHolds
    exact finishTemporary_preserves_all _ _ _ accepted property heapHolds resultHolds

theorem enterTerm_preserves_all (machine : State) (source : Module) (after : Transition)
    (accepted : enterTerm machine source = .ok after) (property : SemanticValue → Prop)
    (holds : All property machine) : All property after.state := by
  simp only [enterTerm, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  simp only [All, state] at holds ⊢
  grind (gen := 32) only [control, frame, status, List.mem_append, List.mem_flatMap, List.mem_cons,
    List.not_mem_nil, List.map_nil, List.flatMap_cons, List.flatMap_nil]

theorem deliverOperand_preserves_all (machine : State) (after : Transition)
    (accepted : deliverOperand machine = .ok after) (property : SemanticValue → Prop)
    (holds : All property machine) : All property after.state := by
  unfold deliverOperand at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  split at accepted
  all_goals cases accepted
  all_goals simp_all only [All, state, control, frame, List.flatMap_cons, List.map_append,
    List.map_cons, List.map_nil, List.mem_append, List.mem_cons, List.not_mem_nil]
  all_goals grind only []

theorem external_preserves_all (machine : State) (context : Context) (action : External) (after : Transition)
    (accepted : external machine context action = .ok after) (property : SemanticValue → Prop)
    (holds : All property machine)
    (externalHolds : ∀ value, Profile.Value.externalValid context.source.schemas value = true → property value) :
    All property after.state := by
  have running : All property { machine with status := .running } := by
    intro value member
    apply holds value
    simp only [state, status, List.append_nil] at member
    exact List.mem_append_left _ member
  have cancelled (reason : Protocol.Reason) :
      All property { machine with status := .running, control := cancelControl machine.control reason, cancellation := some reason } := by
    intro entry member
    simp only [state, status, List.append_nil] at member
    simp only [All, state, List.mem_append] at holds
    rcases List.mem_append.mp member with member | member
    · rcases List.mem_append.mp member with member | member
      · exact holds entry (Or.inl (Or.inl (Or.inl (cancel_control_subset _ _ member))))
      · exact holds entry (Or.inl (Or.inl (Or.inr member)))
    · exact holds entry (Or.inl (Or.inr member))
  have cancellationOnly (reason : Protocol.Reason) :
      All property { machine with cancellation := some reason } := holds
  have requires (condition : Bool) (reason : Invalid) (result : Unit)
      (checked : require condition reason = .ok result) : condition = true := by
    unfold require at checked
    split at checked <;> first | assumption | contradiction
  have scopedResult (value : SemanticValue) (transition : Transition)
      (admitted : Profile.Value.externalValid context.source.schemas value = true)
      (checked : scopedValue { machine with status := .running } value = .ok transition) :
      All property transition.state :=
    scopedValue_preserves_all _ _ _ checked property running (externalHolds value admitted)
  cases phase : machine.status <;> cases action <;>
    simp only [external, phase, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw,
      Except.bind] at accepted <;> try contradiction
  all_goals grind (gen := 32) only []

end ValueInventory

end BoundaryV2.Profile.Source.Machine
