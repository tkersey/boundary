import BoundaryV2.GeneralizedStateReflection

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {Before After : List (TypeOf signature) → TypeOf signature → Type}

/-- Body translation changes neither the physical value fields nor their
handoff permission. This inverse reads the target operation's actual witness. -/
theorem ValueHandoff.of_map
    (transform : ∀ context type, Before context type → After context type)
    (value : Value signature algebra Before type)
    (handoff : ValueHandoff (value.map transform) before after) : ValueHandoff value before after := by
  cases handoff with
  | unowned empty => exact .unowned (by simpa only [Value.map_preserves_owning_fields] using empty)
  | move => simpa only [Value.map_preserves_owning_fields] using (ValueHandoff.move (value := value))

theorem ComputationHandoff.of_map
    (transform : ∀ context type, Before context type → After context type)
    (captured : Environment signature algebra Before types)
    (handoff : ComputationHandoff (captured.map transform) use authority before after) :
    ComputationHandoff captured use authority before after := by
  cases handoff with
  | shared use permitted copyable => exact .shared use permitted (by simpa only [Environment.copyable_map] using copyable)
  | owned use token owner before after retained spent =>
    simpa only [Environment.map_preserves_owning_fields] using ComputationHandoff.owned (captured := captured) use token owner before after retained spent
  | ownedFlat use token owner before after retained spent =>
    simpa only [Environment.map_preserves_owning_fields] using ComputationHandoff.ownedFlat (captured := captured) use token owner before after retained spent

theorem PackageHandoff.of_map
    (transform : ∀ context type, Before context type → After context type)
    (value : Value signature algebra Before content)
    (handoff : PackageHandoff (value.map transform) token owner before after) : PackageHandoff value token owner before after := by
  cases handoff with
  | unpack before after retained spent =>
    simpa only [Value.owningField, Value.map_preserves_owning_fields] using PackageHandoff.unpack (value := value) (token := token) (owner := owner) before after retained spent
  | unpackFlat before after retained spent =>
    simpa only [Value.map_preserves_owning_fields] using PackageHandoff.unpackFlat (value := value) (token := token) (owner := owner) before after retained spent

end BoundaryV2.Generalized

namespace BoundaryV2.Generalized.Target

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

/-- Lean's constructor discriminator projected through a code configuration.
This is used only to rule out different instruction constructors in inversion. -/
def Configuration.codeConstructor : Configuration signature algebra program result → Option Nat
  | .code body _ _ _ => some body.ctorIdx
  | _ => none


