import BoundaryV2.GeneralizedOperandLowering
import BoundaryV2.GeneralizedReification

namespace BoundaryV2.Generalized

theorem Variable.lookup_tuple_map {Index : Type} {context : List Index} {index : Index} {First Second : Index → Type}
    (transform : ∀ index, First index → Second index) (reference : Variable context index)
    (values : Tuple First context) :
    Variable.lookup (Value := Second) reference (Tuple.map transform values) = transform index (Variable.lookup reference values) := by
  induction reference with
  | here => cases values; rfl
  | there reference induction => cases values; exact induction _

namespace Source

/-- The source enters authored lexical code. Permission acquisition is a
separate local operation; this entry keeps the code, argument, and capture
positions that the control interpretation must preserve. -/
def enterClosure (body : Computation signature algebra definitions (parameters ++ captured) result)
    (arguments : RuntimeEnvironment signature algebra definitions parameters)
    (saved : RuntimeEnvironment signature algebra definitions captured) : Program signature algebra definitions result :=
  .evaluate body (arguments.append saved)

def unfoldCall (table : Definitions signature algebra definitions) (reference : Variable definitions body)
    (arguments : RuntimeEnvironment signature algebra definitions body.parameters) :
    Program signature algebra definitions body.result := .evaluate (reference.lookup table) arguments

end Source

namespace Target

