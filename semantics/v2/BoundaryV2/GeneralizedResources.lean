import BoundaryV2.GeneralizedControlCreation
import BoundaryV2.GeneralizedScopes
import BoundaryV2.GeneralizedFields

namespace BoundaryV2.Generalized.Resources

variable {Actor : Type} {Representation : ResourceName → Type}

/-- Fixed program metadata: callers bind this to the declared resource entry,
not a descriptor supplied with a runtime view. Actors are identities in the
finite authored code table. The private data family is authority-free. -/
structure Definition (Actor : Type) where
  name : ResourceName
  introducers : List Actor
  eliminators : List Actor

structure View (name : ResourceName) where
  identity : Id .resource
  authority : Id .custody
  owner : Owner

/-- The resource registry is nonowning; the active/retained physical fields
remain the authority holders, just as for saved control. -/
structure Record (Representation : ResourceName → Type) where
  identity : Id .resource
  name : ResourceName
  authority : Id .custody
  representation : Representation name

structure Store (Representation : ResourceName → Type) where
  fields : UseScope.State
  resources : List (Record Representation)

structure Borrow (name : ResourceName) where
  identity : Id .resource
  scope : Id .scope

def View.toDatum (view : View name) : Datum (Effect := Effect) algebra (.resource name) :=
  .resource view.identity view.authority view.owner

def Borrow.toDatum (view : Borrow name) : Datum (Effect := Effect) algebra (.borrowed name) :=
  .borrowed view.identity view.scope

theorem borrowed_view_has_no_owning_field {signature : Signature} (view : Borrow name) (algebra : LeafAlgebra signature.Data) :
    (Datum.owningField (signature := signature) (view.toDatum (algebra := algebra) (Effect := signature.Effect))).tokens = [] := rfl

structure Loan where
  identity : Id .resource
  name : ResourceName
  scope : Id .scope
  deriving DecidableEq

/-- The owner of a protection keeps this list with its scope state. Merely
constructing a borrowed view does not insert a loan or create authority. -/
abbrev Loans := List Loan

def Store.Valid (store : Store Representation) : Prop :=
  UseScope.Valid store.fields ∧ (store.resources.map Record.identity).Nodup ∧ (store.resources.map Record.authority).Nodup

def lookup (identity : Id .resource) : List (Record Representation) → Option (Record Representation)
  | [] => none
  | record :: rest => if record.identity = identity then some record else lookup identity rest

def custodySupport (store : Store Representation) : List (Id .custody) :=
  UseScope.custodyNames store.fields.active ++ UseScope.custodyNames store.fields.retained ++ store.fields.spent ++
    store.resources.map Record.authority

structure Introduced (Representation : ResourceName → Type) (name : ResourceName) where
  store : Store Representation
  view : View name

def introduce [DecidableEq Actor] (definition : Definition Actor) (actor : Actor) (owner : Owner)
    (representation : Representation definition.name) (store : Store Representation)
    (reservedResources : List (Id .resource)) (reservedAuthority : List (Id .custody)) :
    Option (Introduced Representation definition.name) :=
  if actor ∈ definition.introducers then
    let identity := UseScope.freshName (reservedResources ++ store.resources.map Record.identity)
    let authority := UseScope.freshName (reservedAuthority ++ custodySupport store)
    some ⟨⟨{ store.fields with active := .owned authority owner :: store.fields.active },
      ⟨identity, definition.name, authority, representation⟩ :: store.resources⟩, ⟨identity, authority, owner⟩⟩
  else none

/-- Inspection checks nominal identity, per-definition code authority, and the
actual active owning grant. Returning plain data does not manufacture a grant. -/
def inspectOwned [DecidableEq Actor] (definition : Definition Actor) (actor : Actor) (view : View definition.name)
    (store : Store Representation) : Option (Representation definition.name) :=
  if actor ∈ definition.eliminators then
    (lookup view.identity store.resources).bind fun record =>
      if nominal : record.name = definition.name then
        if record.authority = view.authority && (UseScope.takeGrant view.authority view.owner
            (UseScope.activeFields store.fields.active)).isSome then some (nominal ▸ record.representation)
        else none
      else none
  else none

def lend (view : View name) (scope : Id .scope) (forest : Scope.Forest) (store : Store Representation) (loans : Loans) :
    Option (Borrow name × Loans) :=
  if (Scope.path scope forest).isSome then
    (lookup view.identity store.resources).bind fun record =>
      if record.name = name && record.authority = view.authority &&
          (UseScope.takeGrant view.authority view.owner (UseScope.activeFields store.fields.active)).isSome then
        some (⟨view.identity, scope⟩, ⟨view.identity, name, scope⟩ :: loans)
      else none
  else none

