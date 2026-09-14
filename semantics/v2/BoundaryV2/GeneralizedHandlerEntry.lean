import BoundaryV2.GeneralizedCalls

namespace BoundaryV2.Generalized.Defunctionalization

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

/-- Dispatch preserves each typed payload and scoped computation argument. The
outside continuation is an ordinary return frame, separate from those bodies. -/
theorem compiled_operation_opens_typed_future (table : Source.Definitions signature algebra program)
    (operation : signature.operation effect)
    (capability : Source.Expression signature algebra program context (.capability effect))
    (payload : Source.Expression signature algebra program context (signature.payload operation))
    (bodies : Source.Arguments signature algebra program context ((signature.bodies operation).map BodyType.type))
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (attachment : Id .attachment)
    (payloadValue : Source.RuntimeValue signature algebra program (signature.payload operation))
    (bodyValues : Source.RuntimeEnvironment signature algebra program ((signature.bodies operation).map BodyType.type))
    (capabilityEvaluated : capability.evaluate bindings = .ok (.datum (.capability attachment)))
    (payloadEvaluated : payload.evaluate bindings = .ok payloadValue)
    (bodiesEvaluated : bodies.evaluate bindings = .ok bodyValues)
    (future : Target.Stack signature algebra program (signature.result operation) result) :
    ∃ count, 0 < count ∧ Target.CallSteps (definitions table)
      (.code (computation (.perform operation capability payload bodies)) (environment bindings) .nil future) count
      (.requested operation attachment (value payloadValue) (environment bodyValues)
        (.push (.returnTo .ret (environment bindings) .nil) future)) := by
  obtain ⟨capabilityCount, capabilitySteps⟩ := expression_drains capability bindings
    (expression payload (arguments bodies (.dispatch operation .ret))) .nil _ capabilityEvaluated
  obtain ⟨payloadCount, payloadSteps⟩ := expression_drains payload bindings
    (arguments bodies (.dispatch operation .ret)) (.cons (.datum (.capability attachment)) .nil) _ payloadEvaluated
  obtain ⟨bodyCount, bodySteps⟩ := arguments_drains bodies bindings (.dispatch operation .ret)
    (.cons (value payloadValue) (.cons (.datum (.capability attachment)) .nil)) _ bodiesEvaluated
  refine ⟨capabilityCount + payloadCount + bodyCount + 1, by omega, ?_⟩
  exact (((capabilitySteps.trans payloadSteps).trans bodySteps).in_context (definitions table) future).trans
    (.single .dispatch)

/-- The supplied attachment is passed into the body, while the handler's
lexical environment remains outside that new binding. Return and operation
clauses are compiled as arbitrary computations with their answer type intact. -/
theorem compiled_handler_installs_typed_delimiter (table : Source.Definitions signature algebra program)
    (effect : signature.Effect) (mode : Mode) (attachment : Id .attachment)
    (returned : Source.Computation signature algebra program (bodyType :: context) answer)
    (handlers : Source.Clauses signature algebra program effect mode context bodyType answer)
    (body : Source.Computation signature algebra program (.capability effect :: context) bodyType)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (future : Target.Stack signature algebra program answer result) :
    Target.CallStep (definitions table)
      (.code (computation (.handle effect mode returned handlers body)) (environment bindings) .nil future)
      (.code (computation body) (.cons (.datum (.capability attachment)) (environment bindings)) .nil
        (.push (.handler effect mode attachment (computation returned) (clauses handlers) (environment bindings))
          (.push (.returnTo .ret (environment bindings) .nil) future))) := .attach

/-- The delimiter is removed before the effectful normal-return clause begins;
this transition does not rewrap the clause in that delimiter. Both body-result
and answer types remain independently typed. -/
theorem handler_return_enters_clause_outside_delimiter (table : Source.Definitions signature algebra program)
    (effect : signature.Effect) (mode : Mode) (attachment : Id .attachment)
    (returned : Source.Computation signature algebra program (bodyType :: context) answer)
    (handlers : Source.Clauses signature algebra program effect mode context bodyType answer)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (bodyValue : Source.RuntimeValue signature algebra program bodyType)
    (outside : Target.Stack signature algebra program answer result) :
    Target.CallStep (definitions table)
      (.returned (value bodyValue) (.push (.handler effect mode attachment (computation returned) (clauses handlers) (environment bindings)) outside))
      (.code (computation returned) (environment (.cons bodyValue bindings)) .nil outside) :=
  .handlerReturned

/-- Reinstalling a delimiter of a different nominal identity does not capture
an ambient operation. This is the local freshness obligation of installation. -/
theorem fresh_handler_forwards_ambient (requested fresh : Id .attachment) (different : requested ≠ fresh)
    (effect : signature.Effect) (mode : Mode)
    (returned : Target.Code signature algebra program (bodyType :: context) [] answer)
    (handlers : Target.Clauses signature algebra program effect mode context bodyType answer)
    (bindings : Target.RuntimeEnvironment signature algebra program context)
    (outside : Target.Stack signature algebra program answer result) :
    Target.select requested (.push (.handler effect mode fresh returned handlers bindings) outside) =
      (Target.select requested outside).map (fun selected =>
        { selected with inside := .push (.handler effect mode fresh returned handlers bindings) selected.inside }) := by
  simp only [Target.select, if_neg different]
  rfl

end BoundaryV2.Generalized.Defunctionalization
