import BoundaryV2.GeneralizedSourceFreeze
import BoundaryV2.GeneralizedRegisteredExecution

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}
  [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]

namespace Defunctionalization

/-- Clone evaluates its authored operand, consumes the actual grant, registers
the template, and returns to the related caller in the common runtime. -/
theorem compiled_registered_clone
    (table : Source.Definitions signature algebra program) (use : UseScope.OneShotUse)
    (expression : Source.Expression signature algebra program context (.continuation mode use.type effect input answer))
    (bindings : Source.RuntimeEnvironment signature algebra program context) (view : UseScope.ControlView)
    (store evaluated : Source.Multi.DescribedHeap signature algebra program) (arena : Source.Multi.Arena signature algebra program)
    (partition : Target.Multi.Partition) (regions : List (Id .region))
    (registry registered : Source.Multi.Registry signature algebra program)
    (operands : Source.ExpressionEvaluation bindings
      (arena.cells.reservations.withSupport (Source.Multi.retainedSupport registry arena)).custody store expression
      (.ok (.continuation view.identity (some (view.authority, view.owner)))) evaluated)
    (sourceFrozen : Source.Multi.Frozen signature algebra program ⟨mode, effect, input, answer⟩)
    (accepted : Source.Multi.freezeInto ⟨mode, effect, input, answer⟩ view evaluated arena partition registry = some (sourceFrozen, registered))
    {sourceOutside : Source.Context signature algebra program (.continuation mode .multi effect input answer) result}
    {targetOutside : Target.Stack signature algebra program (.continuation mode .multi effect input answer) result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside) :
    let sourceBefore : Source.Multi.Runtime signature algebra program result :=
      ⟨⟨Source.Multi.sourceHeap store, sourceOutside.plug (.evaluate (.clone expression) bindings)⟩, arena, regions, registry⟩
    let sourceAfter : Source.Multi.Runtime signature algebra program result :=
      ⟨⟨Source.Multi.sourceHeap sourceFrozen.store, sourceOutside.plug (.returned sourceFrozen.value)⟩, sourceFrozen.arena,
        regions.filter (fun region => !partition.regions.contains region), registered⟩
    let targetBefore : Target.Multi.Runtime signature algebra program result :=
      ⟨⟨templateHeap store, .code (computation (.clone expression)) (environment bindings) .nil targetOutside⟩,
        templateArena arena, regions, templateRegistry registry⟩
    let targetAfter : Target.Multi.Runtime signature algebra program result :=
      ⟨⟨(frozen sourceFrozen).store, .returned (frozen sourceFrozen).value targetOutside⟩, (frozen sourceFrozen).arena,
        regions.filter (fun region => !partition.regions.contains region), templateRegistry registered⟩
    Source.Multi.Step table sourceBefore sourceAfter ∧ MultiRuntimeRelated sourceAfter targetAfter ∧
      ∃ count, 0 < count ∧ Target.Multi.Steps (definitions table) targetBefore count targetAfter := by
  dsimp only
  refine ⟨.clone (use := use) rfl rfl operands accepted,
    ⟨⟨template_heap_correspondence sourceFrozen.store, rfl, rfl, rfl⟩, (EntryRelated.returned sourceFrozen.value outside).as_program⟩, ?_⟩
  let convert := UseScope.mapPacked (fun shape => templateFuture (signature := signature) (algebra := algebra) (program := program) (shape := shape))
  obtain ⟨count, targetEvaluated, positive, steps, related⟩ := owned_expression_drains
    (fun first second => convert first = second) bindings
    (arena.cells.reservations.withSupport (Source.Multi.retainedSupport registry arena)).custody expression
    (.continuation view.identity (some (view.authority, view.owner))) operands (.clone (use := use.type) .ret) .nil
    (UseScope.ControlStore.map_related convert store)
  have same := UseScope.ControlStore.related_map_eq convert related
  change templateHeap evaluated = targetEvaluated at same
  subst targetEvaluated
  have reservations : (templateArena arena).cells.reservations = arena.cells.reservations := Cells.reservations_mapBodies _ arena.cells
  rw [← reservations, ← retained_support_corresponds registry arena] at steps
  have targetAccepted : Target.Multi.freezeInto ⟨mode, effect, input, answer⟩ view (templateHeap evaluated)
      (templateArena arena) partition (templateRegistry registry) = some (frozen sourceFrozen, templateRegistry registered) := by
    rw [registered_freeze_corresponds, accepted]
    rfl
  have entered := Target.Multi.Steps.prepend_operands (table := definitions table) (regions := regions)
    (outside := targetOutside) steps (.clone (use := use) rfl targetAccepted)
  refine ⟨count + 2, by omega, ?_⟩
  simpa only [Nat.add_assoc, Nat.zero_add, Nat.reduceAdd, Target.Multi.Runtime.withState,
    convert, templateHeap, computation] using
    entered.trans (Target.Multi.Steps.cons (.core (.cell (.ordinary .returned))) .refl)

