import BoundaryV2.Control

namespace BoundaryV2.Effects

open Core Control

/-- A lexical region contains one mathematical-number cell. Region references
are finite indices; first-order result values cannot contain such references. -/
inductive Heap : Nat → Type where
  | nil : Heap 0
  | cons : Nat → Heap n → Heap (n + 1)

def Heap.read : Heap n → Fin n → Nat
  | .cons value rest, index => Fin.cases value (rest.read) index

def Heap.write : Heap n → Fin n → Nat → Heap n
  | .cons value rest, index, next =>
    Fin.cases (.cons next rest) (fun index => .cons value (rest.write index next)) index

/-- A template stores only the local region prefix. There is no constructor
that can store the outer heap at the capture boundary. -/
inductive LocalHeap : Nat → Nat → Type where
  | done : LocalHeap n n
  | cons : Nat → LocalHeap n m → LocalHeap (n + 1) m

def LocalHeap.restore : LocalHeap n m → Heap m → Heap n
  | .done, outside => outside
  | .cons value rest, outside => .cons value (rest.restore outside)

/-- Capability evidence is separate from ordinary values. Only handler entry
extends this environment; an operation selects an existing evidence slot. -/
abbrev Capabilities (n : Nat) := Vector Nat n

abbrev Atom := List Ty → Ty → Type
abbrev Evaluator (A : Atom) := {ctx : List Ty} → {t : Ty} → A ctx t → Values ctx → Value t

def number : Value .number → Nat
  | .number value => value

def boolean : Value .boolean → Bool
  | .boolean value => value

/-- Clause plans form the checked finite core: disposal, one non-tail resume,
or a left-to-right fold of reusable resumptions. Each postprocessor returns the
handler answer directly. Clause and return expressions are pure in this core. -/
inductive Plan (A : Atom) (ctx : List Ty) (body answer : Ty) where
  | dispose : A (.number :: ctx) answer → Plan A ctx body answer
  | once : (mode : Mode) → A (.number :: ctx) .number →
      A (mode.result body answer :: .number :: ctx) answer → Plan A ctx body answer
  | multi : (mode : Mode) → List (A (.number :: ctx) .number) →
      A (.number :: ctx) answer →
      A (mode.result body answer :: answer :: .number :: ctx) answer → Plan A ctx body answer

structure Handler (A : Atom) (ctx : List Ty) (body answer : Ty) where
  returned : A (body :: ctx) answer
  clause : Plan A ctx body answer

/-- The source control language admits effects in either side of bind, under
branches, and under nested handlers and regions. It has one Nat -> Nat effect
family with arbitrarily many explicit capability instances. -/
inductive Flow (A : Atom) : Nat → Nat → List Ty → Ty → Type where
  | pure : A ctx a → Flow A regions caps ctx a
  | bind : Flow A regions caps ctx a → Flow A regions caps (a :: ctx) b →
      Flow A regions caps ctx b
  | branch : A ctx .boolean → Flow A regions caps ctx a → Flow A regions caps ctx a →
      Flow A regions caps ctx a
  | perform : Fin caps → A ctx .number → Flow A regions caps ctx .number
  | handle : Handler A ctx body answer → Flow A regions (caps + 1) ctx body →
      Flow A regions caps ctx answer
  | region : A ctx .number → Flow A (regions + 1) caps ctx a → Flow A regions caps ctx a
  | read : Fin regions → Flow A regions caps ctx .number
  | write : Fin regions → A ctx .number → Flow A regions caps ctx .unit

mutual
  /-- All suspended source computations and clause callers are explicit data.
  A repeat frame owns an immutable template, never a live one-shot handle. -/
  inductive Frame (A : Atom) : Nat → Ty → Nat → Ty → Type where
    | bind : Flow A regions caps (a :: ctx) b → Values ctx → Capabilities caps →
        Frame A regions a regions b
    | delimiter : Nat → Handler A ctx a b → Values ctx → Frame A regions a regions b
    | region : Frame A (regions + 1) a regions a
    | post : A (a :: ctx) b → Values ctx → Frame A regions a regions b
    | repeat : Stack A inside .number regions a → LocalHeap inside regions → List Nat → Value b →
        A (a :: b :: ctx) b → Values ctx → Frame A regions a regions b

  inductive Stack (A : Atom) : Nat → Ty → Nat → Ty → Type where
    | done : Stack A regions a regions a
    | push : Frame A regions a middle b → Stack A middle b outside c →
        Stack A regions a outside c
