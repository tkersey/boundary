import BoundaryV2.GeneralizedComputationCreation
import BoundaryV2.GeneralizedOperandLowering

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)} {Future : Type}

namespace Source

/-- The local authored-lambda boundary selects lexical captures and gives the
result its physical authority. The surrounding scope supplies the capture
partition and external support; borrowed lifetimes remain explicit premises
of the enclosing capture operation. -/
inductive ClosureEvaluation
    (bindings : RuntimeEnvironment signature algebra program context)
    (reserved : List (Id .custody)) :
    {type : TypeOf signature} → Expression signature algebra program context type →
    UseScope.ControlStore Future → RuntimeValue signature algebra program type →
    UseScope.ControlStore Future → Prop where
  | owned (use : UseScope.OneShotUse)
      (selection : Selection context capturedTypes)
      (body : Computation signature algebra program (parameters ++ capturedTypes) answer)
      (owner : Owner) (before after : List UseScope.Field)
      (store : UseScope.ControlStore Future)
      (partition : store.fields.active = before ++ (bindings.select selection).owningFields ++ after) :
      ClosureEvaluation bindings reserved (.lambda (use := use.type) selection body) store
        (createOwnedComputation use body (bindings.select selection) owner before after store partition reserved).value
        (createOwnedComputation use body (bindings.select selection) owner before after store partition reserved).store
  | shared (use : Use) (permitted : use = .reusable ∨ use = .multi)
      (selection : Selection context capturedTypes)
      (body : Computation signature algebra program (parameters ++ capturedTypes) answer)
      (copyable : (bindings.select selection).copyable = true) :
      ClosureEvaluation bindings reserved (.lambda (use := use) selection body) store
        (.closure body (bindings.select selection) none) store

theorem ClosureEvaluation.preserves_ownership
    (step : ClosureEvaluation bindings reserved expression before value after)
    (valid : UseScope.ControlStore.Valid before) : UseScope.ControlStore.Valid after := by
  cases step with
  | owned use selection body owner before after store partition =>
    exact created_computation_preserves_ownership valid partition
  | shared => exact valid

/-- Every admitted authored closure can cross the application boundary.
This includes owned grants and copyable shared captures without conflating
ordinary reuse permission with template instantiation. -/
theorem ClosureEvaluation.initializes_handoff
    {expression : Expression signature algebra program context (.computation use parameters answer)}
    {produced : RuntimeValue signature algebra program (.computation use parameters answer)}
    (step : ClosureEvaluation bindings reserved expression before produced after) :
    ∃ (capturedTypes : List (TypeOf signature))
      (body : Computation signature algebra program (parameters ++ capturedTypes) answer)
      (captured : RuntimeEnvironment signature algebra program capturedTypes)
      (authority : Option (Id .custody × Owner)) (fields : UseScope.State),
      produced = .closure body captured authority ∧ ComputationHandoff captured use authority after.fields fields := by
  cases step
  case owned =>
    rename_i capturedTypes mode captures owner left right body partition
    have entry := created_computation_can_enter (body := body) (use := mode)
      (captured := bindings.select captures) (owner := owner) (before := left) (after := right)
      (reserved := reserved) partition
    exact ⟨_, body, bindings.select captures, _, _, rfl, entry⟩
  case shared =>
    rename_i capturedTypes captures copyable permitted body
    exact ⟨_, body, bindings.select captures, none, _, rfl, .shared use permitted copyable⟩

theorem ClosureEvaluation.shared_result_copyable
    {expression : Expression signature algebra program context (.computation use parameters answer)}
    {produced : RuntimeValue signature algebra program (.computation use parameters answer)}
    (step : ClosureEvaluation bindings reserved expression before produced after)
    (permitted : use = .reusable ∨ use = .multi) : produced.copyable = true := by
  cases step
  case owned =>
    rename_i capturedTypes mode captures owner left right body partition
    cases mode <;> simp [UseScope.OneShotUse.type] at permitted
  case shared =>
    rcases permitted with rfl | rfl <;> simp_all [Value.copyable]

end Source

namespace Target

def Code.isClosure : Code signature algebra program context stack result → Bool
  | .close _ _ => true
  | _ => false

