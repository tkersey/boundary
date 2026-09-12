import BoundaryV2.SourceLexicalTransitions

namespace BoundaryV2.Profile.Source.Machine
namespace LexicalCoverage

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]


theorem resumeRelease_control (context : Context) (machine : State) (after : AfterRelease) :
    ControlValid context (resumeRelease machine after).state.control := by
  cases after <;> trivial

theorem leaveScope_control (context : Context) (machine : State) (parent : LexicalScopeId) (invocation : InvocationId)
    (tail : List Frame) (value : Located) (after : Transition)
    (accepted : leaveScope machine parent invocation tail value = .ok after) : ControlValid context after.state.control := by
  simp only [leaveScope, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
  trivial

theorem leaveInvocation_control (context : Context) (machine : State) (after : Transition)
    (accepted : leaveInvocation machine = .ok after) : ControlValid context after.state.control := by
  unfold leaveInvocation at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  exact leaveScope_control _ _ _ _ _ _ _ accepted

theorem leaveLexical_control (context : Context) (machine : State) (after : Transition)
    (accepted : leaveLexical machine = .ok after) : ControlValid context after.state.control := by
  unfold leaveLexical at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  trivial

theorem restoreResumeCaller_control (context : Context) (machine : State) (after : Transition)
    (accepted : restoreResumeCaller machine = .ok after) : ControlValid context after.state.control := by
  unfold restoreResumeCaller at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, _, _, finished⟩ := accepted
  have shape := OperandStructure.finishTemporary_shape _ _ _ finished
  simp [ControlValid, shape.1]

theorem installProtection_control (machine : State) (context : Context) (body cleanup : Located)
    (arguments : List Located) (resource : Option Located) (loan : Option (RegionId .source)) (after : Transition)
    (typed : context.typingValid = true)
    (accepted : installProtection machine context body cleanup arguments resource loan = .ok after) : ControlValid context after.state.control := by
  simp only [installProtection, bind, except_bind_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, accepted⟩ := accepted
  cases resource <;> cases loan <;> try contradiction
  · simp only [pure, Except.pure, Except.bind] at accepted
    exact applyClosure_control _ _ _ _ _ typed accepted
  · simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, _, _, _, rfl, applied⟩ := accepted
    exact applyClosure_control _ _ _ _ _ typed applied

theorem beginCleanup_control (machine : State) (context : Context) (identity : ObligationId)
    (exit : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (after : Transition)
    (typed : context.typingValid = true)
    (accepted : beginCleanup machine context identity exit normal tail = .ok after) : ControlValid context after.state.control := by
  simp only [beginCleanup, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, applied, rfl⟩ := accepted
  have result := applyClosure_control _ _ _ _ _ typed applied
  exact result

theorem finishCleanup_control (machine : State) (context : Context) (after : Transition)
    (accepted : finishCleanup machine context = .ok after) : ControlValid context after.state.control := by
  unfold finishCleanup at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, rfl⟩ := accepted
  exact resumeRelease_control _ _ _

theorem cleanupFailed_control (context : Context) (machine : State) (identity : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (inner : Cleanup.Exit .source)
    (after : Transition) (accepted : cleanupFailed machine identity invocation outer normal tail inner = .ok after) :
    ControlValid context after.state.control := by
  unfold cleanupFailed at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  trivial

theorem cleanupAbandoned_control (context : Context) (machine : State) (identity : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (inner : Cleanup.Exit .source)
    (after : Transition) (accepted : cleanupAbandoned machine identity invocation outer normal tail inner = .ok after) :
    ControlValid context after.state.control := by
  simp only [cleanupAbandoned, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
  trivial

theorem finishCleanupUnwind_control (context : Context) (machine : State) (identity : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (inner : Cleanup.Exit .source)
    (after : Transition) (accepted : finishCleanupUnwind machine identity invocation outer normal tail inner = .ok after) :
    ControlValid context after.state.control := by
  unfold finishCleanupUnwind at accepted
  split at accepted <;> first
    | exact cleanupFailed_control _ _ _ _ _ _ _ _ _ accepted
    | exact cleanupAbandoned_control _ _ _ _ _ _ _ _ _ accepted
    | contradiction

theorem finishDisposal_control (context : Context) (machine : State) (after : Transition)
    (accepted : finishDisposal machine = .ok after) : ControlValid context after.state.control := by
  unfold finishDisposal at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  cases accepted
  trivial

theorem releaseScope_control (context : Context) (machine : State) (after : Transition)
    (accepted : releaseScope machine = .ok after) : ControlValid context after.state.control := by
  unfold releaseScope at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  trivial

theorem executeCleanupTerm_control (machine : State) (context : Context) (after : Transition)
    (typed : context.typingValid = true) (accepted : executeCleanupTerm machine context = .ok after) : ControlValid context after.state.control := by
  unfold executeCleanupTerm at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    exact installProtection_control _ _ _ _ _ _ _ _ typed accepted
  · split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
    trivial

theorem discardValues_control (machine : State) (context : Context) (after : Transition)
    (accepted : discardValues machine context = .ok after) : ControlValid context after.state.control := by
  unfold discardValues at accepted
  split at accepted <;> try contradiction
  split at accepted
  · cases accepted; exact resumeRelease_control _ _ _
  · split at accepted
    · cases accepted; trivial
    · simp only [bind, except_bind_ok] at accepted
      obtain ⟨⟨node, stored⟩, _, accepted⟩ := accepted
      cases stored <;> try contradiction
      all_goals simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
      all_goals obtain ⟨_, _, rfl⟩ := accepted
      all_goals trivial

def Valid (context : Context) (machine : State) : Prop :=
  ControlValid context machine.control ∧ SavedFrames.Plain context machine

theorem unwindStep_valid (machine : State) (context : Context) (after : Transition)
    (typed : context.typingValid = true) (accepted : unwindStep machine context = .ok after)
    (covered : Valid context machine) : Valid context after.state := by
  unfold unwindStep at accepted
  split at accepted <;> try contradiction
  rename_i original unwinding
  have currentControl : ControlValid context machine.control := by simp [ControlValid, unwinding]
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  cases stacked : machine.stack with
  | nil =>
    simp only [stacked] at accepted
    split at accepted
    · cases accepted; exact ⟨trivial, by simpa only [SavedFrames.Plain, stacked] using covered.2⟩
    · split at accepted <;> try contradiction
      all_goals cases accepted
      all_goals first
        | exact covered
        | exact ⟨currentControl, by simpa only [SavedFrames.Plain, stacked] using covered.2⟩
  | cons saved tail =>
    have tailTyped : SavedFrames.StackValid context tail := covered.2.1.subset (by intro frame member; rw [stacked]; simp [member])
    have tailPlain : SavedFrames.Plain context { machine with stack := tail } := ⟨tailTyped, covered.2.2⟩
    cases saved <;> simp only [stacked] at accepted
    case invocation =>
      split at accepted
      · cases accepted; exact ⟨trivial, by simpa only [SavedFrames.Plain, stacked] using covered.2⟩
      · cases accepted; exact ⟨currentControl, tailPlain⟩
    case lexical =>
      split at accepted
      · cases accepted; exact ⟨trivial, by simpa only [SavedFrames.Plain, stacked] using covered.2⟩
      · simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
        obtain ⟨_, _, _, _, rfl⟩ := accepted
        exact ⟨currentControl, tailPlain⟩
    case protection =>
      exact ⟨beginCleanup_control _ _ _ _ _ _ _ typed accepted,
        SavedFrames.beginCleanup_plain _ _ _ _ _ _ _ accepted covered.2.2 tailTyped⟩
    case cleanupReturn =>
      exact ⟨finishCleanupUnwind_control _ _ _ _ _ _ _ _ _ accepted,
        SavedFrames.finishCleanupUnwind_plain context _ _ _ _ _ _ _ _ accepted covered.2.2 tailTyped⟩
    case releaseReturn => cases accepted; exact ⟨trivial, tailPlain⟩
    case disposalReturn =>
      repeat' split at accepted
      all_goals simp only [pure, Except.pure, Except.bind, Except.ok.injEq] at accepted
      all_goals cases accepted
      all_goals refine ⟨trivial, ?_⟩
      all_goals first | exact tailPlain | simpa only [SavedFrames.Plain, stacked] using covered.2
    all_goals cases accepted; exact ⟨currentControl, tailPlain⟩

end LexicalCoverage
end BoundaryV2.Profile.Source.Machine