end

/-- Induction on the active spine; dormant templates in repeat frames need not
be inspected for properties that only depend on the traversed region suffix. -/
theorem Stack.spine_induction
    {motive : (r : Nat) → (a : Ty) → (s : Nat) → (b : Ty) → Stack A r a s b → Prop}
    (done : ∀ {r a}, motive r a r a .done)
    (push : ∀ {r a s b t c} (frame : Frame A r a s b) (rest : Stack A s b t c),
      motive s b t c rest → motive r a t c (.push frame rest))
    (stack : Stack A r a s b) : motive r a s b stack :=
  Stack.rec (motive_1 := fun _ _ _ _ _ => True) (motive_2 := motive)
    (fun _ _ _ => True.intro) (fun _ _ _ => True.intro) True.intro
    (fun _ _ => True.intro) (fun _ _ _ _ _ _ _ => True.intro)
    done (fun frame rest _ ih => push frame rest ih) stack

def Stack.append : Stack A r a s b → Stack A s b t c → Stack A r a t c
  | .done, after => after
  | .push frame rest, after => .push frame (rest.append after)

/-- Remove precisely the local region prefix crossed by this continuation. -/
def Stack.outerHeap (stack : Stack A r a s b) : Heap r → Heap s :=
  match stack with
  | .done => fun heap => heap
  | .push frame rest =>
    match frame with
    | .region => fun | .cons _ heap => rest.outerHeap heap
    | .bind _ _ _ | .delimiter _ _ _ | .post _ _ | .repeat _ _ _ _ _ _ => rest.outerHeap

/-- Freeze exactly the local cells crossed by the captured control spine. -/
def Stack.freezeHeap (stack : Stack A r a s b) : Heap r → LocalHeap r s :=
  match stack with
  | .done => fun _ => .done
  | .push frame rest =>
    match frame with
    | .region => fun | .cons value localHeap => .cons value (rest.freezeHeap localHeap)
    | .bind _ _ _ | .delimiter _ _ _ | .post _ _ | .repeat _ _ _ _ _ _ => rest.freezeHeap

def Stack.attachments : Stack A r a s b → List Nat
  | .done => []
  | .push (.delimiter identity _ _) rest => identity :: rest.attachments
  | .push _ rest => rest.attachments

mutual
  def Frame.rename (rename : Nat → Nat) : Frame A r a s b → Frame A r a s b
    | .bind body env caps => .bind body env (caps.map rename)
    | .delimiter identity handler env => .delimiter (rename identity) handler env
    | .region => .region
    | .post expression env => .post expression env
    | .repeat template heap arguments acc fold env =>
      .repeat (template.rename rename) heap arguments acc fold env

  def Stack.rename (rename : Nat → Nat) : Stack A r a s b → Stack A r a s b
    | .done => .done
    | .push frame rest => .push (frame.rename rename) (rest.rename rename)
end

/-- The finite substitution affects captured delimiter identities and all their
aliases, including aliases in a nested dormant template. Other capabilities
remain shared. Allocation consumes a fresh interval of the identity supply. -/
def renameLocal (ids : List Nat) (fresh identity : Nat) : Nat :=
  if identity ∈ ids then fresh + ids.idxOf identity else identity

def Stack.activate (template : Stack A r a s b) (fresh : Nat) : Stack A r a s b × Nat :=
  (template.rename (renameLocal template.attachments fresh), fresh + template.attachments.length)

structure Selected (A : Atom) (regions : Nat) (input : Ty) (outside : Nat) (output : Ty) where
  atRegion : Nat
  body : Ty
  answer : Ty
  ctx : List Ty
  identity : Nat
  inside : Stack A regions input atRegion body
  handler : Handler A ctx body answer
  env : Values ctx
  outsideStack : Stack A atRegion answer outside output

def Selected.prepend (selected : Selected A s b t c) (frame : Frame A r a s b) :
    Selected A r a t c :=
  { selected with inside := .push frame selected.inside }

def select (identity : Nat) : Stack A r a s b → Option (Selected A r a s b)
  | .done => none
  | .push (.delimiter actual handler env) rest =>
    if identity = actual then some ⟨_, _, _, _, actual, .done, handler, env, rest⟩
    else (select identity rest).map (fun selected => selected.prepend (.delimiter actual handler env))
  | .push frame rest => (select identity rest).map (fun selected => selected.prepend frame)