/-- Operand execution with physical closure allocation. The pure operand
rule cannot bypass `close`; shared closure construction checks copyability. -/
inductive OwnedOperandStep (bindings : RuntimeEnvironment signature algebra program context)
    (reserved : List (Id .custody)) :
    UseScope.ControlStore Future → Operands signature algebra program context result →
    UseScope.ControlStore Future → Operands signature algebra program context result → Prop where
  | ordinary (step : OperandStep bindings before after) (neutral : before.code.isClosure = false) :
      OwnedOperandStep bindings reserved store before store after
  | ownedClose (use : UseScope.OneShotUse)
      (body : Code signature algebra program (parameters ++ capturedTypes) [] answer)
      (captured : RuntimeEnvironment signature algebra program capturedTypes)
      (next : Code signature algebra program context (.computation use.type parameters answer :: stack) result)
      (values : RuntimeEnvironment signature algebra program stack)
      (owner : Owner) (before after : List UseScope.Field) (store : UseScope.ControlStore Future)
      (partition : store.fields.active = before ++ captured.owningFields ++ after) :
      OwnedOperandStep bindings reserved store ⟨_, .close body next, captured.pushReverse values⟩
        (createOwnedComputation use body captured owner before after store partition reserved).store
        ⟨_, next, .cons (createOwnedComputation use body captured owner before after store partition reserved).value values⟩
  | sharedClose (use : Use) (permitted : use = .reusable ∨ use = .multi)
      (body : Code signature algebra program (parameters ++ capturedTypes) [] answer)
      (captured : RuntimeEnvironment signature algebra program capturedTypes)
      (next : Code signature algebra program context (.computation use parameters answer :: stack) result)
      (values : RuntimeEnvironment signature algebra program stack)
      (copyable : captured.copyable = true) :
      OwnedOperandStep bindings reserved store ⟨_, .close body next, captured.pushReverse values⟩
        store ⟨_, next, .cons (.closure body captured none) values⟩

inductive OwnedOperandSteps (bindings : RuntimeEnvironment signature algebra program context)
    (reserved : List (Id .custody)) :
    UseScope.ControlStore Future → Operands signature algebra program context result → Nat →
    UseScope.ControlStore Future → Operands signature algebra program context result → Prop where
  | refl : OwnedOperandSteps bindings reserved store operands 0 store operands
  | cons : OwnedOperandStep bindings reserved first before middle during →
      OwnedOperandSteps bindings reserved middle during count last after →
      OwnedOperandSteps bindings reserved first before (count + 1) last after

theorem OwnedOperandSteps.single (step : OwnedOperandStep bindings reserved before first after last) :
    OwnedOperandSteps bindings reserved before first 1 after last := .cons step .refl

theorem OwnedOperandSteps.trans
    (first : OwnedOperandSteps bindings reserved before initial count middle intermediate)
    (second : OwnedOperandSteps bindings reserved middle intermediate rest after final) :
    OwnedOperandSteps bindings reserved before initial (count + rest) after final := by
  induction first with
  | refl => simpa using second
  | cons step tail induction =>
    simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using OwnedOperandSteps.cons step (induction second)

theorem OwnedOperandStep.preserves_ownership
    (step : OwnedOperandStep bindings reserved before initial after final)
    (valid : UseScope.ControlStore.Valid before) : UseScope.ControlStore.Valid after := by
  cases step with
  | ordinary | sharedClose => exact valid
  | ownedClose use body captured next values owner before after store partition =>
    exact created_computation_preserves_ownership valid partition

theorem OwnedOperandSteps.preserves_ownership
    (steps : OwnedOperandSteps bindings reserved before initial count after final)
    (valid : UseScope.ControlStore.Valid before) : UseScope.ControlStore.Valid after := by
  induction steps with
  | refl => exact valid
  | cons step tail induction => exact induction (step.preserves_ownership valid)

end Target

namespace Defunctionalization

theorem selection_drains_with_ownership (captures : Selection context capturedTypes)
    (bindings : Target.RuntimeEnvironment signature algebra program context)
    (next : Target.Code signature algebra program context (capturedTypes.reverse ++ stack) result)
    (values : Target.RuntimeEnvironment signature algebra program stack)
    (store : UseScope.ControlStore Future) (reserved : List (Id .custody)) :
    ∃ count, Target.OwnedOperandSteps bindings reserved store ⟨_, selection captures next, values⟩ count
      store ⟨_, next, (bindings.select captures).pushReverse values⟩ := by
  induction captures generalizing stack with
  | nil => exact ⟨0, .refl⟩
  | cons reference rest induction =>
    obtain ⟨count, steps⟩ := induction (by
      simpa only [List.reverse_cons, List.append_assoc, List.singleton_append] using next)
      (.cons (bindings.lookup reference) values)
    refine ⟨count + 1, ?_⟩
    have finish := Target.Operands.reindex (by
      simp only [List.reverse_cons, List.append_assoc, List.singleton_append]) next
      ((bindings.select rest).pushReverse (.cons (bindings.lookup reference) values))
    exact finish.symm ▸ Target.OwnedOperandSteps.cons (.ordinary .load rfl) steps

