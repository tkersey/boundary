import BoundaryV2.SourceCleanup

namespace BoundaryV2.Profile.Source.Machine

/-- One source transition. Administrative syntax steps are explicit; recursive
functions have no execution fuel in this definition. -/
def tickRunning (state : State) (context : Context) : Except Invalid Transition := do
  match state.control with
  | .term .. => enterTerm state context.source
  | .expression .. => enterExpression state context
  | .invoke .. => enterInvocation state context
  | .release .. => releaseScope state
  | .discard .. => discardValues state context
  | .unwind _ => unwindStep state context
  | .execute intent _ _ => match intent with
    | .primitive .. => executePrimitive state context
    | .term term => match term with
      | .perform _ | .handle .. | .resumeValue .. | .resumeWith .. | .resumeComputation .. | .withRegion .. =>
        executeEffectTerm state context
      | .protect .. | .dispose _ => executeCleanupTerm state context
      | _ => executeControlTerm state context
  | .delivered value => match state.stack with
    | [] =>
      require (Profile.Value.externalValid context.source.schemas value.value) .type
      let entry ← fromOption context.source.functions[context.source.entry.value]? .reference
      require (value.value.schema == entry.result) .type
      return ⟨{ state with status := .completed value.value }, [.completed value.value]⟩
    | .binding .. :: _ => enterBinding state context
    | .operands .. :: _ => deliverOperand state
    | .invocation .. :: _ => leaveInvocation state
    | .lexical _ :: _ => leaveLexical state
    | .restore .. :: _ => restoreResumeCaller state
    | .handler _ :: _ => completeHandler state context
    | .region _ :: tail => return ⟨{ state with stack := tail }, []⟩
    | .protection identity :: tail => beginCleanup state context identity ⟨.normal value.value, [], none⟩ (some value) tail
    | .cleanupReturn .. :: _ => finishCleanup state context
    | .injection _ :: tail => return ⟨{ state with stack := tail }, []⟩
    | .releaseReturn scope after :: tail => return ⟨{ state with control := .release scope after, stack := tail }, []⟩
    | .disposalReturn .. :: _ => throw .type

def tick (state : State) (context : Context) : Except Invalid Transition :=
  match state.status with
  | .running => tickRunning state context
  | _ => .ok ⟨state, []⟩

/-- Control is an explicit input. Polling an already exposed request or yield
does not silently accept a response or manufacture a second event. -/
inductive External where
  | continueYield
  | response : RequestOccurrence → SemanticValue → External
  | cancel : Protocol.Reason → External

/-- Cleanup activity belongs to its obligation lifecycle. A handled operation
can move the return frame into a captured continuation without finishing that
cleanup, so the active stack alone cannot decide whether cancellation waits. -/
def cleanupRunning (state : State) : Bool := state.heap.obligations.any fun obligation => match obligation.phase with
  | .running _ => true
  | _ => false

def cancelControl (control : Control) (reason : Protocol.Reason) : Control := match control with
  | .unwind exit => .unwind (Cleanup.cancel exit reason)
  | .discard values (.unwind exit) => .discard values (.unwind (Cleanup.cancel exit reason))
  | .release scope (.unwind exit) => .release scope (.unwind (Cleanup.cancel exit reason))
  | .discard values (.deliver _) => .discard values (.unwind ⟨.cancellation, [], some reason⟩)
  | .release scope (.deliver _) => .release scope (.unwind ⟨.cancellation, [], some reason⟩)
  | _ => .unwind ⟨.cancellation, [], some reason⟩

def external (state : State) (context : Context) (action : External) : Except Invalid Transition := do
  match state.status with
  | .completed _ | .failed _ | .cancelled _ => throw .inactive
  | _ => pure ()
  match action with
  | .continueYield =>
    let .yielded := state.status | throw .inactive
    return ⟨{ state with status := .running }, []⟩
  | .response occurrence value =>
    let .parked request := state.status | throw .inactive
    require (request.occurrence == occurrence) .reference
    require (value.schema == request.result && Profile.Value.externalValid context.source.schemas value) .type
    let transition ← scopedValue { state with status := .running } value
    return { transition with events := [.resultAccepted occurrence value] }
  | .cancel reason =>
    match reason with
    | .text bytes => require (Profile.UTF8.valid bytes) .type
    | .bytes _ => pure ()
    if state.cancellation.isSome then return ⟨state, []⟩
    let after := { state with cancellation := some reason }
    if cleanupRunning state then
      let events := match state.status with
        | .parked request => [.requestRebound request.occurrence]
        | _ => []
      return ⟨after, events⟩
    else return ⟨{ after with status := .running, control := cancelControl state.control reason }, []⟩

inductive Step (context : Context) : State → List Event → State → Prop where
  | internal : tick before context = .ok ⟨after, events⟩ → Step context before events after
  | external : external before context action = .ok ⟨after, events⟩ → Step context before events after

inductive Steps (context : Context) : State → List Event → State → Prop where
  | refl : Steps context state [] state
  | cons : Step context before first middle → Steps context middle rest after →
      Steps context before (first ++ rest) after

theorem steps_trans (first : Steps context before left middle) (second : Steps context middle right after) :
    Steps context before (left ++ right) after := by
  induction first with
  | refl => simpa using second
  | cons step _ induction => simpa [List.append_assoc] using Steps.cons step (induction second)

theorem parked_poll_has_no_event (state : State) (context : Context) (request : Request)
    (parked : state.status = .parked request) : tick state context = .ok ⟨state, []⟩ := by simp [tick, parked]

theorem yielded_poll_has_no_event (state : State) (context : Context)
    (yielded : state.status = .yielded) : tick state context = .ok ⟨state, []⟩ := by simp [tick, yielded]

/-- A rejected external action has no candidate successor to commit. -/
def attempt (state : State) (context : Context) (action : External) : Transition :=
  match external state context action with
  | .error _ => ⟨state, []⟩
  | .ok transition => transition

theorem rejection_retains_state (state : State) (context : Context) (action : External) (reason : Invalid)
    (rejected : external state context action = .error reason) : attempt state context action = ⟨state, []⟩ := by
  simp [attempt, rejected]

theorem repeated_cancel_retains_machine (state : State) (context : Context) (first next : Protocol.Reason)
    (active : state.status = .running) (existing : state.cancellation = some first)
    (valid : match next with | .text bytes => Profile.UTF8.valid bytes = true | .bytes _ => True) :
    external state context (.cancel next) = .ok ⟨state, []⟩ := by
  cases next <;> simp [external, active, existing, require, valid, bind, Except.bind] <;> rfl

theorem cancellation_view_preserves_failure (state : State) (exit : Cleanup.Exit .source)
    (value : SemanticValue) (failure : exit.primary = .failure value) :
    (observedExit state exit).primary = .failure value := by
  cases found : state.cancellation <;> simp [observedExit, Cleanup.cancel, failure, found]

end BoundaryV2.Profile.Source.Machine
