import BoundaryV2.GeneralizedObservations
import BoundaryV2.GeneralizedOwnership

namespace BoundaryV2.Generalized.Target

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

/-- Logical occurrence names belong to the proof model, not the wire format. -/
structure OccurrenceSupply where
  next : Nat

structure Pending (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) {effect : signature.Effect}
    (operation : signature.operation effect) (result : TypeOf signature) where
  occurrence : Id .occurrence
  attachment : Id .attachment
  payload : RuntimeValue signature algebra program (signature.payload operation)
  bodies : RuntimeEnvironment signature algebra program ((signature.bodies operation).map BodyType.type)
  future : Stack signature algebra program (signature.result operation) result
  owners : UseScope.State

/-- The operation index also binds response typing when two operations happen
to have the same result type. Invalid decoding is represented separately. -/
structure Response (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) {effect : signature.Effect}
    (operation : signature.operation effect) where
  occurrence : Id .occurrence
  attachment : Id .attachment
  value : RuntimeValue signature algebra program (signature.result operation)

structure Opened (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) {effect : signature.Effect}
    (operation : signature.operation effect) (result : TypeOf signature) where
  pending : Pending signature algebra program operation result
  supply : OccurrenceSupply

/-- Opening is allowed only after the dispatch is known to be external. -/
def openRequest (operation : signature.operation effect) (supply : OccurrenceSupply)
    (attachment : Id .attachment) (payload : RuntimeValue signature algebra program (signature.payload operation))
    (bodies : RuntimeEnvironment signature algebra program ((signature.bodies operation).map BodyType.type))
    (future : Stack signature algebra program (signature.result operation) result)
    (owners : UseScope.State) (_external : ¬ Handles operation attachment future) :
    Opened signature algebra program operation result :=
  ⟨⟨⟨supply.next⟩, attachment, payload, bodies, future, owners⟩, ⟨supply.next + 1⟩⟩

inductive InteractionState (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) {effect : signature.Effect}
    (operation : signature.operation effect) (result : TypeOf signature) where
  | parked : Pending signature algebra program operation result → InteractionState signature algebra program operation result
  | running : Configuration signature algebra program result → UseScope.State → InteractionState signature algebra program operation result

inductive InteractionInput (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) {effect : signature.Effect}
    (operation : signature.operation effect) where
  | poll
  | invalid
  | response : Response signature algebra program operation → InteractionInput signature algebra program operation

def matchingResponse (pending : Pending signature algebra program operation result)
    (response : Response signature algebra program operation) : Prop :=
  response.occurrence = pending.occurrence ∧ response.attachment = pending.attachment

instance (pending : Pending signature algebra program operation result) (response : Response signature algebra program operation) :
    Decidable (matchingResponse pending response) := inferInstanceAs (Decidable (_ ∧ _))

/-- Polling and rejection produce no transition into the saved future. A valid
response consumes the parked phase and supplies the value to its actual stack. -/
def interact (state : InteractionState signature algebra program operation result)
    (input : InteractionInput signature algebra program operation) : InteractionState signature algebra program operation result :=
  match state, input with
  | .parked pending, .response response =>
    if matchingResponse pending response then .running (.returned response.value pending.future) pending.owners
    else state
  | _, _ => state

def observePending : InteractionState signature algebra program operation result → Option (Pending signature algebra program operation result)
  | .parked pending => some pending
  | .running _ _ => none

theorem polling_is_silent (state : InteractionState signature algebra program operation result) : interact state .poll = state := by
  cases state <;> rfl

theorem invalid_input_is_silent (state : InteractionState signature algebra program operation result) : interact state .invalid = state := by
  cases state <;> rfl

theorem mismatch_preserves_pending (pending : Pending signature algebra program operation result)
    (response : Response signature algebra program operation) (mismatch : ¬ matchingResponse pending response) :
    interact (.parked pending) (.response response) = .parked pending := by
  simp only [interact, if_neg mismatch]

theorem accepted_response_reenters_typed_future (pending : Pending signature algebra program operation result)
    (response : Response signature algebra program operation) (matched : matchingResponse pending response) :
    interact (.parked pending) (.response response) = .running (.returned response.value pending.future) pending.owners := by
  simp only [interact, if_pos matched]

theorem accepted_response_consumes_parked_phase (pending : Pending signature algebra program operation result)
    (response : Response signature algebra program operation) (matched : matchingResponse pending response) :
    observePending (interact (.parked pending) (.response response)) = none := by
  rw [accepted_response_reenters_typed_future pending response matched]
  rfl

theorem duplicate_response_cannot_reenter (pending : Pending signature algebra program operation result)
    (response : Response signature algebra program operation) (matched : matchingResponse pending response) :
    interact (interact (.parked pending) (.response response)) (.response response) =
      interact (.parked pending) (.response response) := by
  rw [accepted_response_reenters_typed_future pending response matched]
  rfl

theorem equal_requests_have_distinct_occurrences (operation : signature.operation effect) (supply : OccurrenceSupply)
    (attachment : Id .attachment) (payload : RuntimeValue signature algebra program (signature.payload operation))
    (bodies : RuntimeEnvironment signature algebra program ((signature.bodies operation).map BodyType.type))
    (future : Stack signature algebra program (signature.result operation) result) (owners : UseScope.State)
    (external : ¬ Handles operation attachment future) :
    (openRequest operation supply attachment payload bodies future owners external).pending.occurrence ≠
      (openRequest operation (openRequest operation supply attachment payload bodies future owners external).supply
        attachment payload bodies future owners external).pending.occurrence := by
  intro same
  have impossible := congrArg Id.index same
  simp [openRequest] at impossible