/-- Every owned authored lambda has a positive finite first-order allocation
run. No body is executed while its code and lexical captures are installed. -/
theorem compiled_owned_lambda
    {SourceFuture TargetFuture : Type} (related : SourceFuture → TargetFuture → Prop)
    (use : UseScope.OneShotUse) (captures : Selection context capturedTypes)
    (body : Source.Computation signature algebra program (parameters ++ capturedTypes) answer)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (next : Target.Code signature algebra program context (.computation use.type parameters answer :: stack) result)
    (values : Target.RuntimeEnvironment signature algebra program stack)
    (owner : Owner) (before after : List UseScope.Field) (reserved : List (Id .custody))
    {sourceStore : UseScope.ControlStore SourceFuture} {targetStore : UseScope.ControlStore TargetFuture}
    (stores : UseScope.ControlStore.Related related sourceStore targetStore)
    (partition : sourceStore.fields.active = before ++ (bindings.select captures).owningFields ++ after) :
    let created := createOwnedComputation use body (bindings.select captures) owner before after sourceStore partition reserved
    Source.ClosureEvaluation bindings reserved (.lambda (use := use.type) captures body) sourceStore created.value created.store ∧
    ∃ count targetAfter, 0 < count ∧
      Target.OwnedOperandSteps (environment bindings) reserved targetStore
        ⟨_, expression (.lambda (use := use.type) captures body) next, values⟩ count
        targetAfter ⟨_, next, .cons (value created.value) values⟩ ∧
      UseScope.ControlStore.Related related created.store targetAfter := by
  let transform := fun context type (body : Source.Computation signature algebra program context type) => computation body
  have targetPartition : targetStore.fields.active = before ++ ((bindings.select captures).map transform).owningFields ++ after := by
    simpa only [Environment.map_preserves_owning_fields, ← stores.fields] using partition
  have correspondence := owned_computation_creation_corresponds related transform use body (bindings.select captures)
    owner before after reserved stores partition targetPartition
  obtain ⟨count, prefixSteps⟩ := selection_drains_with_ownership captures (environment bindings)
    (.close (computation body) next) values targetStore reserved
  refine ⟨.owned use captures body owner before after sourceStore partition, count + 1, _, by omega, ?_, correspondence.2.2⟩
  have closed := Target.OwnedOperandSteps.single
    (Target.OwnedOperandStep.ownedClose (bindings := environment bindings) (reserved := reserved)
      use (computation body) ((bindings.select captures).map transform) next values owner before after targetStore targetPartition)
  rw [correspondence.2.1] at closed
  have ready : (environment bindings).select captures = (bindings.select captures).map transform :=
    Environment.select_map transform captures bindings
  rw [ready] at prefixSteps
  exact prefixSteps.trans closed

theorem compiled_lambda_evaluation
    {SourceFuture TargetFuture : Type} (related : SourceFuture → TargetFuture → Prop)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (reserved : List (Id .custody))
    (source : Source.Expression signature algebra program context type)
    (produced : Source.RuntimeValue signature algebra program type)
    {sourceStore sourceAfter : UseScope.ControlStore SourceFuture}
    {targetStore : UseScope.ControlStore TargetFuture}
    (evaluation : Source.ClosureEvaluation bindings reserved source sourceStore produced sourceAfter)
    (next : Target.Code signature algebra program context (type :: stack) result)
    (values : Target.RuntimeEnvironment signature algebra program stack)
    (stores : UseScope.ControlStore.Related related sourceStore targetStore) :
    ∃ count targetAfter, 0 < count ∧
      Target.OwnedOperandSteps (environment bindings) reserved targetStore
        ⟨_, expression source next, values⟩ count targetAfter ⟨_, next, .cons (value produced) values⟩ ∧
      UseScope.ControlStore.Related related sourceAfter targetAfter := by
  cases evaluation with
  | owned use captures body owner before after store partition =>
    exact (compiled_owned_lambda related use captures body bindings next values owner before after reserved stores partition).2
  | shared use permitted captures body copyable =>
    obtain ⟨count, prefixSteps⟩ := selection_drains_with_ownership captures (environment bindings)
      (.close (computation body) next) values targetStore reserved
    refine ⟨count + 1, targetStore, by omega, ?_, stores⟩
    have ready : (environment bindings).select captures = environment (bindings.select captures) :=
      Environment.select_map (fun _ _ body => computation body) captures bindings
    rw [ready] at prefixSteps
    apply prefixSteps.trans
    exact Target.OwnedOperandSteps.single (.sharedClose use permitted (computation body)
      (environment (bindings.select captures)) next values
      (by simpa only [environment, Environment.copyable_map] using copyable))

end Defunctionalization
end BoundaryV2.Generalized
