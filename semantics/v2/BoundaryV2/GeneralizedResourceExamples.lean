import BoundaryV2.GeneralizedResources

namespace BoundaryV2.Generalized.ResourceExamples

abbrev Actor := Fin 3
abbrev Representation (_ : ResourceName) := Nat

def alpha : Resources.Definition Actor := ⟨⟨0⟩, [0], [1]⟩
def beta : Resources.Definition Actor := ⟨⟨1⟩, [1], [2]⟩

def empty : Resources.Store Representation := ⟨⟨[], [], []⟩, []⟩
def alphaView : Resources.View alpha.name := ⟨⟨0⟩, ⟨0⟩, .lexical ⟨0⟩ 0⟩
def betaView : Resources.View beta.name := ⟨⟨1⟩, ⟨1⟩, .lexical ⟨0⟩ 1⟩

def afterAlpha : Resources.Store Representation :=
  ⟨⟨[.owned ⟨0⟩ (.lexical ⟨0⟩ 0)], [], []⟩, [⟨⟨0⟩, alpha.name, ⟨0⟩, 7⟩]⟩

def afterBoth : Resources.Store Representation :=
  ⟨⟨[.owned ⟨1⟩ (.lexical ⟨0⟩ 1), .owned ⟨0⟩ (.lexical ⟨0⟩ 0)], [], []⟩,
    [⟨⟨1⟩, beta.name, ⟨1⟩, 7⟩, ⟨⟨0⟩, alpha.name, ⟨0⟩, 7⟩]⟩

theorem alpha_introduction_requires_its_authorized_code :
    Resources.introduce alpha 0 alphaView.owner 7 empty [] [] = some ⟨afterAlpha, alphaView⟩ ∧
      Resources.introduce alpha 2 alphaView.owner 7 empty [] [] = none := ⟨rfl, rfl⟩

theorem beta_gets_distinct_authority_despite_equal_representation :
    Resources.introduce beta 1 betaView.owner 7 afterAlpha [] [] = some ⟨afterBoth, betaView⟩ ∧
      alphaView.identity ≠ betaView.identity ∧ alphaView.authority ≠ betaView.authority := by
  exact ⟨rfl, by decide, by decide⟩

theorem both_resources_have_unique_physical_owners : Resources.Store.Valid afterBoth := by
  have initial : Resources.Store.Valid empty := by
    simp [Resources.Store.Valid, empty, UseScope.Valid, UseScope.inventory, UseScope.tokens]
  have first := Resources.introduction_preserves_ownership initial alpha_introduction_requires_its_authorized_code.1
  exact Resources.introduction_preserves_ownership first beta_gets_distinct_authority_despite_equal_representation.1

theorem each_named_eliminator_can_read_its_representation :
    Resources.inspectOwned alpha 1 alphaView afterBoth = some 7 ∧
      Resources.inspectOwned beta 2 betaView afterBoth = some 7 := by
  simp [Resources.inspectOwned, Resources.lookup, alpha, beta, alphaView, betaView, afterBoth,
    UseScope.takeGrant, UseScope.activeFields, UseScope.exposeField]

theorem introduction_permission_does_not_grant_elimination_permission :
    Resources.inspectOwned alpha 0 alphaView afterBoth = none := rfl

theorem equal_representation_does_not_forge_nominal_resource :
    Resources.inspectOwned beta 2 (⟨alphaView.identity, alphaView.authority, alphaView.owner⟩ : Resources.View beta.name) afterBoth = none := rfl

theorem wrong_owning_context_cannot_read_private_data :
    Resources.inspectOwned alpha 1 { alphaView with owner := .lexical ⟨0⟩ 2 } afterBoth = none := rfl

def openScopes : Scope.Forest := [.node ⟨0⟩ [.node ⟨1⟩ []]]
def closedScopes : Scope.Forest := [.node ⟨0⟩ []]
def borrowedAlpha : Resources.Borrow alpha.name := ⟨alphaView.identity, ⟨1⟩⟩
def activeLoans : Resources.Loans := [⟨alphaView.identity, alpha.name, ⟨1⟩⟩]

theorem owner_can_lend_through_a_live_scope :
    Resources.lend alphaView ⟨1⟩ openScopes afterBoth [] = some (borrowedAlpha, activeLoans) := rfl

theorem recorded_live_loan_exposes_only_plain_representation :
    Resources.inspectBorrowed alpha 1 borrowedAlpha openScopes afterBoth activeLoans = some 7 := by
  simp [Resources.inspectBorrowed, Resources.lookup, alpha, borrowedAlpha, openScopes, Scope.path, Scope.Tree.path,
    activeLoans, alphaView, afterBoth, beta, UseScope.inventory, UseScope.tokens, UseScope.Field.tokens]

theorem an_unrecorded_borrowed_view_has_no_authority :
    Resources.inspectBorrowed alpha 1 borrowedAlpha openScopes afterBoth [] = none := rfl

theorem closing_the_loan_scope_revokes_the_borrowed_view :
    Resources.inspectBorrowed alpha 1 borrowedAlpha closedScopes afterBoth activeLoans = none := rfl

def resourceNoLongerOwned : Resources.Store Representation :=
  { afterBoth with fields := ⟨[.owned ⟨1⟩ (.lexical ⟨0⟩ 1)], [], [⟨0⟩]⟩ }

theorem a_recorded_loan_cannot_revive_consumed_resource_authority :
    Resources.inspectBorrowed alpha 1 borrowedAlpha openScopes resourceNoLongerOwned activeLoans = none := rfl

end BoundaryV2.Generalized.ResourceExamples
