import BoundaryV2.GeneralizedControlMachine

namespace BoundaryV2.Generalized


namespace Source

structure OwnedClause (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (result : TypeOf signature) where
  store : ControlHeap signature algebra program
  view : UseScope.ControlView
  computation : Program signature algebra program result

def OwnedClause.state (clause : OwnedClause signature algebra program result) : ControlState signature algebra program result :=
  ⟨clause.store, clause.computation⟩

/-- This is the owned-clause boundary after nominal selection. It captures the
source context, transfers its designated physical fields, and then enters the
ordinary effectful clause in the outside context. -/
def captureOwnedClause {effect : signature.Effect} {operation : signature.operation effect}
    (selected : SelectedClause signature algebra program operation mode context body answer)
    (use : UseScope.OneShotUse) (_permitted : selected.use = use.type)
    (attachment : Id .attachment)
    (returned : Computation signature algebra program (body :: context) answer)
    (clauses : Clauses signature algebra program effect mode context body answer)
    (bindings : RuntimeEnvironment signature algebra program context)
    (inside : Context signature algebra program (signature.result operation) body)
    (payload : RuntimeValue signature algebra program (signature.payload operation))
    (bodies : RuntimeEnvironment signature algebra program ((signature.bodies operation).map BodyType.type))
    (outside : Context signature algebra program answer result)
    (owner : Owner) (before captured after : List UseScope.Field)
    (store : ControlHeap signature algebra program)
    (partition : store.fields.active = before ++ captured ++ after) :
    OwnedClause signature algebra program result :=
  let future : Sigma (ControlPayload signature algebra program) :=
    ⟨⟨mode, effect, signature.result operation, resumedType mode body answer⟩,
      captureResumption mode effect attachment returned clauses bindings inside⟩
  let created := UseScope.createControl use future owner before captured after store partition
  ⟨created.store, created.view, outside.plug (enterClause selected created.view.identity
    (some (created.view.authority, created.view.owner)) payload bodies bindings)⟩

/-- The one-shot dispatcher performs the source's own typed clause lookup.
Reusable and multi clauses belong to their separate activation operations. -/
def dispatchOwnedClause (operation : signature.operation effect) [DecidableEq (signature.operation effect)]
    (attachment : Id .attachment)
    (returned : Computation signature algebra program (body :: context) answer)
    (clauses : Clauses signature algebra program effect mode context body answer)
    (bindings : RuntimeEnvironment signature algebra program context)
    (inside : Context signature algebra program (signature.result operation) body)
    (payload : RuntimeValue signature algebra program (signature.payload operation))
    (bodies : RuntimeEnvironment signature algebra program ((signature.bodies operation).map BodyType.type))
    (outside : Context signature algebra program answer result)
    (owner : Owner) (before captured after : List UseScope.Field)
    (store : ControlHeap signature algebra program)
    (partition : store.fields.active = before ++ captured ++ after) :
    Option (OwnedClause signature algebra program result) :=
  (clauses.lookup operation).bind fun selected => selected.use.oneShot.map fun admitted =>
    captureOwnedClause selected admitted.val admitted.property attachment returned clauses bindings inside payload bodies
      outside owner before captured after store partition


end Source

namespace Target

structure OwnedClause (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (result : TypeOf signature) where
  store : ControlHeap signature algebra program
  view : UseScope.ControlView
  configuration : Configuration signature algebra program result

def OwnedClause.state (clause : OwnedClause signature algebra program result) : ControlState signature algebra program result :=
  ⟨clause.store, clause.configuration⟩

/-- The target captures only its data frames and stores compiled code. No source
program or source callback is retained in this operation or its result. -/
def captureOwnedClause {effect : signature.Effect} {operation : signature.operation effect}
    (selected : SelectedClause signature algebra program operation mode context body answer)
    (use : UseScope.OneShotUse) (_permitted : selected.use = use.type)
    (attachment : Id .attachment)
    (returned : Code signature algebra program (body :: context) [] answer)
    (clauses : Clauses signature algebra program effect mode context body answer)
    (bindings : RuntimeEnvironment signature algebra program context)
    (inside : Stack signature algebra program (signature.result operation) body)
    (payload : RuntimeValue signature algebra program (signature.payload operation))
    (bodies : RuntimeEnvironment signature algebra program ((signature.bodies operation).map BodyType.type))
    (outside : Stack signature algebra program answer result)
    (owner : Owner) (before captured after : List UseScope.Field)
    (store : ControlHeap signature algebra program)
    (partition : store.fields.active = before ++ captured ++ after) :
    OwnedClause signature algebra program result :=
  let future : Sigma (ControlPayload signature algebra program) :=
    ⟨⟨mode, effect, signature.result operation, resumedType mode body answer⟩,
      captureResumption mode effect attachment returned clauses bindings inside⟩
  let created := UseScope.createControl use future owner before captured after store partition
  ⟨created.store, created.view, enterClause selected created.view.identity
    (some (created.view.authority, created.view.owner)) payload bodies bindings outside⟩

def dispatchOwnedClause (operation : signature.operation effect) [DecidableEq (signature.operation effect)]
    (attachment : Id .attachment)
    (returned : Code signature algebra program (body :: context) [] answer)
    (clauses : Clauses signature algebra program effect mode context body answer)
    (bindings : RuntimeEnvironment signature algebra program context)
    (inside : Stack signature algebra program (signature.result operation) body)
    (payload : RuntimeValue signature algebra program (signature.payload operation))
    (bodies : RuntimeEnvironment signature algebra program ((signature.bodies operation).map BodyType.type))
    (outside : Stack signature algebra program answer result)
    (owner : Owner) (before captured after : List UseScope.Field)
    (store : ControlHeap signature algebra program)
    (partition : store.fields.active = before ++ captured ++ after) :
    Option (OwnedClause signature algebra program result) :=
  (clauses.lookup operation).bind fun selected => selected.use.oneShot.map fun admitted =>
    captureOwnedClause selected admitted.val admitted.property attachment returned clauses bindings inside payload bodies
      outside owner before captured after store partition

theorem dispatch_owned_clause_preserves_ownership {signature : Signature} {algebra : LeafAlgebra signature.Data}
    {program : List (BodyType signature.Data signature.Effect)} {effect : signature.Effect}
    {operation : signature.operation effect} [DecidableEq (signature.operation effect)]
    {mode : Mode} {context : List (TypeOf signature)} {body answer resultType : TypeOf signature}
    {attachment : Id .attachment} {owner : Owner}
    {returned : Code signature algebra program (body :: context) [] answer}
    {clauses : Clauses signature algebra program effect mode context body answer}
    {bindings : RuntimeEnvironment signature algebra program context}
    {inside : Stack signature algebra program (signature.result operation) body}
    {payload : RuntimeValue signature algebra program (signature.payload operation)}
    {bodies : RuntimeEnvironment signature algebra program ((signature.bodies operation).map BodyType.type)}
    {outside : Stack signature algebra program answer resultType}
    {result : OwnedClause signature algebra program resultType}
    {store : ControlHeap signature algebra program} {before captured after : List UseScope.Field}
    {partition : store.fields.active = before ++ captured ++ after} (valid : UseScope.ControlStore.Valid store)
    (accepted : dispatchOwnedClause operation attachment returned clauses bindings inside payload bodies outside
      owner before captured after store partition = some result) : UseScope.ControlStore.Valid result.store := by
  obtain ⟨selected, _, picked⟩ := Option.bind_eq_some_iff.mp accepted
  obtain ⟨admitted, _, rfl⟩ := Option.map_eq_some_iff.mp picked
  exact UseScope.create_control_preserves_ownership valid partition

end Target

namespace Defunctionalization

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

theorem owned_clause_capture_corresponds {effect : signature.Effect} {operation : signature.operation effect}
    (selected : Source.SelectedClause signature algebra program operation mode context body answer)
    (use : UseScope.OneShotUse) (permitted : selected.use = use.type)
    (attachment : Id .attachment)
    (returned : Source.Computation signature algebra program (body :: context) answer)
    (clauses : Source.Clauses signature algebra program effect mode context body answer)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    {sourceInside : Source.Context signature algebra program (signature.result operation) body}
    {targetInside : Target.Stack signature algebra program (signature.result operation) body}
    (inside : ContextRelated signature algebra program sourceInside targetInside)
    (payload : Source.RuntimeValue signature algebra program (signature.payload operation))
    (bodies : Source.RuntimeEnvironment signature algebra program ((signature.bodies operation).map BodyType.type))
    {sourceOutside : Source.Context signature algebra program answer result}
    {targetOutside : Target.Stack signature algebra program answer result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    (owner : Owner) (before captured after : List UseScope.Field)
    (stores : ControlHeapRelated sourceStore targetStore)
    (sourcePartition : sourceStore.fields.active = before ++ captured ++ after)
    (targetPartition : targetStore.fields.active = before ++ captured ++ after) :
    let left := Source.captureOwnedClause selected use permitted attachment returned clauses bindings sourceInside
      payload bodies sourceOutside owner before captured after sourceStore sourcePartition
    let right := Target.captureOwnedClause (selectedClause selected) use permitted attachment (computation returned)
      (Defunctionalization.clauses clauses) (environment bindings) targetInside (value payload) (environment bodies)
      targetOutside owner before captured after targetStore targetPartition
    left.view = right.view ∧ ControlHeapRelated left.store right.store ∧
      EntryRelated left.computation right.configuration := by
  have futures := captured_resumption_corresponds mode effect attachment returned clauses bindings inside
  have packed : UseScope.PackedControlRelated controlPayloadRelated
      ⟨⟨mode, effect, signature.result operation, resumedType mode body answer⟩,
        Source.captureResumption mode effect attachment returned clauses bindings sourceInside⟩
      ⟨⟨mode, effect, signature.result operation, resumedType mode body answer⟩,
        Target.captureResumption mode effect attachment (computation returned) (Defunctionalization.clauses clauses)
          (environment bindings) targetInside⟩ := .same futures
  have created := UseScope.create_control_corresponds (UseScope.PackedControlRelated controlPayloadRelated) stores packed sourcePartition targetPartition
    (use := use) (owner := owner)
  refine ⟨created.1, created.2, ?_⟩
  dsimp only [Source.captureOwnedClause, Target.captureOwnedClause]
  rw [created.1]
  exact operation_clause_entry_corresponds selected _ _ payload bodies bindings outside

structure OwnedClauseRelated
    (source : Source.OwnedClause signature algebra program result)
    (target : Target.OwnedClause signature algebra program result) : Prop where
  view : source.view = target.view
  store : ControlHeapRelated source.store target.store
  entry : EntryRelated source.computation target.configuration

theorem owned_clause_dispatch_corresponds
    (operation : signature.operation effect) [DecidableEq (signature.operation effect)]
    (attachment : Id .attachment)
    (returned : Source.Computation signature algebra program (body :: context) answer)
    (clauses : Source.Clauses signature algebra program effect mode context body answer)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    {sourceInside : Source.Context signature algebra program (signature.result operation) body}
    {targetInside : Target.Stack signature algebra program (signature.result operation) body}
    (inside : ContextRelated signature algebra program sourceInside targetInside)
    (payload : Source.RuntimeValue signature algebra program (signature.payload operation))
    (bodies : Source.RuntimeEnvironment signature algebra program ((signature.bodies operation).map BodyType.type))
    {sourceOutside : Source.Context signature algebra program answer result}
    {targetOutside : Target.Stack signature algebra program answer result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    (owner : Owner) (before captured after : List UseScope.Field)
    {sourceStore : Source.ControlHeap signature algebra program}
    {targetStore : Target.ControlHeap signature algebra program}
    (stores : ControlHeapRelated sourceStore targetStore)
    (sourcePartition : sourceStore.fields.active = before ++ captured ++ after)
    (targetPartition : targetStore.fields.active = before ++ captured ++ after) :
    Option.Rel OwnedClauseRelated
      (Source.dispatchOwnedClause operation attachment returned clauses bindings sourceInside payload bodies sourceOutside
        owner before captured after sourceStore sourcePartition)
      (Target.dispatchOwnedClause operation attachment (computation returned) (Defunctionalization.clauses clauses)
        (environment bindings) targetInside (value payload) (environment bodies) targetOutside
        owner before captured after targetStore targetPartition) := by
  unfold Source.dispatchOwnedClause Target.dispatchOwnedClause
  rw [clause_lookup_corresponds]
  generalize lookupAt : clauses.lookup operation = found
  cases found with
  | none => exact .none
  | some selected =>
    dsimp only [Option.map, Option.bind, selectedClause]
    cases admittedAt : selected.use.oneShot with
    | none => exact .none
    | some admitted =>
      have matched := owned_clause_capture_corresponds selected admitted.val admitted.property attachment returned clauses
        bindings inside payload bodies outside owner before captured after stores sourcePartition targetPartition
      exact .some ⟨matched.1, matched.2.1, matched.2.2⟩


end Defunctionalization
end BoundaryV2.Generalized