/-- An inspection view of the actual application operands and caller. It
exposes their type indices before inversion of the reversed operand layout. -/
structure ApplicationFrame (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (result : TypeOf signature) where
  context : List (TypeOf signature)
  input : TypeOf signature
  use : Use
  parameters : List (TypeOf signature)
  answer : TypeOf signature
  capturedTypes : List (TypeOf signature)
  operands : List (TypeOf signature)
  body : Code signature algebra program (parameters ++ capturedTypes) [] answer
  next : Code signature algebra program context (answer :: operands) input
  bindings : RuntimeEnvironment signature algebra program context
  arguments : RuntimeEnvironment signature algebra program parameters
  captured : RuntimeEnvironment signature algebra program capturedTypes
  authority : Option (Id .custody × Owner)
  values : RuntimeEnvironment signature algebra program operands
  outside : Stack signature algebra program input result

def applicationViewCode (code : Code signature algebra program context types input)
    (bindings : RuntimeEnvironment signature algebra program context)
    (values : RuntimeEnvironment signature algebra program types) (outside : Stack signature algebra program input result) :
    Option (ApplicationFrame signature algebra program result) :=
  match code with
  | @Code.callClosure _ _ _ _ answer operands _ use parameters next =>
    let (arguments, tail) := Environment.popReverse parameters values
    match tail with
    | .cons closure rest => match closure with
      | .closure body captured authority =>
        some ⟨context, input, use, parameters, answer, _, operands, body, next, bindings, arguments, captured, authority, rest, outside⟩
  | _ => none

def Configuration.applicationView : Configuration signature algebra program result → Option (ApplicationFrame signature algebra program result)
  | .code instruction bindings values outside => applicationViewCode instruction bindings values outside
  | _ => none

theorem application_view_exact
    (bindings : RuntimeEnvironment signature algebra program context)
    (values : RuntimeEnvironment signature algebra program operands)
    (next : Code signature algebra program context (answer :: operands) input)
    (outside : Stack signature algebra program input result) (use : Use)
    (body : Code signature algebra program (parameters ++ capturedTypes) [] answer)
    (captured : RuntimeEnvironment signature algebra program capturedTypes)
    (arguments : RuntimeEnvironment signature algebra program parameters) (authority : Option (Id .custody × Owner)) :
    (Configuration.code (.callClosure (use := use) next) bindings
      (arguments.pushReverse (.cons (.closure body captured authority) values)) outside).applicationView =
      some ⟨context, input, use, parameters, answer, capturedTypes, operands, body, next, bindings, arguments, captured, authority, values, outside⟩ := by
  simp only [Configuration.applicationView, applicationViewCode, Environment.popReverse_pushReverse]

theorem OperandStep.needs_no_ownership
    {bindings : RuntimeEnvironment signature algebra program context}
    {before after : Operands signature algebra program context result}
    (step : OperandStep bindings before after) (plain : before.code.isClosure = false) :
    before.code.needsOwnershipStep = false := by cases step <;> first | rfl | cases plain

variable [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]

theorem cell_read_step_inverts
    {table : Definitions signature algebra program}
    (bindings : RuntimeEnvironment signature algebra program context)
    (values : RuntimeEnvironment signature algebra program operands)
    (next : Code signature algebra program context (type :: operands) input)
    (outside : Stack signature algebra program input result)
    (store : ControlHeap signature algebra program)
    (storage : Cells signature algebra (fun context result => Code signature algebra program context [] result))
    (regions : List (Id .region))
    (step : ExecutionStep table
      ⟨⟨store, .code (.cellRead next) bindings (.cons (.cell identity region) values) outside⟩, storage, regions⟩ after) :
    ∃ value, region ∈ regions ∧ Cells.readCopy identity region type storage = some value ∧
      after = ⟨⟨store, .code next bindings (.cons value values) outside⟩, storage, regions⟩ := by
  generalize atCode : Configuration.code (.cellRead next) bindings (.cons (.cell identity region) values) outside = initial at step
  have tag := congrArg Configuration.codeConstructor atCode
  cases step with
  | cell actual =>
    cases actual with
    | ordinary actual neutral =>
      obtain ⟨attachment, computed⟩ := actual.computes_next
      rw [← atCode] at computed
      cases computed
    | allocate | write => cases tag
    | read live found =>
      cases atCode
      exact ⟨_, live, found, rfl⟩
  | control actual =>
    cases actual with
    | ordinary actual neutral =>
      obtain ⟨attachment, computed⟩ := actual.computes_next
      rw [← atCode] at computed
      cases computed
    | @operand context answer result beforeStore afterStore bindings actualBefore actualAfter actualOutside actual =>
      cases actual with
      | ordinary actual neutral =>
        have computed := actual.code_next table ⟨0⟩ actualOutside
        change nextWithAttachment table ⟨0⟩ (.code actualBefore.code bindings actualBefore.values actualOutside) = _ at computed
        rw [← atCode] at computed
        cases computed
      | ownedClose | sharedClose => cases tag
    | application | resume | successor | injection | handled => cases tag
  | installHandler | enterProtection | enterRegion | packageOperand | unpackageOperand => cases tag

theorem cell_write_step_inverts
    {table : Definitions signature algebra program}
    (bindings : RuntimeEnvironment signature algebra program context)
    (values : RuntimeEnvironment signature algebra program operands)
    (next : Code signature algebra program context (.unit :: operands) input)
    (outside : Stack signature algebra program input result)
    (store : ControlHeap signature algebra program)
    (storage : Cells signature algebra (fun context result => Code signature algebra program context [] result))
    (regions : List (Id .region))
    (value : RuntimeValue signature algebra program type)
    (step : ExecutionStep table
      ⟨⟨store, .code (.cellWrite next) bindings (.cons value (.cons (.cell identity region) values)) outside⟩, storage, regions⟩ after) :
    ∃ afterCells, region ∈ regions ∧ Cells.writeCopy identity region value storage = some afterCells ∧
      after = ⟨⟨store, .code next bindings (.cons (.datum .unit) values) outside⟩, afterCells, regions⟩ := by
  generalize atCode : Configuration.code (.cellWrite next) bindings (.cons value (.cons (.cell identity region) values)) outside = initial at step
  have tag := congrArg Configuration.codeConstructor atCode
  cases step with
  | cell actual =>
    cases actual with
    | ordinary actual neutral =>
      obtain ⟨attachment, computed⟩ := actual.computes_next
      rw [← atCode] at computed
      cases computed
    | allocate | read => cases tag
    | write live found =>
      cases atCode
      exact ⟨_, live, found, rfl⟩
  | control actual =>
    cases actual with
    | ordinary actual neutral =>
      obtain ⟨attachment, computed⟩ := actual.computes_next
      rw [← atCode] at computed
      cases computed
    | @operand context answer result beforeStore afterStore bindings actualBefore actualAfter actualOutside actual =>
      cases actual with
      | ordinary actual neutral =>
        have computed := actual.code_next table ⟨0⟩ actualOutside
        change nextWithAttachment table ⟨0⟩ (.code actualBefore.code bindings actualBefore.values actualOutside) = _ at computed
        rw [← atCode] at computed
        cases computed
      | ownedClose | sharedClose => cases tag
    | application | resume | successor | injection | handled => cases tag
  | installHandler | enterProtection | enterRegion | packageOperand | unpackageOperand => cases tag

theorem cell_allocate_step_inverts
    {table : Definitions signature algebra program}
    (bindings : RuntimeEnvironment signature algebra program context)
    (values : RuntimeEnvironment signature algebra program operands)
    (next : Code signature algebra program context (.cell type :: operands) input)
    (outside : Stack signature algebra program input result)
    (store : ControlHeap signature algebra program)
    (storage : Cells signature algebra (fun context result => Code signature algebra program context [] result))
    (regions : List (Id .region))
    (value : RuntimeValue signature algebra program type)
    (step : ExecutionStep table
      ⟨⟨store, .code (.cellNew next) bindings (.cons value (.cons (.datum (.region region)) values)) outside⟩, storage, regions⟩ after) :
    ∃ reserved fields, region ∈ regions ∧ ValueHandoff value store.fields fields ∧
      after = ⟨⟨{ store with fields := fields }, .code next bindings
        (.cons (.cell (Cells.allocate region value storage reserved).identity region) values) outside⟩,
        (Cells.allocate region value storage reserved).cells, regions⟩ := by
  generalize atCode : Configuration.code (.cellNew next) bindings (.cons value (.cons (.datum (.region region)) values)) outside = initial at step
  have tag := congrArg Configuration.codeConstructor atCode
  cases step with
  | cell actual =>
    cases actual with
    | ordinary actual neutral =>
      obtain ⟨attachment, computed⟩ := actual.computes_next
      rw [← atCode] at computed
      cases computed
    | read | write => cases tag
    | allocate live found =>
      cases atCode
      exact ⟨_, _, live, found, rfl⟩
  | control actual =>
    cases actual with
    | ordinary actual neutral =>
      obtain ⟨attachment, computed⟩ := actual.computes_next
      rw [← atCode] at computed
      cases computed
    | @operand context answer result beforeStore afterStore bindings actualBefore actualAfter actualOutside actual =>
      cases actual with
      | ordinary actual neutral =>
        have computed := actual.code_next table ⟨0⟩ actualOutside
        change nextWithAttachment table ⟨0⟩ (.code actualBefore.code bindings actualBefore.values actualOutside) = _ at computed
        rw [← atCode] at computed
        cases computed
      | ownedClose | sharedClose => cases tag
    | application | resume | successor | injection | handled => cases tag
  | installHandler | enterProtection | enterRegion | packageOperand | unpackageOperand => cases tag

theorem package_step_inverts
    {table : Definitions signature algebra program}
    (bindings : RuntimeEnvironment signature algebra program context)
    (values : RuntimeEnvironment signature algebra program operands)
    (next : Code signature algebra program context (.package type :: operands) input)
    (outside : Stack signature algebra program input result)
    (store : ControlHeap signature algebra program)
    (storage : Cells signature algebra (fun context result => Code signature algebra program context [] result))
    (regions : List (Id .region))
    (value : RuntimeValue signature algebra program type)
    (step : ExecutionStep table
      ⟨⟨store, .code (.package next) bindings (.cons value values) outside⟩, storage, regions⟩ after) :
    ∃ owner moved, ∃ (handoff : ValueHandoff value store.fields moved),
      let created := createPackage value owner store moved handoff storage.reservations.custody
      after = ⟨⟨created.store, .code next bindings (.cons created.value values) outside⟩, storage, regions⟩ := by
  generalize atCode : Configuration.code (.package next) bindings (.cons value values) outside = initial at step
  have tag := congrArg Configuration.codeConstructor atCode
  cases step with
  | cell actual =>
    cases actual with
    | ordinary actual neutral =>
      obtain ⟨attachment, computed⟩ := actual.computes_next
      rw [← atCode] at computed
      cases computed
    | allocate | read | write => cases tag
  | control actual =>
    cases actual with
    | ordinary actual neutral =>
      obtain ⟨attachment, computed⟩ := actual.computes_next
      rw [← atCode] at computed
      cases computed
    | @operand context answer result beforeStore afterStore bindings actualBefore actualAfter actualOutside actual =>
      cases actual with
      | ordinary actual neutral =>
        have computed := actual.code_next table ⟨0⟩ actualOutside
        change nextWithAttachment table ⟨0⟩ (.code actualBefore.code bindings actualBefore.values actualOutside) = _ at computed
        rw [← atCode] at computed
        cases computed
      | ownedClose | sharedClose => cases tag
    | application | resume | successor | injection | handled => cases tag
  | installHandler | enterProtection | enterRegion | unpackageOperand => cases tag
  | packageOperand owner handoff =>
    cases atCode
    exact ⟨owner, _, handoff, rfl⟩

theorem unpackage_step_inverts
    {table : Definitions signature algebra program}
    (bindings : RuntimeEnvironment signature algebra program context)
    (values : RuntimeEnvironment signature algebra program operands)
    (next : Code signature algebra program context (type :: operands) input)
    (outside : Stack signature algebra program input result)
    (store : ControlHeap signature algebra program)
    (storage : Cells signature algebra (fun context result => Code signature algebra program context [] result))
    (regions : List (Id .region))
    (value : RuntimeValue signature algebra program type) (token : Id .custody) (owner : Owner)
    (step : ExecutionStep table
      ⟨⟨store, .code (.unpackage next) bindings (.cons (.package token owner value) values) outside⟩, storage, regions⟩ after) :
    ∃ fields, PackageHandoff value token owner store.fields fields ∧
      after = ⟨⟨{ store with fields := fields }, .code next bindings (.cons value values) outside⟩, storage, regions⟩ := by
  generalize atCode : Configuration.code (.unpackage next) bindings (.cons (.package token owner value) values) outside = initial at step
  have tag := congrArg Configuration.codeConstructor atCode
  cases step with
  | cell actual =>
    cases actual with
    | ordinary actual neutral =>
      obtain ⟨attachment, computed⟩ := actual.computes_next
      rw [← atCode] at computed
      cases computed
    | allocate | read | write => cases tag
  | control actual =>
    cases actual with
    | ordinary actual neutral =>
      obtain ⟨attachment, computed⟩ := actual.computes_next
      rw [← atCode] at computed
      cases computed
    | @operand context answer result beforeStore afterStore bindings actualBefore actualAfter actualOutside actual =>
      cases actual with
      | ordinary actual neutral =>
        have computed := actual.code_next table ⟨0⟩ actualOutside
        change nextWithAttachment table ⟨0⟩ (.code actualBefore.code bindings actualBefore.values actualOutside) = _ at computed
        rw [← atCode] at computed
        cases computed
      | ownedClose | sharedClose => cases tag
    | application | resume | successor | injection | handled => cases tag
  | installHandler | enterProtection | enterRegion | packageOperand => cases tag
  | unpackageOperand handoff =>
    cases atCode
    exact ⟨_, handoff, rfl⟩

theorem resume_step_inverts
    {table : Definitions signature algebra program}
    (bindings : RuntimeEnvironment signature algebra program context)
    (values : RuntimeEnvironment signature algebra program operands)
    (next : Code signature algebra program context (body :: operands) input)
    (outside : Stack signature algebra program input result)
    (store : ControlHeap signature algebra program)
    (storage : Cells signature algebra (fun context result => Code signature algebra program context [] result))
    (regions : List (Id .region)) (mode : Mode) (effect : signature.Effect) (use : Use)
    (view : UseScope.ControlView) (response : RuntimeValue signature algebra program responseType)
    (step : ExecutionStep table
      ⟨⟨store, .code (.resume (mode := mode) (effect := effect) (use := use) next) bindings
        (.cons response (.cons (.continuation view.identity (some (view.authority, view.owner))) values)) outside⟩, storage, regions⟩ after) :
    ∃ (oneShot : UseScope.OneShotUse), ∃ afterControl, use = oneShot.type ∧
      resumeControl ⟨mode, effect, responseType, body⟩ view store response (.push (.returnTo next bindings values) outside) = some afterControl ∧
      after = ⟨afterControl, storage, regions⟩ := by
  generalize atCode : Configuration.code (.resume (mode := mode) (effect := effect) (use := use) next) bindings
    (.cons response (.cons (.continuation view.identity (some (view.authority, view.owner))) values)) outside = initial at step
  have tag := congrArg Configuration.codeConstructor atCode
  cases step with
  | cell actual =>
    cases actual with
    | ordinary actual neutral =>
      obtain ⟨attachment, computed⟩ := actual.computes_next
      rw [← atCode] at computed
      cases computed
    | allocate | read | write => cases tag
  | control actual =>
    cases actual with
    | ordinary actual neutral =>
      obtain ⟨attachment, computed⟩ := actual.computes_next
      rw [← atCode] at computed
      cases computed
    | @operand context answer result beforeStore afterStore bindings actualBefore actualAfter actualOutside actual =>
      cases actual with
      | ordinary actual neutral =>
        have computed := actual.code_next table ⟨0⟩ actualOutside
        change nextWithAttachment table ⟨0⟩ (.code actualBefore.code bindings actualBefore.values actualOutside) = _ at computed
        rw [← atCode] at computed
        cases computed
      | ownedClose | sharedClose => cases tag
    | @resume context body operands answer result mode effect responseType actualView store response after oneShot next bindings values outside accepted =>
      cases view
      cases actualView
      cases atCode
      exact ⟨oneShot, _, rfl, accepted, rfl⟩
    | application | successor | injection | handled => cases tag
  | installHandler | enterProtection | enterRegion | packageOperand | unpackageOperand => cases tag

theorem successor_step_inverts
    {table : Definitions signature algebra program}
    (bindings : RuntimeEnvironment signature algebra program context)
    (values : RuntimeEnvironment signature algebra program operands)
    (next : Code signature algebra program context (answer :: operands) input)
    (outside : Stack signature algebra program input result)
    (store : ControlHeap signature algebra program)
    (storage : Cells signature algebra (fun context result => Code signature algebra program context [] result))
    (regions : List (Id .region)) (effect : signature.Effect) (use : Use)
    (returned : Code signature algebra program (body :: context) [] answer)
    (clauses : Clauses signature algebra program effect .deep context body answer)
    (view : UseScope.ControlView) (response : RuntimeValue signature algebra program responseType)
    (step : ExecutionStep table
      ⟨⟨store, .code (.replaceHandler (use := use) effect returned clauses next) bindings
        (.cons response (.cons (.continuation (mode := Mode.shallow) view.identity (some (view.authority, view.owner))) values)) outside⟩, storage, regions⟩ after) :
    ∃ (oneShot : UseScope.OneShotUse), ∃ afterControl, use = oneShot.type ∧
      resumeControlWith view store response returned clauses bindings (.push (.returnTo next bindings values) outside) = some afterControl ∧
      after = ⟨afterControl, storage, regions⟩ := by
  generalize atCode : Configuration.code (.replaceHandler (use := use) effect returned clauses next) bindings
    (.cons response (.cons (.continuation (mode := Mode.shallow) view.identity (some (view.authority, view.owner))) values)) outside = initial at step
  have tag := congrArg Configuration.codeConstructor atCode
  cases step with
  | cell actual =>
    cases actual with
    | ordinary actual neutral =>
      obtain ⟨attachment, computed⟩ := actual.computes_next
      rw [← atCode] at computed
      cases computed
    | allocate | read | write => cases tag
  | control actual =>
    cases actual with
    | ordinary actual neutral =>
      obtain ⟨attachment, computed⟩ := actual.computes_next
      rw [← atCode] at computed
      cases computed
    | @operand context answer result beforeStore afterStore bindings actualBefore actualAfter actualOutside actual =>
      cases actual with
      | ordinary actual neutral =>
        have computed := actual.code_next table ⟨0⟩ actualOutside
        change nextWithAttachment table ⟨0⟩ (.code actualBefore.code bindings actualBefore.values actualOutside) = _ at computed
        rw [← atCode] at computed
        cases computed
      | ownedClose | sharedClose => cases tag
    | @successor context answer operands rest body effect result actualView store responseType response after oneShot next returned clauses bindings values outside accepted =>
      cases view
      cases actualView
      cases atCode
      exact ⟨oneShot, _, rfl, accepted, rfl⟩
    | application | resume | injection | handled => cases tag
  | installHandler | enterProtection | enterRegion | packageOperand | unpackageOperand => cases tag

theorem injection_step_inverts
    {table : Definitions signature algebra program}
    (bindings : RuntimeEnvironment signature algebra program context)
    (values : RuntimeEnvironment signature algebra program operands)
    (next : Code signature algebra program context (answer :: operands) input)
    (outside : Stack signature algebra program input result)
    (store : ControlHeap signature algebra program)
    (storage : Cells signature algebra (fun context result => Code signature algebra program context [] result))
    (regions : List (Id .region)) (mode : Mode) (effect : signature.Effect) (use : Use)
    (view : UseScope.ControlView) (bodyUse : Use)
    (body : Code signature algebra program capturedTypes [] responseType)
    (captured : RuntimeEnvironment signature algebra program capturedTypes) (authority : Option (Id .custody × Owner))
    (step : ExecutionStep table
      ⟨⟨store, .code (.inject (mode := mode) (effect := effect) (use := use) (useBody := bodyUse) next) bindings
        (.cons (.closure body captured authority) (.cons (.continuation view.identity (some (view.authority, view.owner))) values)) outside⟩, storage, regions⟩ after) :
    ∃ (oneShot : UseScope.OneShotUse), ∃ fields afterControl, use = oneShot.type ∧
      ComputationHandoff captured bodyUse authority store.fields fields ∧
      injectControl ⟨mode, effect, responseType, answer⟩ view { store with fields := fields } ⟨capturedTypes, body, captured⟩
        (.push (.returnTo next bindings values) outside) = some afterControl ∧
      after = ⟨afterControl, storage, regions⟩ := by
  generalize atCode : Configuration.code (.inject (mode := mode) (effect := effect) (use := use) (useBody := bodyUse) next) bindings
    (.cons (.closure body captured authority) (.cons (.continuation view.identity (some (view.authority, view.owner))) values)) outside = initial at step
  have tag := congrArg Configuration.codeConstructor atCode
  cases step with
  | cell actual =>
    cases actual with
    | ordinary actual neutral =>
      obtain ⟨attachment, computed⟩ := actual.computes_next
      rw [← atCode] at computed
      cases computed
    | allocate | read | write => cases tag
  | control actual =>
    cases actual with
    | ordinary actual neutral =>
      obtain ⟨attachment, computed⟩ := actual.computes_next
      rw [← atCode] at computed
      cases computed
    | @operand context answer result beforeStore afterStore bindings actualBefore actualAfter actualOutside actual =>
      cases actual with
      | ordinary actual neutral =>
        have computed := actual.code_next table ⟨0⟩ actualOutside
        change nextWithAttachment table ⟨0⟩ (.code actualBefore.code bindings actualBefore.values actualOutside) = _ at computed
        rw [← atCode] at computed
        cases computed
      | ownedClose | sharedClose => cases tag
    | @injection context answer operands rest capturedTypes input result authority fields mode effect actualView store after oneShot bodyUse next body captured bindings values outside handoff accepted =>
      cases view
      cases actualView
      cases atCode
      exact ⟨oneShot, _, _, rfl, handoff, accepted, rfl⟩
    | application | successor | resume | handled => cases tag
  | installHandler | enterProtection | enterRegion | packageOperand | unpackageOperand => cases tag

theorem application_step_inverts
    {table : Definitions signature algebra program}
    (bindings : RuntimeEnvironment signature algebra program context)
    (values : RuntimeEnvironment signature algebra program operands)
    (next : Code signature algebra program context (answer :: operands) input)
    (outside : Stack signature algebra program input result)
    (store : ControlHeap signature algebra program)
    (storage : Cells signature algebra (fun context result => Code signature algebra program context [] result))
    (regions : List (Id .region)) (use : Use)
    (body : Code signature algebra program (parameters ++ capturedTypes) [] answer)
    (captured : RuntimeEnvironment signature algebra program capturedTypes)
    (arguments : RuntimeEnvironment signature algebra program parameters) (authority : Option (Id .custody × Owner))
    (step : ExecutionStep table
      ⟨⟨store, .code (.callClosure (use := use) next) bindings
        (arguments.pushReverse (.cons (.closure body captured authority) values)) outside⟩, storage, regions⟩ after) :
    ∃ fields, ComputationHandoff captured use authority store.fields fields ∧
      after = ⟨⟨{ store with fields := fields }, .code body (arguments.append captured) .nil
        (.push (.returnTo next bindings values) outside)⟩, storage, regions⟩ := by
  generalize atCode : Configuration.code (.callClosure (use := use) next) bindings
    (arguments.pushReverse (.cons (.closure body captured authority) values)) outside = initial at step
  have tag := congrArg Configuration.codeConstructor atCode
  cases step with
  | cell actual =>
    cases actual with
    | ordinary actual neutral =>
      obtain ⟨attachment, computed⟩ := actual.computes_next
      rw [← atCode] at computed
      rw [← atCode] at neutral
      cases neutral
    | allocate | read | write => cases tag
  | control actual =>
    cases actual with
    | ordinary actual neutral =>
      obtain ⟨attachment, computed⟩ := actual.computes_next
      rw [← atCode] at computed
      rw [← atCode] at neutral
      cases neutral
    | @operand context answer result beforeStore afterStore bindings actualBefore actualAfter actualOutside actual =>
      cases actual with
      | ordinary actual neutral =>
        have neutral : (Configuration.code actualBefore.code bindings actualBefore.values actualOutside).needsOwnershipStep = false := actual.needs_no_ownership neutral
        rw [← atCode] at neutral
        cases neutral
      | ownedClose | sharedClose => cases tag
    | application handoff =>
      have same := congrArg Configuration.applicationView atCode
      simp only [application_view_exact, Option.some.injEq] at same
      cases same
      exact ⟨_, handoff, rfl⟩
    | resume | successor | injection | handled => cases tag
  | installHandler | enterProtection | enterRegion | packageOperand | unpackageOperand => cases tag

theorem installation_step_inverts
    {table : Definitions signature algebra program}
    (effect : signature.Effect) (mode : Mode)
    (returned : Code signature algebra program (bodyType :: context) [] answer)
    (clauses : Clauses signature algebra program effect mode context bodyType answer)
    (body : Code signature algebra program (.capability effect :: context) [] bodyType)
    (bindings : RuntimeEnvironment signature algebra program context)
    (values : RuntimeEnvironment signature algebra program operands)
    (next : Code signature algebra program context (answer :: operands) input)
    (outside : Stack signature algebra program input result)
    (store : ControlHeap signature algebra program)
    (storage : Cells signature algebra (fun context result => Code signature algebra program context [] result))
    (regions : List (Id .region))
    (step : ExecutionStep table
      ⟨⟨store, .code (.attach effect mode returned clauses body next) bindings values outside⟩, storage, regions⟩ after) :
    ∃ extra,
      let identity := freshAttachment table (.attach effect mode returned clauses body next) bindings values outside store storage extra
      after = ⟨⟨store, .code body (.cons (.datum (.capability identity)) bindings) .nil
        (.push (.handler effect mode identity returned clauses bindings) (.push (.returnTo next bindings values) outside))⟩, storage, regions⟩ := by
  generalize atCode : Configuration.code (.attach effect mode returned clauses body next) bindings values outside = initial at step
  have tag := congrArg Configuration.codeConstructor atCode
  cases step with
  | cell actual =>
    cases actual with
    | ordinary actual neutral => rw [← atCode] at neutral; cases neutral
    | allocate | read | write => cases tag
  | control actual =>
    cases actual with
    | ordinary actual neutral => rw [← atCode] at neutral; cases neutral
    | @operand context input result beforeStore afterStore bindings first last actualOutside actual =>
      cases actual with
      | ordinary actual neutral =>
        have neutral : (Configuration.code first.code bindings first.values actualOutside).needsOwnershipStep = false := actual.needs_no_ownership neutral
        rw [← atCode] at neutral
        cases neutral
      | ownedClose | sharedClose => cases tag
    | application | resume | successor | injection | handled => cases tag
  | installHandler extra created =>
    cases atCode
    subst_vars
    exact ⟨extra, rfl⟩
  | enterProtection | enterRegion | packageOperand | unpackageOperand => cases tag

theorem protection_step_inverts
    {table : Definitions signature algebra program}
    (cleanup : Code signature algebra program (.exit :: context) [] .unit)
    (body : Code signature algebra program context [] answer)
    (bindings : RuntimeEnvironment signature algebra program context)
    (values : RuntimeEnvironment signature algebra program operands)
    (next : Code signature algebra program context (answer :: operands) input)
    (outside : Stack signature algebra program input result)
    (store : ControlHeap signature algebra program)
    (storage : Cells signature algebra (fun context result => Code signature algebra program context [] result))
    (regions : List (Id .region))
    (step : ExecutionStep table
      ⟨⟨store, .code (.protect cleanup body next) bindings values outside⟩, storage, regions⟩ after) :
    ∃ extra,
      let identity := freshObligation table (.protect cleanup body next) bindings values outside store storage extra
      after = ⟨⟨store, .code body bindings .nil
        (.push (.protection identity cleanup bindings) (.push (.returnTo next bindings values) outside))⟩, storage, regions⟩ := by
  generalize atCode : Configuration.code (.protect cleanup body next) bindings values outside = initial at step
  have tag := congrArg Configuration.codeConstructor atCode
  cases step with
  | cell actual =>
    cases actual with
    | ordinary actual neutral =>
      obtain ⟨attachment, computed⟩ := actual.computes_next
      rw [← atCode] at computed
      cases computed
    | allocate | read | write => cases tag
  | control actual =>
    cases actual with
    | ordinary actual neutral =>
      obtain ⟨attachment, computed⟩ := actual.computes_next
      rw [← atCode] at computed
      cases computed
    | @operand context input result beforeStore afterStore bindings first last actualOutside actual =>
      cases actual with
      | ordinary actual neutral =>
        have computed := actual.code_next table ⟨0⟩ actualOutside
        change nextWithAttachment table ⟨0⟩ (.code first.code bindings first.values actualOutside) = _ at computed
        rw [← atCode] at computed
        cases computed
      | ownedClose | sharedClose => cases tag
    | application | resume | successor | injection | handled => cases tag
  | enterProtection extra created =>
    cases atCode
    subst_vars
    exact ⟨extra, rfl⟩
  | installHandler | enterRegion | packageOperand | unpackageOperand => cases tag

theorem region_step_inverts
    {table : Definitions signature algebra program}
    (body : Code signature algebra program (.region :: context) [] answer)
    (bindings : RuntimeEnvironment signature algebra program context)
    (values : RuntimeEnvironment signature algebra program operands)
    (next : Code signature algebra program context (answer :: operands) input)
    (outside : Stack signature algebra program input result)
    (store : ControlHeap signature algebra program)
    (storage : Cells signature algebra (fun context result => Code signature algebra program context [] result))
    (regions : List (Id .region))
    (step : ExecutionStep table
      ⟨⟨store, .code (.enterRegion body next) bindings values outside⟩, storage, regions⟩ after) :
    ∃ extra,
      let identity := freshRegion table (.enterRegion body next) bindings values outside store storage regions extra
      after = ⟨⟨store, .code body (.cons (.datum (.region identity)) bindings) .nil
        (.push (.region identity) (.push (.returnTo next bindings values) outside))⟩, storage, identity :: regions⟩ := by
  generalize atCode : Configuration.code (.enterRegion body next) bindings values outside = initial at step
  have tag := congrArg Configuration.codeConstructor atCode
  cases step with
  | cell actual =>
    cases actual with
    | ordinary actual neutral =>
      obtain ⟨attachment, computed⟩ := actual.computes_next
      rw [← atCode] at computed
      cases computed
    | allocate | read | write => cases tag
  | control actual =>
    cases actual with
    | ordinary actual neutral =>
      obtain ⟨attachment, computed⟩ := actual.computes_next
      rw [← atCode] at computed
      cases computed
    | @operand context input result beforeStore afterStore bindings first last actualOutside actual =>
      cases actual with
      | ordinary actual neutral =>
        have computed := actual.code_next table ⟨0⟩ actualOutside
        change nextWithAttachment table ⟨0⟩ (.code first.code bindings first.values actualOutside) = _ at computed
        rw [← atCode] at computed
        cases computed
      | ownedClose | sharedClose => cases tag
    | application | resume | successor | injection | handled => cases tag
  | enterRegion extra created =>
    cases atCode
    subst_vars
    exact ⟨extra, rfl⟩
  | installHandler | enterProtection | packageOperand | unpackageOperand => cases tag

end BoundaryV2.Generalized.Target

namespace BoundaryV2.Generalized.Defunctionalization

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}
  [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]