theorem stale_occurrence_rejects (pending : Pending signature algebra program operation result)
    (response : Response signature algebra program operation) (stale : response.occurrence ≠ pending.occurrence) :
    interact (.parked pending) (.response response) = .parked pending :=
  mismatch_preserves_pending pending response (fun matched => stale matched.1)

inductive SilentInput (pending : Pending signature algebra program operation result) :
    InteractionInput signature algebra program operation → Prop where
  | poll : SilentInput pending .poll
  | invalid : SilentInput pending .invalid
  | mismatch : ¬ matchingResponse pending response → SilentInput pending (.response response)

def interactMany (state : InteractionState signature algebra program operation result)
    (inputs : List (InteractionInput signature algebra program operation)) : InteractionState signature algebra program operation result :=
  inputs.foldl interact state

theorem finite_silent_inputs_preserve_future (pending : Pending signature algebra program operation result)
    (inputs : List (InteractionInput signature algebra program operation))
    (silent : ∀ input ∈ inputs, SilentInput pending input) : interactMany (.parked pending) inputs = .parked pending := by
  induction inputs with
  | nil => rfl
  | cons input rest induction =>
    have first := silent input (by simp)
    have unchanged : interact (.parked pending) input = .parked pending := by
      cases first with
      | poll => exact polling_is_silent _
      | invalid => exact invalid_input_is_silent _
      | mismatch mismatch => exact mismatch_preserves_pending _ _ mismatch
    change interactMany (interact (.parked pending) input) rest = _
    rw [unchanged]
    exact induction (fun input member => silent input (by simp [member]))

/-- A history records logical openings, not polls of an already parked state. -/
structure OpeningHistory where
  supply : OccurrenceSupply
  issued : List (Id .occurrence)

def OpeningHistory.Valid (history : OpeningHistory) : Prop :=
  history.issued.Nodup ∧ ∀ occurrence ∈ history.issued, occurrence.index < history.supply.next

def OpeningHistory.record (history : OpeningHistory) : OpeningHistory :=
  ⟨⟨history.supply.next + 1⟩, ⟨history.supply.next⟩ :: history.issued⟩

theorem opening_history_preserves_freshness (valid : OpeningHistory.Valid history) : OpeningHistory.Valid history.record := by
  constructor
  · apply List.nodup_cons.mpr
    refine ⟨?_, valid.1⟩
    intro previous
    have impossible := valid.2 _ previous
    exact Nat.lt_irrefl _ impossible
  · intro occurrence member
    simp only [OpeningHistory.record, List.mem_cons] at member
    rcases member with rfl | previous
    · exact Nat.lt_succ_self _
    · have earlier := valid.2 _ previous
      exact Nat.lt_trans earlier (Nat.lt_succ_self _)

theorem initial_opening_history_valid : OpeningHistory.Valid ⟨⟨0⟩, []⟩ := by
  simp [OpeningHistory.Valid]

theorem opening_records_its_issued_name (operation : signature.operation effect) (history : OpeningHistory)
    (attachment : Id .attachment) (payload : RuntimeValue signature algebra program (signature.payload operation))
    (bodies : RuntimeEnvironment signature algebra program ((signature.bodies operation).map BodyType.type))
    (future : Stack signature algebra program (signature.result operation) result) (owners : UseScope.State)
    (external : ¬ Handles operation attachment future) :
    (openRequest operation history.supply attachment payload bodies future owners external).supply = history.record.supply ∧
      history.record.issued =
        (openRequest operation history.supply attachment payload bodies future owners external).pending.occurrence :: history.issued :=
  ⟨rfl, rfl⟩

/-- Custody includes every live owner in the supplied core state. Polling,
rejection, and response handoff neither invent nor discard one of those fields. -/
def InteractionState.owners : InteractionState signature algebra program operation result → UseScope.State
  | .parked pending => pending.owners
  | .running _ owners => owners

theorem interaction_preserves_all_owners (state : InteractionState signature algebra program operation result)
    (input : InteractionInput signature algebra program operation) : (interact state input).owners = state.owners := by
  cases state with
  | running configuration owners => cases input <;> rfl
  | parked pending =>
    cases input with
    | poll | invalid => rfl
    | response response =>
      by_cases matched : matchingResponse pending response
      all_goals simp only [interact, matched, if_true, if_false, InteractionState.owners]

end BoundaryV2.Generalized.Target

namespace BoundaryV2.Generalized.Defunctionalization

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

theorem accepted_input_preserves_source_interpretation
    (operation : signature.operation effect)
    (pending : Target.Pending signature algebra program operation result)
    (sourceFuture : Source.Context signature algebra program (signature.result operation) result)
    (future : ContextRelated signature algebra program sourceFuture pending.future)
    (response : Source.RuntimeValue signature algebra program (signature.result operation)) :
    Target.interact (.parked pending) (.response ⟨pending.occurrence, pending.attachment, value response⟩) =
      .running (.returned (value response) pending.future) pending.owners ∧
    EntryRelated (sourceFuture.plug (.returned response)) (.returned (value response) pending.future) := by
  exact ⟨Target.accepted_response_reenters_typed_future pending _ ⟨rfl, rfl⟩, .returned response future⟩

end BoundaryV2.Generalized.Defunctionalization
