import BoundaryV2.ProgramReferences

namespace BoundaryV2.Profile.Target.Canonical

/-- Regions are names under an upper bound, not an allocated catalog. The
worklist enumerates the actual nine catalogs and visits region references only
when encountered. Its termination measure is independent of program execution. -/
def catalogReferences (program : Program) : List Reference :=
  (kinds.filter (· != .region)).flatMap (fun kind =>
    (List.range (count program kind)).map (fun index => ⟨kind, index⟩))

def orderOf (order : List Reference) (kind : Kind) : List Nat :=
  order.filterMap (fun reference => if reference.kind == kind then some reference.index else none)

def interned (program : Program) (order : List Reference) (reference : Reference) : Bool :=
  reference.kind == .constant && (program.constants[reference.index]?).any (fun literal =>
    (orderOf order .constant).any (fun index => program.constants[index]? == some literal))

def walk (program : Program) (remaining pending order : List Reference) : Option (List Reference) :=
  match pending with
  | [] => some order
  | reference :: tail =>
    match nodeReferences program reference with
    | none => none
    | some children =>
      if reference.kind == .region then
        walk program remaining tail (if order.contains reference then order else order ++ [reference])
      else if _fresh : reference ∈ remaining then
        if interned program order reference then
          walk program (remaining.erase reference) tail order
        else walk program (remaining.erase reference) (children ++ tail) (order ++ [reference])
      else walk program remaining tail order
termination_by (remaining.length, pending.length)
decreasing_by
  all_goals simp_wf
  all_goals first
    | have size := List.length_erase_of_mem _fresh
      have positive := List.length_pos_of_mem _fresh
      omega
    | exact Prod.Lex.right _ (by omega)

def discover (program : Program) : Option (List Reference) :=
  walk program (catalogReferences program) (rootReferences program.roots) []

/-- This checks first-visit numbering and completeness, including referenced
region names. Comparing a length before indices avoids allocating regionCount
elements when a malformed image supplies a huge nominal bound. -/
def completeOrder (program : Program) (order : List Reference) : Bool :=
  kinds.all (fun kind =>
    let indices := orderOf order kind
    indices.length == count program kind && indices.zipIdx.all (fun (old, index) => old == index))

def check (program : Program) : Bool := (discover program).any (completeOrder program)

/-- Canonical numbering is a property of the complete root traversal. Program
typing, constant value admission, use and borrow checking are separate. -/
def Numbered (program : Program) : Prop :=
  ∃ order, discover program = some order ∧
    ∀ kind, orderOf order kind = List.range (count program kind)

private theorem numbered_list (values : List Nat) :
    values.zipIdx.all (fun (old, index) => old == index) = true ↔ values = List.range values.length := by
  constructor
  · intro accepted
    apply List.ext_getElem
    · simp
    · intro index leftBound rightBound
      have member : (values[index], index) ∈ values.zipIdx := by
        exact List.mem_iff_getElem?.mpr ⟨index, by simp [leftBound]⟩
      have same := List.all_eq_true.mp accepted _ member
      simpa using same
  · intro equal
    rw [equal]
    simp only [List.all_eq_true, beq_iff_eq]
    intro pair member
    obtain ⟨index, found⟩ := List.mem_iff_getElem?.mp member
    simp only [List.getElem?_zipIdx] at found
    cases original : (List.range values.length)[index]? with
    | none => simp [original] at found
    | some value =>
      have bound : index < values.length := by
        have bound := (List.getElem?_eq_some_iff.mp original).1
        simpa only [List.length_range] using bound
      have atIndex : value = index := Option.some.inj (original.symm.trans (List.getElem?_range bound))
      simp only [original, Option.map_some, Option.some.injEq] at found
      subst pair
      simpa using atIndex

theorem completeOrder_exact (program : Program) (order : List Reference) :
    completeOrder program order = true ↔
      ∀ kind, orderOf order kind = List.range (count program kind) := by
  unfold completeOrder
  rw [List.all_eq_true]
  constructor
  · intro accepted kind
    have member : kind ∈ kinds := by cases kind <;> simp [kinds]
    have checked := accepted kind member
    simp only [Bool.and_eq_true, beq_iff_eq] at checked
    obtain ⟨size, indexed⟩ := checked
    simpa [size] using (numbered_list _).mp indexed
  · intro numbered kind _
    rw [numbered kind]
    simp only [Bool.and_eq_true, beq_iff_eq, List.length_range]
    exact ⟨True.intro, (numbered_list _).mpr (by simp)⟩

theorem check_exact (program : Program) : check program = true ↔ Numbered program := by
  simp only [check, Numbered, Option.any_eq_true, completeOrder_exact]

theorem completeOrder_no_missing_catalog (program : Program) (order : List Reference)
    (accepted : completeOrder program order = true) (kind : Kind) (index : Nat)
    (bounded : index < count program kind) : index ∈ orderOf order kind := by
  rw [(completeOrder_exact program order).mp accepted kind]
  exact List.mem_range.mpr bounded

theorem completeOrder_preserves_nominal_distinctions (program : Program) (order : List Reference)
    (accepted : completeOrder program order = true) (kind : Kind) : (orderOf order kind).Nodup := by
  rw [(completeOrder_exact program order).mp accepted kind]
  exact List.nodup_range

theorem constant_interning_uses_schema_and_full_bytes (program : Program) (order : List Reference)
    (reference : Reference) (accepted : interned program order reference = true) :
    reference.kind = .constant ∧ ∃ literal index,
      program.constants[reference.index]? = some literal ∧ index ∈ orderOf order .constant ∧
      program.constants[index]? = some literal := by
  simpa only [interned, Bool.and_eq_true, beq_iff_eq, Option.any_eq_true, List.any_eq_true,
    exists_and_left, and_assoc] using accepted

end BoundaryV2.Profile.Target.Canonical
