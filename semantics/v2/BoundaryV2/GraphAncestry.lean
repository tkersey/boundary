import BoundaryV2.GraphValueTypes

namespace BoundaryV2.Profile.Graph.Admission

def forestNode (record : Node) : Bool := isFrame record || match record with | .region .. => true | _ => false

/-- Follow the actual parent fields, deleting each visited node from the
finite inventory. Repeated links and missing records reject. The inventory is
a structural termination measure, not a bound on program execution. -/
def chain (state : State) (parent : Node → Option NodeId) (allowed : Node → Bool)
    (remaining : List NodeId) (current : Option NodeId) : Option (List NodeId) :=
  match current with
  | none => some []
  | some reference =>
    if _fresh : reference ∈ remaining then do
      let record ← node state reference
      if allowed record then
        let rest ← chain state parent allowed (remaining.erase reference) (parent record)
        return reference :: rest
      else none
    else none
termination_by remaining.length
decreasing_by
  have erased := List.length_erase_of_mem _fresh
  have positive := List.length_pos_of_mem _fresh
  omega

def inventory (state : State) : List NodeId := (List.range state.nodes.length).map (fun index => ⟨index⟩)

def ancestry (state : State) (current : Option NodeId) : Option (List NodeId) :=
  chain state treeParent forestNode (inventory state) current

def forestValid (state : State) : Bool := state.nodes.zipIdx.all fun (record, index) =>
  !forestNode record || (ancestry state (some ⟨index⟩)).isSome

def containsScope (state : State) (context : Option NodeId) (required : NodeId) : Bool :=
  (ancestry state context).any (·.contains required)

def normalReturning (state : State) (reference : NodeId) : Bool :=
  (ancestry state (some reference)).any fun path => path.foldr (fun current parentReturning =>
    match node state current with
    | some (.cleanupReturn ..) => true
    | some record => match record with
      | .control _ | .continuation _ | .attachment .. | .regionScope ..
      | .injection _ | .protection .. => (frameParent record).isNone || parentReturning
      | _ => false
    | none => false) false

theorem chain_members (state : State) (parent : Node → Option NodeId) (allowed : Node → Bool)
    (remaining : List NodeId) (current : Option NodeId) (path : List NodeId)
    (accepted : chain state parent allowed remaining current = some path) :
    ∀ reference ∈ path, reference ∈ remaining ∧ ∃ record, node state reference = some record ∧ allowed record = true := by
  induction remaining, current using chain.induct parent generalizing path with
  | case1 remaining => simp [chain] at accepted; cases accepted; simp
  | case2 remaining reference fresh ih =>
    cases found : node state reference with
    | none => simp [chain, fresh, found] at accepted
    | some record =>
      cases permitted : allowed record with
      | false => simp [chain, fresh, found, permitted] at accepted
      | true =>
        simp only [chain, fresh, ↓reduceDIte, found, bind, Option.bind, permitted, ↓reduceIte] at accepted
        cases suffix : chain state parent allowed (remaining.erase reference) (parent record) with
        | none => simp [suffix] at accepted
        | some rest =>
          simp [suffix] at accepted
          cases accepted
          intro candidate member
          rcases List.mem_cons.mp member with same | later
          · subst candidate; exact ⟨fresh, record, found, permitted⟩
          · have member := ih record rest suffix candidate later
            exact ⟨List.mem_of_mem_erase member.1, member.2⟩
  | case3 remaining reference repeated => simp [chain, repeated] at accepted

theorem chain_distinct (state : State) (parent : Node → Option NodeId) (allowed : Node → Bool)
    (remaining : List NodeId) (current : Option NodeId) (path : List NodeId)
    (unique : remaining.Nodup) (accepted : chain state parent allowed remaining current = some path) : path.Nodup := by
  induction remaining, current using chain.induct parent generalizing path with
  | case1 remaining => simp [chain] at accepted; cases accepted; exact List.nodup_nil
  | case2 remaining reference fresh ih =>
    cases found : node state reference with
    | none => simp [chain, fresh, found] at accepted
    | some record =>
      cases permitted : allowed record with
      | false => simp [chain, fresh, found, permitted] at accepted
      | true =>
        simp only [chain, fresh, ↓reduceDIte, found, bind, Option.bind, permitted, ↓reduceIte] at accepted
        cases suffix : chain state parent allowed (remaining.erase reference) (parent record) with
        | none => simp [suffix] at accepted
        | some rest =>
          simp [suffix] at accepted
          cases accepted
          apply List.nodup_cons.mpr
          refine ⟨?_, ih record rest (unique.erase reference) suffix⟩
          intro member
          exact unique.not_mem_erase ((chain_members state parent allowed _ _ rest suffix reference member).1)
  | case3 remaining reference repeated => simp [chain, repeated] at accepted

theorem inventory_distinct (state : State) : (inventory state).Nodup := by
  apply List.nodup_range.map
  intro a b different same
  exact different (congrArg Ref.value same)

theorem ancestry_no_repeated_allocation (state : State) (current : Option NodeId) (path : List NodeId)
    (accepted : ancestry state current = some path) : path.Nodup := by
  apply chain_distinct state treeParent forestNode _ current path _ accepted
  exact inventory_distinct state

theorem scope_has_actual_ancestor (state : State) (context : Option NodeId) (required : NodeId)
    (accepted : containsScope state context required = true) :
    ∃ path record, ancestry state context = some path ∧ required ∈ path ∧
      node state required = some record ∧ forestNode record = true := by
  obtain ⟨path, found, member⟩ := (Option.any_eq_true _ _).mp accepted
  have member : required ∈ path := by simpa using member
  obtain ⟨_, record, actual, allowed⟩ := chain_members state treeParent forestNode _ _ path found required member
  exact ⟨path, record, found, member, actual, allowed⟩

theorem direct_parent_cycle_rejected (state : State) (reference : NodeId) (record : Node)
    (actual : node state reference = some record) (cycle : treeParent record = some reference) :
    ancestry state (some reference) = none := by
  unfold ancestry
  rw [chain]
  split
  · rename_i fresh
    simp only [actual, bind, Option.bind]
    split
    · have unique := inventory_distinct state
      simp [cycle, chain, unique.not_mem_erase]
    · rfl
  · rfl

end BoundaryV2.Profile.Graph.Admission
