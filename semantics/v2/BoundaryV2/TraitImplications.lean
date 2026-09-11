import BoundaryV2.TraitCompleteness

namespace BoundaryV2.Profile.Traits

private theorem clone_rule_copy (shape : Schema space) (children : List (Atom space))
    (checked : premises shape .clone = some children) :
    ∃ copied, premises shape .copy = some copied ∧
      ∀ child ∈ copied, (child.2 = .copy ∨ child.2 = .clone) ∧ (child.1, .clone) ∈ children := by
  cases shape with
  | product fields | sum fields =>
    simp only [premises, Option.some.injEq] at checked
    refine ⟨fields.map (·, .copy), rfl, ?_⟩
    intro child member
    obtain ⟨field, fieldMember, rfl⟩ := List.mem_map.mp member
    exact ⟨Or.inl rfl, checked ▸ List.mem_map.mpr ⟨field, fieldMember, rfl⟩⟩
  | seq element | vector element _ | array element _ =>
    simp only [premises, Option.some.injEq] at checked
    refine ⟨[(element, .copy)], rfl, ?_⟩
    intro child member
    simp only [List.mem_singleton] at member
    subst child
    exact ⟨Or.inl rfl, checked ▸ List.mem_singleton_self _⟩
  | internal inner =>
    cases inner with
    | computation signature =>
      simp [premises] at checked
      refine ⟨signature.captureBound.map (·, .copy), ?_, ?_⟩
      · simp [premises, checked.1]
      · intro child member
        obtain ⟨field, fieldMember, rfl⟩ := List.mem_map.mp member
        exact ⟨Or.inl rfl, checked.2 ▸ List.mem_map.mpr ⟨field, fieldMember, rfl⟩⟩
    | resumption signature =>
      simp [premises] at checked
      refine ⟨signature.captureBound.map (·, .clone), ?_, ?_⟩
      · simp [premises, checked.1, checked.2.1]
      · intro child member
        obtain ⟨field, fieldMember, rfl⟩ := List.mem_map.mp member
        exact ⟨Or.inr rfl, checked.2.2 ▸ List.mem_map.mpr ⟨field, fieldMember, rfl⟩⟩
    | suspensionPackage _ | abstractResource _ => simp [premises] at checked
    | capability _ | region _ | cell _ _ | borrowed _ _ => exact ⟨[], rfl, by simp⟩
  | unit | boolean | i8 | i16 | i32 | i64 | u8 | u16 | u32 | u64 | bytes | text
  | boundedBytes _ | boundedText _ | enumeration _ => exact ⟨[], rfl, by simp⟩

private theorem clone_children_mode (shape : Schema space) (children : List (Atom space))
    (checked : premises shape .clone = some children) (child : Atom space) (member : child ∈ children) :
    child.2 = .clone := by
  have mapped (fields : List (SchemaId space)) (equal : fields.map (·, Kind.clone) = children) : child.2 = .clone := by
    obtain ⟨field, _, pair⟩ := List.mem_map.mp (equal ▸ member)
    exact congrArg Prod.snd pair.symm
  have single (field : SchemaId space) (equal : [(field, Kind.clone)] = children) : child.2 = .clone := by
    have pair := List.mem_singleton.mp (equal ▸ member)
    exact congrArg Prod.snd pair
  cases shape with
  | product fields | sum fields => exact mapped fields (by simpa [premises] using checked)
  | seq element | vector element _ | array element _ => exact single element (by simpa [premises] using checked)
  | internal inner =>
    cases inner with
    | computation signature => simp [premises] at checked; exact mapped _ checked.2
    | resumption signature => simp [premises] at checked; exact mapped _ checked.2.2
    | cell element _ | borrowed element _ => exact single element (by simpa [premises] using checked)
    | capability _ | region _ =>
      simp only [premises, Option.some.injEq] at checked
      cases checked
      contradiction
    | suspensionPackage _ | abstractResource _ => simp [premises] at checked
  | unit | boolean | i8 | i16 | i32 | i64 | u8 | u16 | u32 | u64 | bytes | text
  | boundedBytes _ | boundedText _ | enumeration _ =>
    simp only [premises, Option.some.injEq] at checked
    cases checked
    contradiction

/-- Clone safety entails copy safety. For resumptions, both rules keep their
clone dependencies; for computations, each copied capture inherits the law. -/
theorem Safe.clone_implies_copy (schemas : List (Schema space)) (type : SchemaId space)
    (safe : Safe schemas (type, .clone)) : Safe schemas (type, .copy) := by
  have inherited (atom : Atom space) (path : Reach schemas (type, .copy) atom) :
      (atom.2 = .copy ∨ atom.2 = .clone) ∧ Safe schemas (atom.1, .clone) := by
    induction path with
    | refl => exact ⟨Or.inl rfl, safe⟩
    | @step parent children child path checked member induction =>
      obtain ⟨modes, parentSafe⟩ := induction
      rcases modes with copyMode | cloneMode
      · obtain ⟨cloneChildren, cloneChecked⟩ := parentSafe _ .refl
        cases found : schemas[parent.1.value]? with
        | none => simp [rule, found] at cloneChecked
        | some shape =>
          have clonePremises : premises shape .clone = some cloneChildren := by
            simpa [rule, found] using cloneChecked
          obtain ⟨copied, copiedChecked, copiedChildren⟩ := clone_rule_copy shape cloneChildren clonePremises
          have same : copied = children := by
            simpa [rule, found, copyMode, copiedChecked] using checked
          obtain ⟨mode, childMember⟩ := copiedChildren child (same ▸ member)
          exact ⟨mode, parentSafe.reachable (.step .refl cloneChecked childMember)⟩
      · have childPath : Reach schemas (parent.1, .clone) child := by
          apply Reach.step Reach.refl
          · exact (show parent = (parent.1, Kind.clone) from Prod.ext rfl cloneMode) ▸ checked
          · exact member
        have childMode : child.2 = .clone := by
          cases found : schemas[parent.1.value]? with
          | none => simp [rule, found] at checked
          | some shape =>
            have clonePremises : premises shape .clone = some children := by
              simpa [rule, found, cloneMode] using checked
            exact clone_children_mode shape children clonePremises child member
        exact ⟨Or.inr childMode,
          (show child = (child.1, Kind.clone) from Prod.ext rfl childMode) ▸ parentSafe.reachable childPath⟩
  intro atom path
  obtain ⟨mode, atomSafe⟩ := inherited atom path
  obtain ⟨children, checked⟩ := atomSafe _ .refl
  rcases mode with copyMode | cloneMode
  · cases found : schemas[atom.1.value]? with
    | none => simp [rule, found] at checked
    | some shape =>
      obtain ⟨copied, copiedChecked, _⟩ := clone_rule_copy shape children (by simpa [rule, found] using checked)
      exact ⟨copied, by simpa [rule, found, copyMode] using copiedChecked⟩
  · exact ⟨children, by simpa [rule, cloneMode] using checked⟩

theorem check_clone_implies_copy (schemas : List (Schema space)) (type : SchemaId space)
    (checked : check schemas .clone type = true) : check schemas .copy type = true :=
  check_complete schemas .copy type ((check_sound schemas .clone type checked).clone_implies_copy schemas type)

end BoundaryV2.Profile.Traits
