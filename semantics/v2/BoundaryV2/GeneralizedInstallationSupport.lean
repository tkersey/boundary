import BoundaryV2.GeneralizedSourceSupport
import BoundaryV2.GeneralizedRuntimeSupport
import BoundaryV2.GeneralizedControlPayload
import BoundaryV2.GeneralizedCellExecution

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

mutual
  def UseScope.Field.references : UseScope.Field → List Reference
    | .owned token owner => [.name .custody token, .owner owner]
    | .alias token => [.name .custody token]
    | .borrowed scope => [.name .scope scope]
    | .group fields | .closure fields | .package fields => UseScope.fieldsReferences fields
    | .continuation identity fields => .name .control identity :: UseScope.fieldsReferences fields
    | .cleanup identity fields => .name .obligation identity :: UseScope.fieldsReferences fields

  def UseScope.fieldsReferences : List UseScope.Field → List Reference
    | [] => []
    | first :: rest => first.references ++ UseScope.fieldsReferences rest
end

def UseScope.stateReferences (state : UseScope.State) : List Reference :=
  fieldsReferences state.active ++ fieldsReferences state.retained

namespace Source

mutual
  def valueReferences : {type : TypeOf signature} → RuntimeValue signature algebra program type → List Reference
    | _, .datum datum => datum.references
    | _, .pair first second => valueReferences first ++ valueReferences second
    | _, .left value | _, .right value => valueReferences value
    | _, .closure body captured authority => body.references ++ environmentReferences captured ++ Target.authorityReferences authority
    | _, .continuation identity authority => .name .control identity :: Target.authorityReferences authority
    | _, .package token owner value => .name .custody token :: .owner owner :: valueReferences value
    | _, .cell identity region => [.name .cell identity, .name .region region]
    | _, .exit _ => []

  def environmentReferences : {types : List (TypeOf signature)} → RuntimeEnvironment signature algebra program types → List Reference
    | _, .nil => []
    | _, .cons value rest => valueReferences value ++ environmentReferences rest
end

/-- Higher-order continuations carry a structural support witness. It is
derived from their authored body and environment, not by inspecting a Lean function. -/
inductive FrameSupported : Frame signature algebra program input result → List Reference → Prop where
  | bind (body : Computation signature algebra program (input :: context) result)
      (captured : RuntimeEnvironment signature algebra program context) :
      FrameSupported (.bind (fun value => .evaluate body (.cons value captured)))
        (body.references ++ environmentReferences captured)
  | handler (effect : signature.Effect) (mode : Mode) (attachment : Id .attachment)
      (returned : Computation signature algebra program (input :: context) result)
      (clauses : Clauses signature algebra program effect mode context input result)
      (captured : RuntimeEnvironment signature algebra program context) :
      FrameSupported (.handler effect mode attachment returned clauses captured)
        (.name .attachment attachment :: (returned.references ++ clauses.references ++ environmentReferences captured))
  | region (identity : Id .region) : FrameSupported (.region identity) [.name .region identity]
  | protection (identity : Id .obligation) (cleanup : Computation signature algebra program (.exit :: context) .unit)
      (captured : RuntimeEnvironment signature algebra program context) :
      FrameSupported (.protection identity cleanup captured) (.name .obligation identity :: (cleanup.references ++ environmentReferences captured))

inductive ContextSupported : Context signature algebra program input result → List Reference → Prop where
  | done : ContextSupported .done []
  | push : FrameSupported frame first → ContextSupported rest remaining →
      ContextSupported (.push frame rest) (first ++ remaining)

def cellsReferences (cells : Cells signature algebra (Computation signature algebra program)) : List Reference :=
  cells.flatMap fun cell => .name .cell cell.identity :: .name .region cell.region :: valueReferences cell.value

inductive ControlSupported : Sigma (ControlPayload signature algebra program) → List Reference → Prop where
  | supported {payload : ControlPayload signature algebra program shape} : ContextSupported payload.future support →
      ControlSupported ⟨shape, payload⟩ (.name .attachment payload.attachment :: support)

inductive ControlInfosSupported : List (UseScope.ControlInfo (Sigma (ControlPayload signature algebra program))) → List Reference → Prop where
  | nil : ControlInfosSupported [] []
  | cons : ControlSupported first.future head → ControlInfosSupported rest tail → ControlInfosSupported (first :: rest) (head ++ tail)