theorem cell_read_execution_reflected
    (table : Source.Definitions signature algebra program)
    (reference : Source.Expression signature algebra program context (.cell type))
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (storage : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region))
    {sourceStore evaluated : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (operands : Source.ExpressionEvaluation bindings storage.reservations.custody sourceStore reference (.ok (.cell identity region)) evaluated)
    (stores : ControlHeapRelated evaluated targetStore)
    {sourceOutside : Source.Context signature algebra program type result} {targetOutside : Target.Stack signature algebra program type result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    {final : Target.State signature algebra program result}
    (run : Target.ExecutionSteps (definitions table)
      ⟨⟨targetStore, .code (.cellRead .ret) (environment bindings) (.cons (.cell identity region) .nil) targetOutside⟩, cells storage, regions⟩ count final)
    (head : Target.HeadObservation final.control.configuration observation) :
    ∃ sourceAfter targetAfter remaining, remaining < count ∧
      Source.ExecutionStep table ⟨⟨sourceStore, sourceOutside.plug (.evaluate (.cellRead reference) bindings)⟩, storage, regions⟩ sourceAfter ∧
      ExecutionStateRelated sourceAfter targetAfter ∧ Target.ExecutionSteps (definitions table) targetAfter remaining final := by
  cases run with
  | refl => cases head
  | cons step tail =>
    obtain ⟨targetValue, live, read, afterAt⟩ := Target.cell_read_step_inverts (environment bindings) .nil .ret targetOutside targetStore (cells storage) regions step
    rw [afterAt] at tail
    rw [cells, Cells.readCopy_mapBodies] at read
    obtain ⟨sourceValue, sourceRead, valueAt⟩ := Option.map_eq_some_iff.mp read
    subst targetValue
    obtain ⟨remaining, counted, following⟩ := Target.ordinary_cancel_stateful_observed Target.CallStep.returned rfl tail head
    exact ⟨_, _, remaining, by omega, .cell (.read operands live sourceRead),
      ⟨stores, rfl, rfl, (EntryRelated.returned sourceValue outside).as_program⟩, following⟩

theorem cell_write_execution_reflected
    (table : Source.Definitions signature algebra program)
    (reference : Source.Expression signature algebra program context (.cell type))
    (replacement : Source.Expression signature algebra program context type)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (sourceValue : Source.RuntimeValue signature algebra program type)
    (storage : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region))
    {sourceStore evaluated : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (operands : Source.ArgumentsEvaluation bindings storage.reservations.custody sourceStore (.cons reference (.cons replacement .nil))
      (.ok (.cons (.cell identity region) (.cons sourceValue .nil))) evaluated)
    (stores : ControlHeapRelated evaluated targetStore)
    {sourceOutside : Source.Context signature algebra program .unit result} {targetOutside : Target.Stack signature algebra program .unit result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    {final : Target.State signature algebra program result}
    (run : Target.ExecutionSteps (definitions table)
      ⟨⟨targetStore, .code (.cellWrite .ret) (environment bindings) (.cons (value sourceValue) (.cons (.cell identity region) .nil)) targetOutside⟩,
        cells storage, regions⟩ count final)
    (head : Target.HeadObservation final.control.configuration observation) :
    ∃ sourceAfter targetAfter remaining, remaining < count ∧
      Source.ExecutionStep table ⟨⟨sourceStore, sourceOutside.plug (.evaluate (.cellWrite reference replacement) bindings)⟩, storage, regions⟩ sourceAfter ∧
      ExecutionStateRelated sourceAfter targetAfter ∧ Target.ExecutionSteps (definitions table) targetAfter remaining final := by
  cases run with
  | refl => cases head
  | cons step tail =>
    obtain ⟨targetCells, live, written, afterAt⟩ := Target.cell_write_step_inverts (environment bindings) .nil .ret targetOutside
      targetStore (cells storage) regions (value sourceValue) step
    rw [afterAt] at tail
    rw [cells, value, Cells.writeCopy_mapBodies] at written
    obtain ⟨sourceCells, sourceWrite, cellsAt⟩ := Option.map_eq_some_iff.mp written
    subst targetCells
    obtain ⟨remaining, counted, following⟩ := Target.ordinary_cancel_stateful_observed Target.CallStep.returned rfl tail head
    exact ⟨_, _, remaining, by omega, .cell (.write operands live sourceWrite),
      ⟨stores, rfl, rfl, (EntryRelated.returned (.datum .unit) outside).as_program⟩, following⟩

theorem cell_allocation_execution_reflected
    (table : Source.Definitions signature algebra program)
    (regionExpression : Source.Expression signature algebra program context .region)
    (initializer : Source.Expression signature algebra program context type)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (sourceValue : Source.RuntimeValue signature algebra program type)
    (storage : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region))
    {sourceStore evaluated : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (operands : Source.ArgumentsEvaluation bindings storage.reservations.custody sourceStore (.cons regionExpression (.cons initializer .nil))
      (.ok (.cons (.datum (.region region)) (.cons sourceValue .nil))) evaluated)
    (stores : ControlHeapRelated evaluated targetStore)
    {sourceOutside : Source.Context signature algebra program (.cell type) result} {targetOutside : Target.Stack signature algebra program (.cell type) result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    {final : Target.State signature algebra program result}
    (run : Target.ExecutionSteps (definitions table)
      ⟨⟨targetStore, .code (.cellNew .ret) (environment bindings) (.cons (value sourceValue) (.cons (.datum (.region region)) .nil)) targetOutside⟩,
        cells storage, regions⟩ count final)
    (head : Target.HeadObservation final.control.configuration observation) :
    ∃ sourceAfter targetAfter remaining, remaining < count ∧
      Source.ExecutionStep table ⟨⟨sourceStore, sourceOutside.plug (.evaluate (.cellNew regionExpression initializer) bindings)⟩, storage, regions⟩ sourceAfter ∧
      ExecutionStateRelated sourceAfter targetAfter ∧ Target.ExecutionSteps (definitions table) targetAfter remaining final := by
  cases run with
  | refl => cases head
  | cons step tail =>
    obtain ⟨reserved, fields, live, handoff, afterAt⟩ := Target.cell_allocate_step_inverts (environment bindings) .nil .ret targetOutside
      targetStore (cells storage) regions (value sourceValue) step
    rw [afterAt] at tail
    have sourceHandoff := handoff.of_map (fun _ _ body => computation body) sourceValue
    rw [← stores.fields] at sourceHandoff
    have allocated := Cells.allocate_mapBodies (fun _ _ body => computation body) region sourceValue storage reserved
    obtain ⟨remaining, counted, following⟩ := Target.ordinary_cancel_stateful_observed Target.CallStep.returned rfl tail head
    refine ⟨_, _, remaining, by omega, .cell (.allocate (reserved := reserved) operands live sourceHandoff), ?_, following⟩
    refine ⟨⟨rfl, stores.controls, stores.disposing⟩, allocated.2, rfl, ?_⟩
    have identityAt : (Cells.allocate region (value sourceValue) (cells storage) reserved).identity =
        (Cells.allocate region sourceValue storage reserved).identity := allocated.1
    dsimp only
    rw [identityAt]
    exact (EntryRelated.returned (.cell (Cells.allocate region sourceValue storage reserved).identity region) outside).as_program

theorem package_execution_reflected
    (table : Source.Definitions signature algebra program)
    (expression : Source.Expression signature algebra program context content)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (sourceValue : Source.RuntimeValue signature algebra program content)
    (storage : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region))
    {sourceStore evaluated : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (operands : Source.ExpressionEvaluation bindings storage.reservations.custody sourceStore expression (.ok sourceValue) evaluated)
    (stores : ControlHeapRelated evaluated targetStore)
    {sourceOutside : Source.Context signature algebra program (.package content) result} {targetOutside : Target.Stack signature algebra program (.package content) result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    {final : Target.State signature algebra program result}
    (run : Target.ExecutionSteps (definitions table)
      ⟨⟨targetStore, .code (.package .ret) (environment bindings) (.cons (value sourceValue) .nil) targetOutside⟩, cells storage, regions⟩ count final)
    (head : Target.HeadObservation final.control.configuration observation) :
    ∃ sourceAfter targetAfter remaining, remaining < count ∧
      Source.ExecutionStep table ⟨⟨sourceStore, sourceOutside.plug (.evaluate (.package expression) bindings)⟩, storage, regions⟩ sourceAfter ∧
      ExecutionStateRelated sourceAfter targetAfter ∧ Target.ExecutionSteps (definitions table) targetAfter remaining final := by
  cases run with
  | refl => cases head
  | cons step tail =>
    obtain ⟨owner, moved, handoff, afterAt⟩ := Target.package_step_inverts (environment bindings) .nil .ret targetOutside targetStore (cells storage) regions (value sourceValue) step
    rw [afterAt] at tail
    have sourceHandoff := handoff.of_map (fun _ _ body => computation body) sourceValue
    rw [← stores.fields] at sourceHandoff
    have reservations : (cells storage).reservations.custody = storage.reservations.custody :=
      congrArg UseScope.ReservedNames.custody (Cells.reservations_mapBodies (fun _ _ body => computation body) storage)
    have matched := package_creation_corresponds
      (Before := Source.Computation signature algebra program)
      (After := fun context result => Target.Code signature algebra program context [] result)
      (UseScope.PackedControlRelated controlPayloadRelated) (fun _ _ body => computation body)
      sourceValue owner storage.reservations.custody stores sourceHandoff handoff
    obtain ⟨remaining, counted, following⟩ := Target.ordinary_cancel_stateful_observed Target.CallStep.returned rfl tail head
    rw [reservations] at following
    refine ⟨_, _, remaining, by omega, .packageOperand owner sourceHandoff operands,
      ⟨matched.2.2, rfl, rfl, ?_⟩, following⟩
    have valuesAt : (createPackage (value sourceValue) owner targetStore moved handoff storage.reservations.custody).value =
        value (createPackage sourceValue owner evaluated moved sourceHandoff storage.reservations.custody).value := matched.2.1
    dsimp only
    rw [valuesAt]
    exact (EntryRelated.returned _ outside).as_program

theorem unpackage_execution_reflected
    (table : Source.Definitions signature algebra program)
    (expression : Source.Expression signature algebra program context (.package content))
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (sourceValue : Source.RuntimeValue signature algebra program content) (token : Id .custody) (owner : Owner)
    (storage : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region))
    {sourceStore evaluated : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (operands : Source.ExpressionEvaluation bindings storage.reservations.custody sourceStore expression (.ok (.package token owner sourceValue)) evaluated)
    (stores : ControlHeapRelated evaluated targetStore)
    {sourceOutside : Source.Context signature algebra program content result} {targetOutside : Target.Stack signature algebra program content result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    {final : Target.State signature algebra program result}
    (run : Target.ExecutionSteps (definitions table)
      ⟨⟨targetStore, .code (.unpackage .ret) (environment bindings) (.cons (.package token owner (value sourceValue)) .nil) targetOutside⟩,
        cells storage, regions⟩ count final)
    (head : Target.HeadObservation final.control.configuration observation) :
    ∃ sourceAfter targetAfter remaining, remaining < count ∧
      Source.ExecutionStep table ⟨⟨sourceStore, sourceOutside.plug (.evaluate (.unpackage expression) bindings)⟩, storage, regions⟩ sourceAfter ∧
      ExecutionStateRelated sourceAfter targetAfter ∧ Target.ExecutionSteps (definitions table) targetAfter remaining final := by
  cases run with
  | refl => cases head
  | cons step tail =>
    obtain ⟨fields, handoff, afterAt⟩ := Target.unpackage_step_inverts (environment bindings) .nil .ret targetOutside
      targetStore (cells storage) regions (value sourceValue) token owner step
    rw [afterAt] at tail
    have sourceHandoff := handoff.of_map (fun _ _ body => computation body) sourceValue
    rw [← stores.fields] at sourceHandoff
    obtain ⟨remaining, counted, following⟩ := Target.ordinary_cancel_stateful_observed Target.CallStep.returned rfl tail head
    exact ⟨_, _, remaining, by omega, .unpackageOperand operands sourceHandoff,
      ⟨⟨rfl, stores.controls, stores.disposing⟩, rfl, rfl, (EntryRelated.returned sourceValue outside).as_program⟩, following⟩

omit [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)] in
theorem corresponding_target_acceptance {relation : A → B → Prop} {acceptedValue : B}
    (matched : Option.Rel relation source target) (accepted : target = some acceptedValue) :
    ∃ original, source = some original ∧ relation original acceptedValue := by
  cases matched with
  | none => cases accepted
  | some proof => cases accepted; exact ⟨_, rfl, proof⟩

theorem resume_execution_reflected
    (table : Source.Definitions signature algebra program)
    (continuation : Source.Expression signature algebra program context (.continuation mode use effect input answer))
    (response : Source.Expression signature algebra program context input)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (inputValue : Source.RuntimeValue signature algebra program input) (view : UseScope.ControlView)
    (storage : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region))
    {sourceStore evaluated : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (operands : Source.ArgumentsEvaluation bindings storage.reservations.custody sourceStore (.cons continuation (.cons response .nil))
      (.ok (.cons (.continuation view.identity (some (view.authority, view.owner))) (.cons inputValue .nil))) evaluated)
    (stores : ControlHeapRelated evaluated targetStore)
    {sourceOutside : Source.Context signature algebra program answer result} {targetOutside : Target.Stack signature algebra program answer result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    {final : Target.State signature algebra program result}
    (run : Target.ExecutionSteps (definitions table)
      ⟨⟨targetStore, .code (.resume (mode := mode) (effect := effect) (use := use) .ret) (environment bindings)
        (.cons (value inputValue) (.cons (.continuation view.identity (some (view.authority, view.owner))) .nil)) targetOutside⟩,
        cells storage, regions⟩ count final)
    (head : Target.HeadObservation final.control.configuration observation) :
    ∃ sourceAfter targetAfter remaining, remaining < count ∧
      Source.ExecutionStep table ⟨⟨sourceStore, sourceOutside.plug (.evaluate (.resume continuation response) bindings)⟩, storage, regions⟩ sourceAfter ∧
      ExecutionStateRelated sourceAfter targetAfter ∧ Target.ExecutionSteps (definitions table) targetAfter remaining final := by
  cases run with
  | refl => cases head
  | cons step tail =>
    obtain ⟨oneShot, targetControl, useAt, accepted, afterAt⟩ := Target.resume_step_inverts (environment bindings) .nil .ret targetOutside
      targetStore (cells storage) regions mode effect use view (value inputValue) step
    subst use
    obtain ⟨sourceControl, sourceAccepted, matched⟩ := corresponding_target_acceptance
      (resume_control_corresponds stores ⟨mode, effect, input, answer⟩ view inputValue (.passthrough bindings outside)) accepted
    rw [afterAt] at tail
    exact ⟨_, _, _, by omega, .control (.resume (use := oneShot) operands sourceAccepted),
      ⟨matched.store, rfl, rfl, matched.entry.as_program⟩, tail⟩

theorem successor_execution_reflected
    (table : Source.Definitions signature algebra program)
    (continuation : Source.Expression signature algebra program context (.continuation .shallow use effect input body))
    (response : Source.Expression signature algebra program context input)
    (returned : Source.Computation signature algebra program (body :: context) answer)
    (clauses : Source.Clauses signature algebra program effect .deep context body answer)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (inputValue : Source.RuntimeValue signature algebra program input) (view : UseScope.ControlView)
    (storage : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region))
    {sourceStore evaluated : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (operands : Source.ArgumentsEvaluation bindings storage.reservations.custody sourceStore (.cons continuation (.cons response .nil))
      (.ok (.cons (.continuation view.identity (some (view.authority, view.owner))) (.cons inputValue .nil))) evaluated)
    (stores : ControlHeapRelated evaluated targetStore)
    {sourceOutside : Source.Context signature algebra program answer result} {targetOutside : Target.Stack signature algebra program answer result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    {final : Target.State signature algebra program result}
    (run : Target.ExecutionSteps (definitions table)
      ⟨⟨targetStore, .code (.replaceHandler (use := use) effect (computation returned) (Defunctionalization.clauses clauses) .ret) (environment bindings)
        (.cons (value inputValue) (.cons (.continuation view.identity (some (view.authority, view.owner))) .nil)) targetOutside⟩,
        cells storage, regions⟩ count final)
    (head : Target.HeadObservation final.control.configuration observation) :
    ∃ sourceAfter targetAfter remaining, remaining < count ∧
      Source.ExecutionStep table ⟨⟨sourceStore, sourceOutside.plug (.evaluate (.resumeWith effect continuation response returned clauses) bindings)⟩, storage, regions⟩ sourceAfter ∧
      ExecutionStateRelated sourceAfter targetAfter ∧ Target.ExecutionSteps (definitions table) targetAfter remaining final := by
  cases run with
  | refl => cases head
  | cons step tail =>
    obtain ⟨oneShot, targetControl, useAt, accepted, afterAt⟩ := Target.successor_step_inverts (environment bindings) .nil .ret targetOutside
      targetStore (cells storage) regions effect use (computation returned) (Defunctionalization.clauses clauses) view (value inputValue) step
    subst use
    obtain ⟨sourceControl, sourceAccepted, matched⟩ := corresponding_target_acceptance
      (successor_control_corresponds stores view inputValue returned clauses bindings (.passthrough bindings outside)) accepted
    rw [afterAt] at tail
    exact ⟨_, _, _, by omega, .control (.successor (use := oneShot) operands sourceAccepted),
      ⟨matched.store, rfl, rfl, matched.entry.as_program⟩, tail⟩

theorem injection_execution_reflected
    (table : Source.Definitions signature algebra program)
    (continuation : Source.Expression signature algebra program context (.continuation mode use effect input answer))
    (injected : Source.Expression signature algebra program context (.computation bodyUse [] input))
    (body : Source.Computation signature algebra program capturedTypes input)
    (captured : Source.RuntimeEnvironment signature algebra program capturedTypes) (authority : Option (Id .custody × Owner))
    (bindings : Source.RuntimeEnvironment signature algebra program context) (view : UseScope.ControlView)
    (storage : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region))
    {sourceStore evaluated : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (operands : Source.ArgumentsEvaluation bindings storage.reservations.custody sourceStore (.cons continuation (.cons injected .nil))
      (.ok (.cons (.continuation view.identity (some (view.authority, view.owner))) (.cons (.closure body captured authority) .nil))) evaluated)
    (stores : ControlHeapRelated evaluated targetStore)
    {sourceOutside : Source.Context signature algebra program answer result} {targetOutside : Target.Stack signature algebra program answer result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    {final : Target.State signature algebra program result}
    (run : Target.ExecutionSteps (definitions table)
      ⟨⟨targetStore, .code (.inject (mode := mode) (effect := effect) (use := use) (useBody := bodyUse) .ret) (environment bindings)
        (.cons (.closure (computation body) (environment captured) authority) (.cons (.continuation view.identity (some (view.authority, view.owner))) .nil)) targetOutside⟩,
        cells storage, regions⟩ count final)
    (head : Target.HeadObservation final.control.configuration observation) :
    ∃ sourceAfter targetAfter remaining, remaining < count ∧
      Source.ExecutionStep table ⟨⟨sourceStore, sourceOutside.plug (.evaluate (.inject continuation injected) bindings)⟩, storage, regions⟩ sourceAfter ∧
      ExecutionStateRelated sourceAfter targetAfter ∧ Target.ExecutionSteps (definitions table) targetAfter remaining final := by
  cases run with
  | refl => cases head
  | cons step tail =>
    obtain ⟨oneShot, fields, targetControl, useAt, handoff, accepted, afterAt⟩ := Target.injection_step_inverts (environment bindings) .nil .ret targetOutside
      targetStore (cells storage) regions mode effect use view bodyUse (computation body) (environment captured) authority step
    subst use
    have sourceHandoff := handoff.of_map (fun _ _ body => computation body) captured
    rw [← stores.fields] at sourceHandoff
    have moved : ControlHeapRelated { evaluated with fields := fields } { targetStore with fields := fields } :=
      ⟨rfl, stores.controls, stores.disposing⟩
    obtain ⟨sourceControl, sourceAccepted, matched⟩ := corresponding_target_acceptance
      (inject_control_corresponds moved ⟨mode, effect, input, answer⟩ view body captured (.passthrough bindings outside)) accepted
    rw [afterAt] at tail
    exact ⟨_, _, _, by omega, .control (.injection (use := oneShot) operands sourceHandoff sourceAccepted),
      ⟨matched.store, rfl, rfl, matched.entry.as_program⟩, tail⟩

theorem application_execution_reflected
    (table : Source.Definitions signature algebra program)
    (function : Source.Expression signature algebra program context (.computation use parameters answer))
    (arguments : Source.Arguments signature algebra program context parameters)
    (body : Source.Computation signature algebra program (parameters ++ capturedTypes) answer)
    (captured : Source.RuntimeEnvironment signature algebra program capturedTypes)
    (actual : Source.RuntimeEnvironment signature algebra program parameters) (authority : Option (Id .custody × Owner))
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (storage : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region))
    {sourceStore evaluated : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (operands : Source.ArgumentsEvaluation bindings storage.reservations.custody sourceStore (.cons function arguments)
      (.ok (.cons (.closure body captured authority) actual)) evaluated)
    (stores : ControlHeapRelated evaluated targetStore)
    {sourceOutside : Source.Context signature algebra program answer result} {targetOutside : Target.Stack signature algebra program answer result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    {final : Target.State signature algebra program result}
    (run : Target.ExecutionSteps (definitions table)
      ⟨⟨targetStore, .code (.callClosure (use := use) .ret) (environment bindings)
        ((environment actual).pushReverse (.cons (.closure (computation body) (environment captured) authority) .nil)) targetOutside⟩,
        cells storage, regions⟩ count final)
    (head : Target.HeadObservation final.control.configuration observation) :
    ∃ sourceAfter targetAfter remaining, remaining < count ∧
      Source.ExecutionStep table ⟨⟨sourceStore, sourceOutside.plug (.evaluate (.apply function arguments) bindings)⟩, storage, regions⟩ sourceAfter ∧
      ExecutionStateRelated sourceAfter targetAfter ∧ Target.ExecutionSteps (definitions table) targetAfter remaining final := by
  cases run with
  | refl => cases head
  | cons step tail =>
    obtain ⟨fields, handoff, afterAt⟩ := Target.application_step_inverts (environment bindings) .nil .ret targetOutside
      targetStore (cells storage) regions use (computation body) (environment captured) (environment actual) authority step
    have sourceHandoff := handoff.of_map (fun _ _ body => computation body) captured
    rw [← stores.fields] at sourceHandoff
    rw [afterAt] at tail
    refine ⟨_, _, _, by omega, .applicationOperands operands sourceHandoff,
      ⟨⟨rfl, stores.controls, stores.disposing⟩, rfl, rfl, ?_⟩, tail⟩
    simpa only [Source.enterClosure, captured_arguments_keep_order] using
      (EntryRelated.evaluate body (actual.append captured) (.passthrough bindings outside)).as_program

theorem installation_execution_reflected
    (table : Source.Definitions signature algebra program) (effect : signature.Effect) (mode : Mode)
    (returned : Source.Computation signature algebra program (bodyType :: context) answer)
    (clauses : Source.Clauses signature algebra program effect mode context bodyType answer)
    (body : Source.Computation signature algebra program (.capability effect :: context) bodyType)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (storage : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region))
    {sourceStore : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (stores : ControlHeapRelated sourceStore targetStore)
    {sourceOutside : Source.Context signature algebra program answer result} {targetOutside : Target.Stack signature algebra program answer result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    {final : Target.State signature algebra program result}
    (run : Target.ExecutionSteps (definitions table)
      ⟨⟨targetStore, .code (computation (.handle effect mode returned clauses body)) (environment bindings) .nil targetOutside⟩,
        cells storage, regions⟩ count final)
    (head : Target.HeadObservation final.control.configuration observation) :
    ∃ sourceAfter targetAfter remaining, remaining < count ∧
      Source.ExecutionStep table ⟨⟨sourceStore, sourceOutside.plug (.evaluate (.handle effect mode returned clauses body) bindings)⟩, storage, regions⟩ sourceAfter ∧
      ExecutionStateRelated sourceAfter targetAfter ∧ Target.ExecutionSteps (definitions table) targetAfter remaining final := by
  cases run with
  | refl => cases head
  | cons step tail =>
    obtain ⟨extra, afterAt⟩ := Target.installation_step_inverts effect mode (computation returned) (Defunctionalization.clauses clauses)
      (computation body) (environment bindings) .nil .ret targetOutside targetStore (cells storage) regions step
    obtain ⟨sourceStep, _, matched⟩ := compiled_fresh_handler table effect mode returned clauses body bindings outside stores storage regions extra
    rw [afterAt] at tail
    exact ⟨_, _, _, by omega, sourceStep, matched.as_execution, tail⟩

theorem protection_execution_reflected
    (table : Source.Definitions signature algebra program)
    (cleanup : Source.Computation signature algebra program (.exit :: context) .unit)
    (body : Source.Computation signature algebra program context answer)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (storage : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region))
    {sourceStore : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (stores : ControlHeapRelated sourceStore targetStore)
    {sourceOutside : Source.Context signature algebra program answer result} {targetOutside : Target.Stack signature algebra program answer result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    {final : Target.State signature algebra program result}
    (run : Target.ExecutionSteps (definitions table)
      ⟨⟨targetStore, .code (computation (.protect cleanup body)) (environment bindings) .nil targetOutside⟩,
        cells storage, regions⟩ count final)
    (head : Target.HeadObservation final.control.configuration observation) :
    ∃ sourceAfter targetAfter remaining, remaining < count ∧
      Source.ExecutionStep table ⟨⟨sourceStore, sourceOutside.plug (.evaluate (.protect cleanup body) bindings)⟩, storage, regions⟩ sourceAfter ∧
      ExecutionStateRelated sourceAfter targetAfter ∧ Target.ExecutionSteps (definitions table) targetAfter remaining final := by
  cases run with
  | refl => cases head
  | cons step tail =>
    obtain ⟨extra, afterAt⟩ := Target.protection_step_inverts (computation cleanup) (computation body)
      (environment bindings) .nil .ret targetOutside targetStore (cells storage) regions step
    obtain ⟨sourceStep, _, matched⟩ := compiled_protection_entry table cleanup body bindings outside stores storage regions extra
    rw [afterAt] at tail
    exact ⟨_, _, _, by omega, sourceStep, matched.as_execution, tail⟩

theorem region_execution_reflected
    (table : Source.Definitions signature algebra program)
    (body : Source.Computation signature algebra program (.region :: context) answer)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (storage : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region))
    {sourceStore : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (stores : ControlHeapRelated sourceStore targetStore)
    {sourceOutside : Source.Context signature algebra program answer result} {targetOutside : Target.Stack signature algebra program answer result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    {final : Target.State signature algebra program result}
    (run : Target.ExecutionSteps (definitions table)
      ⟨⟨targetStore, .code (computation (.withRegion body)) (environment bindings) .nil targetOutside⟩,
        cells storage, regions⟩ count final)
    (head : Target.HeadObservation final.control.configuration observation) :
    ∃ sourceAfter targetAfter remaining, remaining < count ∧
      Source.ExecutionStep table ⟨⟨sourceStore, sourceOutside.plug (.evaluate (.withRegion body) bindings)⟩, storage, regions⟩ sourceAfter ∧
      ExecutionStateRelated sourceAfter targetAfter ∧ Target.ExecutionSteps (definitions table) targetAfter remaining final := by
  cases run with
  | refl => cases head
  | cons step tail =>
    obtain ⟨extra, afterAt⟩ := Target.region_step_inverts (computation body)
      (environment bindings) .nil .ret targetOutside targetStore (cells storage) regions step
    obtain ⟨sourceStep, _, matched⟩ := compiled_region_entry table body bindings outside stores storage regions extra
    rw [afterAt] at tail
    exact ⟨_, _, _, by omega, sourceStep, matched.as_execution, tail⟩

/-- Compose arbitrary function/argument evaluation with actual closure entry.
The source operands and its handoff are both recovered from the target run. -/
theorem applied_computation_step_reflected
    (table : Source.Definitions signature algebra program)
    (function : Source.Expression signature algebra program context (.computation use parameters answer))
    (arguments : Source.Arguments signature algebra program context parameters)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (storage : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region))
    {sourceStore : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (stores : ControlHeapRelated sourceStore targetStore)
    {sourceOutside : Source.Context signature algebra program answer result} {targetOutside : Target.Stack signature algebra program answer result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    {final : Target.State signature algebra program result}
    (run : Target.ExecutionSteps (definitions table)
      ⟨⟨targetStore, .code (computation (.apply function arguments)) (environment bindings) .nil targetOutside⟩,
        cells storage, regions⟩ count final)
    (head : Target.HeadObservation final.control.configuration observation) :
    ∃ sourceAfter targetAfter remaining, remaining < count ∧
      Source.ExecutionStep table ⟨⟨sourceStore, sourceOutside.plug (.evaluate (.apply function arguments) bindings)⟩, storage, regions⟩ sourceAfter ∧
      ExecutionStateRelated sourceAfter targetAfter ∧ Target.ExecutionSteps (definitions table) targetAfter remaining final := by
  obtain ⟨outcome, sourceEvaluated, targetEvaluated, remaining, operands, evaluatedRelated, bounded, faultLess, tail⟩ :=
    computation_operands_observing_run_reflected table (.apply function arguments) bindings storage regions stores targetOutside run head
  cases outcome with
  | error fault =>
    exact ⟨_, _, remaining, faultLess fault rfl, .operandFault operands,
      ⟨evaluatedRelated, rfl, rfl, (EntryRelated.failed fault outside).as_program⟩, tail⟩
  | ok values =>
    change Source.ArgumentsEvaluation bindings storage.reservations.custody sourceStore (.cons function arguments) (.ok values) sourceEvaluated at operands
    cases values with
    | cons closure actual =>
      cases closure with
      | datum datum => cases datum
      | closure body captured authority =>
        have atCall : Target.Configuration.code (operandTail (.apply function arguments)) (environment bindings)
            ((environment (.cons (.closure body captured authority) actual)).pushReverse .nil) targetOutside =
            .code (.callClosure (use := use) (parameters := parameters) .ret) (environment bindings)
              ((environment actual).pushReverse (.cons (.closure (computation body) (environment captured) authority) .nil)) targetOutside := by
          simp only [operandTail, environment, Environment.map, Value.map, Environment.pushReverse]
          apply configuration_reindex
          simp [List.reverse_cons]
        change Target.ExecutionSteps (definitions table)
          ⟨⟨targetEvaluated, .code (operandTail (.apply function arguments)) (environment bindings)
            ((environment (.cons (.closure body captured authority) actual)).pushReverse .nil) targetOutside⟩,
            cells storage, regions⟩ remaining final at tail
        rw [atCall] at tail
        obtain ⟨sourceAfter, targetAfter, rest, less, sourceStep, related, following⟩ :=
          application_execution_reflected table function arguments body captured actual authority bindings storage regions
            operands evaluatedRelated outside tail head
        exact ⟨sourceAfter, targetAfter, rest, by omega, sourceStep, related, following⟩

end BoundaryV2.Generalized.Defunctionalization
