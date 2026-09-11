import BoundaryV2.BorrowRequirements

namespace BoundaryV2.Profile.Target.Borrow

theorem all_cons_checked (predicate : α → Bool) (head : α) (tail : List α)
    (first : predicate head = true) (rest : tail.all predicate = true) :
    (head :: tail).all predicate = true := by simp [first, rest]

theorem all_of_exact_list (predicate : α → Bool) (actual named : List α)
    (same : actual = named) (checked : named.all predicate = true) : actual.all predicate = true := by
  rw [same]; exact checked

theorem check_of_parts (program : Program) (witness : Witness)
    (queriesUnique : decide (witness.queries.map QueryRow.query).Nodup = true)
    (requirementsUnique : decide (witness.requirements.map RequirementsRow.start).Nodup = true)
    (functions : program.functions.all (fun function => (requirementsAt witness function.entry).isSome) = true)
    (queries : witness.queries.all (queryRowValid program witness) = true)
    (requirements : witness.requirements.all (requirementsRowValid program witness) = true)
    (scopedChecked : scopedResultsValid program witness = true) : check program witness = true := by
  simp only [check, Bool.and_eq_true, and_assoc]
  exact ⟨queriesUnique, requirementsUnique, functions, queries, requirements, scopedChecked⟩

theorem scoped_of_exact_rows (program : Program) (witness : Witness) (rows : List (Block × Nat))
    (same : program.blocks.zipIdx = rows)
    (checked : rows.all (fun (block, index) =>
      (scopedBindings program ⟨index⟩ block.terminator).any
        (fun bindings => bindings.all (scopedResultValid program witness))) = true) :
    scopedResultsValid program witness = true := by
  unfold scopedResultsValid
  rw [same]
  exact checked

end BoundaryV2.Profile.Target.Borrow

namespace BoundaryV2.Profile.Target.Borrow

def blockRequirements (program : Program) (witness : Witness) (start block : BlockId) :
    Option (List Constraint) := do
  let code ← program.blocks[block.value]?
  let directConstraints ← code.instructions.mapM fun instruction => do
    if instruction.opcode == .cellNew || instruction.opcode == .cellSet then
      let value ← instruction.operands[1]?
      let owner ← instruction.operands[0]?
      relation program witness start block value owner .region
    else some []
  let control ← terminatorRequirements program witness start block code.terminator
  return directConstraints.flatten ++ control

theorem mapM_cons_checked (function : α → Option β) (head : α) (tail : List α)
    (first : β) (rest : List β)
    (headChecked : function head = some first) (tailChecked : tail.mapM function = some rest) :
    (head :: tail).mapM function = some (first :: rest) := by
  simp [List.mapM_cons, headChecked, tailChecked]

theorem requirementsStep_of_blocks (program : Program) (witness : Witness) (start : BlockId)
    (blocks : List BlockId) (parts : List (List Constraint))
    (reachableChecked : reachable program start = blocks)
    (partsChecked : blocks.mapM (blockRequirements program witness start) = some parts) :
    requirementsStep program witness start = some parts.flatten := by
  change (do let parts ← (reachable program start).mapM (blockRequirements program witness start)
             pure parts.flatten) = _
  rw [reachableChecked, partsChecked]
  rfl

theorem requirementsRow_of_step (program : Program) (witness : Witness) (row : RequirementsRow)
    (constraints : List Constraint)
    (bounded : decide (row.start.value < program.blocks.length) = true)
    (step : requirementsStep program witness row.start = some constraints)
    (subset : Admission.subset constraints row.constraints = true) :
    requirementsRowValid program witness row = true := by
  simp only [requirementsRowValid, bounded, Bool.true_and, step, Option.any_some, subset]

end BoundaryV2.Profile.Target.Borrow

namespace BoundaryV2.Profile.Target.Borrow

theorem forall_mem_cons_checked (predicate : α → Prop) (head : α) (tail : List α)
    (first : predicate head) (rest : ∀ value ∈ tail, predicate value) :
    ∀ value ∈ head :: tail, predicate value := by
  intro value member
  rcases List.mem_cons.mp member with same | member
  · subst value; exact first
  · exact rest value member

theorem flattened_mapM_empty (function : α → Option (List β)) (items : List α)
    (empty : ∀ item ∈ items, function item = some []) :
    (do let parts ← items.mapM function; pure parts.flatten) = some ([] : List β) := by
  induction items with
  | nil => rfl
  | cons item items ih =>
    have first := empty item (by simp)
    have rest := ih (fun value member => empty value (List.mem_cons_of_mem _ member))
    simp only [List.mapM_cons, first]
    cases mapped : items.mapM function <;> simp [mapped] at rest ⊢
    exact rest

theorem requirementsStep_empty (program : Program) (witness : Witness)
    (empty : ∀ block ∈ blockIds program, ∀ start, blockRequirements program witness start block = some [])
    (start : BlockId) : requirementsStep program witness start = some [] := by
  change (do let parts ← (reachable program start).mapM (blockRequirements program witness start)
             pure parts.flatten) = some []
  apply flattened_mapM_empty
  intro block member
  exact empty block (List.mem_filter.mp member).1 start

theorem requirements_all_empty (program : Program) (witness : Witness)
    (empty : ∀ block ∈ blockIds program, ∀ start, blockRequirements program witness start block = some [])
    (bounded : witness.requirements.all (fun row => row.start.value < program.blocks.length) = true) :
    witness.requirements.all (requirementsRowValid program witness) = true := by
  apply List.all_eq_true.mpr
  intro row member
  have bound := List.all_eq_true.mp bounded row member
  apply requirementsRow_of_step _ _ _ [] bound (requirementsStep_empty _ _ empty _)
  rfl

end BoundaryV2.Profile.Target.Borrow
