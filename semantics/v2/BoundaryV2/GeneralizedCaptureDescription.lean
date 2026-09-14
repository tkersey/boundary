import BoundaryV2.GeneralizedFreeze

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

namespace Source

/-- Authored provenance for a captured higher-order context. `future` builds
the source callbacks; this description never executes target code. -/
inductive Capture (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) : TypeOf signature → TypeOf signature → Type where
  | done : Capture signature algebra program result result
  | bind (body : Computation signature algebra program (input :: context) middle)
      (bindings : RuntimeEnvironment signature algebra program context)
      (rest : Capture signature algebra program middle result) : Capture signature algebra program input result
  | handler (effect : signature.Effect) (mode : Mode) (identity : Id .attachment)
      (returned : Computation signature algebra program (input :: context) middle)
      (clauses : Clauses signature algebra program effect mode context input middle)
      (bindings : RuntimeEnvironment signature algebra program context)
      (rest : Capture signature algebra program middle result) : Capture signature algebra program input result
  | region (identity : Id .region) (rest : Capture signature algebra program input result) :
      Capture signature algebra program input result
  | protection (identity : Id .obligation)
      (cleanup : Computation signature algebra program (.exit :: context) .unit)
      (bindings : RuntimeEnvironment signature algebra program context)
      (rest : Capture signature algebra program input result) : Capture signature algebra program input result
  | cleanupReturn (identity : Id .obligation) (original : Option (RuntimeValue signature algebra program middle))
      (exit : ExitInfo algebra.Fault algebra.Reason) (rest : Capture signature algebra program middle result) :
      Capture signature algebra program .unit result

def Capture.future : Capture signature algebra program input result → Context signature algebra program input result
  | .done => .done
  | .bind body bindings rest => .push (.bindAuthored body bindings) rest.future
  | .handler effect mode identity returned clauses bindings rest =>
      .push (.handler effect mode identity returned clauses bindings) rest.future
  | .region identity rest => .push (.region identity) rest.future
  | .protection identity cleanup bindings rest => .push (.protection identity cleanup bindings) rest.future
  | .cleanupReturn identity original exit rest => .push (.cleanupReturn identity original exit) rest.future

/-- Project the authored data already present in each source frame. This does
not assert that an arbitrary callback agrees with its metadata; it is used as
a left inverse on futures constructed from an actual Capture. -/
def Context.captureMetadata (future : Context signature algebra program input result) :
    Capture signature algebra program input result :=
  match future with
  | .done => .done
  | .push (.bind _ description) rest => .bind description.body description.environment rest.captureMetadata
  | .push (.handler effect mode identity returned clauses bindings) rest =>
      .handler effect mode identity returned clauses bindings rest.captureMetadata
  | .push (.region identity) rest => .region identity rest.captureMetadata
  | .push (.protection identity cleanup bindings) rest => .protection identity cleanup bindings rest.captureMetadata
  | .push (.cleanupReturn identity original exit) rest => .cleanupReturn identity original exit rest.captureMetadata
termination_by future.length
decreasing_by all_goals simp_all only [Context.length]; omega

theorem Capture.metadata_of_future (capture : Capture signature algebra program input result) :
    capture.future.captureMetadata = capture := by
  induction capture <;> simp_all only [Capture.future, Context.captureMetadata, Frame.bindAuthored]

theorem Capture.future_injective {first second : Capture signature algebra program input result}
    (same : first.future = second.future) : first = second := by
  simpa only [Capture.metadata_of_future] using congrArg Context.captureMetadata same

def Capture.references : Capture signature algebra program input result → List Reference
  | .done => []
  | .bind body bindings rest => (body.references ++ environmentReferences bindings) ++ rest.references
  | .handler _ _ identity returned clauses bindings rest =>
      (.name .attachment identity :: (returned.references ++ clauses.references ++ environmentReferences bindings)) ++ rest.references
  | .region identity rest => .name .region identity :: rest.references
  | .protection identity cleanup bindings rest =>
      (.name .obligation identity :: (cleanup.references ++ environmentReferences bindings)) ++ rest.references
  | .cleanupReturn identity original _ rest =>
      (.name .obligation identity :: original.toList.flatMap valueReferences) ++ rest.references

def Capture.copyable : Capture signature algebra program input result → Bool
  | .done => true
  | .bind _ bindings rest | .handler _ _ _ _ _ bindings rest => bindings.copyable && rest.copyable
  | .region _ rest => rest.copyable
  | .protection _ _ _ _ | .cleanupReturn _ _ _ _ => false

theorem Capture.supported (capture : Capture signature algebra program input result) :
    ContextSupported capture.future capture.references := by
  induction capture with
  | done => exact .done
  | bind body bindings rest induction => exact .push (.bind body bindings) induction
  | handler effect mode identity returned clauses bindings rest induction =>
      exact .push (.handler effect mode identity returned clauses bindings) induction
  | region identity rest induction => exact .push (.region identity) induction
  | protection identity cleanup bindings rest induction => exact .push (.protection identity cleanup bindings) induction
  | cleanupReturn identity original exit rest induction => exact .push (.cleanupReturn identity original exit) induction

theorem Capture.future_copyable (capture : Capture signature algebra program input result) :
    capture.future.copyable = capture.copyable := by
  induction capture <;> simp_all only [Capture.future, Capture.copyable, Context.copyable,
    Frame.copyable, Frame.bindAuthored, Bool.true_and, Bool.false_and]

