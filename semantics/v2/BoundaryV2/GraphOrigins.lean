import BoundaryV2.GraphCapture
import BoundaryV2.FiniteDependency

namespace BoundaryV2.Profile.Graph.Admission

/-- All physical value fields, including values in dormant captures and cleanup
records. Following node references is the separate origin relation below. -/
def recordValues : Node → List Value
  | .control control => control.arguments
  | .continuation saved => saved.arguments.filterMap id
  | .handler _ values _ _ | .environment values _ | .aggregate _ _ values
  | .disposalReturn _ _ values | .unwind _ values => values
  | .cell _ _ value => value.toList
  | .oneShot capture | .multiTemplate capture => capture.useSiteCapabilities
  | .package _ value | .resource _ value | .pending _ value _ _ => [value]
  | .obligation _ cleanup resource status => cleanup.toList ++ resource.toList ++
      (match status with | .failed value => [value] | _ => [])
  | .exit exit => (match exit.reason with | .normal value | .failure value => [value] | _ => []) ++
      exit.cleanupFailures ++ exit.discarded
  | .attachment .. | .region .. | .regionScope .. | .injection _ | .protection ..
  | .cleanupReturn .. | .branch .. | .computation .. | .borrow .. => []

def frameChild (state : State) (parent : NodeId) : Option NodeId :=
  (state.nodes.zipIdx.find? (fun (record, _) => (nodeEdges record).any (fun edge =>
    edge.role == .frame && edge.target == parent))).map (fun (_, index) => ⟨index⟩)

def capturedSchema (state : State) (delimiter : NodeId) : Option (SchemaId .target) :=
  ((capturedDelimiters state).find? (fun pair => pair.1 == delimiter)).map Prod.snd

structure OriginInput where
  exposed : Bool := false
  dependencies : List NodeId := []
  deriving DecidableEq, Repr

def OriginInput.merge (left right : OriginInput) : OriginInput :=
  ⟨left.exposed || right.exposed, left.dependencies ++ right.dependencies⟩

def valueOrigin (program : Target.Program) (effect : EffectId .target) (origin : NodeId) (value : Value) : OriginInput :=
  match program.schemas[value.schema.value]? with
  | some (.internal (.capability nominal)) =>
    ⟨nominal == effect && (match value.body with | .reference reference => reference == origin | _ => false), []⟩
  | _ => match value.body with
    | .reference reference => ⟨false, [reference]⟩
    | .owned reference => ⟨false, [reference.node]⟩
    | _ => {}

def valuesOrigin (program : Target.Program) (effect : EffectId .target) (origin : NodeId) (values : List Value) : OriginInput :=
  values.foldl (fun prior value => prior.merge (valueOrigin program effect origin value)) {}

def childOrigin (program : Target.Program) (state : State) (effect : EffectId .target)
    (origin parent : NodeId) (mask : Option NodeId) : OriginInput :=
  if mask.any (containsScope state (some origin)) then {} else
  match frameChild state parent with
  | none => {}
  | some child => match node state child with
    | some (.oneShot capture) | some (.multiTemplate capture) => valuesOrigin program effect origin capture.useSiteCapabilities
    | some (.pending ..) => {}
    | some _ => ⟨false, [child]⟩
    | none => ⟨true, []⟩

def originInput (program : Target.Program) (state : State) (effect : EffectId .target)
    (origin reference : NodeId) : OriginInput := ((do
  let record ← node state reference
  match record with
  | .attachment activation _ _ phase _ =>
    let definition ← handler program state activation
    let reinstated ← match phase with
      | .active => some true
      | .suspended => do
        let signature ← Target.Admission.resumption program (← capturedSchema state reference)
        pure (signature.mode == .deep)
    let mask := if reinstated && definition.clauses.any (fun clause => clause.effect == effect) then some reference else none
    pure ((childOrigin program state effect origin reference mask).merge
      ⟨false, if reinstated then [activation] else []⟩)
  | .oneShot capture | .multiTemplate capture => pure ⟨false, [capture.delimiter]⟩
  | _ =>
    let explicit := match record with
      | .computation _ environment => [environment]
      | .protection _ obligation _ _ _ _ => [obligation.node]
      | .cleanupReturn _ _ exit => [exit]
      | .borrow _ resource _ => [resource]
      | .exit exit => exit.outer.toList
      | _ => []
    pure ((⟨false, explicit⟩ : OriginInput).merge (valuesOrigin program effect origin (recordValues record))
      |>.merge (childOrigin program state effect origin reference none))) : Option OriginInput).getD ⟨true, []⟩

def originDirect (program : Target.Program) (state : State) (effect : EffectId .target)
    (origin reference : NodeId) : Bool := (originInput program state effect origin reference).exposed
def originDependencies (program : Target.Program) (state : State) (effect : EffectId .target)
    (origin reference : NodeId) : List NodeId := (originInput program state effect origin reference).dependencies

abbrev OriginReaches (program : Target.Program) (state : State) (effect : EffectId .target) (origin : NodeId) :=
  BoundaryV2.FiniteDependency.Depends (originDirect program state effect origin) (originDependencies program state effect origin)

def originInputs (program : Target.Program) (state : State) (effect : EffectId .target) (origin : NodeId) : List OriginInput :=
  (inventory state).map (originInput program state effect origin)

def tableInput (table : List OriginInput) (reference : NodeId) : OriginInput :=
  table[reference.value]?.getD ⟨true, []⟩

