import BoundaryV2.GeneralizedStateExecution
import BoundaryV2.GeneralizedHandlerEntry

namespace BoundaryV2.Generalized.Defunctionalization

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}
  [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]

variable {retained : List Reference}

/-- Fresh installation binds the new capability only in the body. Both sides
use their own support collectors, with source support witnesses for callbacks. -/
theorem compiled_fresh_handler
    (table : Source.Definitions signature algebra program) (effect : signature.Effect) (mode : Mode)
    (returned : Source.Computation signature algebra program (bodyType :: context) answer)
    (handlers : Source.Clauses signature algebra program effect mode context bodyType answer)
    (body : Source.Computation signature algebra program (.capability effect :: context) bodyType)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    {sourceOutside : Source.Context signature algebra program answer result}
    {targetOutside : Target.Stack signature algebra program answer result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    {sourceStore : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (stores : ControlHeapRelated sourceStore targetStore)
    (sourceCells : Cells signature algebra (Source.Computation signature algebra program))
    (regions : List (Id .region)) (extra : List Reference) :
    let attachment := Target.freshAttachment (definitions table) (computation (.handle effect mode returned handlers body))
      (environment bindings) .nil targetOutside targetStore (cells sourceCells) (retained ++ extra)
    Source.ExecutionStep (retained := retained) table
      ⟨⟨sourceStore, sourceOutside.plug (.evaluate (.handle effect mode returned handlers body) bindings)⟩, sourceCells, regions⟩
      ⟨⟨sourceStore, sourceOutside.plug (.handler effect mode attachment returned handlers bindings
        (.evaluate body (.cons (.datum (.capability attachment)) bindings)))⟩, sourceCells, regions⟩ ∧
    Target.ExecutionSteps (retained := retained) (definitions table)
      ⟨⟨targetStore, .code (computation (.handle effect mode returned handlers body)) (environment bindings) .nil targetOutside⟩,
        cells sourceCells, regions⟩ 1
      ⟨⟨targetStore, .code (computation body) (.cons (.datum (.capability attachment)) (environment bindings)) .nil
        (.push (.handler effect mode attachment (computation returned) (clauses handlers) (environment bindings))
          (.push (.returnTo .ret (environment bindings) .nil) targetOutside))⟩, cells sourceCells, regions⟩ ∧
    CellStateRelated
      ⟨⟨sourceStore, sourceOutside.plug (.handler effect mode attachment returned handlers bindings
        (.evaluate body (.cons (.datum (.capability attachment)) bindings)))⟩, sourceCells, regions⟩
      ⟨⟨targetStore, .code (computation body) (.cons (.datum (.capability attachment)) (environment bindings)) .nil
        (.push (.handler effect mode attachment (computation returned) (clauses handlers) (environment bindings))
          (.push (.returnTo .ret (environment bindings) .nil) targetOutside))⟩, cells sourceCells, regions⟩ := by
  dsimp only
  have same := fresh_attachment_corresponds table (.handle effect mode returned handlers body) bindings targetOutside targetStore sourceCells (retained ++ extra)
  refine ⟨.installHandler extra (context_installation_support outside) (store_installation_support stores) same.symm,
    .single (.installHandler extra rfl), ?_⟩
  let attachment := Target.freshAttachment (definitions table) (computation (.handle effect mode returned handlers body))
    (environment bindings) .nil targetOutside targetStore (cells sourceCells) (retained ++ extra)
  refine ⟨⟨stores, ?_⟩, rfl, rfl⟩
  simpa only [attachment, Source.Context.plug, Source.Frame.plug, environment, Environment.map, Value.map] using
    EntryRelated.evaluate body (.cons (.datum (.capability attachment)) bindings)
      (.push (.handler effect mode attachment returned handlers bindings) (.passthrough bindings outside))

end BoundaryV2.Generalized.Defunctionalization
