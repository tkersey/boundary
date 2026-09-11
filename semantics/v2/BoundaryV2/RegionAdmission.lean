import BoundaryV2.TerminatorAdmission

namespace BoundaryV2.Profile.Target.Admission

def schemaRegion : Schema .target → Option (RegionId .target)
  | .internal (.region region) | .internal (.cell _ region) | .internal (.borrowed _ region) => some region
  | _ => none

/-- A nominal upper bound does not allocate all names below it. Only referenced
regions occupy dependency columns, as in the admitted program's finite catalog. -/
def referencedRegions (program : Program) : List (RegionId .target) :=
  (program.schemas.filterMap schemaRegion).eraseDups

abbrev RegionFacts := List (RegionId .target × List (SchemaId .target))

def regionFacts (program : Program) : RegionFacts :=
  (referencedRegions program).map (fun region => (region, regionSafeSchemas program region))

def regionAllowed (facts : RegionFacts) (type : SchemaId .target) (regions : List (RegionId .target)) : Bool :=
  facts.all (fun (region, safe) => safe.contains type || regions.contains region)

def regionOccurs (facts : RegionFacts) (type : SchemaId .target) (region : RegionId .target) : Bool :=
  facts.any (fun (owner, safe) => owner == region && !safe.contains type)

def handlerRegionsAllowed (program : Program) (handler : Handler .target) (regions : List (RegionId .target)) : Bool :=
  (program.functions[handler.returnFunction.value]?).any (fun function => subset function.regions regions) &&
  handler.clauses.all (fun clause =>
    (program.functions[clause.function.value]?).any (fun function => subset function.regions regions))

def blockRegionsValid (program : Program) (facts : RegionFacts) (block : Block) : Bool := ((do
  let function ← program.functions[block.function.value]?
  let slots := blockSlots block
  let common := slots.all (fun type => regionAllowed facts type function.regions)
  match block.terminator with
  | .call callee _ _ =>
    let callee ← program.functions[callee.value]?
    return common && subset callee.regions function.regions
  | .handle handler _ _ _ _ | .resumeWith _ _ handler _ _ =>
    let handler ← program.handlers[handler.value]?
    return common && handlerRegionsAllowed program handler function.regions
  | .withRegion region body _ _ =>
    let body ← slotComputation program slots body
    return common && !regionOccurs facts body.result region
  | .protect body _ _ _ loanRegion _ =>
    match loanRegion with
    | none => return common
    | some region =>
      let body ← slotComputation program slots body
      return common && !regionOccurs facts body.result region
  | .returnValue _ | .jump _ | .branch .. | .switchVariant .. | .unpackProduct ..
  | .perform _ | .yieldValue _ | .fail _ | .apply .. | .resumeValue ..
  | .resumeComputation .. | .forward _ | .dispose .. => return common) : Option Bool).getD false

def regionsValid (program : Program) : Bool :=
  let facts := regionFacts program
  program.functions.all (fun function =>
    orderedRefs program.scopes.regionCount function.regions &&
    (function.result :: function.parameters).all (fun type => regionAllowed facts type function.regions)) &&
  program.blocks.all (blockRegionsValid program facts)

theorem regionAllowed_excludes_outside (program : Program) (type : SchemaId .target)
    (regions : List (RegionId .target)) (region : RegionId .target)
    (valid : SchemaAdmission.valid program.schemas = true) (inside : type.value < program.schemas.length)
    (referenced : region ∈ referencedRegions program) (outside : region ∉ regions)
    (accepted : regionAllowed (regionFacts program) type regions = true) :
    ¬ RegionDependency program region type := by
  have member : (region, regionSafeSchemas program region) ∈ regionFacts program :=
    List.mem_map.mpr ⟨region, referenced, rfl⟩
  have allowed := List.all_eq_true.mp accepted _ member
  have safe : type ∈ regionSafeSchemas program region := by simpa [outside] using allowed
  exact (regionSafe_exact program region type valid inside).mp safe

theorem regionOccurs_exact (program : Program) (type : SchemaId .target) (region : RegionId .target)
    (valid : SchemaAdmission.valid program.schemas = true) (inside : type.value < program.schemas.length)
    (referenced : region ∈ referencedRegions program) :
    regionOccurs (regionFacts program) type region = true ↔ RegionDependency program region type := by
  classical
  simp only [regionOccurs, regionFacts, List.any_map]
  simp only [Function.comp_def, List.any_eq_true, Bool.and_eq_true, beq_iff_eq,
    Bool.not_eq_true', Bool.eq_false_iff]
  constructor
  · rintro ⟨owner, _, equal, absent⟩
    subst owner
    exact Classical.byContradiction (fun notDependent => absent
      (List.contains_iff_mem.mpr ((regionSafe_exact program region type valid inside).mpr notDependent)))
  · intro dependent
    exact ⟨region, referenced, rfl, fun safe =>
      (regionSafe_exact program region type valid inside).mp (List.contains_iff_mem.mp safe) dependent⟩

end BoundaryV2.Profile.Target.Admission