/-- Equality of actual source futures now preserves capture admission data,
even when callback extensionality alone cannot distinguish their bodies. -/
theorem Capture.equal_futures_preserve_provenance
    {first second : Capture signature algebra program input result} (same : first.future = second.future) :
    first.references = second.references ∧ first.copyable = second.copyable := by
  cases Capture.future_injective same
  exact ⟨rfl, rfl⟩

end Source

namespace Defunctionalization

def capture : Source.Capture signature algebra program input result → Target.Stack signature algebra program input result
  | .done => .done
  | .bind body bindings rest => .push (.returnTo (.enter (computation body)) (environment bindings) .nil) (capture rest)
  | .handler effect mode identity returned clauses bindings rest =>
      .push (.handler effect mode identity (computation returned) (Defunctionalization.clauses clauses) (environment bindings)) (capture rest)
  | .region identity rest => .push (.region identity) (capture rest)
  | .protection identity cleanup bindings rest => .push (.protection identity (computation cleanup) (environment bindings)) (capture rest)
  | .cleanupReturn identity original exit rest => .push (.cleanupReturn identity (original.map value) exit) (capture rest)

theorem capture_correspondence (source : Source.Capture signature algebra program input result) :
    ContextRelated signature algebra program source.future (capture source) := by
  induction source with
  | done => exact .done
  | bind body bindings rest induction => exact .push (.bind body bindings) induction
  | handler effect mode identity returned clauses bindings rest induction =>
      exact .push (.handler effect mode identity returned clauses bindings) induction
  | region identity rest induction => exact .push (.region identity) induction
  | protection identity cleanup bindings rest induction => exact .push (.protection identity cleanup bindings) induction
  | cleanupReturn identity original exit rest induction => exact .push (.cleanupReturn identity original exit) induction

/-- Every context already related by the core has authored provenance. Only
the target's silent identity frames disappear; no source frame is discarded. -/
theorem related_context_has_capture
    {source : Source.Context signature algebra program input result}
    {target : Target.Stack signature algebra program input result}
    (related : ContextRelated signature algebra program source target) :
    ∃ description : Source.Capture signature algebra program input result,
      description.future = source ∧ capture description = target.cloneView := by
  induction related with
  | done => exact ⟨.done, rfl, rfl⟩
  | passthrough bindings rest induction => exact induction
  | push frame rest induction =>
    obtain ⟨description, original, compiled⟩ := induction
    cases frame with
    | bind body bindings => exact ⟨.bind body bindings description, congrArg _ original, congrArg _ compiled⟩
    | handler effect mode identity returned clauses bindings =>
        exact ⟨.handler effect mode identity returned clauses bindings description, congrArg _ original, congrArg _ compiled⟩
    | region identity => exact ⟨.region identity description, congrArg _ original, congrArg _ compiled⟩
    | protection identity cleanup bindings =>
        exact ⟨.protection identity cleanup bindings description, congrArg _ original, congrArg _ compiled⟩
    | cleanupReturn identity saved exit =>
        exact ⟨.cleanupReturn identity saved exit description, congrArg _ original, congrArg _ compiled⟩

theorem capture_of_related_context (source : Source.Capture signature algebra program input result)
    (related : ContextRelated signature algebra program source.future target) :
    capture source = target.cloneView := by
  obtain ⟨description, original, compiled⟩ := related_context_has_capture related
  have same := Source.Capture.future_injective original
  rw [same] at compiled
  exact compiled

theorem capture_copyability (source : Source.Capture signature algebra program input result) :
    (capture source).copyable = source.copyable := by
  induction source with
  | done => rfl
  | bind body bindings rest induction =>
      simp only [capture, Target.Stack.copyable, Target.Frame.copyable, environment,
        Environment.copyable_map, Environment.copyable, Bool.and_true, Source.Capture.copyable, induction]
  | handler effect mode identity returned clauses bindings rest induction =>
      simp only [capture, Target.Stack.copyable, Target.Frame.copyable, environment,
        Environment.copyable_map, Source.Capture.copyable, induction]
  | region identity rest induction => exact induction
  | protection identity cleanup bindings rest induction => rfl
  | cleanupReturn identity original exit rest induction => rfl

theorem capture_references (source : Source.Capture signature algebra program input result) :
    (capture source).references = source.references := by
  induction source with
  | done => rfl
  | bind body bindings rest induction =>
      simp only [capture, Target.Stack.references, Target.Frame.references, Target.Code.references,
        computation_reference_support, environment_reference_support, Target.environmentReferences,
        List.append_nil, Source.Capture.references, induction]
  | handler effect mode identity returned clauses bindings rest induction =>
      simp only [capture, Target.Stack.references, Target.Frame.references, computation_reference_support,
        clauses_reference_support, environment_reference_support, Source.Capture.references, induction]
  | region identity rest induction => exact congrArg (Reference.name .region identity :: ·) induction
  | cleanupReturn identity original exit rest induction =>
      cases original <;> simp [capture, Target.Stack.references, Target.Frame.references, value_reference_support, Source.Capture.references, induction]
  | protection identity cleanup bindings rest induction =>
      simp only [capture, Target.Stack.references, Target.Frame.references, computation_reference_support,
        environment_reference_support, Source.Capture.references, induction]

end Defunctionalization
end BoundaryV2.Generalized
