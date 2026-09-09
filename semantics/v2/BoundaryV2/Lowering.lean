import Std

namespace BoundaryV2.Core

/-- The total, pure fragment used inside the control model. Numbers are
mathematical naturals; fixed-width arithmetic and authored faults are separate
executable conformance obligations. -/
inductive Ty where
  | unit | boolean | number | product (left right : Ty)
  deriving DecidableEq, Repr

inductive Value : Ty → Type where
  | unit : Value .unit
  | boolean : Bool → Value .boolean
  | number : Nat → Value .number
  | pair : Value a → Value b → Value (.product a b)

inductive Values : List Ty → Type where
  | nil : Values []
  | cons : Value t → Values ts → Values (t :: ts)

inductive Variable : List Ty → Ty → Type where
  | here : Variable (t :: ts) t
  | there : Variable ts t → Variable (u :: ts) t

def Variable.lookup : Variable ctx t → Values ctx → Value t
  | .here, .cons value _ => value
  | .there reference, .cons _ rest => reference.lookup rest

/-- Lexically scoped source: bind extends the variable environment. -/
inductive Expr : List Ty → Ty → Type where
  | literal : Value t → Expr ctx t
  | ref : Variable ctx t → Expr ctx t
  | add : Expr ctx .number → Expr ctx .number → Expr ctx .number
  | equal : Expr ctx .number → Expr ctx .number → Expr ctx .boolean
  | pair : Expr ctx a → Expr ctx b → Expr ctx (.product a b)
  | first : Expr ctx (.product a b) → Expr ctx a
  | second : Expr ctx (.product a b) → Expr ctx b
  | bind : Expr ctx a → Expr (a :: ctx) b → Expr ctx b

def Expr.eval : Expr ctx t → Values ctx → Value t
  | .literal item, _ => item
  | .ref reference, env => reference.lookup env
  | .add left right, env =>
    match left.eval env, right.eval env with
    | .number a, .number b => .number (a + b)
  | .equal left right, env =>
    match left.eval env, right.eval env with
    | .number a, .number b => .boolean (a == b)
  | .pair left right, env => .pair (left.eval env) (right.eval env)
  | .first expression, env => match expression.eval env with | .pair left _ => left
  | .second expression, env => match expression.eval env with | .pair _ right => right
  | .bind value body, env => body.eval (.cons (value.eval env) env)

/-- First-order instruction data. The four indices describe the environment and
operand stack before/after the instruction, rather than a native closure. -/
inductive Instruction : List Ty → List Ty → List Ty → List Ty → Type where
  | push : Value t → Instruction ctx ctx stack (t :: stack)
  | load : Variable ctx t → Instruction ctx ctx stack (t :: stack)
  | add : Instruction ctx ctx (.number :: .number :: stack) (.number :: stack)
  | equal : Instruction ctx ctx (.number :: .number :: stack) (.boolean :: stack)
  | pair : Instruction ctx ctx (b :: a :: stack) (.product a b :: stack)
  | first : Instruction ctx ctx (.product a b :: stack) (a :: stack)
  | second : Instruction ctx ctx (.product a b :: stack) (b :: stack)
  | enter : Instruction ctx (t :: ctx) (t :: stack) stack
  | leave : Instruction (t :: ctx) ctx stack stack

def Instruction.run : Instruction ctx ctx' stack stack' →
    Values ctx → Values stack → Values ctx' × Values stack'
  | .push value, env, stack => (env, .cons value stack)
  | .load reference, env, stack => (env, .cons (reference.lookup env) stack)
  | .add, env, .cons (.number b) (.cons (.number a) stack) =>
    (env, .cons (.number (a + b)) stack)
  | .equal, env, .cons (.number b) (.cons (.number a) stack) =>
    (env, .cons (.boolean (a == b)) stack)
  | .pair, env, .cons b (.cons a stack) => (env, .cons (.pair a b) stack)
  | .first, env, .cons (.pair a _) stack => (env, .cons a stack)
  | .second, env, .cons (.pair _ b) stack => (env, .cons b stack)
  | .enter, env, .cons value stack => (.cons value env, stack)
  | .leave, .cons _ env, stack => (env, stack)

inductive Code : List Ty → List Ty → List Ty → List Ty → Type where
  | done : Code ctx ctx stack stack
  | next : Instruction ctx mid stack temp → Code mid out temp result →
    Code ctx out stack result

def Code.append : Code ctx mid stack temp → Code mid out temp result →
    Code ctx out stack result
  | .done, after => after
  | .next instruction rest, after => .next instruction (rest.append after)

def Code.run : Code ctx out stack result → Values ctx → Values stack →
    Values out × Values result
  | .done, env, stack => (env, stack)
  | .next instruction rest, env, stack =>
    let next := instruction.run env stack
    rest.run next.1 next.2

theorem code_append_runs_in_order (before : Code ctx mid stack temp)
    (after : Code mid out temp result) (env : Values ctx) (values : Values stack) :
    (before.append after).run env values =
      let next := before.run env values
      after.run next.1 next.2 := by
  induction before with
  | done => rfl
  | next instruction rest ih => exact ih after _ _

/-- Administrative normalization turns lexical bind into explicit environment
instructions and a flat typed instruction sequence. -/
def compile (expr : Expr ctx t) (stack : List Ty) : Code ctx ctx stack (t :: stack) :=
  match expr with
  | .literal item => .next (.push item) .done
  | .ref reference => .next (.load reference) .done
  | .add left right =>
    (compile left stack).append
      ((compile right (.number :: stack)).append (.next .add .done))
  | .equal left right =>
    (compile left stack).append
      ((compile right (.number :: stack)).append (.next .equal .done))
  | .pair left right =>
    (compile left stack).append
      ((compile right (_ :: stack)).append (.next .pair .done))
  | .first expression => (compile expression stack).append (.next .first .done)
  | .second expression => (compile expression stack).append (.next .second .done)
  | .bind value body =>
    (compile value stack).append
      (.next .enter ((compile body stack).append (.next .leave .done)))

theorem compile_preserves_value_and_scope (expr : Expr ctx t)
    (env : Values ctx) (stack : List Ty) (values : Values stack) :
    (compile expr stack).run env values = (env, .cons (expr.eval env) values) := by
  induction expr generalizing stack with
  | literal item => rfl
  | ref reference => rfl
  | add left right ihLeft ihRight =>
    simp only [compile, code_append_runs_in_order, ihLeft, ihRight,
      Code.run, Instruction.run, Expr.eval]
    cases left.eval env
    cases right.eval env
    rfl
  | equal left right ihLeft ihRight =>
    simp only [compile, code_append_runs_in_order, ihLeft, ihRight,
      Code.run, Instruction.run, Expr.eval]
    cases left.eval env
    cases right.eval env
    rfl
  | pair left right ihLeft ihRight =>
    simp only [compile, code_append_runs_in_order, ihLeft, ihRight,
      Code.run, Instruction.run, Expr.eval]
  | first pair ih =>
    simp only [compile, code_append_runs_in_order, ih, Code.run, Instruction.run, Expr.eval]
    cases pair.eval env
    rfl
  | second pair ih =>
    simp only [compile, code_append_runs_in_order, ih, Code.run, Instruction.run, Expr.eval]
    cases pair.eval env
    rfl
  | bind value body ihValue ihBody =>
    simp only [compile, code_append_runs_in_order, ihValue, ihBody, Code.run,
      Instruction.run, Expr.eval]

end BoundaryV2.Core