/-- The compositional clone case accepts the actual related target heap. Its
other controls may retain administrative frames; only the frozen image is
normalized by the existing clone operation. -/
theorem related_registered_clone_execution
    (table : Source.Definitions signature algebra program) (use : UseScope.OneShotUse)
    (expression : Source.Expression signature algebra program context (.continuation mode use.type effect input answer))
    (bindings : Source.RuntimeEnvironment signature algebra program context) (view : UseScope.ControlView)
    (store evaluated : Source.Multi.DescribedHeap signature algebra program)
    {targetStore : Target.ControlHeap signature algebra program} (stores : DescribedHeapRelated store targetStore)
    (arena : Source.Multi.Arena signature algebra program) (partition : Target.Multi.Partition) (regions : List (Id .region))
    (registry registered : Source.Multi.Registry signature algebra program)
    (operands : Source.ExpressionEvaluation bindings
      (arena.cells.reservations.withSupport (Source.Multi.retainedSupport registry arena)).custody store expression
      (.ok (.continuation view.identity (some (view.authority, view.owner)))) evaluated)
    (sourceFrozen : Source.Multi.Frozen signature algebra program ⟨mode, effect, input, answer⟩)
    (accepted : Source.Multi.freezeInto ⟨mode, effect, input, answer⟩ view evaluated arena partition registry = some (sourceFrozen, registered))
    {sourceOutside : Source.Context signature algebra program (.continuation mode .multi effect input answer) result}
    {targetOutside : Target.Stack signature algebra program (.continuation mode .multi effect input answer) result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside) :
    ∃ targetAfter count, 0 < count ∧
      MultiRuntimeRelated
        ⟨⟨Source.Multi.sourceHeap sourceFrozen.store, sourceOutside.plug (.returned sourceFrozen.value)⟩,
          sourceFrozen.arena, regions.filter (fun region => !partition.regions.contains region), registered⟩ targetAfter ∧
      Target.Multi.Steps (definitions table)
        ⟨⟨targetStore, .code (computation (.clone expression)) (environment bindings) .nil targetOutside⟩,
          templateArena arena, regions, templateRegistry registry⟩ count targetAfter := by
  obtain ⟨count, targetEvaluated, positive, steps, evaluatedRelated⟩ := owned_expression_drains
    (UseScope.PackedControlRelated describedPayloadRelated) bindings
    (arena.cells.reservations.withSupport (Source.Multi.retainedSupport registry arena)).custody expression
    (.continuation view.identity (some (view.authority, view.owner))) operands (.clone (use := use.type) .ret) .nil stores
  obtain ⟨⟨targetFrozen, targetRegistry⟩, targetAccepted, frozenRelated, registryRelated⟩ := corresponding_acceptance
    (registered_freeze_related ⟨mode, effect, input, answer⟩ view evaluatedRelated arena partition registry) accepted
  change FrozenRelated sourceFrozen targetFrozen at frozenRelated
  change targetRegistry = templateRegistry registered at registryRelated
  let targetAfter : Target.Multi.Runtime signature algebra program result :=
    ⟨⟨targetFrozen.store, .returned targetFrozen.value targetOutside⟩, targetFrozen.arena,
      regions.filter (fun region => !partition.regions.contains region), targetRegistry⟩
  have sameValue : targetFrozen.value = value sourceFrozen.value := by
    simp only [Target.Multi.Frozen.value, Source.Multi.Frozen.value, value, Value.map]
    exact congrArg (fun identity => Value.continuation identity none) frozenRelated.identity
  have matching : MultiRuntimeRelated
      (⟨⟨Source.Multi.sourceHeap sourceFrozen.store, sourceOutside.plug (.returned sourceFrozen.value)⟩,
        sourceFrozen.arena, regions.filter (fun region => !partition.regions.contains region), registered⟩ :
        Source.Multi.Runtime signature algebra program result) targetAfter := by
    refine ⟨⟨(described_heap_related_iff _ _).mp frozenRelated.store, frozenRelated.arena, rfl, registryRelated⟩, ?_⟩
    change ProgramRelated (sourceOutside.plug (.returned sourceFrozen.value)) .done (.returned targetFrozen.value targetOutside)
    rw [sameValue]
    exact (EntryRelated.returned sourceFrozen.value outside).as_program
  have reservations : (templateArena arena).cells.reservations = arena.cells.reservations := Cells.reservations_mapBodies _ arena.cells
  rw [← reservations, ← retained_support_corresponds registry arena] at steps
  have entered := Target.Multi.Steps.prepend_operands (table := definitions table) (regions := regions)
    (outside := targetOutside) steps (.clone (use := use) rfl targetAccepted)
  refine ⟨targetAfter, count + 2, by omega, matching, ?_⟩
  simpa only [Nat.add_assoc, Nat.zero_add, Nat.reduceAdd, Target.Multi.Runtime.withState,
    targetAfter, computation] using
    entered.trans (Target.Multi.Steps.cons (.core (.cell (.ordinary .returned))) .refl)

end Defunctionalization
end BoundaryV2.Generalized