def StoreSupported (store : ControlHeap signature algebra program) (support : List Reference) : Prop :=
  ∃ active disposing, ControlInfosSupported store.controls active ∧ ControlInfosSupported store.disposing disposing ∧
    support = UseScope.stateReferences store.fields ++ active ++ disposing

def definitionReferences : {types : List (BodyType signature.Data signature.Effect)} →
    Tuple (fun body => Computation signature algebra program body.parameters body.result) types → List Reference
  | _, .nil => []
  | _, .cons body rest => body.references ++ definitionReferences rest

def installationSupport (table : Definitions signature algebra program)
    (code : Computation signature algebra program context result)
    (bindings : RuntimeEnvironment signature algebra program context)
    (outside stored : List Reference) (cells : Cells signature algebra (Computation signature algebra program))
    (extra : List Reference) : List Reference :=
  definitionReferences table ++ code.references ++ environmentReferences bindings ++ outside ++ stored ++ cellsReferences cells ++ extra

def freshAttachment (table : Definitions signature algebra program)
    (code : Computation signature algebra program context result)
    (bindings : RuntimeEnvironment signature algebra program context)
    (outside stored : List Reference) (cells : Cells signature algebra (Computation signature algebra program))
    (extra : List Reference) : Id .attachment :=
  UseScope.freshName (referenceNames (installationSupport table code bindings outside stored cells extra) .attachment)

def freshObligation (table : Definitions signature algebra program)
    (code : Computation signature algebra program context result)
    (bindings : RuntimeEnvironment signature algebra program context)
    (outside stored : List Reference) (cells : Cells signature algebra (Computation signature algebra program))
    (extra : List Reference) : Id .obligation :=
  UseScope.freshName (referenceNames (installationSupport table code bindings outside stored cells extra) .obligation)

end Source

namespace Target

/-- An administrative return with `ret` does not inspect its saved bindings.
All actual handler, bind, and cleanup captures remain in installation support.
The full physical reference collector remains unchanged for relocation. -/
def Frame.installationReferences : Frame signature algebra program input result → List Reference
  | .returnTo code bindings operands => match code with
    | .ret => []
    | _ => code.references ++ environmentReferences bindings ++ environmentReferences operands
  | .handler _ _ attachment returned clauses bindings =>
    .name .attachment attachment :: (returned.references ++ clauses.references ++ environmentReferences bindings)
  | .region identity => [.name .region identity]
  | .protection identity cleanup bindings => .name .obligation identity :: (cleanup.references ++ environmentReferences bindings)

def Stack.installationReferences : Stack signature algebra program input result → List Reference
  | .done => []
  | .push frame rest => frame.installationReferences ++ rest.installationReferences

def controlReferences (packed : Sigma (ControlPayload signature algebra program)) : List Reference :=
  .name .attachment packed.snd.attachment :: packed.snd.future.installationReferences

def storeReferences (store : ControlHeap signature algebra program) : List Reference :=
  UseScope.stateReferences store.fields ++ (store.controls ++ store.disposing).flatMap fun record => controlReferences record.future

def definitionReferences : {types : List (BodyType signature.Data signature.Effect)} →
    Tuple (fun body => Code signature algebra program body.parameters [] body.result) types → List Reference
  | _, .nil => []
  | _, .cons body rest => body.references ++ definitionReferences rest

def installationSupport (table : Definitions signature algebra program)
    (code : Code signature algebra program context operands input)
    (bindings : RuntimeEnvironment signature algebra program context)
    (values : RuntimeEnvironment signature algebra program operands)
    (outside : Stack signature algebra program input result) (store : ControlHeap signature algebra program)
    (cells : Cells signature algebra (fun context result => Code signature algebra program context [] result))
    (extra : List Reference) : List Reference :=
  definitionReferences table ++ code.references ++ environmentReferences bindings ++ environmentReferences values ++
    outside.installationReferences ++ storeReferences store ++ cellsReferences cells ++ extra

def freshAttachment (table : Definitions signature algebra program)
    (code : Code signature algebra program context operands input)
    (bindings : RuntimeEnvironment signature algebra program context)
    (values : RuntimeEnvironment signature algebra program operands)
    (outside : Stack signature algebra program input result) (store : ControlHeap signature algebra program)
    (cells : Cells signature algebra (fun context result => Code signature algebra program context [] result))
    (extra : List Reference) : Id .attachment :=
  UseScope.freshName (referenceNames (installationSupport table code bindings values outside store cells extra) .attachment)

