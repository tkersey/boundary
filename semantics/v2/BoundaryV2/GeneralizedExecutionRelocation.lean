import BoundaryV2.GeneralizedFutureRelocation

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {Before After : List (TypeOf signature) → TypeOf signature → Type}

theorem Value.relocate_first (relocation : UseScope.Relocation)
    (body : ∀ context type, Before context type → After context type)
    {leftType rightType : TypeOf signature} (value : Value signature algebra Before (.product leftType rightType)) :
    (value.relocate relocation body).first = value.first.relocate relocation body := by
  cases value with
  | datum datum => cases datum; rfl
  | pair first second => rfl

theorem Value.relocate_second (relocation : UseScope.Relocation)
    (body : ∀ context type, Before context type → After context type)
    {leftType rightType : TypeOf signature} (value : Value signature algebra Before (.product leftType rightType)) :
    (value.relocate relocation body).second = value.second.relocate relocation body := by
  cases value with
  | datum datum => cases datum; rfl
  | pair first second => rfl

theorem Value.relocate_leaf (relocation : UseScope.Relocation)
    (body : ∀ context type, Before context type → After context type)
    (value : Value signature algebra Before (.leaf type)) : (value.relocate relocation body).leaf = value.leaf := by
  cases value with | datum datum => cases datum; rfl

theorem Environment.relocate_leaves (relocation : UseScope.Relocation)
    (body : ∀ context type, Before context type → After context type)
    {types : List signature.Data} (values : Environment signature algebra Before (types.map Ty.leaf)) :
    (values.relocate relocation body).leaves = values.leaves := by
  induction types with
  | nil => cases values; rfl
  | cons type types induction => cases values with
    | cons value rest => simp only [Environment.relocate, Environment.leaves, Value.relocate_leaf, induction rest]

private theorem relocate_environment_cast (relocation : UseScope.Relocation)
    (body : ∀ context type, Before context type → After context type)
    (equal : left = right) (values : Environment signature algebra Before right) :
    ((congrArg (Environment signature algebra Before) equal).mpr values).relocate relocation body =
      (congrArg (Environment signature algebra After) equal).mpr (values.relocate relocation body) := by
  cases equal
  rfl

theorem Environment.relocate_pushReverse (relocation : UseScope.Relocation)
    (body : ∀ context type, Before context type → After context type)
    (values : Environment signature algebra Before types) (stack : Environment signature algebra Before stackTypes) :
    (values.pushReverse stack).relocate relocation body =
      (values.relocate relocation body).pushReverse (stack.relocate relocation body) := by
  induction types generalizing stackTypes with
  | nil => cases values; rfl
  | cons type types induction => cases values with
    | cons value rest =>
      have shape : (type :: types).reverse ++ stackTypes = types.reverse ++ type :: stackTypes := by
        simp only [List.reverse_cons, List.append_assoc, List.singleton_append]
      have transported := relocate_environment_cast relocation body shape (rest.pushReverse (.cons value stack))
      simpa only [Environment.pushReverse, Environment.relocate, induction rest] using transported

namespace Target

variable {program : List (BodyType signature.Data signature.Effect)}

def Operands.relocate (relocation : UseScope.Relocation) (operands : Operands signature algebra program context result) :
    Operands signature algebra program context result :=
  ⟨operands.types, operands.code.relocate relocation, relocateEnvironment relocation operands.values⟩

theorem OperandStep.relocate (relocation : UseScope.Relocation)
    (step : OperandStep (environment : RuntimeEnvironment signature algebra program context) before after) :
    OperandStep (relocateEnvironment relocation environment) (before.relocate relocation) (after.relocate relocation) := by
  cases step with
  | push => exact .push
  | load =>
    simp only [Operands.relocate, Code.relocate, relocateEnvironment, Environment.relocate,
      ← Environment.relocate_lookup]
    exact .load
  | pair => exact .pair
  | first =>
    simp only [Operands.relocate, Code.relocate, relocateEnvironment, Environment.relocate, ← Value.relocate_first]
    exact .first
  | second =>
    simp only [Operands.relocate, Code.relocate, relocateEnvironment, Environment.relocate, ← Value.relocate_second]
    exact .second
  | left => exact .left
  | right => exact .right
  | close =>
    simp only [Operands.relocate, Code.relocate, relocateEnvironment, Environment.relocate_pushReverse,
      Environment.relocate, Value.relocate, relocateAuthority, Option.map_none]
    exact .close
  | primitive outcome =>
    simp only [Operands.relocate, Code.relocate, relocateEnvironment, Environment.relocate_pushReverse,
      Environment.relocate, Value.relocate, Datum.relocate]
    exact .primitive (by simpa only [Environment.relocate_leaves] using outcome)
  | primitiveFault outcome =>
    simp only [Operands.relocate, Code.relocate, relocateEnvironment, Environment.relocate_pushReverse]
    exact .primitiveFault (by simpa only [Environment.relocate_leaves] using outcome)

theorem CallStep.relocate (relocation : UseScope.Relocation)
    (step : CallStep (table : Definitions signature algebra program) before after) :
    CallStep (relocateDefinitions relocation table) (before.relocate relocation) (after.relocate relocation) := by
  cases step with
  | operand step => exact .operand (step.relocate relocation)
  | returned => exact .returned
  | enter => exact .enter
  | block => exact .block
  | named =>
    simp only [Configuration.relocate, Code.relocate, Stack.relocate, Frame.relocate,
      relocateDefinitions, relocateEnvironment, Environment.relocate_pushReverse, Environment.relocate]
    rw [← Variable.lookup_tuple_map (fun (type : BodyType signature.Data signature.Effect)
      (body : Code signature algebra program type.parameters [] type.result) => body.relocate relocation)]
    exact .named
  | closure =>
    simp only [Configuration.relocate, Code.relocate, Stack.relocate, Frame.relocate, relocateEnvironment,
      Environment.relocate_pushReverse, Environment.relocate_append, Environment.relocate, Value.relocate]
    exact .closure
  | dispatch =>
    simp only [Configuration.relocate, Code.relocate, Stack.relocate, Frame.relocate, relocateEnvironment,
      Environment.relocate_pushReverse, Environment.relocate, Value.relocate, Datum.relocate, relocateValue]
    exact .dispatch
  | attach => exact .attach
  | handlerReturned => exact .handlerReturned
  | caller => exact .caller
  | fault => exact .fault
  | yield => exact .yield

/-- Relocation preserves the number and order of ordinary instructions, including
operand faults, lexical calls, handler installation/return, requests, and yields.
Nominal selection and authority lookup require their own injectivity premises. -/
theorem CallSteps.relocate (relocation : UseScope.Relocation)
    (steps : CallSteps (table : Definitions signature algebra program) before count after) :
    CallSteps (relocateDefinitions relocation table) (before.relocate relocation) count (after.relocate relocation) := by
  induction steps with
  | refl => exact .refl
  | cons step tail induction => exact .cons (step.relocate relocation) induction

end Target
end BoundaryV2.Generalized
