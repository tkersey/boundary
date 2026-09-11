import BoundaryV2.GraphOrigins

namespace BoundaryV2.Profile.Graph.Admission

/-- No component means this use imposes no constraint there. A present component
with no enclosing node forbids retaining an identity in that component. -/
structure UseContext where
  frame : Option (Option NodeId) := none
  region : Option (Option NodeId) := none
  deriving DecidableEq, Repr

structure ValueUse where
  value : Value
  context : UseContext
  deriving DecidableEq, Repr

def within (state : State) (required : Option NodeId) (use : Option (Option NodeId)) : Bool :=
  required.all (fun required => use.all (fun context => containsScope state context required))

def holder : Node → Bool
  | .computation .. | .environment .. | .aggregate .. | .package .. => true
  | _ => false

def holderReference (state : State) (value : Value) : Option NodeId := do
  let reference ← match value.body with
    | .reference reference => some reference | .owned reference => some reference.node | _ => none
  if (node state reference).any holder then some reference else none

def holderDependencies (state : State) (reference : NodeId) : List NodeId :=
  match node state reference with
  | some (.computation _ environment) => [environment]
  | some (.environment values _) | some (.aggregate _ _ values) => values.filterMap (holderReference state)
  | some (.package _ value) => (holderReference state value).toList
  | _ => []

def holderWithout (state : State) (target : NodeId) : List NodeId :=
  BoundaryV2.FiniteDependency.refine (fun reference => reference == target) (holderDependencies state) (inventory state)

def holderAcyclic (state : State) : Bool := state.nodes.zipIdx.all fun (record, index) =>
  !holder record || (holderDependencies state ⟨index⟩).all (holderWithout state ⟨index⟩).contains

def regionFrame (state : State) (region : NodeId) : Option NodeId :=
  (state.nodes.zipIdx.find? (fun (record, _) => match record with
    | .regionScope _ actual _ => actual == region
    | .protection _ _ _ _ _ loan => loan == some region
    | _ => false)).map (fun (_, index) => ⟨index⟩)

def obligationFrame (state : State) (obligation : NodeId) : Option NodeId :=
  (state.nodes.zipIdx.find? (fun (record, _) => match record with
    | .protection _ owned _ _ _ _ => owned.node == obligation
    | _ => false)).map (fun (_, index) => ⟨index⟩)

def usesAt (frame region : Option NodeId) (values : List Value) : List ValueUse :=
  values.map (fun value => ⟨value, ⟨some frame, some region⟩⟩)

def activeFrame (state : State) : Option NodeId := state.roots.current.or (state.roots.pending.bind fun reference =>
  match node state reference with | some (.pending _ _ saved _) => some saved | _ => none)

/-- Direct use locations are derived from every record. The future-use
projection adds the demands of values not yet returned to saved holes. -/
def directRecordUses (state : State) (index : Nat) (record : Node) : Option (List ValueUse) := do
  match record with
  | .control control => pure (usesAt control.parent control.region control.arguments)
  | .continuation saved => pure (usesAt saved.parent saved.region (saved.arguments.filterMap id))
  | .handler _ values evidence region => pure (usesAt evidence region values)
  | .cell _ region content => pure (usesAt (regionFrame state region) (some region) [← content])
  | .oneShot capture | .multiTemplate capture =>
    let saved ← capture.capture
    let .continuation saved ← node state saved | none
    pure (usesAt saved.parent saved.region capture.useSiteCapabilities)
  | .unwind parent values | .disposalReturn _ parent values =>
    pure (usesAt parent (availableRegion state parent) values)
  | .obligation _ cleanup resource _ => match cleanup with
    | none => pure []
    | some cleanup =>
      let frame ← obligationFrame state ⟨index⟩
      let .protection _ _ parent _ region _ ← node state frame | none
      pure (usesAt parent region (cleanup :: resource.toList))
  | .exit exit =>
    let frame := exit.stop.or (activeFrame state)
    let values := (match exit.reason with | .normal value => [value] | _ => []) ++ exit.discarded
    pure (usesAt frame (availableRegion state frame) values)
  | _ => pure []

def directUses (state : State) : Option (List ValueUse) :=
  (state.nodes.zipIdx.mapM (fun (record, index) => directRecordUses state index record)).map List.flatten

def directValueUse (state : State) (value : Value) (use : UseContext) : Bool := ((do
  let reference ← match value.body with
    | .reference reference => some (some reference) | .owned reference => some (some reference.node) | _ => some none
  match reference with
  | none => pure true
  | some reference => match ← node state reference with
    | .attachment .. => pure (within state (some reference) use.frame)
    | .region .. => pure (within state (some reference) use.region)
    | .cell _ region _ | .borrow _ _ region => pure (within state (some region) use.region)
    | .oneShot capture | .multiTemplate capture =>
      let .attachment activation outer _ _ _ ← node state capture.delimiter | none
      let .handler _ _ _ region ← node state activation | none
      pure (within state outer use.frame && within state region use.region)
    | _ => pure true) : Option Bool).getD false

def holderFields : Node → List Value
  | .environment values _ | .aggregate _ _ values => values
  | .package _ value => [value]
  | _ => []

def supportedUse (state : State) (use : ValueUse) : Bool :=
  directValueUse state use.value use.context &&
  (holderReference state use.value).all (fun root =>
    (inventory state).all (fun target =>
      (holderWithout state target).contains root ||
        (node state target).any (fun record => (holderFields record).all
          (fun value => directValueUse state value use.context))))

def usesValid (state : State) (uses : List ValueUse) : Bool := holderAcyclic state && uses.all (supportedUse state)

theorem present_empty_context_forbids_capture (state : State) (required : NodeId) :
    within state (some required) (some none) = false := by simp [within, containsScope, ancestry, chain]

theorem absent_component_imposes_no_constraint (state : State) (required : Option NodeId) :
    within state required none = true := by cases required <;> simp [within]

theorem every_use_checked (state : State) (uses : List ValueUse) (use : ValueUse)
    (accepted : usesValid state uses = true) (member : use ∈ uses) : supportedUse state use = true := by
  simp only [usesValid, Bool.and_eq_true] at accepted
  exact List.all_eq_true.mp accepted.2 use member

theorem use_reaches_every_holder_field (state : State) (use : ValueUse) (root target : NodeId) (record : Node)
    (accepted : supportedUse state use = true) (starts : holderReference state use.value = some root)
    (inside : target ∈ inventory state) (actual : node state target = some record)
    (reaches : BoundaryV2.FiniteDependency.Depends (fun reference => reference == target) (holderDependencies state) root) :
    ∀ value ∈ holderFields record, directValueUse state value use.context = true := by
  have absent := BoundaryV2.FiniteDependency.refine_excludes_dependencies _ _ (inventory state) root reaches
  simp only [supportedUse, starts, Option.all_some, Bool.and_eq_true] at accepted
  have checked := List.all_eq_true.mp accepted.2 target inside
  simpa [holderWithout, absent, actual, List.all_eq_true] using checked

end BoundaryV2.Profile.Graph.Admission
