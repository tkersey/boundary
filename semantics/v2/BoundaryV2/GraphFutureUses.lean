import BoundaryV2.GraphProjection

namespace BoundaryV2.Profile.Graph.Admission

def projectionRowsValid (program : Target.Program) (state : State) (borrows : Target.Borrow.Witness)
    (rows : List ProjectionRow) : Bool :=
  decide (rows.map ProjectionRow.root).Nodup && rows.all (projectionRowValid program state borrows)

def projectedAt (rows : List ProjectionRow) (task : ProjectionTask) : Option (List Projected) :=
  (rows.find? (fun row => row.root == task)).map ProjectionRow.outputs

def valueOwnerScope (state : State) (remaining : List NodeId) (value : Value)
    (bound : Target.Borrow.Bound) : Option (Option UseContext) := do
  let reference ← match value.body with
    | .reference reference => some (some reference) | .owned reference => some (some reference.node) | _ => some none
  match reference with
  | none => pure none
  | some reference =>
    if _fresh : reference ∈ remaining then do
      let record ← node state reference
      match bound with
      | .region =>
        let region := match record with
          | .region .. => some reference | .cell _ region _ | .borrow _ _ region => some region | _ => none
        pure (region.map (fun region => ⟨some (regionFrame state region), some (some region)⟩))
      | .clause | .capture =>
        match record with
        | .package _ continuation => valueOwnerScope state (remaining.erase reference) continuation bound
        | _ =>
          let delimiter ← match record with
            | .attachment .. => some (some record)
            | .oneShot capture | .multiTemplate capture => some <$> node state capture.delimiter
            | _ => some none
          match delimiter with
          | none => pure none
          | some delimiter =>
            let .attachment activation outer parent phase _ := delimiter | none
            let .handler _ _ _ region ← node state activation | none
            pure (some ⟨some (if bound == .clause && phase == .active then parent else outer), some region⟩)
    else none
termination_by remaining.length
decreasing_by
  have size := List.length_erase_of_mem _fresh
  have positive := List.length_pos_of_mem _fresh
  omega

def ownerScope (state : State) (owner : Projected) (bound : Target.Borrow.Bound) : Option (Option UseContext) :=
  match owner with
  | .borrow context => some (some context)
  | .value value => valueOwnerScope state (inventory state) value bound

inductive FutureObligation where
  | constraint : ProjectionTask → ProjectionTask → Target.Borrow.Bound → FutureObligation
  | outside : ProjectionTask → UseContext → FutureObligation
  deriving DecidableEq, Repr

def futureRecordObligations (program : Target.Program) (state : State) (borrows : Target.Borrow.Witness)
    (index : Nat) (record : Node) : Option (List FutureObligation) := do
  let frame : NodeId := ⟨index⟩
  let start ← returnedStart program state record
  let constraints ← match start with
    | none => pure []
    | some start =>
      (← Target.Borrow.requirementsAt borrows start).mapM (fun constraint =>
        pure (FutureObligation.constraint (.source frame constraint.owner) (.source frame constraint.value) constraint.bound))
  let outside ← match record with
    | .attachment activation outer parent phase _ => do
      let .handler _ _ _ region ← node state activation | none
      pure (some (UseContext.mk (some (if phase == .active then parent else outer)) (some region)))
    | .regionScope _ region parent => do
      let .region _ outer _ ← node state region | none
      pure (some (UseContext.mk (some parent) (some outer)))
    | .protection _ _ parent _ region (some _) => pure (some (UseContext.mk (some parent) (some region)))
    | _ => pure none
  pure (constraints ++ outside.toList.map (FutureObligation.outside (.delivered frame [])))

def futureObligations (program : Target.Program) (state : State) (borrows : Target.Borrow.Witness) : Option (List FutureObligation) :=
  (state.nodes.zipIdx.mapM (fun (record, index) => futureRecordObligations program state borrows index record)).map List.flatten

structure ScopeDemand where
  supplied : Projected
  use : UseContext
  deriving DecidableEq, Repr

def obligationDemands (state : State) (rows : List ProjectionRow) : FutureObligation → Option (List ScopeDemand)
  | .outside task use => (projectedAt rows task).map (List.map (fun supplied => ⟨supplied, use⟩))
  | .constraint owner value bound => do
    let owners ← projectedAt rows owner
    let values ← projectedAt rows value
    let uses ← owners.mapM (fun owner => ownerScope state owner bound)
    pure ((uses.filterMap id).flatMap (fun use => values.map (fun supplied => ⟨supplied, use⟩)))

def futureDemands (program : Target.Program) (state : State) (borrows : Target.Borrow.Witness)
    (rows : List ProjectionRow) : Option (List ScopeDemand) := do
  let obligations ← futureObligations program state borrows
  (obligations.mapM (obligationDemands state rows)).map List.flatten

def scopeDemandValid (state : State) (demand : ScopeDemand) : Bool := match demand.supplied with
  | .value value => supportedUse state ⟨value, demand.use⟩
  | .borrow supplied => within state (supplied.frame.getD none) demand.use.frame &&
      within state (supplied.region.getD none) demand.use.region

def futureScopesValid (program : Target.Program) (state : State) (borrows : Target.Borrow.Witness)
    (rows : List ProjectionRow) : Bool :=
  projectionRowsValid program state borrows rows &&
    (futureDemands program state borrows rows).any (fun demands => demands.all (scopeDemandValid state))

theorem projected_lookup_has_checked_row (program : Target.Program) (state : State)
    (borrows : Target.Borrow.Witness) (rows : List ProjectionRow) (task : ProjectionTask) (outputs : List Projected)
    (accepted : projectionRowsValid program state borrows rows = true)
    (found : projectedAt rows task = some outputs) :
    ∃ row ∈ rows, row.root = task ∧ row.outputs = outputs ∧ projectionRowValid program state borrows row = true := by
  simp only [projectionRowsValid, Bool.and_eq_true] at accepted
  unfold projectedAt at found
  obtain ⟨row, selected, same⟩ := Option.map_eq_some_iff.mp found
  have member := List.mem_of_find?_eq_some selected
  exact ⟨row, member, by simpa using List.find?_some selected, same, List.all_eq_true.mp accepted.2 row member⟩

theorem requested_projection_cannot_be_omitted (program : Target.Program) (state : State)
    (borrows : Target.Borrow.Witness) (rows : List ProjectionRow) (task : ProjectionTask) (outputs : List Projected)
    (accepted : projectionRowsValid program state borrows rows = true) (found : projectedAt rows task = some outputs)
    (projects : Projects program state borrows task output) : output ∈ outputs := by
  obtain ⟨row, _, root, values, checked⟩ := projected_lookup_has_checked_row program state borrows rows task outputs accepted found
  subst task
  subst outputs
  exact projection_row_sound program state borrows row checked projects

theorem all_future_demands_checked (program : Target.Program) (state : State) (borrows : Target.Borrow.Witness)
    (rows : List ProjectionRow) (demands : List ScopeDemand)
    (accepted : futureScopesValid program state borrows rows = true)
    (derived : futureDemands program state borrows rows = some demands) :
    ∀ demand ∈ demands, scopeDemandValid state demand = true := by
  simp only [futureScopesValid, Bool.and_eq_true] at accepted
  simpa [derived, List.all_eq_true] using accepted.2

end BoundaryV2.Profile.Graph.Admission