def Selected.capture (selected : Selected A r a s b) (mode : Mode) :
    Stack A r a selected.atRegion (mode.result selected.body selected.answer) :=
  match mode with
  | .deep => selected.inside.append
      (.push (.delimiter selected.identity selected.handler selected.env) .done)
  | .shallow => selected.inside

inductive Focus (A : Atom) (regions : Nat) (result : Ty) where
  | code : Flow A regions caps ctx result → Values ctx → Capabilities caps → Focus A regions result
  | value : Value result → Focus A regions result

structure Position (A : Atom) (outside : Nat) (result : Ty) where
  regions : Nat
  input : Ty
  focus : Focus A regions input
  heap : Heap regions
  stack : Stack A regions input outside result

structure Pending (A : Atom) (outside : Nat) (result : Ty) where
  regions : Nat
  identity : Nat
  payload : Nat
  token : Nat
  heap : Heap regions
  stack : Stack A regions .number outside result

inductive Status (A : Atom) (outside : Nat) (result : Ty) where
  | running : Position A outside result → Status A outside result
  | pending : Pending A outside result → Status A outside result
  | returned : Value result → Status A outside result
  | disposed : Status A outside result
  | transferred : Pending A outside result → Status A outside result

structure Machine (A : Atom) (outside : Nat) (result : Ty) where
  ownership : Ownership
  freshAttachment : Nat
  status : Status A outside result

/-- A handled operation's capture is consumed before control enters a resumed
body. No live token is stored in a bind, postprocessor, or repeat frame. -/
def _root_.BoundaryV2.Ownership.finishCapture (state : Ownership) : Ownership :=
  ⟨state.fresh + 1, state.live, state.fresh :: state.spent⟩

theorem finish_capture_is_capture_then_consume (state : Ownership) :
    state.capture.consume state.fresh = some state.finishCapture := by
  simp [BoundaryV2.Ownership.capture, BoundaryV2.Ownership.consume, Ownership.finishCapture]

theorem finish_capture_preserves_ownership (state : Ownership) (valid : state.Valid) :
    state.finishCapture.Valid :=
  consume_preserves_ownership state.capture state.finishCapture state.fresh
    (capture_preserves_ownership state valid) (finish_capture_is_capture_then_consume state)

def returnValue (eval : Evaluator A) (machine : Machine A outside result)
    (value : Value a) (heap : Heap regions) (stack : Stack A regions a outside result) : Machine A outside result :=
  match stack, heap, value with
  | .done, _, value => { machine with status := .returned value }
  | .push (.bind body env caps) rest, heap, value =>
    { machine with status := .running ⟨_, _, .code body (.cons value env) caps, heap, rest⟩ }
  | .push (.delimiter _ handler env) rest, heap, value =>
    { machine with status := .running ⟨_, _, .value (eval handler.returned (.cons value env)), heap, rest⟩ }
  | .push .region rest, .cons _ outside, value =>
    { machine with status := .running ⟨_, _, .value value, outside, rest⟩ }
  | .push (.post expression env) rest, heap, value =>
    { machine with status := .running ⟨_, _, .value (eval expression (.cons value env)), heap, rest⟩ }
  | .push (.repeat template frozen arguments acc fold env) rest, heap, value =>
    let nextAcc := eval fold (.cons value (.cons acc env))
    match arguments with
    | [] => { machine with status := .running ⟨_, _, .value nextAcc, heap, rest⟩ }
    | argument :: arguments =>
      let activated := template.activate machine.freshAttachment
      { ownership := machine.ownership.finishCapture, freshAttachment := activated.2,
        status := .running ⟨_, _, .value (.number argument), frozen.restore heap,
          activated.1.append (.push (.repeat template frozen arguments nextAcc fold env) rest)⟩ }