/-- Every executable field is target code, a value, or a frame. The return stack
is retained on requests, faults, and yields for the control/exit interpretation. -/
inductive Configuration (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (definitions : List (BodyType signature.Data signature.Effect)) (result : TypeOf signature) where
  | code : Code signature algebra definitions context operands answer →
    RuntimeEnvironment signature algebra definitions context → RuntimeEnvironment signature algebra definitions operands →
    Stack signature algebra definitions answer result → Configuration signature algebra definitions result
  | returned : RuntimeValue signature algebra definitions answer → Stack signature algebra definitions answer result →
    Configuration signature algebra definitions result
  | requested : (operation : signature.operation effect) → Id .attachment →
    RuntimeValue signature algebra definitions (signature.payload operation) →
    RuntimeEnvironment signature algebra definitions ((signature.bodies operation).map BodyType.type) →
    Stack signature algebra definitions (signature.result operation) result → Configuration signature algebra definitions result
  | failed : algebra.Fault → Stack signature algebra definitions answer result → Configuration signature algebra definitions result
  | yielded : Configuration signature algebra definitions result → Configuration signature algebra definitions result

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {definitions : List (BodyType signature.Data signature.Effect)}

/-- These are code and ordinary return transitions. Resumption permission,
handler selection, and exit transitions extend this same configuration; they
are not smuggled into an opaque primitive or a source-evaluator instruction. -/
inductive CallStep (table : Definitions signature algebra definitions) :
    Configuration signature algebra definitions result → Configuration signature algebra definitions result → Prop where
  | operand : OperandStep environment before after →
      CallStep table (.code before.code environment before.values future) (.code after.code environment after.values future)
  | returned : CallStep table (.code .ret environment (.cons value operands) future) (.returned value future)
  | enter : CallStep table (.code (.enter body) environment (.cons value operands) future)
      (.code body (.cons value environment) operands future)
  | block : CallStep table (.code (.callBlock body next) environment operands future)
      (.code body environment .nil (.push (.returnTo next environment operands) future))
  | named : CallStep table (.code (.callNamed reference next) environment (arguments.pushReverse operands) future)
      (.code (reference.lookup table) arguments .nil (.push (.returnTo next environment operands) future))
  | closure {parameters capturedTypes : List (TypeOf signature)} {answer : TypeOf signature} {use : Use}
      {body : Code signature algebra definitions (parameters ++ capturedTypes) [] answer}
      {arguments : RuntimeEnvironment signature algebra definitions parameters}
      {captured : RuntimeEnvironment signature algebra definitions capturedTypes}
      {context stack : List (TypeOf signature)} {middle : TypeOf signature}
      {next : Code signature algebra definitions context (answer :: stack) middle}
      {environment : RuntimeEnvironment signature algebra definitions context}
      {operands : RuntimeEnvironment signature algebra definitions stack}
      {future : Stack signature algebra definitions middle result}
      {authority : Option (Id .custody × Owner)} : CallStep table
      (.code (.callClosure (use := use) next) environment (arguments.pushReverse (.cons (.closure body captured authority) operands)) future)
      (.code body (arguments.append captured) .nil (.push (.returnTo next environment operands) future))
  | dispatch {effect : signature.Effect} {operation : signature.operation effect}
      {context stack : List (TypeOf signature)} {answer : TypeOf signature}
      {next : Code signature algebra definitions context (signature.result operation :: stack) answer}
      {environment : RuntimeEnvironment signature algebra definitions context}
      {operands : RuntimeEnvironment signature algebra definitions stack}
      {payload : RuntimeValue signature algebra definitions (signature.payload operation)}
      {bodies : RuntimeEnvironment signature algebra definitions ((signature.bodies operation).map BodyType.type)}
      {future : Stack signature algebra definitions answer result} : CallStep table
      (.code (.dispatch operation next) environment
        (bodies.pushReverse (.cons payload (.cons (.datum (.capability attachment)) operands))) future)
      (.requested operation attachment payload bodies (.push (.returnTo next environment operands) future))
  | attach : CallStep table (.code (.attach effect mode returned clauses body next) environment operands future)
      (.code body (.cons (.datum (.capability attachment)) environment) .nil
        (.push (.handler effect mode attachment returned clauses environment) (.push (.returnTo next environment operands) future)))
  | handlerReturned : CallStep table
      (.returned value (.push (.handler effect mode attachment returned clauses environment) future))
      (.code returned (.cons value environment) .nil future)
  | caller : CallStep table (.returned value (.push (.returnTo next environment operands) future))
      (.code next environment (.cons value operands) future)
  | fault : CallStep table (.code (.fault fault) environment operands future) (.failed fault future)
  | yield : CallStep table (.code (.yieldThen next) environment operands future)
      (.yielded (.code next environment operands future))

inductive CallSteps (table : Definitions signature algebra definitions) :
    Configuration signature algebra definitions result → Nat → Configuration signature algebra definitions result → Prop where
  | refl : CallSteps table state 0 state
  | cons : CallStep table first middle → CallSteps table middle count last → CallSteps table first (count + 1) last

theorem CallSteps.single (step : CallStep table before after) : CallSteps table before 1 after := .cons step .refl

theorem CallSteps.trans (first : CallSteps table before count middle) (second : CallSteps table middle rest after) :
    CallSteps table before (count + rest) after := by
  induction first with
  | refl => simpa using second
  | cons step tail induction => simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using CallSteps.cons step (induction second)

theorem OperandSteps.in_context {context : List (TypeOf signature)} {answer result : TypeOf signature}
    {before after : Operands signature algebra definitions context answer}
    {environment : RuntimeEnvironment signature algebra definitions context}
    (steps : OperandSteps environment before count after)
    (table : Definitions signature algebra definitions) (future : Stack signature algebra definitions answer result) :
    CallSteps table (.code before.code environment before.values future) count (.code after.code environment after.values future) := by
  induction steps with
  | refl => exact .refl
  | cons step tail induction => exact .cons (.operand step) induction

end Target

namespace Defunctionalization

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

/-- The finite table remains finite. Recursion is a typed table reference; one
call unfolds exactly one body on each side and adds the ordinary caller frame. -/
theorem recursive_table_lookup (table : Source.Definitions signature algebra program) (reference : Variable program body) :
    reference.lookup (definitions table) = computation (reference.lookup table) :=
  Variable.lookup_tuple_map _ _ _

theorem named_call_enters_corresponding_body (table : Source.Definitions signature algebra program)
    (reference : Variable program body) (arguments : Source.RuntimeEnvironment signature algebra program body.parameters)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (next : Target.Code signature algebra program context (body.result :: stack) answer)
    (operands : Target.RuntimeEnvironment signature algebra program stack)
    (future : Target.Stack signature algebra program answer result) :
    Target.CallStep (definitions table)
      (.code (.callNamed reference next) (environment bindings) ((environment arguments).pushReverse operands) future)
      (.code (computation (reference.lookup table)) (environment arguments) .nil
        (.push (.returnTo next (environment bindings) operands) future)) := by
  simpa only [recursive_table_lookup] using Target.CallStep.named
    (table := definitions table) (reference := reference) (next := next)
    (environment := environment bindings) (arguments := environment arguments) (operands := operands) (future := future)

theorem closure_call_enters_corresponding_body (table : Source.Definitions signature algebra program)
    (body : Source.Computation signature algebra program (parameters ++ captured) answer)
    (arguments : Source.RuntimeEnvironment signature algebra program parameters)
    (saved : Source.RuntimeEnvironment signature algebra program captured)
    (authority : Option (Id .custody × Owner))
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (next : Target.Code signature algebra program context (answer :: stack) middle)
    (operands : Target.RuntimeEnvironment signature algebra program stack)
    (future : Target.Stack signature algebra program middle result) :
    Target.CallStep (definitions table)
      (.code (.callClosure (use := use) next) (environment bindings)
        ((environment arguments).pushReverse (.cons (value (.closure body saved authority)) operands)) future)
      (.code (computation body) (environment (arguments.append saved)) .nil
        (.push (.returnTo next (environment bindings) operands) future)) := by
  simpa only [value, Value.map, environment, Environment.map_append] using Target.CallStep.closure
    (table := definitions table) (body := computation body) (captured := environment saved)
    (arguments := environment arguments) (authority := authority) (use := use) (parameters := parameters) (answer := answer) (next := next)
    (environment := environment bindings) (operands := operands) (future := future)

theorem compiled_recursive_call (table : Source.Definitions signature algebra program) (reference : Variable program body)
    (arguments : Source.Arguments signature algebra program context body.parameters)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (actual : Source.RuntimeEnvironment signature algebra program body.parameters)
    (evaluated : arguments.evaluate bindings = .ok actual)
    (future : Target.Stack signature algebra program body.result result) :
    ∃ count, 0 < count ∧ Target.CallSteps (definitions table)
      (.code (computation (.call reference arguments)) (environment bindings) .nil future) count
      (.code (computation (reference.lookup table)) (environment actual) .nil
        (.push (.returnTo .ret (environment bindings) .nil) future)) := by
  obtain ⟨count, steps⟩ := arguments_drains arguments bindings (.callNamed reference .ret) .nil actual evaluated
  refine ⟨count + 1, by omega, ?_⟩
  exact (steps.in_context (definitions table) future).trans (.single (named_call_enters_corresponding_body table reference actual bindings .ret .nil future))

theorem compiled_closure_call (table : Source.Definitions signature algebra program)
    (function : Source.Expression signature algebra program context (.computation use parameters answer))
    (arguments : Source.Arguments signature algebra program context parameters)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (body : Source.Computation signature algebra program (parameters ++ captured) answer)
    (saved : Source.RuntimeEnvironment signature algebra program captured) (authority : Option (Id .custody × Owner))
    (actual : Source.RuntimeEnvironment signature algebra program parameters)
    (functionValue : function.evaluate bindings = .ok (.closure body saved authority))
    (argumentValues : arguments.evaluate bindings = .ok actual)
    (future : Target.Stack signature algebra program answer result) :
    ∃ count, 0 < count ∧ Target.CallSteps (definitions table)
      (.code (computation (.apply function arguments)) (environment bindings) .nil future) count
      (.code (computation body) (environment (actual.append saved)) .nil
        (.push (.returnTo .ret (environment bindings) .nil) future)) := by
  obtain ⟨functionCount, functionSteps⟩ := expression_drains function bindings
    (Defunctionalization.arguments arguments (.callClosure .ret)) .nil _ functionValue
  obtain ⟨argumentCount, argumentSteps⟩ := arguments_drains arguments bindings (.callClosure .ret)
    (.cons (value (.closure body saved authority)) .nil) actual argumentValues
  refine ⟨functionCount + argumentCount + 1, by omega, ?_⟩
  exact ((functionSteps.trans argumentSteps).in_context (definitions table) future).trans
    (.single (closure_call_enters_corresponding_body table body actual saved authority bindings .ret .nil future))

/-- On ordinary return, the callee's result is put above the caller's saved
operand tail. Entering a lexical bind extends the caller environment once. -/
theorem ordinary_return_preserves_caller (table : Target.Definitions signature algebra program)
    (returned : Target.RuntimeValue signature algebra program input)
    (body : Target.Code signature algebra program (input :: context) stack answer)
    (bindings : Target.RuntimeEnvironment signature algebra program context)
    (operands : Target.RuntimeEnvironment signature algebra program stack)
    (future : Target.Stack signature algebra program answer result) :
    Target.CallSteps table (.returned returned (.push (.returnTo (.enter body) bindings operands) future)) 2
      (.code body (.cons returned bindings) operands future) :=
  .cons .caller (.cons .enter .refl)

theorem return_passthrough_takes_two_steps (table : Target.Definitions signature algebra program)
    (returned : Target.RuntimeValue signature algebra program input)
    (bindings : Target.RuntimeEnvironment signature algebra program context)
    (operands : Target.RuntimeEnvironment signature algebra program stack)
    (future : Target.Stack signature algebra program input result) :
    Target.CallSteps table (.returned returned (.push (.returnTo .ret bindings operands) future)) 2
      (.returned returned future) := .cons .caller (.cons .returned .refl)

end Defunctionalization
end BoundaryV2.Generalized
