import BoundaryV2.GraphOrigins

namespace BoundaryV2.Profile.Graph.Admission

def invocationEffect (program : Target.Program) (facts : Target.Admission.EffectFacts)
    (source : Target.Block) (effect : EffectId .target) : Bool := ((do
  match source.terminator with
  | .call function _ _ => pure ((← program.functions[function.value]?).effects.contains effect)
  | .apply closure _ _ | .withRegion _ closure _ _ =>
    pure ((← Target.Admission.computation program (← slotType source closure)).effects.contains effect)
  | .handle selected closure _ _ _ =>
    let definition ← program.handlers[selected.value]?
    let body ← Target.Admission.computation program (← slotType source closure)
    pure (definition.effects.contains effect || (body.effects.contains effect &&
      !Target.Admission.discharged facts definition body effect))
  | .resumeValue token _ _ | .resumeComputation token _ _ | .dispose token _ =>
    pure ((← Target.Admission.resumption program (← slotType source token)).effects.contains effect)
  | .resumeWith token _ selected _ _ =>
    let signature ← Target.Admission.resumption program (← slotType source token)
    let definition ← program.handlers[selected.value]?
    pure (definition.effects.contains effect || (signature.effects.contains effect &&
      (!Target.Admission.covers definition effect || signature.escaping.contains effect)))
  | .perform operation => pure ((← program.effects[operation.effect.value]?).useSiteEffects.contains effect)
  | .protect body cleanup _ _ _ _ =>
    let body ← Target.Admission.computation program (← slotType source body)
    let cleanup ← Target.Admission.computation program (← slotType source cleanup)
    pure (body.effects.contains effect || cleanup.effects.contains effect)
  | _ => pure false) : Option Bool).getD false

def scopeEffect (program : Target.Program) (source : BlockId) (cleanup : Bool) (effect : EffectId .target) : Bool := ((do
  let source ← block program source
  let operand ← match source.terminator with
    | .withRegion _ body _ _ => some body
    | .protect body cleanupBody _ _ _ _ => some (if cleanup then cleanupBody else body)
    | _ => none
  pure ((← Target.Admission.computation program (← slotType source operand)).effects.contains effect)) : Option Bool).getD false

/-- An effect is permitted by the first enclosing interface that supplies an
answer. Active attachments can defer to their caller; suspended attachments
must justify the effect through their own signature and retained capabilities. -/
def allowsEffectUsing (program : Target.Program) (state : State) (facts : Target.Admission.EffectFacts)
    (isLocal : NodeId → EffectId .target → Bool) (remaining : List NodeId) (parent : Option NodeId) (effect : EffectId .target) : Bool :=
  match parent with
  | none => program.functions[program.roots.entry.value]?.any (fun entry => entry.effects.contains effect)
  | some reference =>
    if _fresh : reference ∈ remaining then ((do
      let record ← node state reference
      match record with
      | .continuation saved => pure (invocationEffect program facts (← block program saved.sourceBlock) effect)
      | .attachment activation _ caller phase _ =>
        let definition ← handler program state activation
        let permission ← match phase with
          | .active => some (none : Option Bool)
          | .suspended => do
            let signature ← Target.Admission.resumption program (← capturedSchema state reference)
            pure (if signature.effects.contains effect then some true
              else if signature.mode != .deep then some false else none)
        match permission with
        | some permitted => pure permitted
        | none =>
          if definition.clauses.any (fun clause => clause.effect == effect) && isLocal reference effect then pure true
          else if phase == .suspended then pure false
          else pure (allowsEffectUsing program state facts isLocal (remaining.erase reference) caller effect)
      | .regionScope source _ _ | .protection source _ _ _ _ _ => pure (scopeEffect program source false effect)
      | .cleanupReturn obligation _ _ =>
        let .obligation source _ _ _ ← node state obligation.node | none
        pure (scopeEffect program source true effect)
      | .injection continuation =>
        let .continuation saved ← node state continuation | none
        let source ← block program saved.sourceBlock
        let .perform operation := source.terminator | none
        pure ((← program.effects[operation.effect.value]?).useSiteEffects.contains effect)
      | .disposalReturn schema _ _ => pure ((← Target.Admission.resumption program schema).effects.contains effect)
      | _ => pure false) : Option Bool).getD false
    else false