def freshObligation (table : Definitions signature algebra program)
    (code : Code signature algebra program context operands input)
    (bindings : RuntimeEnvironment signature algebra program context)
    (values : RuntimeEnvironment signature algebra program operands)
    (outside : Stack signature algebra program input result) (store : ControlHeap signature algebra program)
    (cells : Cells signature algebra (fun context result => Code signature algebra program context [] result))
    (extra : List Reference) : Id .obligation :=
  UseScope.freshName (referenceNames (installationSupport table code bindings values outside store cells extra) .obligation)

end Target

namespace Defunctionalization

mutual
  theorem value_reference_support {type : TypeOf signature} (source : Source.RuntimeValue signature algebra program type) :
      Target.valueReferences (value source) = Source.valueReferences source := by
    cases source with
    | datum datum | continuation identity authority | cell identity region | exit information => rfl
    | pair first second =>
      exact (congrArg (· ++ Target.valueReferences (value second)) (value_reference_support first)).trans
        (congrArg (Source.valueReferences first ++ ·) (value_reference_support second))
    | left value | right value => exact value_reference_support value
    | closure body captured authority =>
      simp only [value, Value.map, Target.valueReferences, Source.valueReferences, computation_reference_support]
      exact congrArg (· ++ Target.authorityReferences authority) (congrArg (body.references ++ ·) (environment_reference_support captured))
    | package token owner value =>
      exact congrArg (fun tail => Reference.name .custody token :: Reference.owner owner :: tail) (value_reference_support value)
  termination_by sizeOf source

  theorem environment_reference_support {types : List (TypeOf signature)} (source : Source.RuntimeEnvironment signature algebra program types) :
      Target.environmentReferences (environment source) = Source.environmentReferences source := by
    cases source with
    | nil => rfl
    | cons item rest =>
      exact (congrArg (· ++ Target.environmentReferences (environment rest)) (value_reference_support item)).trans
        (congrArg (Source.valueReferences item ++ ·) (environment_reference_support rest))
  termination_by sizeOf source
end

theorem frame_installation_support (related : FrameRelated signature algebra program source target) :
    Source.FrameSupported source target.installationReferences := by
  cases related with
  | bind body captured =>
    simpa only [Target.Frame.installationReferences, Target.Code.references, computation_reference_support,
      environment_reference_support, Target.environmentReferences, List.append_nil] using Source.FrameSupported.bind body captured
  | handler effect mode identity returned handled captured =>
    simpa only [Target.Frame.installationReferences, computation_reference_support, clauses_reference_support,
      environment_reference_support] using Source.FrameSupported.handler effect mode identity returned handled captured
  | region identity => exact .region identity
  | protection identity cleanup captured =>
    simpa only [Target.Frame.installationReferences, computation_reference_support, environment_reference_support] using
      Source.FrameSupported.protection identity cleanup captured

theorem context_installation_support (related : ContextRelated signature algebra program source target) :
    Source.ContextSupported source target.installationReferences := by
  induction related with
  | done => exact .done
  | push frame rest induction => exact .push (frame_installation_support frame) induction
  | passthrough bindings rest induction => exact induction

theorem cell_installation_support (source : Cells signature algebra (Source.Computation signature algebra program)) :
    Target.cellsReferences (cells source) = Source.cellsReferences source := by
  induction source with
  | nil => rfl
  | cons first rest induction =>
    change (Reference.name .cell first.identity :: Reference.name .region first.region :: Target.valueReferences (value first.value)) ++
      Target.cellsReferences (cells rest) =
      (Reference.name .cell first.identity :: Reference.name .region first.region :: Source.valueReferences first.value) ++ Source.cellsReferences rest
    rw [value_reference_support first.value, induction]

theorem control_installation_support
    (related : UseScope.PackedControlRelated (controlPayloadRelated (signature := signature) (algebra := algebra) (program := program)) source target) :
    Source.ControlSupported source (Target.controlReferences target) := by
  cases related with
  | same matched =>
    have supported := Source.ControlSupported.supported (context_installation_support matched.future)
    simpa only [Target.controlReferences, matched.attachment] using supported

theorem records_installation_support
    (related : UseScope.ControlInfosRelated (UseScope.PackedControlRelated (controlPayloadRelated (signature := signature) (algebra := algebra) (program := program))) source target) :
    Source.ControlInfosSupported source (target.flatMap fun record => Target.controlReferences record.future) := by
  induction related with
  | nil => exact .nil
  | cons first rest induction => exact .cons (control_installation_support first.future) induction

