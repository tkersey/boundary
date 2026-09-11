import BoundaryV2.GraphUses
import BoundaryV2.BorrowQueries

namespace BoundaryV2.Profile.Graph.Admission

open Target.Borrow (Ambient Path)

inductive Projected where
  | value : Value → Projected
  | borrow : UseContext → Projected
  deriving DecidableEq, Repr

inductive ProjectionTask where
  | value : Value → Path → ProjectionTask
  | source : NodeId → Target.Borrow.Source → ProjectionTask
  | delivered : NodeId → Path → ProjectionTask
  deriving DecidableEq, Repr

structure ProjectionExpansion where
  outputs : List Projected := []
  next : List ProjectionTask := []
  deriving DecidableEq, Repr

def selectedContext (context : UseContext) (component : Option Ambient) : UseContext :=
  ⟨if component == some .region then none else context.frame,
    if component == some .evidence then none else context.region⟩

def frameContext (state : State) (frame : NodeId) : Option UseContext := do
  match ← node state frame with
  | .control control => pure ⟨some control.evidence, some control.region⟩
  | .continuation saved => pure ⟨some saved.evidence, some saved.region⟩
  | .attachment activation _ _ _ _ =>
    let .handler _ _ evidence region ← node state activation | none
    pure ⟨some evidence, some region⟩
  | _ => none

def frameArgument (state : State) (frame : NodeId) (index : Nat) : Option (Option Value) := do
  match ← node state frame with
  | .control control => some <$> control.arguments[index]?
  | .continuation saved => saved.arguments[index]?
  | .attachment activation _ _ _ _ =>
    let .handler _ values _ _ ← node state activation | none
    pure values[index]?
  | _ => none

def returnedStart (program : Target.Program) (state : State) (record : Node) : Option (Option BlockId) := do
  match record with
  | .control control => pure (some control.block)
  | .continuation saved => pure (some (← nextEdge (← block program saved.sourceBlock).terminator).block)
  | .attachment activation _ _ _ _ =>
    let definition ← handler program state activation
    pure (some (← program.functions[definition.returnFunction.value]?).entry)
  | _ => pure none

def projectionStep (program : Target.Program) (state : State) (borrows : Target.Borrow.Witness) :
    ProjectionTask → Option ProjectionExpansion
  | .source frame source => match source with
    | .ambient component => do
      pure ⟨[.borrow (selectedContext (← frameContext state frame) (some component))], []⟩
    | .parameter index path => do
      match ← frameArgument state frame index with
      | some argument => pure ⟨[], [.value argument path]⟩
      | none => pure ⟨[], [.delivered frame path]⟩
  | .value value [] => some ⟨[.value value], []⟩
  | .value value (step :: tail) => do
    let reference ← match value.body with
      | .reference reference => some (some reference) | .owned reference => some (some reference.node) | _ => some none
    match reference with
    | none => pure {}
    | some reference =>
      let record ← node state reference
      match step with
      | .field field => match record with
        | .aggregate _ tag fields =>
          match program.schemas[value.schema.value]? with
          | some (.sum _) => if tag == field then pure ⟨[], [.value (← fields[0]?) tail]⟩ else pure {}
          | _ => pure ⟨[], fields[field]?.toList.map (fun value => .value value tail)⟩
        | _ => pure {}
      | .element => match record with
        | .aggregate _ _ fields => pure ⟨[], fields.map (fun value => .value value tail)⟩
        | _ => pure {}
      | .environment constructor field => match record with
        | .computation actual environment =>
          if actual != constructor then pure {} else do
            let .environment values _ ← node state environment | none
            pure ⟨[], [.value (← values[field]?) tail]⟩
        | _ => pure {}
      | .handlerState selected field => match record with
        | .attachment activation _ _ _ _ =>
          let .handler actual values _ _ ← node state activation | none
          if actual == selected then pure ⟨[], [.value (← values[field]?) tail]⟩ else pure {}
        | _ => pure {}
      | .bodyResult schema =>
        let delimiter := match record with
          | .oneShot capture | .multiTemplate capture => some capture.delimiter
          | .attachment .. => some reference
          | _ => none
        match delimiter with
        | none => pure {}
        | some delimiter =>
          let .attachment activation _ _ _ _ ← node state delimiter | none
          let definition ← handler program state activation
          pure ⟨[], if definition.input == schema then [.delivered delimiter tail] else []⟩
      | .cellContent => match record with
        | .cell _ _ value => pure ⟨[], [.value (← value) tail]⟩
        | _ => pure {}
      | .packageToken => match record with
        | .package _ value => pure ⟨[], [.value value tail]⟩
        | _ => pure {}
      | .useSite index _ => match record with
        | .oneShot capture | .multiTemplate capture => pure ⟨[], [.value (← capture.useSiteCapabilities[index]?) tail]⟩
        | _ => pure {}
      | .outer component => match record with
        | .attachment activation outer _ _ _ =>
          let .handler _ _ _ region ← node state activation | none
          pure ⟨[.borrow (selectedContext ⟨some outer, some region⟩ component)], []⟩
        | _ => pure {}
      | .resumed component => match record with
        | .oneShot capture | .multiTemplate capture =>
          let saved ← capture.capture
          let .continuation saved ← node state saved | none
          pure ⟨[.borrow (selectedContext ⟨some saved.evidence, some saved.region⟩ component)], []⟩
        | .attachment _ _ _ _ region =>
          pure ⟨[.borrow (selectedContext ⟨some (some reference), some region⟩ component)], []⟩
        | _ => pure {}
  | .delivered frame path => do
    let child ← frameChild state frame
    let record ← node state child
    match record with
    | .regionScope .. | .protection .. | .injection _ => pure ⟨[], [.delivered child path]⟩
    | .cleanupReturn _ _ exit =>
      let .exit exit ← node state exit | none
      pure ⟨[], match exit.reason with | .normal value => [.value value path] | _ => []⟩
    | .oneShot _ | .multiTemplate _ | .pending .. | .disposalReturn .. | .unwind .. => pure {}
    | .control _ | .continuation _ | .attachment .. =>
      let some start ← returnedStart program state record | none
      let sources ← Target.Borrow.sourcesAt program borrows ⟨start, .returned path⟩
      pure ⟨[], sources.map (ProjectionTask.source child)⟩
    | _ => none