termination_by remaining.length
decreasing_by
  have size := List.length_erase_of_mem _fresh
  have positive := List.length_pos_of_mem _fresh
  omega

def allowsEffect (program : Target.Program) (state : State) (facts : Target.Admission.EffectFacts) :=
  allowsEffectUsing program state facts (localEffect program state facts)

def requireEffectsUsing (program : Target.Program) (state : State) (facts : Target.Admission.EffectFacts)
    (isLocal : NodeId → EffectId .target → Bool) (parent : Option NodeId) (effects : List (EffectId .target)) : Bool :=
  effects.all (allowsEffectUsing program state facts isLocal (inventory state) parent)

def requireEffects (program : Target.Program) (state : State) (facts : Target.Admission.EffectFacts) :=
  requireEffectsUsing program state facts (localEffect program state facts)

def recordEffectsUsing (program : Target.Program) (state : State) (facts : Target.Admission.EffectFacts)
    (isLocal : NodeId → EffectId .target → Bool) (index : Nat) (record : Node) : Bool := ((do
  match record with
  | .control control =>
    let source ← block program control.block
    pure (requireEffectsUsing program state facts isLocal control.parent (← program.functions[source.function.value]?).effects)
  | .continuation saved =>
    let source ← block program saved.sourceBlock
    pure (requireEffectsUsing program state facts isLocal saved.parent (← program.functions[source.function.value]?).effects)
  | .attachment activation _ parent phase _ =>
    let definition ← handler program state activation
    match phase with
    | .active => pure (requireEffectsUsing program state facts isLocal parent definition.effects)
    | .suspended =>
      let signature ← Target.Admission.resumption program (← capturedSchema state ⟨index⟩)
      pure (signature.mode != .deep || definition.effects.all signature.effects.contains)
  | _ => pure true) : Option Bool).getD false

def recordEffectsValid (program : Target.Program) (state : State) (facts : Target.Admission.EffectFacts) :=
  recordEffectsUsing program state facts (localEffect program state facts)

def effectsValidWith (program : Target.Program) (state : State) (facts : Target.Admission.EffectFacts) : Bool :=
  let table := originTable program state facts
  state.nodes.zipIdx.all (fun (record, index) =>
    recordEffectsUsing program state facts (localEffectFromTable program state facts table) index record)

theorem effect_origin_sharing_exact (program : Target.Program) (state : State) (facts : Target.Admission.EffectFacts) :
    effectsValidWith program state facts =
      state.nodes.zipIdx.all (fun (record, index) => recordEffectsValid program state facts index record) := by
  have same : localEffectFromTable program state facts (originTable program state facts) = localEffect program state facts := by
    funext scope effect
    exact origin_table_preserves_local_permission program state facts scope effect
  simp only [effectsValidWith, same]
  rfl

def effectsValid (program : Target.Program) (state : State) : Bool :=
  effectsValidWith program state (Target.Admission.effectFacts program)

theorem required_effect_is_permitted (program : Target.Program) (state : State) (facts : Target.Admission.EffectFacts)
    (parent : Option NodeId) (effects : List (EffectId .target)) (effect : EffectId .target)
    (accepted : requireEffects program state facts parent effects = true) (member : effect ∈ effects) :
    allowsEffect program state facts (inventory state) parent effect = true := List.all_eq_true.mp accepted effect member

theorem outermost_effect_uses_entry_interface (program : Target.Program) (state : State)
    (facts : Target.Admission.EffectFacts) (remaining : List NodeId) (effect : EffectId .target) :
    allowsEffect program state facts remaining none effect = true ↔
      ∃ entry, program.functions[program.roots.entry.value]? = some entry ∧ effect ∈ entry.effects := by
  simp [allowsEffect, allowsEffectUsing, Option.any_eq_true]

end BoundaryV2.Profile.Graph.Admission
