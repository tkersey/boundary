import BoundaryV2.GeneralizedContinuations

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {Body Before After : List (TypeOf signature) → TypeOf signature → Type}
  {definitions : List (BodyType signature.Data signature.Effect)}

def Value.first {leftType rightType : TypeOf signature} :
    Value signature algebra Body (.product leftType rightType) → Value signature algebra Body leftType
  | .datum (.pair first _) => .datum first
  | .pair first _ => first

def Value.second {leftType rightType : TypeOf signature} :
    Value signature algebra Body (.product leftType rightType) → Value signature algebra Body rightType
  | .datum (.pair _ second) => .datum second
  | .pair _ second => second

def Value.leaf : Value signature algebra Body (.leaf type) → algebra.Value type
  | .datum (.leaf value) => value

def Environment.leaves : {types : List signature.Data} →
    Environment signature algebra Body (types.map Ty.leaf) → Tuple algebra.Value types
  | [], .nil => .nil
  | _ :: _, .cons value rest => .cons value.leaf rest.leaves

theorem Value.first_map (transform : ∀ context type, Before context type → After context type)
    {leftType rightType : TypeOf signature} (value : Value signature algebra Before (.product leftType rightType)) :
    (value.map transform).first = value.first.map transform := by
  cases value with
  | datum datum => cases datum; rfl
  | pair first second => rfl

theorem Value.second_map (transform : ∀ context type, Before context type → After context type)
    {leftType rightType : TypeOf signature} (value : Value signature algebra Before (.product leftType rightType)) :
    (value.map transform).second = value.second.map transform := by
  cases value with
  | datum datum => cases datum; rfl
  | pair first second => rfl

theorem Value.leaf_map (transform : ∀ context type, Before context type → After context type)
    (value : Value signature algebra Before (.leaf type)) : (value.map transform).leaf = value.leaf := by
  cases value with | datum datum => cases datum; rfl

theorem Environment.leaves_map (transform : ∀ context type, Before context type → After context type)
    {types : List signature.Data}
    (values : Environment signature algebra Before (types.map Ty.leaf)) :
    (values.map transform).leaves = values.leaves := by
  induction types with
  | nil => cases values; rfl
  | cons type types induction =>
    cases values with
    | cons value rest => simp only [Environment.map, Environment.leaves, Value.leaf_map, induction rest]

theorem Environment.select_map (transform : ∀ context type, Before context type → After context type)
    (selection : Selection context types) (values : Environment signature algebra Before context) :
    (values.map transform).select selection = (values.select selection).map transform := by
  induction selection with
  | nil => rfl
  | cons reference rest induction =>
    simp only [Environment.select, Environment.map, Environment.lookup_map, induction]

/-- Push operands from left to right. The last evaluated operand is on top;
the receiving instruction knows the original argument-type list. -/
def Environment.pushReverse : {types stack : List (TypeOf signature)} →
    Environment signature algebra Body types → Environment signature algebra Body stack →
    Environment signature algebra Body (types.reverse ++ stack)
  | _, _, .nil, stack => stack
  | _, _, .cons value rest, stack => by
    simpa only [List.reverse_cons, List.append_assoc, List.singleton_append] using rest.pushReverse (.cons value stack)

namespace Source

/- These operations evaluate expression data and captured code values. Use
permissions and physical custody are handled at control admission; the lexical
environment here is a view, not an additional physical owner. -/
mutual
  def Expression.evaluate (expression : Expression signature algebra definitions context type)
      (environment : RuntimeEnvironment signature algebra definitions context) :
      Except algebra.Fault (RuntimeValue signature algebra definitions type) :=
    match expression with
    | .datum datum => .ok (.datum datum)
    | .reference reference => .ok (environment.lookup reference)
    | .pair first second =>
      match first.evaluate environment with
      | .error fault => .error fault
      | .ok firstValue => match second.evaluate environment with
        | .error fault => .error fault
        | .ok secondValue => .ok (.pair firstValue secondValue)
    | .first value => (value.evaluate environment).map Value.first
    | .second value => (value.evaluate environment).map Value.second
    | .left value => (value.evaluate environment).map Value.left
    | .right value => (value.evaluate environment).map Value.right
    | .primitive operation inputs =>
      match inputs.evaluate environment with
      | .error fault => .error fault
      | .ok values => (algebra.evaluate operation values.leaves).map (fun value => .datum (.leaf value))
    | .lambda captures body => .ok (.closure body (environment.select captures) none)

  def Arguments.evaluate (arguments : Arguments signature algebra definitions context types)
      (environment : RuntimeEnvironment signature algebra definitions context) :
      Except algebra.Fault (RuntimeEnvironment signature algebra definitions types) :=
    match arguments with
    | .nil => .ok .nil
    | .cons first rest =>
      match first.evaluate environment with
      | .error fault => .error fault
      | .ok firstValue => match rest.evaluate environment with
        | .error fault => .error fault
        | .ok restValues => .ok (.cons firstValue restValues)
end

end Source

namespace Target

