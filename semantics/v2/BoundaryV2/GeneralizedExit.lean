import BoundaryV2.GeneralizedCalls
import BoundaryV2.GeneralizedOwnership

namespace BoundaryV2.Generalized

namespace ExitInfo

/-- Cancellation records the first accepted reason. An original failure keeps
precedence; accepting cancellation does not append a cleanup failure. -/
def cancel (reason : Reason) (exit : ExitInfo Fault Reason) : ExitInfo Fault Reason :=
  { exit with
    primary := match exit.primary with | .failure fault => .failure fault | _ => .cancelled
    cancellation := exit.cancellation.or (some reason) }

def cleanupFailure (fault : Fault) (exit : ExitInfo Fault Reason) : ExitInfo Fault Reason :=
  { exit with
    primary := match exit.primary with
      | .normal | .abandoned => .failure fault
      | other => other
    failures := exit.failures ++ [fault] }

def abandon (exit : ExitInfo Fault Reason) : ExitInfo Fault Reason :=
  { exit with primary := match exit.primary with
      | .failure fault => .failure fault
      | .cancelled => .cancelled
      | _ => .abandoned }

theorem cancel_keeps_first_reason (first later : Reason) (exit : ExitInfo Fault Reason) :
    cancel later (cancel first exit) = cancel first exit := by
  cases exit with
  | mk primary failures cancellation => cases primary <;> cases cancellation <;> rfl

theorem failure_order (first second : Fault) (exit : ExitInfo Fault Reason) :
    (cleanupFailure second (cleanupFailure first exit)).failures = exit.failures ++ [first, second] := by
  simp [cleanupFailure, List.append_assoc]

theorem cancellation_preserves_original_failure (fault : Fault) (reason : Reason)
    (failures : List Fault) (accepted : Option Reason) :
    (cancel reason ⟨.failure fault, failures, accepted⟩).primary = .failure fault := rfl

theorem abandonment_preserves_original_failure (fault : Fault)
    (failures : List Fault) (accepted : Option Reason) :
    (abandon ⟨.failure fault, failures, accepted⟩).primary = .failure fault := rfl

end ExitInfo

namespace ExitComposition

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {definitions : List (BodyType signature.Data signature.Effect)}