def inspectBorrowed [DecidableEq Actor] (definition : Definition Actor) (actor : Actor) (view : Borrow definition.name)
    (forest : Scope.Forest) (store : Store Representation) (loans : Loans) : Option (Representation definition.name) :=
  if actor ∈ definition.eliminators ∧ Loan.mk view.identity definition.name view.scope ∈ loans ∧ (Scope.path view.scope forest).isSome then
    (lookup view.identity store.resources).bind fun record =>
      if nominal : record.name = definition.name then
        if record.authority ∈ UseScope.inventory store.fields then some (nominal ▸ record.representation) else none
      else none
  else none

theorem borrowed_inspection_requires_recorded_live_loan [DecidableEq Actor]
    {definition : Definition Actor} {view : Borrow definition.name} {store : Store Representation}
    {representation : Representation definition.name}
    (accepted : inspectBorrowed definition actor view forest store loans = some representation) :
    actor ∈ definition.eliminators ∧ Loan.mk view.identity definition.name view.scope ∈ loans ∧
      (Scope.path view.scope forest).isSome = true := by
  unfold inspectBorrowed at accepted
  split at accepted
  · assumption
  · contradiction

theorem closed_loan_cannot_expose_representation [DecidableEq Actor]
    (definition : Definition Actor) (actor : Actor) (view : Borrow definition.name)
    (forest : Scope.Forest) (store : Store Representation) (loans : Loans)
    (closed : Scope.path view.scope forest = none) : inspectBorrowed definition actor view forest store loans = none := by
  simp [inspectBorrowed, closed]

theorem borrowed_inspection_requires_live_resource [DecidableEq Actor]
    {definition : Definition Actor} {view : Borrow definition.name} {store : Store Representation}
    {representation : Representation definition.name}
    (accepted : inspectBorrowed definition actor view forest store loans = some representation) :
    ∃ record, lookup view.identity store.resources = some record ∧ record.name = definition.name ∧
      record.authority ∈ UseScope.inventory store.fields := by
  unfold inspectBorrowed at accepted
  split at accepted
  · obtain ⟨record, found, accepted⟩ := Option.bind_eq_some_iff.mp accepted
    split at accepted
    · rename_i nominal
      split at accepted
      · exact ⟨record, found, nominal, by assumption⟩
      · contradiction
    · contradiction
  · contradiction

theorem lending_records_exact_resource_and_scope
    {view : View name} {store : Store Representation}
    (accepted : lend view scope forest store loans = some (borrow, after)) :
    borrow.identity = view.identity ∧ borrow.scope = scope ∧ after = ⟨view.identity, name, scope⟩ :: loans := by
  unfold lend at accepted
  split at accepted
  · obtain ⟨record, _, accepted⟩ := Option.bind_eq_some_iff.mp accepted
    split at accepted
    · cases accepted
      exact ⟨rfl, rfl, rfl⟩
    · contradiction
  · contradiction

theorem lending_requires_active_owner {view : View name} {store : Store Representation}
    (accepted : lend view scope forest store loans = some result) :
    ∃ record, lookup view.identity store.resources = some record ∧ record.name = name ∧ record.authority = view.authority ∧
      (UseScope.takeGrant view.authority view.owner (UseScope.activeFields store.fields.active)).isSome = true := by
  unfold lend at accepted
  split at accepted
  · obtain ⟨record, found, accepted⟩ := Option.bind_eq_some_iff.mp accepted
    split at accepted
    · rename_i permitted
      have both := Bool.and_eq_true_iff.mp permitted
      have identities := Bool.and_eq_true_iff.mp both.1
      exact ⟨record, found, by simpa using identities.1, by simpa using identities.2, both.2⟩
    · contradiction
  · contradiction

theorem lookup_identifies (found : lookup identity records = some record) : record.identity = identity ∧ record ∈ records := by
  induction records with
  | nil => simp [lookup] at found
  | cons first rest induction =>
    simp only [lookup] at found
    split at found
    · rename_i same
      cases found
      exact ⟨same, List.mem_cons_self⟩
    · obtain ⟨same, member⟩ := induction found
      exact ⟨same, List.mem_cons_of_mem _ member⟩

theorem introduction_requires_named_authority [DecidableEq Actor]
    {definition : Definition Actor} {representation : Representation definition.name} {store : Store Representation}
    {result : Introduced Representation definition.name}
    (accepted : introduce definition actor owner representation store reservedResources reservedAuthority = some result) :
    actor ∈ definition.introducers := by
  unfold introduce at accepted
  split at accepted
  · assumption
  · contradiction

theorem inspection_requires_named_authority [DecidableEq Actor]
    {definition : Definition Actor} {view : View definition.name} {store : Store Representation}
    {representation : Representation definition.name}
    (accepted : inspectOwned definition actor view store = some representation) : actor ∈ definition.eliminators := by
  unfold inspectOwned at accepted
  split at accepted
  · assumption
  · contradiction

