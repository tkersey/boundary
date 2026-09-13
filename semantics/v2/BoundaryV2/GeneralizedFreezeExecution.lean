import BoundaryV2.GeneralizedSourceFreeze
import BoundaryV2.GeneralizedStateExecution

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}
  [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]

namespace Source.Multi

structure CloneResult (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (shape : ControlShape signature) (result : TypeOf signature) where
  frozen : Frozen signature algebra program shape
  program : Program signature algebra program result
  regions : List (Id .region)

def CloneResult.state (result : CloneResult signature algebra program shape answer) : State signature algebra program answer :=
  ⟨⟨sourceHeap result.frozen.store, result.program⟩, result.frozen.arena.cells, result.regions⟩

/-- The operand evaluator is parametric in saved futures. Retaining authored
provenance does not change operand values, physical fields, or the source
program; the resulting ordinary source heap holds the actual callbacks. -/
inductive CloneEntry (table : Definitions signature algebra program) : State signature algebra program result →
    (Sigma fun shape => CloneResult signature algebra program shape result) → Prop where
  | freeze {use : UseScope.OneShotUse}
      {expression : Expression signature algebra program context (.continuation mode use.type effect input answer)}
      {bindings : RuntimeEnvironment signature algebra program context}
      {outside : Context signature algebra program (.continuation mode .multi effect input answer) result}
      {view : UseScope.ControlView} {partition : Target.Multi.Partition}
      {store evaluated : DescribedHeap signature algebra program} {arena : Arena signature algebra program}
      {frozen : Frozen signature algebra program ⟨mode, effect, input, answer⟩} :
      ExpressionEvaluation bindings arena.cells.reservations.custody store expression
        (.ok (.continuation view.identity (some (view.authority, view.owner)))) evaluated →
      freezeOwned ⟨mode, effect, input, answer⟩ view evaluated arena partition = some frozen →
      CloneEntry table ⟨⟨sourceHeap store, outside.plug (.evaluate (.clone expression) bindings)⟩, arena.cells, regions⟩
        ⟨⟨mode, effect, input, answer⟩, ⟨frozen, outside.plug (.returned frozen.value),
          regions.filter (fun region => !partition.regions.contains region)⟩⟩

end Source.Multi

namespace Defunctionalization

/-- An arbitrary successful source clone operand has a finite positive target
drain into the emitted clone instruction, which returns the same template binding. -/
theorem compiled_clone_entry
    (table : Source.Definitions signature algebra program) (use : UseScope.OneShotUse)
    (expression : Source.Expression signature algebra program context (.continuation mode use.type effect input answer))
    (bindings : Source.RuntimeEnvironment signature algebra program context) (view : UseScope.ControlView)
    (store evaluated : Source.Multi.DescribedHeap signature algebra program) (arena : Source.Multi.Arena signature algebra program)
    (partition : Target.Multi.Partition) (regions : List (Id .region))
    (operands : Source.ExpressionEvaluation bindings arena.cells.reservations.custody store expression
      (.ok (.continuation view.identity (some (view.authority, view.owner)))) evaluated)
    (sourceFrozen : Source.Multi.Frozen signature algebra program ⟨mode, effect, input, answer⟩)
    (accepted : Source.Multi.freezeOwned ⟨mode, effect, input, answer⟩ view evaluated arena partition = some sourceFrozen)
    (sourceOutside : Source.Context signature algebra program (.continuation mode .multi effect input answer) result)
    (targetOutside : Target.Stack signature algebra program (.continuation mode .multi effect input answer) result) :
    Source.Multi.CloneEntry table
      ⟨⟨Source.Multi.sourceHeap store, sourceOutside.plug (.evaluate (.clone expression) bindings)⟩, arena.cells, regions⟩
      ⟨⟨mode, effect, input, answer⟩, ⟨sourceFrozen, sourceOutside.plug (.returned sourceFrozen.value),
        regions.filter (fun region => !partition.regions.contains region)⟩⟩ ∧
    ∃ count, 0 < count ∧
      Target.ExecutionSteps (definitions table)
        ⟨⟨templateHeap store, .code (computation (.clone expression)) (environment bindings) .nil targetOutside⟩,
          cells arena.cells, regions⟩ count
        ⟨⟨templateHeap evaluated, .code (.clone (use := use.type) .ret) (environment bindings)
          (.cons (.continuation view.identity (some (view.authority, view.owner))) .nil) targetOutside⟩, cells arena.cells, regions⟩ ∧
      Target.Multi.CloneEntry (definitions table)
        ⟨⟨templateHeap evaluated, .code (.clone (use := use.type) .ret) (environment bindings)
          (.cons (.continuation view.identity (some (view.authority, view.owner))) .nil) targetOutside⟩, cells arena.cells, regions⟩
        ⟨⟨mode, effect, input, answer⟩, ⟨frozen sourceFrozen,
          .code .ret (environment bindings) (.cons (frozen sourceFrozen).value .nil) targetOutside,
          regions.filter (fun region => !partition.regions.contains region)⟩⟩ := by
  let convert := UseScope.mapPacked (fun shape => templateFuture (signature := signature) (algebra := algebra) (program := program) (shape := shape))
  obtain ⟨count, targetEvaluated, positive, steps, related⟩ := owned_expression_drains
    (fun first second => convert first = second) bindings arena.cells.reservations.custody expression
    (.continuation view.identity (some (view.authority, view.owner))) operands (.clone (use := use.type) .ret) .nil
    (UseScope.ControlStore.map_related convert store)
  have same := UseScope.ControlStore.related_map_eq convert related
  change templateHeap evaluated = targetEvaluated at same
  subst targetEvaluated
  have reservations : (cells arena.cells).reservations = arena.cells.reservations := Cells.reservations_mapBodies _ arena.cells
  rw [← reservations] at steps
  refine ⟨.freeze operands accepted, count, positive, steps.in_execution (definitions table) targetOutside (cells arena.cells) regions, ?_⟩
  apply Target.Multi.CloneEntry.freeze (use := use) (arena := templateArena arena)
  rw [freeze_owned_corresponds, accepted]
  rfl

theorem frozen_reference_returns_to_the_related_caller
    (table : Target.Definitions signature algebra program)
    (source : Source.Multi.Frozen signature algebra program shape)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    {sourceOutside : Source.Context signature algebra program
      (.continuation shape.mode .multi shape.effect shape.input shape.answer) result}
    {targetOutside : Target.Stack signature algebra program
      (.continuation shape.mode .multi shape.effect shape.input shape.answer) result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside) (regions : List (Id .region)) :
    Target.ExecutionSteps table
      ⟨⟨(frozen source).store, .code .ret (environment bindings) (.cons (frozen source).value .nil) targetOutside⟩,
        (frozen source).arena.cells, regions⟩ 1
      ⟨⟨(frozen source).store, .returned (frozen source).value targetOutside⟩, (frozen source).arena.cells, regions⟩ ∧
    ProgramRelated (sourceOutside.plug (.returned source.value)) .done
      (.returned (frozen source).value targetOutside) :=
  ⟨.single (.cell (.ordinary .returned)), outside.close_program (.returned source.value targetOutside)⟩

end Defunctionalization
end BoundaryV2.Generalized
