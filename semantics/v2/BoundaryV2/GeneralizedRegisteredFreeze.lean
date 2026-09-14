import BoundaryV2.GeneralizedTemplateRegistry

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}
  [DecidableEq (ControlShape signature)]

/-- The consumed successor and returned reference become available together
with their immutable binding. Failed registration exposes neither successor. -/
def Source.Multi.freezeInto (shape : ControlShape signature) (view : UseScope.ControlView)
    (store : DescribedHeap signature algebra program) (arena : Arena signature algebra program)
    (partition : Target.Multi.Partition) (registry : Registry signature algebra program) :
    Option (Frozen signature algebra program shape × Registry signature algebra program) :=
  (freezeOwned shape view store arena partition).bind fun frozen =>
    (TemplateRegistry.insert frozen.identity frozen.template registry).map fun registered => (frozen, registered)

def Target.Multi.freezeInto (shape : ControlShape signature) (view : UseScope.ControlView)
    (store : ControlHeap signature algebra program) (arena : Arena signature algebra program)
    (partition : Partition) (registry : Registry signature algebra program) :
    Option (Frozen signature algebra program shape × Registry signature algebra program) :=
  (freezeOwned shape view store arena partition).bind fun frozen =>
    (TemplateRegistry.insert frozen.identity frozen.template registry).map fun registered => (frozen, registered)

theorem Source.Multi.freeze_into_retains_the_actual_binding
    {store : DescribedHeap signature algebra program} {arena : Arena signature algebra program}
    {registry registered : Registry signature algebra program} {frozen : Frozen signature algebra program shape}
    (accepted : freezeInto shape view store arena partition registry = some (frozen, registered)) :
    freezeOwned shape view store arena partition = some frozen ∧
      TemplateRegistry.lookup shape frozen.identity registered = some frozen.template := by
  obtain ⟨created, accepted, inserted⟩ := Option.bind_eq_some_iff.mp accepted
  obtain ⟨after, inserted, result⟩ := Option.map_eq_some_iff.mp inserted
  cases result
  exact ⟨accepted, TemplateRegistry.lookup_after_insert inserted⟩

theorem Target.Multi.freeze_into_retains_the_actual_binding
    {store : ControlHeap signature algebra program} {arena : Arena signature algebra program}
    {registry registered : Registry signature algebra program} {frozen : Frozen signature algebra program shape}
    (accepted : freezeInto shape view store arena partition registry = some (frozen, registered)) :
    freezeOwned shape view store arena partition = some frozen ∧
      TemplateRegistry.lookup shape frozen.identity registered = some frozen.template := by
  obtain ⟨created, accepted, inserted⟩ := Option.bind_eq_some_iff.mp accepted
  obtain ⟨after, inserted, result⟩ := Option.map_eq_some_iff.mp inserted
  cases result
  exact ⟨accepted, TemplateRegistry.lookup_after_insert inserted⟩

theorem Defunctionalization.registered_freeze_corresponds (shape : ControlShape signature) (view : UseScope.ControlView)
    (store : Source.Multi.DescribedHeap signature algebra program) (arena : Source.Multi.Arena signature algebra program)
    (partition : Target.Multi.Partition) (registry : Source.Multi.Registry signature algebra program) :
    Target.Multi.freezeInto shape view (templateHeap store) (templateArena arena) partition (templateRegistry registry) =
      (Source.Multi.freezeInto shape view store arena partition registry).map
        (fun (created, registered) => (frozen created, templateRegistry registered)) := by
  unfold Target.Multi.freezeInto Source.Multi.freezeInto
  rw [freeze_owned_corresponds]
  cases Source.Multi.freezeOwned shape view store arena partition with
  | none => rfl
  | some created =>
    simp only [Option.map_some, Option.bind_some]
    change (TemplateRegistry.insert created.identity (template created.template)
      (TemplateRegistry.map (fun _ => template) registry)).map _ = _
    rw [TemplateRegistry.insert_map]
    cases TemplateRegistry.insert created.identity created.template registry <;> rfl

theorem Defunctionalization.registered_freeze_related (shape : ControlShape signature) (view : UseScope.ControlView)
    {source : Source.Multi.DescribedHeap signature algebra program} {target : Target.ControlHeap signature algebra program}
    (stores : DescribedHeapRelated source target) (arena : Source.Multi.Arena signature algebra program)
    (partition : Target.Multi.Partition) (registry : Source.Multi.Registry signature algebra program) :
    Option.Rel (fun first second => FrozenRelated first.1 second.1 ∧ second.2 = templateRegistry first.2)
      (Source.Multi.freezeInto shape view source arena partition registry)
      (Target.Multi.freezeInto shape view target (templateArena arena) partition (templateRegistry registry)) := by
  have matched := freeze_owned_related shape view stores arena partition
  unfold Source.Multi.freezeInto Target.Multi.freezeInto
  generalize sourceAt : Source.Multi.freezeOwned shape view source arena partition = sourceFrozen at matched ⊢
  generalize targetAt : Target.Multi.freezeOwned shape view target (templateArena arena) partition = targetFrozen at matched ⊢
  cases matched with
  | none => exact .none
  | @some sourceFrozen targetFrozen matching =>
    simp only [Option.bind_some, matching.identity, matching.template, templateRegistry, TemplateRegistry.insert_map]
    cases TemplateRegistry.insert sourceFrozen.identity sourceFrozen.template registry with
    | none => exact .none
    | some registered => exact .some ⟨matching, rfl⟩

end BoundaryV2.Generalized