theorem inspection_binds_nominal_resource [DecidableEq Actor]
    {definition : Definition Actor} {view : View definition.name} {store : Store Representation}
    {representation : Representation definition.name}
    (accepted : inspectOwned definition actor view store = some representation) :
    ∃ record, lookup view.identity store.resources = some record ∧ record.name = definition.name ∧
      record.authority = view.authority ∧
      (UseScope.takeGrant view.authority view.owner (UseScope.activeFields store.fields.active)).isSome = true := by
  unfold inspectOwned at accepted
  split at accepted
  · obtain ⟨record, found, accepted⟩ := Option.bind_eq_some_iff.mp accepted
    split at accepted
    · rename_i nominal
      split at accepted
      · rename_i authority
        have both := Bool.and_eq_true_iff.mp authority
        exact ⟨record, found, nominal, by simpa using both.1, both.2⟩
      · contradiction
    · contradiction
  · contradiction

theorem wrong_nominal_resource_rejects [DecidableEq Actor]
    {definition : Definition Actor} {view : View definition.name} {store : Store Representation}
    (found : lookup view.identity store.resources = some record) (different : record.name ≠ definition.name) :
    inspectOwned definition actor view store = none := by
  simp [inspectOwned, found, different]

theorem introduced_resource_can_be_inspected [DecidableEq Actor] (definition : Definition Actor) (creator reader : Actor) (owner : Owner)
    (representation : Representation definition.name) (store : Store Representation)
    (reservedResources : List (Id .resource)) (reservedAuthority : List (Id .custody))
    (canIntroduce : creator ∈ definition.introducers) (canInspect : reader ∈ definition.eliminators) :
    ∃ introduced, introduce definition creator owner representation store reservedResources reservedAuthority = some introduced ∧
      inspectOwned definition reader introduced.view introduced.store = some representation := by
  simp only [introduce, if_pos canIntroduce]
  refine ⟨_, rfl, ?_⟩
  simp [inspectOwned, canInspect, lookup, UseScope.activeFields, UseScope.exposeField, UseScope.takeGrant]

theorem introduced_identity_and_authority_are_fresh [DecidableEq Actor]
    {definition : Definition Actor} {store : Store Representation} {representation : Representation definition.name}
    {result : Introduced Representation definition.name}
    (accepted : introduce definition actor owner representation store reservedResources reservedAuthority = some result) :
    result.view.identity ∉ reservedResources ++ store.resources.map Record.identity ∧
      result.view.authority ∉ reservedAuthority ++ custodySupport store := by
  unfold introduce at accepted
  split at accepted
  · cases accepted
    exact ⟨UseScope.fresh_name_not_supported _, UseScope.fresh_name_not_supported _⟩
  · contradiction

theorem introduction_preserves_ownership [DecidableEq Actor]
    {definition : Definition Actor} {store : Store Representation} {representation : Representation definition.name}
    {result : Introduced Representation definition.name}
    (valid : Store.Valid store)
    (accepted : introduce definition actor owner representation store reservedResources reservedAuthority = some result) : Store.Valid result.store := by
  unfold introduce at accepted
  split at accepted
  · cases accepted
    have fresh := UseScope.fresh_name_not_supported (reservedAuthority ++ custodySupport store)
    have freshLive : UseScope.freshName (reservedAuthority ++ custodySupport store) ∉ UseScope.inventory store.fields := by
      intro member
      apply fresh
      apply List.mem_append_right
      rcases List.mem_append.mp member with active | retained
      · have supported := UseScope.tokens_are_supported _ _ active
        simp only [custodySupport, List.mem_append]
        exact Or.inl (Or.inl (Or.inl supported))
      · have supported := UseScope.tokens_are_supported _ _ retained
        simp only [custodySupport, List.mem_append]
        exact Or.inl (Or.inl (Or.inr supported))
    have freshSpent : UseScope.freshName (reservedAuthority ++ custodySupport store) ∉ store.fields.spent := by
      intro member
      apply fresh
      apply List.mem_append_right
      simp only [custodySupport, List.mem_append]
      exact Or.inl (Or.inr member)
    refine ⟨?_, ?_, ?_⟩
    · refine ⟨List.nodup_cons.mpr ⟨freshLive, valid.1.1⟩, valid.1.2.1, ?_⟩
      intro token member
      rcases List.mem_cons.mp member with rfl | existing
      · exact freshSpent
      · exact valid.1.2.2 token existing
    · apply List.nodup_cons.mpr
      refine ⟨?_, valid.2.1⟩
      intro member
      exact UseScope.fresh_name_not_supported _ (List.mem_append_right reservedResources member)
    · apply List.nodup_cons.mpr
      refine ⟨?_, valid.2.2⟩
      intro member
      exact fresh (List.mem_append_right _ (List.mem_append_right _ member))
  · contradiction

end BoundaryV2.Generalized.Resources
