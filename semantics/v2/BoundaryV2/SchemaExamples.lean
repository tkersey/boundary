import BoundaryV2.SchemaClasses

namespace BoundaryV2.Profile.SchemaExamples

open SchemaAdmission SchemaEquivalence SchemaDescriptor

private def recursiveTypes : List (Schema .target) := [.unit, .sum [0, 1]]

theorem productive_recursive_widths : widths recursiveTypes = [0, 1] := by
  have round0 : widthRound recursiveTypes [infinity, infinity] = [0, infinity] := by decide +kernel
  have round1 : widthRound recursiveTypes [0, infinity] = [0, 1] := by decide +kernel
  have fixed : widthRound recursiveTypes [0, 1] = [0, 1] := by decide +kernel
  change widthLoop recursiveTypes [infinity, infinity] = [0, 1]
  rw [← widthLoop_round, round0, ← widthLoop_round, round1]
  exact widthLoop_of_fixed _ _ fixed

theorem productive_recursive_schema_admitted : SchemaAdmission.valid recursiveTypes = true := by
  rw [SchemaAdmission.valid, productive_recursive_widths]
  decide +kernel

theorem unguarded_recursive_product_rejected :
    SchemaAdmission.valid ([.product [0]] : List (Schema .target)) = false := by
  have fixed : widthRound ([.product [0]] : List (Schema .target)) [infinity] = [infinity] := by decide +kernel
  have result : widths ([.product [0]] : List (Schema .target)) = [infinity] := widthLoop_of_fixed _ _ fixed
  simp [SchemaAdmission.valid, result]

theorem zero_length_recursive_array_admitted :
    SchemaAdmission.valid ([.array 0 0] : List (Schema .target)) = true := by
  have first : widthRound ([.array 0 0] : List (Schema .target)) [infinity] = [0] := by decide +kernel
  have fixed : widthRound ([.array 0 0] : List (Schema .target)) [0] = [0] := by decide +kernel
  have result : widths ([.array 0 0] : List (Schema .target)) = [0] := by
    change widthLoop _ [infinity] = [0]
    rw [← widthLoop_round, first]
    exact widthLoop_of_fixed _ _ fixed
  rw [SchemaAdmission.valid, result]
  decide +kernel

private def repeatedCycles : List (Schema .target) :=
  [.product [1, 2], .sum [3, 1], .sum [3, 2], .unit]

theorem recursive_alias_classes_collapse : classes repeatedCycles 1 = classes repeatedCycles 2 := by
  apply classes_equal_of_bisimilar
  let witness : List (SchemaEquivalence.Pair .target) := [(1, 2), (3, 3)]
  have bounded : witness ⊆ allPairs repeatedCycles := by decide +kernel
  have closed : ∀ pair ∈ witness, pairValid repeatedCycles witness pair = true := by decide +kernel
  exact bisimilar_greatest repeatedCycles witness bounded closed (by decide)

theorem array_length_distinction_preserved :
    ((0 : SchemaId .target), 1) ∉ bisimilar [.array 2 1, .array 2 2, .unit] := by
  intro related
  obtain ⟨a, b, foundA, foundB, same, _⟩ :=
    bisimilar_is_bisimulation [.array 2 1, .array 2 2, .unit] 0 1 related
  have left : a = .array 2 1 := Option.some.inj foundA.symm
  have right : b = .array 2 2 := Option.some.inj foundB.symm
  subst a
  subst b
  cases same

theorem enumeration_label_distinction_preserved :
    ((0 : SchemaId .target), 1) ∉ bisimilar [.enumeration [1, 2], .enumeration [1, 3]] := by
  intro related
  obtain ⟨a, b, foundA, foundB, same, _⟩ :=
    bisimilar_is_bisimulation [.enumeration [1, 2], .enumeration [1, 3]] 0 1 related
  have left : a = .enumeration [1, 2] := Option.some.inj foundA.symm
  have right : b = .enumeration [1, 3] := Option.some.inj foundB.symm
  subst a
  subst b
  cases same

end BoundaryV2.Profile.SchemaExamples