theorem origin_inputs_exact (program : Target.Program) (state : State) (effect : EffectId .target)
    (origin reference : NodeId) :
    tableInput (originInputs program state effect origin) reference = originInput program state effect origin reference := by
  by_cases inside : reference.value < state.nodes.length
  · have eta : (⟨reference.value⟩ : NodeId) = reference := by cases reference; rfl
    simp [tableInput, originInputs, inventory, inside, eta]
  · have absent : node state reference = none := by simp [node, Nat.not_lt.mp inside]
    simp [tableInput, originInputs, inventory, inside, originInput, absent]

def withoutOrigin (program : Target.Program) (state : State) (effect : EffectId .target) (origin : NodeId) : List NodeId :=
  let table := originInputs program state effect origin
  BoundaryV2.FiniteDependency.refine (fun reference => (tableInput table reference).exposed)
    (fun reference => (tableInput table reference).dependencies) (inventory state)

theorem origin_input_sharing_exact (program : Target.Program) (state : State) (effect : EffectId .target) (origin : NodeId) :
    withoutOrigin program state effect origin =
      BoundaryV2.FiniteDependency.refine (originDirect program state effect origin)
        (originDependencies program state effect origin) (inventory state) := by
  simp only [withoutOrigin, origin_inputs_exact]
  rfl

def capabilityOrigins (program : Target.Program) (state : State) (effect : EffectId .target) : List NodeId :=
  ((state.nodes.flatMap recordValues).filterMap (fun value =>
    match program.schemas[value.schema.value]?, value.body with
    | some (.internal (.capability nominal)), .reference reference => if nominal == effect then some reference else none
    | _, _ => none)).eraseDups

def inputExposes (without : List NodeId) (input : OriginInput) : Bool :=
  input.exposed || input.dependencies.any (fun reference => !without.contains reference)

def localOrigin (program : Target.Program) (state : State) (effect : EffectId .target) (scope origin : NodeId) : Bool :=
  containsScope state (some origin) scope ||
    !inputExposes (withoutOrigin program state effect origin) (childOrigin program state effect origin scope none)

def localEffect (program : Target.Program) (state : State) (facts : Target.Admission.EffectFacts)
    (scope : NodeId) (effect : EffectId .target) : Bool :=
  !(facts.ambient[effect.value]?).getD true && (capabilityOrigins program state effect).all (localOrigin program state effect scope)

abbrev OriginColumn := NodeId × List NodeId

def originColumns (program : Target.Program) (state : State) (effect : EffectId .target) : List OriginColumn :=
  (capabilityOrigins program state effect).map (fun origin => (origin, withoutOrigin program state effect origin))

def originTable (program : Target.Program) (state : State) (facts : Target.Admission.EffectFacts) : List (List OriginColumn) :=
  (List.range program.effects.length).map (fun index =>
    if facts.ambient[index]?.getD true then [] else originColumns program state ⟨index⟩)

def localEffectFromTable (program : Target.Program) (state : State) (facts : Target.Admission.EffectFacts)
    (table : List (List OriginColumn)) (scope : NodeId) (effect : EffectId .target) : Bool :=
  !facts.ambient[effect.value]?.getD true &&
  (match table[effect.value]? with | some columns => columns | none => originColumns program state effect).all
    (fun (origin, without) => containsScope state (some origin) scope ||
      !inputExposes without (childOrigin program state effect origin scope none))

/-- Each origin fixed point is computed once for a state and nominal effect.
Every enclosing-interface check reuses that same, definitionally derived data. -/
theorem origin_table_preserves_local_permission (program : Target.Program) (state : State)
    (facts : Target.Admission.EffectFacts) (scope : NodeId) (effect : EffectId .target) :
    localEffectFromTable program state facts (originTable program state facts) scope effect =
      localEffect program state facts scope effect := by
  by_cases ambient : facts.ambient[effect.value]?.getD true = true
  · simp [localEffectFromTable, localEffect, ambient]
  · have ambient : facts.ambient[effect.value]?.getD true = false := by simpa using ambient
    have eta : (⟨effect.value⟩ : EffectId .target) = effect := by cases effect; rfl
    by_cases inside : effect.value < program.effects.length
    · simp [localEffectFromTable, originTable, inside, ambient, eta, originColumns, localEffect, List.all_map]
      rfl
    · simp [localEffectFromTable, originTable, inside, ambient, originColumns, localEffect, List.all_map]
      rfl

theorem without_origin_excludes_reachable_origin (program : Target.Program) (state : State)
    (effect : EffectId .target) (origin reference : NodeId)
    (reaches : OriginReaches program state effect origin reference) :
    reference ∉ withoutOrigin program state effect origin := by
  rw [origin_input_sharing_exact]
  exact BoundaryV2.FiniteDependency.refine_excludes_dependencies _ _ _ _ reaches

theorem admitted_local_origin_is_inside (program : Target.Program) (state : State) (effect : EffectId .target)
    (scope origin child : NodeId)
    (accepted : localOrigin program state effect scope origin = true)
    (edge : child ∈ (childOrigin program state effect origin scope none).dependencies)
    (reaches : OriginReaches program state effect origin child) : containsScope state (some origin) scope = true := by
  have absent := without_origin_excludes_reachable_origin program state effect origin child reaches
  have exposed : inputExposes (withoutOrigin program state effect origin) (childOrigin program state effect origin scope none) = true := by
    simp only [inputExposes, Bool.or_eq_true]
    right
    exact List.any_eq_true.mpr ⟨child, edge, by simpa using absent⟩
  simpa [localOrigin, exposed] using accepted

theorem ambient_effect_cannot_be_discharged_as_local (program : Target.Program) (state : State)
    (facts : Target.Admission.EffectFacts) (scope : NodeId) (effect : EffectId .target)
    (ambient : (facts.ambient[effect.value]?).getD true = true) : localEffect program state facts scope effect = false := by
  simp [localEffect, ambient]

end BoundaryV2.Profile.Graph.Admission