structure ProjectionRow where
  root : ProjectionTask
  support : List ProjectionTask
  outputs : List Projected
  deriving DecidableEq, Repr

/-- Finite proof data covers the complete local work graph, including cycles
through delivered values. A producer cannot omit a dependency or terminal
projection and retain acceptance. No execution horizon appears here. -/
def projectionRowValid (program : Target.Program) (state : State) (borrows : Target.Borrow.Witness)
    (row : ProjectionRow) : Bool := row.support.contains row.root && row.support.all (fun task =>
  (projectionStep program state borrows task).any (fun expansion =>
    Target.Admission.subset expansion.outputs row.outputs && Target.Admission.subset expansion.next row.support))

inductive Projects (program : Target.Program) (state : State) (borrows : Target.Borrow.Witness) :
    ProjectionTask → Projected → Prop where
  | direct : projectionStep program state borrows task = some expansion → output ∈ expansion.outputs →
      Projects program state borrows task output
  | through : projectionStep program state borrows task = some expansion → next ∈ expansion.next →
      Projects program state borrows next output → Projects program state borrows task output

theorem projection_support_closed (program : Target.Program) (state : State) (borrows : Target.Borrow.Witness)
    (row : ProjectionRow) (accepted : projectionRowValid program state borrows row = true) :
    row.root ∈ row.support ∧ ∀ task ∈ row.support, ∃ expansion,
      projectionStep program state borrows task = some expansion ∧ expansion.outputs ⊆ row.outputs ∧ expansion.next ⊆ row.support := by
  simpa [projectionRowValid, Bool.and_eq_true, List.all_eq_true, Option.any_eq_true, Target.Admission.subset,
    DeclarationAdmission.subset, List.subset_def] using accepted

theorem supported_projection_cannot_be_omitted (program : Target.Program) (state : State) (borrows : Target.Borrow.Witness)
    (row : ProjectionRow) (accepted : projectionRowValid program state borrows row = true)
    (member : task ∈ row.support) (projects : Projects program state borrows task output) : output ∈ row.outputs := by
  have closed := (projection_support_closed program state borrows row accepted).2
  induction projects with
  | direct actual memberOutput =>
    obtain ⟨expansion, found, outputs, _⟩ := closed _ member
    cases Option.some.inj (actual.symm.trans found)
    exact outputs memberOutput
  | through actual memberNext _ ih =>
    obtain ⟨expansion, found, _, next⟩ := closed _ member
    cases Option.some.inj (actual.symm.trans found)
    exact ih (next memberNext)

theorem projection_row_sound (program : Target.Program) (state : State) (borrows : Target.Borrow.Witness)
    (row : ProjectionRow) (accepted : projectionRowValid program state borrows row = true)
    (projects : Projects program state borrows row.root output) : output ∈ row.outputs :=
  supported_projection_cannot_be_omitted program state borrows row accepted
    (projection_support_closed program state borrows row accepted).1 projects

end BoundaryV2.Profile.Graph.Admission