structure Operands (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (definitions : List (BodyType signature.Data signature.Effect)) (context : List (TypeOf signature))
    (result : TypeOf signature) where
  types : List (TypeOf signature)
  code : Code signature algebra definitions context types result
  values : RuntimeEnvironment signature algebra definitions types

theorem Operands.reindex {first second : List (TypeOf signature)} (equal : first = second)
    (code : Code signature algebra definitions context first result)
    (values : RuntimeEnvironment signature algebra definitions second) :
    (⟨first, code, cast (congrArg (RuntimeEnvironment signature algebra definitions) equal.symm) values⟩ :
      Operands signature algebra definitions context result) =
      ⟨second, cast (congrArg (fun types => Code signature algebra definitions context types result) equal) code, values⟩ := by
  cases equal
  rfl

/-- Individual target instructions act on first-order operand and environment
data. No source term or source evaluation function occurs in these rules. -/
inductive OperandStep (environment : RuntimeEnvironment signature algebra definitions context) :
    Operands signature algebra definitions context result → Operands signature algebra definitions context result → Prop where
  | push : OperandStep environment ⟨_, .push datum next, values⟩ ⟨_, next, .cons (.datum datum) values⟩
  | load : OperandStep environment ⟨_, .load reference next, values⟩ ⟨_, next, .cons (environment.lookup reference) values⟩
  | pair : OperandStep environment ⟨_, .pair next, .cons second (.cons first values)⟩
      ⟨_, next, .cons (.pair first second) values⟩
  | first : OperandStep environment ⟨_, .first next, .cons value values⟩ ⟨_, next, .cons value.first values⟩
  | second : OperandStep environment ⟨_, .second next, .cons value values⟩ ⟨_, next, .cons value.second values⟩
  | left : OperandStep environment ⟨_, .left next, .cons value values⟩ ⟨_, next, .cons (.left value) values⟩
  | right : OperandStep environment ⟨_, .right next, .cons value values⟩ ⟨_, next, .cons (.right value) values⟩
  | close : OperandStep environment ⟨_, .close body next, captured.pushReverse values⟩
      ⟨_, next, .cons (.closure body captured none) values⟩
  | primitive {parameters : List signature.Data} {answer : signature.Data}
      {operation : algebra.operation parameters answer}
      {arguments : RuntimeEnvironment signature algebra definitions (parameters.map Ty.leaf)}
      {value : algebra.Value answer} {stack : List (TypeOf signature)}
      {values : RuntimeEnvironment signature algebra definitions stack}
      {next : Code signature algebra definitions context (.leaf answer :: stack) result} :
      algebra.evaluate operation arguments.leaves = .ok value →
      OperandStep environment ⟨_, .primitive operation next, arguments.pushReverse values⟩
        ⟨_, next, .cons (.datum (.leaf (type := answer) value)) values⟩
  | primitiveFault {parameters : List signature.Data} {answer : signature.Data}
      {operation : algebra.operation parameters answer}
      {arguments : RuntimeEnvironment signature algebra definitions (parameters.map Ty.leaf)}
      {stack : List (TypeOf signature)} {values : RuntimeEnvironment signature algebra definitions stack}
      {next : Code signature algebra definitions context (.leaf answer :: stack) result} :
      algebra.evaluate operation arguments.leaves = .error fault →
      OperandStep environment ⟨_, .primitive operation next, arguments.pushReverse values⟩
        ⟨_, .fault fault, arguments.pushReverse values⟩

/-- A finite, explicitly counted instruction drain. Every cons witnesses one
real instruction; the evaluator cannot hide infinitely many silent steps. -/
inductive OperandSteps (environment : RuntimeEnvironment signature algebra definitions context) :
    Operands signature algebra definitions context result → Nat → Operands signature algebra definitions context result → Prop where
  | refl : OperandSteps environment state 0 state
  | cons : OperandStep environment first middle → OperandSteps environment middle count last →
      OperandSteps environment first (count + 1) last

theorem OperandSteps.trans (first : OperandSteps environment before count middle)
    (second : OperandSteps environment middle rest after) : OperandSteps environment before (count + rest) after := by
  induction first with
  | refl => simpa using second
  | cons step tail induction => simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using OperandSteps.cons step (induction second)

theorem OperandSteps.single (step : OperandStep environment before after) : OperandSteps environment before 1 after :=
  .cons step .refl

theorem OperandSteps.zero_eq (steps : OperandSteps environment before 0 after) : before = after := by
  cases steps
  rfl

inductive Faulted (fault : algebra.Fault) : Operands signature algebra definitions context result → Prop where
  | fault : Faulted fault ⟨_, .fault fault, values⟩

def ReachesFault (environment : RuntimeEnvironment signature algebra definitions context)
    (before : Operands signature algebra definitions context result) (fault : algebra.Fault) : Prop :=
  ∃ count after, OperandSteps environment before count after ∧ Faulted fault after

theorem ReachesFault.prepend (steps : OperandSteps environment before count middle)
    (failed : ReachesFault environment middle fault) : ReachesFault environment before fault := by
  obtain ⟨rest, after, tail, terminal⟩ := failed
  exact ⟨count + rest, after, steps.trans tail, terminal⟩

end Target
end BoundaryV2.Generalized