def dispatch (eval : Evaluator A) (machine : Machine A outside result) (payload : Nat)
    (heap : Heap regions) (selected : Selected A regions .number outside result) : Machine A outside result :=
  let clauseEnv := Values.cons (.number payload) selected.env
  let outsideHeap := selected.inside.outerHeap heap
  let consumed := machine.ownership.finishCapture
  match selected.handler.clause with
  | .dispose expression =>
    { machine with
      ownership := consumed,
      status := .running ⟨_, _, .value (eval expression clauseEnv), outsideHeap, selected.outsideStack⟩ }
  | .once mode argument post =>
    { machine with
      ownership := consumed,
      status := .running ⟨_, _, .value (eval argument clauseEnv), heap,
        (selected.capture mode).append (.push (.post post clauseEnv) selected.outsideStack)⟩ }
  | .multi mode arguments seed fold =>
    let acc := eval seed clauseEnv
    match arguments.map (fun expression => number (eval expression clauseEnv)) with
    | [] => { machine with
        ownership := consumed,
        status := .running ⟨_, _, .value acc, outsideHeap, selected.outsideStack⟩ }
    | argument :: arguments =>
      let template := selected.capture mode
      let frozen := template.freezeHeap heap
      let activated := template.activate machine.freshAttachment
      { ownership := consumed.finishCapture, freshAttachment := activated.2,
        status := .running ⟨_, _, .value (.number argument), frozen.restore outsideHeap,
          activated.1.append (.push (.repeat template frozen arguments acc fold clauseEnv) selected.outsideStack)⟩ }

