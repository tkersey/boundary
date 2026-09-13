import BoundaryV2.GeneralizedScopeCapture

namespace BoundaryV2.Generalized.ScopeExamples

/-- Scope 1 is the creator; 2 is owned captured work; 3 is a younger unowned
dependency. Scope 4 is a sibling destination under the longer-lived root 0. -/
def original : Scope.Forest :=
  [.node ⟨0⟩ [.node ⟨1⟩ [.node ⟨2⟩ [], .node ⟨3⟩ []], .node ⟨4⟩ []]]

def retained : Scope.Forest :=
  [.node ⟨0⟩ [.node ⟨1⟩ [.node ⟨3⟩ []], .node ⟨4⟩ [.node ⟨5⟩ [.node ⟨2⟩ []]]]]

def afterCreatorClosed : Scope.Forest :=
  [.node ⟨0⟩ [.node ⟨4⟩ [.node ⟨5⟩ [.node ⟨2⟩ []]]]]

def supportedFields : List UseScope.Field :=
  [.owned ⟨7⟩ (.lexical ⟨2⟩ 0), .closure [.borrowed ⟨2⟩, .borrowed ⟨0⟩]]

def escapingFields : List UseScope.Field :=
  [.owned ⟨7⟩ (.lexical ⟨2⟩ 0), .closure [.borrowed ⟨3⟩]]

def retainedPackage : UseScope.ScopedPackage :=
  ⟨⟨⟨5⟩, retained⟩, ⟨[], [.package supportedFields], []⟩⟩

theorem original_forest_is_valid : Scope.Valid original := by
  unfold Scope.Valid
  decide

theorem root_can_supply_a_borrow_to_its_descendant : Scope.permitsBorrow original ⟨4⟩ ⟨0⟩ = true := rfl

theorem younger_scope_cannot_supply_an_escaping_borrow : Scope.permitsBorrow original ⟨4⟩ ⟨3⟩ = false := rfl

theorem owned_scope_and_outer_borrow_can_be_retained :
    UseScope.packageScoped ⟨2⟩ ⟨4⟩ original [] supportedFields [] [] [] = some retainedPackage := rfl

theorem dormant_younger_borrow_prevents_retention :
    UseScope.packageScoped ⟨2⟩ ⟨4⟩ original [] escapingFields [] [] [] = none := rfl

theorem retained_package_keeps_unique_ownership_and_scopes :
    UseScope.Valid retainedPackage.fields ∧ Scope.Valid retainedPackage.lifetime.forest := by
  have fields : UseScope.Valid ⟨[] ++ supportedFields ++ [], [], []⟩ := by
    simp [UseScope.Valid, UseScope.inventory, UseScope.tokens, UseScope.Field.tokens, supportedFields]
  exact ⟨UseScope.scoped_package_preserves_ownership fields owned_scope_and_outer_borrow_can_be_retained,
    UseScope.scoped_package_preserves_scope_forest original_forest_is_valid owned_scope_and_outer_borrow_can_be_retained⟩

theorem creator_closes_without_destroying_transferred_work :
    Scope.close ⟨1⟩ retained = some (.node ⟨1⟩ [.node ⟨3⟩ []], afterCreatorClosed) := rfl

theorem owned_retention_outlives_its_creator :
    Scope.path ⟨2⟩ afterCreatorClosed = some [⟨0⟩, ⟨4⟩, ⟨5⟩, ⟨2⟩] ∧
      Scope.path ⟨1⟩ afterCreatorClosed = none ∧ Scope.path ⟨3⟩ afterCreatorClosed = none := ⟨rfl, rfl, rfl⟩

theorem closed_younger_scope_cannot_supply_later_borrows :
    Scope.permitsBorrow afterCreatorClosed ⟨2⟩ ⟨3⟩ = false :=
  Scope.closed_scope_cannot_supply_a_borrow retained_package_keeps_unique_ownership_and_scopes.2
    creator_closes_without_destroying_transferred_work (by simp [Scope.Tree.names, Scope.names])

theorem moving_under_itself_or_its_child_rejects :
    Scope.move ⟨2⟩ ⟨2⟩ original = none ∧ Scope.move ⟨1⟩ ⟨2⟩ original = none := ⟨rfl, rfl⟩

theorem duplicate_scope_names_are_invalid : ¬ Scope.Valid [.node ⟨0⟩ [], .node ⟨0⟩ []] := by
  unfold Scope.Valid
  decide

end BoundaryV2.Generalized.ScopeExamples