theorem store_installation_support (related : ControlHeapRelated source target) :
    Source.StoreSupported source (Target.storeReferences target) := by
  refine ⟨_, _, records_installation_support related.controls, records_installation_support related.disposing, ?_⟩
  simp only [Target.storeReferences, List.flatMap_append, List.append_assoc, related.fields]

theorem definition_reference_support
    (source : Tuple (fun body : BodyType signature.Data signature.Effect => Source.Computation signature algebra program body.parameters body.result) types) :
    Target.definitionReferences (source.map (fun _ body => computation body)) = Source.definitionReferences source := by
  induction source with
  | nil => rfl
  | cons body rest induction =>
    simp only [Tuple.map, Target.definitionReferences, Source.definitionReferences, computation_reference_support, induction]

theorem fresh_attachment_corresponds
    (table : Source.Definitions signature algebra program)
    (code : Source.Computation signature algebra program context input)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (outside : Target.Stack signature algebra program input result)
    (store : Target.ControlHeap signature algebra program)
    (sourceCells : Cells signature algebra (Source.Computation signature algebra program)) (extra : List Reference) :
    Source.freshAttachment table code bindings outside.installationReferences (Target.storeReferences store) sourceCells extra =
      Target.freshAttachment (definitions table) (computation code) (environment bindings) .nil outside store (cells sourceCells) extra := by
  simp only [Source.freshAttachment, Target.freshAttachment, Source.installationSupport, Target.installationSupport,
    definitions, definition_reference_support, computation_reference_support, environment_reference_support,
    Target.environmentReferences, cell_installation_support, List.append_nil]

theorem fresh_obligation_corresponds
    (table : Source.Definitions signature algebra program)
    (code : Source.Computation signature algebra program context input)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (outside : Target.Stack signature algebra program input result)
    (store : Target.ControlHeap signature algebra program)
    (sourceCells : Cells signature algebra (Source.Computation signature algebra program)) (extra : List Reference) :
    Source.freshObligation table code bindings outside.installationReferences (Target.storeReferences store) sourceCells extra =
      Target.freshObligation (definitions table) (computation code) (environment bindings) .nil outside store (cells sourceCells) extra := by
  simp only [Source.freshObligation, Target.freshObligation, Source.installationSupport, Target.installationSupport,
    definitions, definition_reference_support, computation_reference_support, environment_reference_support,
    Target.environmentReferences, cell_installation_support, List.append_nil]

end Defunctionalization

theorem Source.fresh_attachment_avoids_support
    (table : Source.Definitions signature algebra program) (code : Source.Computation signature algebra program context result)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (outside stored : List Reference) (cells : Cells signature algebra (Source.Computation signature algebra program)) (extra : List Reference) :
    Source.freshAttachment table code bindings outside stored cells extra ∉
      referenceNames (Source.installationSupport table code bindings outside stored cells extra) .attachment :=
  UseScope.fresh_name_not_supported _

theorem Target.fresh_attachment_avoids_support
    (table : Target.Definitions signature algebra program) (code : Target.Code signature algebra program context operands input)
    (bindings : Target.RuntimeEnvironment signature algebra program context)
    (values : Target.RuntimeEnvironment signature algebra program operands)
    (outside : Target.Stack signature algebra program input result) (store : Target.ControlHeap signature algebra program)
    (cells : Cells signature algebra (fun context result => Target.Code signature algebra program context [] result)) (extra : List Reference) :
    Target.freshAttachment table code bindings values outside store cells extra ∉
      referenceNames (Target.installationSupport table code bindings values outside store cells extra) .attachment :=
  UseScope.fresh_name_not_supported _

theorem Target.fresh_obligation_avoids_support
    (table : Target.Definitions signature algebra program) (code : Target.Code signature algebra program context operands input)
    (bindings : Target.RuntimeEnvironment signature algebra program context)
    (values : Target.RuntimeEnvironment signature algebra program operands)
    (outside : Target.Stack signature algebra program input result) (store : Target.ControlHeap signature algebra program)
    (cells : Cells signature algebra (fun context result => Target.Code signature algebra program context [] result)) (extra : List Reference) :
    Target.freshObligation table code bindings values outside store cells extra ∉
      referenceNames (Target.installationSupport table code bindings values outside store cells extra) .obligation :=
  UseScope.fresh_name_not_supported _

end BoundaryV2.Generalized
