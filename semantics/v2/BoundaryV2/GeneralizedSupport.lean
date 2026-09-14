import BoundaryV2.GeneralizedCodeRelocation

namespace BoundaryV2.Generalized

/-- Support records reference occurrences, not a deduplicated set of owners. -/
inductive Reference where
  | name : (domain : Domain) → Id domain → Reference
  | owner : Owner → Reference

def Reference.relocate (relocation : UseScope.Relocation) : Reference → Reference
  | .name domain identity => .name domain (relocation.name domain identity)
  | .owner holder => .owner (relocation.owner holder)

def Reference.inDomain (domain : Domain) : Reference → Option (Id domain)
  | .name actual identity => if same : actual = domain then some (same ▸ identity) else none
  | .owner _ => none

def referenceNames (support : List Reference) (domain : Domain) : List (Id domain) :=
  support.filterMap (Reference.inDomain domain)

theorem reference_names_append (first second : List Reference) (domain : Domain) :
    referenceNames (first ++ second) domain = referenceNames first domain ++ referenceNames second domain :=
  List.filterMap_append

theorem reference_name_member {support : List Reference} {domain : Domain} {identity : Id domain} :
    identity ∈ referenceNames support domain ↔ Reference.name domain identity ∈ support := by
  induction support with
  | nil => simp [referenceNames]
  | cons reference rest induction =>
    cases reference with
    | name actual name =>
      by_cases same : actual = domain
      · subst actual
        simp_all [referenceNames, Reference.inDomain]
      · simp_all [referenceNames, Reference.inDomain, Ne.symm same]
    | owner holder => simp_all [referenceNames, Reference.inDomain]

theorem reference_names_relocate (relocation : UseScope.Relocation) (support : List Reference) (domain : Domain) :
    referenceNames (support.map (Reference.relocate relocation)) domain =
      (referenceNames support domain).map (relocation.name domain) := by
  induction support with
  | nil => rfl
  | cons reference rest induction =>
    cases reference with
    | name actual name =>
      by_cases same : actual = domain
      · subst actual
        simp_all [referenceNames, Reference.inDomain, Reference.relocate]
      · simp_all [referenceNames, Reference.inDomain, Reference.relocate]
    | owner holder => exact induction

def Datum.references : Datum (Effect := Effect) algebra type → List Reference
  | .leaf _ | .unit => []
  | .pair first second => first.references ++ second.references
  | .left value | .right value => value.references
  | .capability identity => [.name .attachment identity]
  | .region identity => [.name .region identity]
  | .resource identity token owner => [.name .resource identity, .name .custody token, .owner owner]
  | .borrowed identity scope => [.name .resource identity, .name .scope scope]

theorem Datum.references_relocate (relocation : UseScope.Relocation) (datum : Datum (Effect := Effect) algebra type) :
    (datum.relocate relocation).references = datum.references.map (Reference.relocate relocation) := by
  induction datum <;> simp_all only [Datum.relocate, Datum.references, List.map_append, List.map_cons, List.map_nil, Reference.relocate]

namespace Target

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

mutual
  def Code.references : Code signature algebra program context operands result → List Reference
    | .ret | .fault _ => []
    | .push datum next => datum.references ++ next.references
    | .load _ next | .pair next | .first next | .second next | .left next | .right next | .enter next |
      .callNamed _ next | .callClosure next | .primitive _ next | .dispatch _ next | .resume next | .inject next |
      .cellNew next | .cellRead next | .cellWrite next | .dispose next | .clone next | .package next |
      .unpackage next | .yieldThen next => next.references
    | .close body next | .callBlock body next | .enterRegion body next => body.references ++ next.references
    | .branch left right => left.references ++ right.references
    | .attach _ _ returned clauses body next => returned.references ++ clauses.references ++ body.references ++ next.references
    | .replaceHandler _ returned clauses next => returned.references ++ clauses.references ++ next.references
    | .protect cleanup body next => cleanup.references ++ body.references ++ next.references

  def Clauses.references : Clauses signature algebra program effect mode context body answer → List Reference
    | .nil => []
    | .cons _ _ code rest => code.references ++ rest.references
end

private theorem references_relocate_bound (relocation : UseScope.Relocation) (bound : Nat) :
    (∀ {context operands result} (code : Code signature algebra program context operands result), sizeOf code < bound →
      (code.relocate relocation).references = code.references.map (Reference.relocate relocation)) ∧
    (∀ {effect mode context body answer} (clauses : Clauses signature algebra program effect mode context body answer), sizeOf clauses < bound →
      (clauses.relocate relocation).references = clauses.references.map (Reference.relocate relocation)) := by
  induction bound with
  | zero => constructor <;> intros <;> omega
  | succ bound induction =>
    constructor
    · intro context operands result code sized
      cases code with
      | ret | fault fault => rfl
      | push datum next => simp only [Code.relocate, Code.references, List.map_append,
          Datum.references_relocate, induction.1 next (by simp_all; omega)]
      | load reference next | pair next | first next | second next | left next | right next | enter next =>
        exact induction.1 next (by simp_all; omega)
      | callNamed reference next | callClosure next | primitive operation next | dispatch operation next | resume next | inject next =>
        exact induction.1 next (by simp_all; omega)
      | cellNew next | cellRead next | cellWrite next | dispose next | clone next | package next | unpackage next | yieldThen next =>
        exact induction.1 next (by simp_all; omega)
      | close body next | callBlock body next | enterRegion body next => simp only [Code.relocate, Code.references, List.map_append,
          induction.1 body (by simp_all; omega), induction.1 next (by simp_all; omega)]
      | branch left right => simp only [Code.relocate, Code.references, List.map_append,
          induction.1 left (by simp_all; omega), induction.1 right (by simp_all; omega)]
      | attach effect mode returned clauses body next => simp only [Code.relocate, Code.references, List.map_append,
          induction.1 returned (by simp_all; omega), induction.2 clauses (by simp_all; omega),
          induction.1 body (by simp_all; omega), induction.1 next (by simp_all; omega)]
      | replaceHandler effect returned clauses next => simp only [Code.relocate, Code.references, List.map_append,
          induction.1 returned (by simp_all; omega), induction.2 clauses (by simp_all; omega),
          induction.1 next (by simp_all; omega)]
      | protect cleanup body next => simp only [Code.relocate, Code.references, List.map_append,
          induction.1 cleanup (by simp_all; omega), induction.1 body (by simp_all; omega), induction.1 next (by simp_all; omega)]
    · intro effect mode context body answer clauses sized
      cases clauses with
      | nil => rfl
      | cons operation use body rest => simp only [Clauses.relocate, Clauses.references, List.map_append,
          induction.1 body (by simp_all; omega), induction.2 rest (by simp_all; omega)]

theorem Code.references_relocate (relocation : UseScope.Relocation) (code : Code signature algebra program context operands result) :
    (code.relocate relocation).references = code.references.map (Reference.relocate relocation) :=
  (references_relocate_bound relocation (sizeOf code + 1)).1 code (by omega)

theorem Clauses.references_relocate (relocation : UseScope.Relocation) (clauses : Clauses signature algebra program effect mode context body answer) :
    (clauses.relocate relocation).references = clauses.references.map (Reference.relocate relocation) :=
  (references_relocate_bound relocation (sizeOf clauses + 1)).2 clauses (by omega)

end Target
end BoundaryV2.Generalized