/-- Cleanup runs the same first-order target code as an ordinary computation,
with a unit answer. There is no second cursor representation to keep in sync. -/
abbrev Cursor (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (definitions : List (BodyType signature.Data signature.Effect)) :=
  Target.Configuration signature algebra definitions .unit

def pendingProtections : Target.Stack signature algebra definitions input result → List (Id .obligation)
  | .done => []
  | .push (.protection obligationId _ _) rest => obligationId :: pendingProtections rest
  | .push _ rest => pendingProtections rest

def cursorProtections : Cursor signature algebra definitions → List (Id .obligation)
  | .code _ _ _ future | .returned _ future | .requested _ _ _ _ future | .failed _ future => pendingProtections future
  | .yielded next => cursorProtections next

inductive Location where
  | active
  | captured : Id .control → Location
  | parked
  deriving DecidableEq

inductive Completion (Fault : Type) where
  | returned
  | failed : Fault → Completion Fault
  | abandoned

structure Cleanup (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (definitions : List (BodyType signature.Data signature.Effect)) where
  context : List (TypeOf signature)
  body : Target.Code signature algebra definitions (.exit :: context) [] .unit
  environment : Target.RuntimeEnvironment signature algebra definitions context

/-- Only pending carries the right to initiate. Running carries the actual
future, wherever it is held; terminal states cannot be started again. -/
inductive Phase (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (definitions : List (BodyType signature.Data signature.Effect)) where
  | pending : Cleanup signature algebra definitions → Phase signature algebra definitions
  | running : Cursor signature algebra definitions → Location → Phase signature algebra definitions
  | finished : Completion algebra.Fault → Phase signature algebra definitions

structure Obligation (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (definitions : List (BodyType signature.Data signature.Effect)) where
  id : Id .obligation
  phase : Phase signature algebra definitions
  fields : List UseScope.Field
  exit : ExitInfo algebra.Fault algebra.Reason

def Phase.right : Phase signature algebra definitions → Nat
  | .pending _ => 1
  | .running _ _ | .finished _ => 0

def cancel (reason : algebra.Reason) (obligation : Obligation signature algebra definitions) :=
  { obligation with exit := obligation.exit.cancel reason }

theorem cancel_preserves_future (reason : algebra.Reason) (obligation : Obligation signature algebra definitions) :
    (cancel reason obligation).phase = obligation.phase := rfl

theorem cancel_preserves_owning_fields (reason : algebra.Reason) (obligation : Obligation signature algebra definitions) :
    (cancel reason obligation).fields = obligation.fields := rfl

theorem repeated_cancellation (first later : algebra.Reason) (obligation : Obligation signature algebra definitions) :
    cancel later (cancel first obligation) = cancel first obligation := by
  cases obligation
  simp only [cancel, ExitInfo.cancel_keeps_first_reason]

/-- Local lifecycle transitions include actual target instructions as well as
initiation, storage, response handoff, and the three terminal outcomes. The Nat label counts actual
initiations, not machine steps or semantic fuel. -/
inductive Step (table : Target.Definitions signature algebra definitions) : Obligation signature algebra definitions → Nat → Obligation signature algebra definitions → Prop where
  | begin : Step table ⟨obligationId, .pending entry, fields, exit⟩ 1
      ⟨obligationId, .running (.code entry.body (.cons (.exit exit) entry.environment) .nil .done) .active, fields, exit⟩
  | execute : Target.CallStep table before after →
      Step table ⟨obligationId, .running before .active, fields, exit⟩ 0
        ⟨obligationId, .running after .active, fields, exit⟩
  | capture : Step table ⟨obligationId, .running cursor .active, fields, exit⟩ 0
      ⟨obligationId, .running cursor (.captured controlId), fields, exit⟩
  | reattach : Step table ⟨obligationId, .running cursor (.captured controlId), fields, exit⟩ 0
      ⟨obligationId, .running cursor .active, fields, exit⟩
  | park : Step table ⟨obligationId, .running (.requested operation attachment payload bodies future) .active, fields, exit⟩ 0
      ⟨obligationId, .running (.requested operation attachment payload bodies future) .parked, fields, exit⟩
  | parkYield : Step table ⟨obligationId, .running (.yielded future) .active, fields, exit⟩ 0
      ⟨obligationId, .running (.yielded future) .parked, fields, exit⟩
  | continueYield : Step table ⟨obligationId, .running (.yielded future) .parked, fields, exit⟩ 0
      ⟨obligationId, .running future .active, fields, exit⟩
  | response : Step table ⟨obligationId, .running (.requested operation attachment payload bodies future) .parked, fields, exit⟩ 0
      ⟨obligationId, .running (.returned response future) .active, fields, exit⟩
  | cancelled : Step table obligation 0 (cancel reason obligation)
  | returned : Step table ⟨obligationId, .running (.returned (.datum .unit) .done) .active, fields, exit⟩ 0
      ⟨obligationId, .finished .returned, fields, exit⟩
  | failed : Step table ⟨obligationId, .running (.failed fault .done) .active, fields, exit⟩ 0
      ⟨obligationId, .finished (.failed fault), fields, exit.cleanupFailure fault⟩
  | abandoned : cursorProtections cursor = [] → Step table ⟨obligationId, .running cursor location, fields, exit⟩ 0
      ⟨obligationId, .finished .abandoned, fields, exit.abandon⟩

theorem step_preserves_fields (step : Step table before initiations after) : after.fields = before.fields := by
  cases step <;> rfl

theorem initiation_conservation (step : Step table before initiations after) :
    initiations + after.phase.right = before.phase.right := by
  cases step <;> simp [Phase.right, cancel]

inductive Steps (table : Target.Definitions signature algebra definitions) : Obligation signature algebra definitions → Nat → Obligation signature algebra definitions → Prop where
  | refl : Steps table state 0 state
  | cons : Step table first count middle → Steps table middle rest last → Steps table first (count + rest) last

theorem execute_steps (steps : Target.CallSteps table before count after) :
    Steps table ⟨obligationId, .running before .active, fields, exit⟩ 0
      ⟨obligationId, .running after .active, fields, exit⟩ := by
  induction steps with
  | refl => exact .refl
  | cons step tail induction => exact .cons (.execute step) induction

theorem finite_initiation_conservation (steps : Steps table before initiations after) :
    initiations + after.phase.right = before.phase.right := by
  induction steps with
  | refl => simp
  | cons step rest induction =>
    rw [Nat.add_assoc, induction]
    exact initiation_conservation step

theorem at_most_one_initiation (steps : Steps table before initiations after) : initiations ≤ 1 := by
  have conserved := finite_initiation_conservation steps
  have bounded : before.phase.right ≤ 1 := by cases before.phase <;> simp [Phase.right]
  omega

theorem running_never_restarts
    (steps : Steps table ⟨obligationId, .running cursor location, fields, exit⟩ initiations after) : initiations = 0 := by
  have conserved := finite_initiation_conservation steps
  simp only [Phase.right] at conserved
  omega

theorem finite_steps_preserve_fields (steps : Steps table before initiations after) : after.fields = before.fields := by
  induction steps with
  | refl => rfl
  | cons step rest induction => exact induction.trans (step_preserves_fields step)

/-- An operand stays in the evaluating scope until all operands are ready.
The earlier values are actual fields, in evaluation order. On failure, the same
fields go to unwinding; there is no premature transfer to an incomplete call. -/
structure OperandScope where
  collected : List UseScope.Field
  outer : List (List UseScope.Field)

def acceptOperand (scope : OperandScope) (value : UseScope.Field) : OperandScope :=
  { scope with collected := scope.collected ++ [value] }

def receiveOperands (scope : OperandScope) : List UseScope.Field × List (List UseScope.Field) :=
  (scope.collected, scope.outer)

/-- The scope list is innermost first; fields within a scope are oldest first.
Flattening deliberately preserves both orders and every repeated occurrence. -/
def unwindOrder (scopes : List (List UseScope.Field)) : List UseScope.Field := scopes.flatten

def operandFailure (scope : OperandScope) := unwindOrder (scope.collected :: scope.outer)

theorem failed_later_operand_preserves_earlier (scope : OperandScope) :
    operandFailure scope = scope.collected ++ unwindOrder scope.outer := rfl

theorem ready_handoff_preserves_fields (scope : OperandScope) :
    (receiveOperands scope).1 ++ unwindOrder (receiveOperands scope).2 = operandFailure scope := rfl

theorem inner_scope_before_outer (inner outer : List (List UseScope.Field)) :
    unwindOrder (inner ++ outer) = unwindOrder inner ++ unwindOrder outer := List.flatten_append

theorem creation_order (scope : OperandScope) (first second : UseScope.Field) :
    (acceptOperand (acceptOperand scope first) second).collected = scope.collected ++ [first, second] := by
  simp [acceptOperand, List.append_assoc]

theorem operand_failure_preserves_multiplicity (scope : OperandScope) :
    UseScope.tokens (operandFailure scope) = UseScope.tokens scope.collected ++ UseScope.tokens (unwindOrder scope.outer) :=
  UseScope.tokens_append _ _

end ExitComposition
end BoundaryV2.Generalized
