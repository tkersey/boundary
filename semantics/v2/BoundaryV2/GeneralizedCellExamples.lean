import BoundaryV2.GeneralizedCopying
import BoundaryV2.GeneralizedExamples

namespace BoundaryV2.Generalized.Examples

abbrev ExampleCells := Cells signature algebra (fun context result => Target.Code signature algebra [] context [] result)

def initialOuterCell : ExampleCells := [⟨⟨2⟩, ⟨0⟩, .leaf .integer, .datum (.leaf 10)⟩]
def currentOuterCell : ExampleCells := [⟨⟨2⟩, ⟨0⟩, .leaf .integer, .datum (.leaf 99)⟩]

/-- The retained local initial value contains no snapshot of shared outer state. -/
def capturedLocalInitial : Target.RuntimeValue signature algebra [] (.leaf .integer) := .datum (.leaf 0)

def firstBranchCell := Cells.allocate ⟨1⟩ capturedLocalInitial currentOuterCell []
def secondBranchCell := Cells.allocate ⟨2⟩ capturedLocalInitial firstBranchCell.cells []

def updatedBranches : ExampleCells :=
  [⟨⟨4⟩, ⟨2⟩, .leaf .integer, .datum (.leaf 0)⟩,
   ⟨⟨3⟩, ⟨1⟩, .leaf .integer, .datum (.leaf 7)⟩,
   ⟨⟨2⟩, ⟨0⟩, .leaf .integer, .datum (.leaf 99)⟩]

theorem update_shared_outer_state_before_activation :
    Cells.writeCopy (signature := signature) (algebra := algebra) ⟨2⟩ ⟨0⟩ (.datum (.leaf (type := Data.integer) 99)) initialOuterCell = some currentOuterCell := by
  simp [Cells.writeCopy, Cells.exchange, Value.copyable, Datum.copyable, initialOuterCell, currentOuterCell]

theorem branches_allocate_distinct_mutable_cells :
    firstBranchCell.identity = ⟨3⟩ ∧ secondBranchCell.identity = ⟨4⟩ ∧ firstBranchCell.identity ≠ secondBranchCell.identity := by
  exact ⟨rfl, rfl, by decide⟩

theorem update_one_branch_cell :
    Cells.writeCopy (signature := signature) (algebra := algebra) firstBranchCell.identity ⟨1⟩ (.datum (.leaf (type := Data.integer) 7)) secondBranchCell.cells =
      some updatedBranches := by
  simp [Cells.writeCopy, Cells.exchange, firstBranchCell, secondBranchCell, Cells.allocate, Cells.identities,
    FreshNames.bound, currentOuterCell, capturedLocalInitial, Value.copyable, Datum.copyable, updatedBranches]

theorem other_branch_and_shared_state_are_current :
    Cells.readCopy (signature := signature) (algebra := algebra) secondBranchCell.identity ⟨2⟩ (.leaf .integer) updatedBranches = some (.datum (.leaf 0)) ∧
      Cells.readCopy (signature := signature) (algebra := algebra) ⟨2⟩ ⟨0⟩ (.leaf .integer) updatedBranches = some (.datum (.leaf 99)) := by
  simp [Cells.readCopy, Cells.read, Cells.lookup, updatedBranches, secondBranchCell, firstBranchCell,
    Cells.allocate, Cells.identities, FreshNames.bound, currentOuterCell, Value.copyable, Datum.copyable]

def aliasedBranchCell : Target.RuntimeValue signature algebra []
    (.product (.cell (.leaf .integer)) (.cell (.leaf .integer))) :=
  .pair (.cell firstBranchCell.identity ⟨1⟩) (.cell firstBranchCell.identity ⟨1⟩)

def readIntegerCell (reference : Target.RuntimeValue signature algebra [] (.cell (.leaf .integer))) (cells : ExampleCells) :=
  match reference with | .cell identity region => Cells.readCopy (signature := signature) (algebra := algebra) identity region (.leaf .integer) cells

theorem both_aliases_observe_the_branch_write :
    readIntegerCell aliasedBranchCell.first updatedBranches = some (.datum (.leaf 7)) ∧
      readIntegerCell aliasedBranchCell.second updatedBranches = some (.datum (.leaf 7)) := by
  simp [readIntegerCell, aliasedBranchCell, Value.first, Value.second, Cells.readCopy, Cells.read, Cells.lookup,
    firstBranchCell, Cells.allocate, Cells.identities, FreshNames.bound, currentOuterCell, updatedBranches,
    Value.copyable, Datum.copyable]

theorem cell_identity_cannot_override_region_or_type :
    Cells.read (signature := signature) (algebra := algebra) ⟨3⟩ ⟨2⟩ (.leaf .integer) updatedBranches = none ∧
      Cells.read (signature := signature) (algebra := algebra) ⟨3⟩ ⟨1⟩ (.leaf .boolean) updatedBranches = none := by
  simp [Cells.read, Cells.lookup, updatedBranches]

def exclusiveResource : Target.RuntimeValue signature algebra [] (.resource ⟨0⟩) :=
  .datum (.resource ⟨5⟩ ⟨6⟩ (.lexical ⟨0⟩ 0))

def exclusiveCell : ExampleCells := [⟨⟨8⟩, ⟨0⟩, .resource ⟨0⟩, exclusiveResource⟩]

theorem exclusive_cell_contents_are_not_duplicated_by_get :
    Cells.readCopy (signature := signature) (algebra := algebra) ⟨8⟩ ⟨0⟩ (.resource ⟨0⟩) exclusiveCell = none := by
  simp [Cells.readCopy, Cells.read, Cells.lookup, exclusiveCell, exclusiveResource, Value.copyable, Datum.copyable]

def mislabeledReusableClosure : Target.RuntimeValue signature algebra [] (.computation .reusable [] .unit) :=
  .closure (.push .unit .ret) (.cons exclusiveResource .nil) none

theorem reusable_label_does_not_hide_an_exclusive_capture :
    mislabeledReusableClosure.copyable = false ∧
      mislabeledReusableClosure.owningField.tokens = [⟨6⟩] := ⟨rfl, rfl⟩

end BoundaryV2.Generalized.Examples