/-- One internal transition. It has no semantic fuel, admission oracle, host
callback, or error alternative. Residual effects and terminal states park. -/
def tick (eval : Evaluator A) (machine : Machine A outside result) : Machine A outside result :=
  match machine.status with
  | .running ⟨regions, input, focus, heap, stack⟩ =>
    match focus with
    | .value value => returnValue eval machine value heap stack
    | .code expression env caps =>
      match expression with
      | .pure expression =>
        { machine with status := .running ⟨regions, input, .value (eval expression env), heap, stack⟩ }
      | .bind first after =>
        { machine with status := .running ⟨_, _, .code first env caps, heap, .push (.bind after env caps) stack⟩ }
      | .branch condition yes no =>
        { machine with status := .running ⟨_, _, .code (if boolean (eval condition env) then yes else no) env caps, heap, stack⟩ }
      | .perform index payload =>
        let identity := caps[index]
        let argument := number (eval payload env)
        match select identity stack with
        | none => { machine with
            ownership := machine.ownership.capture,
            status := .pending ⟨_, identity, argument, machine.ownership.fresh, heap, stack⟩ }
        | some selected => dispatch eval machine argument heap selected
      | .handle handler body =>
        { machine with
          freshAttachment := machine.freshAttachment + 1,
          status := .running ⟨_, _, .code body env ((#[machine.freshAttachment].toVector ++ caps).cast (by simp [Nat.add_comm])), heap,
            .push (.delimiter machine.freshAttachment handler env) stack⟩ }
      | .region initial body =>
        { machine with status := .running ⟨_, _, .code body env caps,
            .cons (number (eval initial env)) heap, .push .region stack⟩ }
      | .read index =>
        { machine with status := .running ⟨_, _, .value (.number (heap.read index)), heap, stack⟩ }
      | .write index expression =>
        { machine with status := .running ⟨_, _, .value .unit, heap.write index (number (eval expression env)), stack⟩ }
  | _ => machine

inductive Input where
  | internal | resume (value : Nat) | dispose | transfer
  deriving DecidableEq, Repr

/-- An invalid external action rejects without changing the state. A residual
continuation is consumed before it can become running, disposed, or transferred. -/
def transition (eval : Evaluator A) (machine : Machine A outside result) : Input → Option (Machine A outside result)
  | .internal => some (tick eval machine)
  | action =>
    match machine.status with
    | .pending pending => do
      let consumed ← machine.ownership.consume pending.token
      let status := match action with
        | .resume value => Status.running ⟨_, _, .value (.number value), pending.heap, pending.stack⟩
        | .dispose => .disposed
        | .transfer => .transferred pending
        | .internal => .pending pending
      return { machine with ownership := consumed, status }
    | _ => none

/-- A machine owns all live linear captures through its sole pending position.
This core has no resource values or obligations; these cannot hide in frames. -/
def Machine.Valid (machine : Machine A outside result) : Prop :=
  machine.ownership.Valid ∧
  match machine.status with
  | .pending pending => machine.ownership.live = [pending.token]
  | _ => machine.ownership.live = []

def initial (body : Flow A 0 caps [] result) (capabilities : Capabilities caps)
    (fresh : Nat) : Machine A 0 result :=
  ⟨.empty, fresh, .running ⟨0, result, .code body .nil capabilities, .nil, .done⟩⟩

theorem initial_is_well_owned (body : Flow A 0 caps [] result)
    (capabilities : Capabilities caps) (fresh : Nat) : (initial body capabilities fresh).Valid :=
  ⟨ownership_empty_valid, rfl⟩

theorem return_preserves_ownership (eval : Evaluator A) (machine : Machine A outside result)
    (value : Value a) (heap : Heap regions) (stack : Stack A regions a outside result)
    (valid : machine.ownership.Valid) (empty : machine.ownership.live = []) :
    (returnValue eval machine value heap stack).Valid := by
  cases stack with
  | done => exact ⟨valid, empty⟩
  | push frame rest =>
    cases frame with
    | bind => exact ⟨valid, empty⟩
    | delimiter => exact ⟨valid, empty⟩
    | region => cases heap; exact ⟨valid, empty⟩
    | post => exact ⟨valid, empty⟩
    | «repeat» template frozen arguments acc fold env =>
      cases arguments with
      | nil => exact ⟨valid, empty⟩
      | cons argument arguments =>
        exact ⟨finish_capture_preserves_ownership machine.ownership valid, empty⟩

theorem dispatch_preserves_ownership (eval : Evaluator A) (machine : Machine A outside result)
    (payload : Nat) (heap : Heap regions) (selected : Selected A regions .number outside result)
    (valid : machine.ownership.Valid) (empty : machine.ownership.live = []) :
    (dispatch eval machine payload heap selected).Valid := by
  have finished := finish_capture_preserves_ownership machine.ownership valid
  cases clause : selected.handler.clause with
  | dispose => simp only [dispatch, clause, Machine.Valid]; exact ⟨finished, empty⟩
  | once => simp only [dispatch, clause, Machine.Valid]; exact ⟨finished, empty⟩
  | multi mode arguments seed fold =>
    simp only [dispatch, clause]
    split
    · exact ⟨finished, empty⟩
    · exact ⟨finish_capture_preserves_ownership machine.ownership.finishCapture finished, empty⟩

/-- Every internal control constructor preserves unique ownership. Region and
value typing are preserved by the indexed result of `tick`: a successor has
the same root scope and result type, and every cell access still has a Fin
index into its actual heap. No preservation premise assumes a successful tick. -/
theorem tick_preserves_invariants (eval : Evaluator A) (machine : Machine A outside result)
    (valid : machine.Valid) : (tick eval machine).Valid := by
  rcases valid with ⟨owned, custody⟩
  cases state : machine.status with
  | pending => simpa [tick, state, Machine.Valid] using And.intro owned custody
  | returned => simpa [tick, state, Machine.Valid] using And.intro owned custody
  | disposed => simpa [tick, state, Machine.Valid] using And.intro owned custody
  | transferred => simpa [tick, state, Machine.Valid] using And.intro owned custody
  | running position =>
    simp only [state] at custody
    rcases position with ⟨regions, input, focus, heap, stack⟩
    cases focus with
    | value value =>
      simpa [tick, state] using return_preserves_ownership eval machine value heap stack owned custody
    | code expression env caps =>
      cases expression with
      | pure => simpa [tick, state, Machine.Valid] using And.intro owned custody
      | bind => simpa [tick, state, Machine.Valid] using And.intro owned custody
      | branch => simpa [tick, state, Machine.Valid] using And.intro owned custody
      | handle => simpa [tick, state, Machine.Valid] using And.intro owned custody
      | region => simpa [tick, state, Machine.Valid] using And.intro owned custody
      | read => simpa [tick, state, Machine.Valid] using And.intro owned custody
      | write => simpa [tick, state, Machine.Valid] using And.intro owned custody
      | perform index payload =>
        simp only [tick, state]
        split
        next =>
          exact ⟨capture_preserves_ownership machine.ownership owned,
            by simp [BoundaryV2.Ownership.capture, custody]⟩
        next selected found =>
          exact dispatch_preserves_ownership eval machine (number (eval payload env)) heap selected owned custody

theorem transition_preserves_invariants (eval : Evaluator A) (machine next : Machine A outside result)
    (input : Input) (valid : machine.Valid) (step : transition eval machine input = some next) :
    next.Valid := by
  cases input with
  | internal =>
    have equal : tick eval machine = next := Option.some.inj step
    exact equal ▸ tick_preserves_invariants eval machine valid
  | resume value | dispose | transfer =>
    cases state : machine.status <;> try simp [transition, state] at step
    next pending =>
      have owned := valid.1
      have custody : machine.ownership.live = [pending.token] := by simpa [Machine.Valid, state] using valid.2
      have consumed : machine.ownership.consume pending.token =
          some ⟨machine.ownership.fresh, [], pending.token :: machine.ownership.spent⟩ := by
        simp [BoundaryV2.Ownership.consume, custody]
      simp [consumed] at step
      subst next
      exact ⟨consume_preserves_ownership _ _ _ owned consumed, rfl⟩

/-- This is a disposition of this live machine, not a historical anti-replay
claim about independently copied snapshots. The spent token cannot be reused
even for a different terminal action in the successor ledger. -/
theorem residual_disposition_consumes_once (eval : Evaluator A)
    (machine next : Machine A outside result) (pending : Pending A outside result)
    (input : Input) (external : input ≠ .internal) (valid : machine.Valid)
    (parked : machine.status = .pending pending)
    (step : transition eval machine input = some next) :
    next.ownership.consume pending.token = none := by
  cases input with
  | internal => exact False.elim (external rfl)
  | resume value | dispose | transfer =>
    cases consumed : machine.ownership.consume pending.token with
    | none => simp [transition, parked, consumed] at step
    | some after =>
      simp [transition, parked, consumed] at step
      subst next
      exact consumed_token_cannot_resume _ _ _ valid.1 consumed

theorem live_residual_progress (eval : Evaluator A) (machine : Machine A outside result)
    (pending : Pending A outside result) (valid : machine.Valid)
    (parked : machine.status = .pending pending) (input : Input) :
    ∃ next, transition eval machine input = some next ∧ next.Valid := by
  have custody : machine.ownership.live = [pending.token] := by simpa [Machine.Valid, parked] using valid.2
  have consumed : machine.ownership.consume pending.token =
      some ⟨machine.ownership.fresh, [], pending.token :: machine.ownership.spent⟩ := by
    simp [BoundaryV2.Ownership.consume, custody]
  have existsNext : ∃ next, transition eval machine input = some next := by
    cases input <;> simp [transition, parked, consumed]
  obtain ⟨next, step⟩ := existsNext
  exact ⟨next, step, transition_preserves_invariants eval machine next input valid step⟩

inductive Observation (result : Ty) where
  | request : Nat → Nat → Observation result
  | returned : Value result → Observation result
  | disposed : Observation result
  | transferred : Nat → Nat → Observation result

def observe (machine : Machine A outside result) : Option (Observation result) :=
  match machine.status with
  | .running _ => none
  | .pending pending => some (.request pending.identity pending.payload)
  | .returned value => some (.returned value)
  | .disposed => some .disposed
  | .transferred pending => some (.transferred pending.identity pending.payload)

/-- Global progress: the machine exposes a terminal/residual observation, or
its running control takes a well-typed, scope-preserving, well-owned step. -/
theorem machine_progress (eval : Evaluator A) (machine : Machine A outside result)
    (valid : machine.Valid) :
    (∃ observation, observe machine = some observation) ∨
    (observe machine = none ∧ ∃ next, transition eval machine .internal = some next ∧ next.Valid) := by
  cases state : machine.status with
  | running => exact .inr ⟨by simp [observe, state], _, rfl, tick_preserves_invariants eval machine valid⟩
  | pending pending => exact .inl ⟨.request pending.identity pending.payload, by simp [observe, state]⟩
  | returned value => exact .inl ⟨.returned value, by simp [observe, state]⟩
  | disposed => exact .inl ⟨.disposed, by simp [observe, state]⟩
  | transferred pending => exact .inl ⟨.transferred pending.identity pending.payload, by simp [observe, state]⟩

theorem rebasing_preserves_current_outer_heap (stack : Stack A r a s b)
    (frozen : Heap r) (outside : Heap s) :
    stack.outerHeap ((stack.freezeHeap frozen).restore outside) = outside := by
  induction stack using Stack.spine_induction with
  | done => rfl
  | push frame rest ih =>
    cases frame with
    | bind | delimiter | post | «repeat» => exact ih frozen outside
    | region => cases frozen; exact ih _ outside

end BoundaryV2.Effects
