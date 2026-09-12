import BoundaryV2.GeneralizedOwnedResume
import BoundaryV2.GeneralizedControlCorrespondence

namespace BoundaryV2.Generalized

def UseScope.OneShotUse.type : UseScope.OneShotUse → Use
  | .affine => .affine
  | .linear => .linear

def Use.oneShot : (use : Use) → Option { kind : UseScope.OneShotUse // use = kind.type }
  | .affine => some ⟨.affine, rfl⟩
  | .linear => some ⟨.linear, rfl⟩
  | .reusable | .multi => none

namespace Source

structure OwnedClause (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (mode : Mode)
    (effect : signature.Effect) (input resumed result : TypeOf signature) where
  store : UseScope.ControlStore (Resumption signature algebra program mode effect input resumed)
  view : UseScope.ControlView
  computation : Program signature algebra program result

/-- This is the owned-clause boundary after nominal selection. It captures the
source context, transfers its designated physical fields, and then enters the
ordinary effectful clause in the outside context. -/
def captureOwnedClause
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
    (store : UseScope.ControlStore (Resumption signature algebra program mode effect (signature.result operation) (resumedType mode body answer)))
    (partition : store.fields.active = before ++ captured ++ after) :
    OwnedClause signature algebra program mode effect (signature.result operation) (resumedType mode body answer) result :=
  let future := captureResumption mode effect attachment returned clauses bindings inside
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
    (store : UseScope.ControlStore (Resumption signature algebra program mode effect (signature.result operation) (resumedType mode body answer)))
    (partition : store.fields.active = before ++ captured ++ after) :
    Option (OwnedClause signature algebra program mode effect (signature.result operation) (resumedType mode body answer) result) :=
  (clauses.lookup operation).bind fun selected => selected.use.oneShot.map fun admitted =>
    captureOwnedClause selected admitted.val admitted.property attachment returned clauses bindings inside payload bodies
      outside owner before captured after store partition

structure Resumed (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (mode : Mode)
    (effect : signature.Effect) (input answer result : TypeOf signature) where
  store : UseScope.ControlStore (Resumption signature algebra program mode effect input answer)
  computation : Program signature algebra program result

def resumeOwned (view : UseScope.ControlView)
    (store : UseScope.ControlStore (Resumption signature algebra program mode effect input answer))
    (value : RuntimeValue signature algebra program input) (outside : Context signature algebra program answer result) :
    Option (Resumed signature algebra program mode effect input answer result) :=
  (UseScope.acquire view store).map fun acquired => ⟨acquired.store, outside.plug (reenter acquired.future (.returned value))⟩

def injectOwned (view : UseScope.ControlView)
    (store : UseScope.ControlStore (Resumption signature algebra program mode effect input answer))
    (body : Computation signature algebra program context input) (bindings : RuntimeEnvironment signature algebra program context)
    (outside : Context signature algebra program answer result) :
    Option (Resumed signature algebra program mode effect input answer result) :=
  (UseScope.acquire view store).map fun acquired => ⟨acquired.store, outside.plug (reenter acquired.future (.evaluate body bindings))⟩

end Source

namespace Target

structure OwnedClause (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (mode : Mode)
    (effect : signature.Effect) (input resumed result : TypeOf signature) where
  store : UseScope.ControlStore (Resumption signature algebra program mode effect input resumed)
  view : UseScope.ControlView
  configuration : Configuration signature algebra program result

/-- The target captures only its data frames and stores compiled code. No source
program or source callback is retained in this operation or its result. -/
def captureOwnedClause
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
    (store : UseScope.ControlStore (Resumption signature algebra program mode effect (signature.result operation) (resumedType mode body answer)))
    (partition : store.fields.active = before ++ captured ++ after) :
    OwnedClause signature algebra program mode effect (signature.result operation) (resumedType mode body answer) result :=
  let future := captureResumption mode effect attachment returned clauses bindings inside
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
    (store : UseScope.ControlStore (Resumption signature algebra program mode effect (signature.result operation) (resumedType mode body answer)))
    (partition : store.fields.active = before ++ captured ++ after) :
    Option (OwnedClause signature algebra program mode effect (signature.result operation) (resumedType mode body answer) result) :=
  (clauses.lookup operation).bind fun selected => selected.use.oneShot.map fun admitted =>
    captureOwnedClause selected admitted.val admitted.property attachment returned clauses bindings inside payload bodies
      outside owner before captured after store partition

end Target

namespace Defunctionalization

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

theorem owned_clause_capture_corresponds
    (selected : Source.SelectedClause signature algebra program operation mode context body answer)
    (use : UseScope.OneShotUse) (permitted : selected.use = use.type)
    (attachment : Id .attachment)
    (returned : Source.Computation signature algebra program (body :: context) answer)
    (clauses : Source.Clauses signature algebra program effect mode context body answer)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (inside : ContextRelated signature algebra program sourceInside targetInside)
    (payload : Source.RuntimeValue signature algebra program (signature.payload operation))
    (bodies : Source.RuntimeEnvironment signature algebra program ((signature.bodies operation).map BodyType.type))
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    (owner : Owner) (before captured after : List UseScope.Field)
    (stores : UseScope.ControlStore.Related ResumptionRelated sourceStore targetStore)
    (sourcePartition : sourceStore.fields.active = before ++ captured ++ after)
    (targetPartition : targetStore.fields.active = before ++ captured ++ after) :
    let left := Source.captureOwnedClause selected use permitted attachment returned clauses bindings sourceInside
      payload bodies sourceOutside owner before captured after sourceStore sourcePartition
    let right := Target.captureOwnedClause (selectedClause selected) use permitted attachment (computation returned)
      (Defunctionalization.clauses clauses) (environment bindings) targetInside (value payload) (environment bodies)
      targetOutside owner before captured after targetStore targetPartition
    left.view = right.view ∧ UseScope.ControlStore.Related ResumptionRelated left.store right.store ∧
      EntryRelated left.computation right.configuration := by
  have futures := captured_resumption_corresponds mode effect attachment returned clauses bindings inside
  have created := UseScope.create_control_corresponds ResumptionRelated stores futures sourcePartition targetPartition
    (use := use) (owner := owner)
  refine ⟨created.1, created.2, ?_⟩
  dsimp only [Source.captureOwnedClause, Target.captureOwnedClause]
  rw [created.1]
  exact operation_clause_entry_corresponds selected _ _ payload bodies bindings outside

structure OwnedClauseRelated
    (source : Source.OwnedClause signature algebra program mode effect input resumed result)
    (target : Target.OwnedClause signature algebra program mode effect input resumed result) : Prop where
  view : source.view = target.view
  store : UseScope.ControlStore.Related ResumptionRelated source.store target.store
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
    {sourceStore : UseScope.ControlStore (Source.Resumption signature algebra program mode effect
      (signature.result operation) (resumedType mode body answer))}
    {targetStore : UseScope.ControlStore (Target.Resumption signature algebra program mode effect
      (signature.result operation) (resumedType mode body answer))}
    (stores : UseScope.ControlStore.Related ResumptionRelated sourceStore targetStore)
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

structure OwnedEntryRelated
    (source : Source.Resumed signature algebra program mode effect input answer result)
    (target : Target.Resumed signature algebra program mode effect input answer result) : Prop where
  store : UseScope.ControlStore.Related ResumptionRelated source.store target.store
  entry : EntryRelated source.computation target.configuration

/-- This relates both acceptance and rejection of an actual store lookup. On
acceptance, the stored futures are entered only after the shared authority has
been consumed. The outside clause caller remains a separate continuation. -/
theorem owned_resumption_corresponds
    {sourceStore : UseScope.ControlStore (Source.Resumption signature algebra program mode effect inputType answer)}
    {targetStore : UseScope.ControlStore (Target.Resumption signature algebra program mode effect inputType answer)}
    (stores : UseScope.ControlStore.Related ResumptionRelated sourceStore targetStore)
    (view : UseScope.ControlView) (input : Source.RuntimeValue signature algebra program inputType)
    (outside : ContextRelated signature algebra program sourceOutside targetOutside) :
    Option.Rel OwnedEntryRelated (Source.resumeOwned view sourceStore input sourceOutside)
      (Target.resumeOwned view targetStore (value input) targetOutside) := by
  have acquired := UseScope.acquire_corresponds ResumptionRelated stores view
  unfold Source.resumeOwned Target.resumeOwned
  generalize sourceAt : UseScope.acquire view sourceStore = sourceTaken at acquired ⊢
  generalize targetAt : UseScope.acquire view targetStore = targetTaken at acquired ⊢
  cases acquired with
  | none => exact .none
  | some matching => exact .some ⟨matching.store, resumption_reentry_corresponds matching.future input outside⟩

theorem owned_injection_corresponds
    {sourceStore : UseScope.ControlStore (Source.Resumption signature algebra program mode effect inputType answer)}
    {targetStore : UseScope.ControlStore (Target.Resumption signature algebra program mode effect inputType answer)}
    (stores : UseScope.ControlStore.Related ResumptionRelated sourceStore targetStore)
    (view : UseScope.ControlView) (body : Source.Computation signature algebra program context inputType)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (outside : ContextRelated signature algebra program sourceOutside targetOutside) :
    Option.Rel OwnedEntryRelated (Source.injectOwned view sourceStore body bindings sourceOutside)
      (Target.injectOwned view targetStore ⟨context, computation body, environment bindings⟩ targetOutside) := by
  have acquired := UseScope.acquire_corresponds ResumptionRelated stores view
  unfold Source.injectOwned Target.injectOwned
  generalize sourceAt : UseScope.acquire view sourceStore = sourceTaken at acquired ⊢
  generalize targetAt : UseScope.acquire view targetStore = targetTaken at acquired ⊢
  cases acquired with
  | none => exact .none
  | some matching => exact .some ⟨matching.store, computation_injection_corresponds matching.future body bindings outside⟩

end Defunctionalization
end BoundaryV2.Generalized
