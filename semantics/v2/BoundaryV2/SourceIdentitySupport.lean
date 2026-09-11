import BoundaryV2.SourceAllocationLaws
import BoundaryV2.SourceActivationLaws
import BoundaryV2.SourceCellStorage

namespace BoundaryV2.Profile.Source.Machine
namespace IdentitySupport

/-- Bounds for the distinct runtime allocation domains. Nominal source catalog
identities, custody-token alignment, and owning-edge locations have their own
contracts. Every stored object is inspected, including dormant captures. -/
abbrev Limits := Domain → Nat

def limits (heap : Heap) : Limits
  | .attachment => heap.nextAttachment
  | .regionInstance => heap.nextRegion
  | .cell => heap.nextCell
  | .lexicalScope => heap.nextScope
  | .invocation => heap.nextInvocation
  | .obligation => heap.nextObligation
  | _ => 0

def Bound (limit : Limits) (identity : Ref .runtime domain) : Prop := identity.value < limit domain

def ActivationValid (limit : Limits) (activation : Activation) : Prop :=
  Bound limit activation.identity ∧ Bound limit activation.scope ∧ Bound limit activation.invocation ∧
    ∀ outer ∈ activation.outer, Bound limit outer

def FrameValid (limit : Limits) : Frame → Prop
  | .binding _ _ _ scope | .lexical scope | .releaseReturn scope _ => Bound limit scope
  | .invocation invocation scope | .restore invocation scope | .disposalReturn _ _ invocation scope =>
    Bound limit invocation ∧ Bound limit scope
  | .handler activation => ActivationValid limit activation
  | .region region => Bound limit region
  | .protection obligation => Bound limit obligation
  | .cleanupReturn obligation invocation _ _ => Bound limit obligation ∧ Bound limit invocation
  | .operands .. | .injection _ => True

def FrozenValid (limit : Limits) (cell : FrozenCell) : Prop :=
  Bound limit cell.identity ∧ Bound limit cell.region

def CaptureValid (limit : Limits) (capture : Capture) : Prop :=
  (∀ frame ∈ capture.frames, FrameValid limit frame) ∧ ActivationValid limit capture.delimiter ∧
  (∀ region ∈ capture.localRegions, Bound limit region) ∧
  (∀ cell ∈ capture.frozenCells, FrozenValid limit cell) ∧
  Bound limit capture.scope ∧ Bound limit capture.invocation

def ObjectValid (limit : Limits) : Object → Prop
  | .capability attachment _ => Bound limit attachment
  | .region region _ invocation outer =>
    Bound limit region ∧ Bound limit invocation ∧ ∀ parent ∈ outer, Bound limit parent
  | .cell cell _ region _ => Bound limit cell ∧ Bound limit region
  | .oneShot capture | .multiTemplate capture => CaptureValid limit capture
  | .borrow _ _ region invocation => Bound limit region ∧ Bound limit invocation
  | .closure .. | .package .. | .resource .. => True

def ScopeValid (limit : Limits) (scope : Scope) : Prop :=
  Bound limit scope.id ∧ Bound limit scope.invocation ∧ ∀ parent ∈ scope.parent, Bound limit parent

def InvocationValid (limit : Limits) (invocation : Invocation) : Prop :=
  Bound limit invocation.id ∧ (∀ parent ∈ invocation.capabilityParents, Bound limit parent) ∧
    ∀ parent ∈ invocation.regionParents, Bound limit parent

def ObligationValid (limit : Limits) (obligation : Cleanup.Obligation .source) : Prop :=
  Bound limit obligation.id ∧ Bound limit obligation.scope ∧
  (match obligation.phase with | .running invocation => Bound limit invocation | _ => True)

structure HeapValid (limit : Limits) (heap : Heap) : Prop where
  objects : ∀ object ∈ heap.objects, ∀ present ∈ object, ObjectValid limit present
  scopes : ∀ scope ∈ heap.scopes, ScopeValid limit scope
  invocations : ∀ invocation ∈ heap.invocations, InvocationValid limit invocation
  obligations : ∀ obligation ∈ heap.obligations, ObligationValid limit obligation
  loans : ∀ loan ∈ heap.loans, Bound limit loan.1 ∧ Bound limit loan.2

def ControlValid (limit : Limits) : Control → Prop
  | .release scope _ => Bound limit scope
  | _ => True

structure ValidAt (limit : Limits) (state : State) : Prop where
  heap : HeapValid limit state.heap
  frames : ∀ frame ∈ state.stack, FrameValid limit frame
  control : ControlValid limit state.control
  scope : Bound limit state.scope
  invocation : Bound limit state.invocation

abbrev Valid (state : State) := ValidAt (limits state.heap) state

theorem limits_monotone (growth : before.AllocationLE after) :
    ∀ domain, limits before domain ≤ limits after domain := by
  intro domain
  cases domain <;> simp only [limits]
  all_goals first | exact Nat.le_refl _ | exact growth.attachments | exact growth.regions | exact growth.cells | exact growth.scopes | exact growth.invocations | exact growth.obligations

theorem bound_mono (growth : ∀ domain, before domain ≤ after domain)
    (bounded : Bound before identity) : Bound after identity := Nat.lt_of_lt_of_le bounded (growth _)

theorem activation_mono (growth : ∀ domain, before domain ≤ after domain)
    (bounded : ActivationValid before activation) : ActivationValid after activation := by
  rcases bounded with ⟨identity, scope, invocation, outer⟩
  exact ⟨bound_mono growth identity, bound_mono growth scope, bound_mono growth invocation,
    fun parent member => bound_mono growth (outer parent member)⟩

theorem frame_mono (growth : ∀ domain, before domain ≤ after domain)
    (bounded : FrameValid before frame) : FrameValid after frame := by
  cases frame <;> simp only [FrameValid] at bounded ⊢
  all_goals first | exact True.intro | exact bound_mono growth bounded | exact activation_mono growth bounded | exact ⟨bound_mono growth bounded.1, bound_mono growth bounded.2⟩

theorem frozen_mono (growth : ∀ domain, before domain ≤ after domain)
    (bounded : FrozenValid before cell) : FrozenValid after cell :=
  ⟨bound_mono growth bounded.1, bound_mono growth bounded.2⟩

theorem capture_mono (growth : ∀ domain, before domain ≤ after domain)
    (bounded : CaptureValid before capture) : CaptureValid after capture :=
  ⟨fun frame member => frame_mono growth (bounded.1 frame member), activation_mono growth bounded.2.1,
    fun region member => bound_mono growth (bounded.2.2.1 region member),
    fun cell member => frozen_mono growth (bounded.2.2.2.1 cell member),
    bound_mono growth bounded.2.2.2.2.1, bound_mono growth bounded.2.2.2.2.2⟩

theorem object_mono (growth : ∀ domain, before domain ≤ after domain)
    (bounded : ObjectValid before object) : ObjectValid after object := by
  cases object <;> simp only [ObjectValid] at bounded ⊢
  all_goals first | exact True.intro | exact bound_mono growth bounded | exact capture_mono growth bounded | exact ⟨bound_mono growth bounded.1, bound_mono growth bounded.2⟩ | exact ⟨bound_mono growth bounded.1, bound_mono growth bounded.2.1,
      fun parent member => bound_mono growth (bounded.2.2 parent member)⟩

theorem scope_mono (growth : ∀ domain, before domain ≤ after domain)
    (bounded : ScopeValid before scope) : ScopeValid after scope :=
  ⟨bound_mono growth bounded.1, bound_mono growth bounded.2.1,
    fun parent member => bound_mono growth (bounded.2.2 parent member)⟩

theorem invocation_mono (growth : ∀ domain, before domain ≤ after domain)
    (bounded : InvocationValid before invocation) : InvocationValid after invocation :=
  ⟨bound_mono growth bounded.1, fun parent member => bound_mono growth (bounded.2.1 parent member),
    fun parent member => bound_mono growth (bounded.2.2 parent member)⟩

theorem obligation_mono (growth : ∀ domain, before domain ≤ after domain)
    (bounded : ObligationValid before obligation) : ObligationValid after obligation := by
  refine ⟨bound_mono growth bounded.1, bound_mono growth bounded.2.1, ?_⟩
  have phaseBound := bounded.2.2
  cases phase : obligation.phase <;> simp only [phase] at phaseBound ⊢
  all_goals first | exact True.intro | exact bound_mono growth phaseBound

theorem heap_mono (growth : ∀ domain, before domain ≤ after domain)
    (bounded : HeapValid before heap) : HeapValid after heap :=
  ⟨fun object member present found => object_mono growth (bounded.objects object member present found),
    fun scope member => scope_mono growth (bounded.scopes scope member),
    fun invocation member => invocation_mono growth (bounded.invocations invocation member),
    fun obligation member => obligation_mono growth (bounded.obligations obligation member),
    fun loan member => ⟨bound_mono growth (bounded.loans loan member).1,
      bound_mono growth (bounded.loans loan member).2⟩⟩

theorem valid_mono (growth : ∀ domain, before domain ≤ after domain)
    (bounded : ValidAt before state) : ValidAt after state := by
  refine ⟨heap_mono growth bounded.heap, fun frame member => frame_mono growth (bounded.frames frame member),
    ?_, bound_mono growth bounded.scope, bound_mono growth bounded.invocation⟩
  have control := bounded.control
  cases executing : state.control <;> simp only [ControlValid, executing] at control ⊢
  all_goals first | exact True.intro | exact bound_mono growth control

/-- Renaming preserves the bound of each identity domain independently. -/
structure Renames (before after : Limits) (mapping : Renaming) : Prop where
  attachments : ∀ identity, Bound before identity → Bound after (renamed mapping.attachments identity)
  regions : ∀ identity, Bound before identity → Bound after (renamed mapping.regions identity)
  cells : ∀ identity, Bound before identity → Bound after (renamed mapping.cells identity)
  scopes : ∀ identity, Bound before identity → Bound after (renamed mapping.scopes identity)
  invocations : ∀ identity, Bound before identity → Bound after (renamed mapping.invocations identity)
  obligations : ∀ identity : ObligationId, Bound before identity → Bound after identity

theorem fresh_map_bound (domain : Domain) (start finish : Nat)
    (identities : List (Ref .runtime domain)) (identity : Ref .runtime domain)
    (old : identity.value < start) (capacity : start + identities.eraseDups.length ≤ finish) :
    (renamed (freshMap .runtime domain start identities) identity).value < finish := by
  by_cases inside : identity ∈ identities
  · exact Nat.lt_of_lt_of_le (source_activation_interval _ _ _ _ _ inside).2 capacity
  · rw [renamed_outside_fresh_map _ _ _ _ _ inside]
    omega

theorem rename_activation (renames : Renames before after mapping)
    (bounded : ActivationValid before activation) : ActivationValid after (renameActivation mapping activation) := by
  refine ⟨renames.attachments _ bounded.1, renames.scopes _ bounded.2.1,
    renames.invocations _ bounded.2.2.1, ?_⟩
  intro outer member
  obtain ⟨original, found, rfl⟩ := Option.map_eq_some_iff.mp member
  exact renames.attachments _ (bounded.2.2.2 original found)

theorem rename_frame (renames : Renames before after mapping)
    (bounded : FrameValid before frame) : FrameValid after (renameFrame mapping frame) := by
  cases frame <;> simp only [renameFrame, FrameValid] at bounded ⊢
  all_goals first | exact True.intro | exact renames.scopes _ bounded | exact renames.regions _ bounded | exact renames.obligations _ bounded | exact rename_activation renames bounded | exact ⟨renames.invocations _ bounded.1, renames.scopes _ bounded.2⟩ | exact ⟨renames.obligations _ bounded.1, renames.invocations _ bounded.2⟩

theorem rename_capture (renames : Renames before after mapping)
    (bounded : CaptureValid before capture) : CaptureValid after (renameCapture mapping capture) := by
  refine ⟨?_, rename_activation renames bounded.2.1, ?_, ?_,
    renames.scopes _ bounded.2.2.2.2.1, renames.invocations _ bounded.2.2.2.2.2⟩
  · intro frame member
    simp only [renameCapture] at member
    obtain ⟨original, originalMember, rfl⟩ := List.mem_map.mp member
    exact rename_frame renames (bounded.1 original originalMember)
  · intro region member
    simp only [renameCapture] at member
    obtain ⟨original, originalMember, rfl⟩ := List.mem_map.mp member
    exact renames.regions _ (bounded.2.2.1 original originalMember)
  · intro cell member
    simp only [renameCapture] at member
    obtain ⟨original, originalMember, rfl⟩ := List.mem_map.mp member
    exact ⟨renames.cells _ (bounded.2.2.2.1 original originalMember).1,
      renames.regions _ (bounded.2.2.2.1 original originalMember).2⟩

theorem rename_object (renames : Renames before after mapping)
    (bounded : ObjectValid before object) : ObjectValid after (renameObject mapping object) := by
  cases object <;> simp only [renameObject, ObjectValid] at bounded ⊢
  all_goals first | exact True.intro | exact renames.attachments _ bounded | exact rename_capture renames bounded | exact ⟨renames.cells _ bounded.1, renames.regions _ bounded.2⟩ | exact ⟨renames.regions _ bounded.1, renames.invocations _ bounded.2⟩ | skip
  refine ⟨renames.regions _ bounded.1, renames.invocations _ bounded.2.1, ?_⟩
  intro parent member
  obtain ⟨original, found, rfl⟩ := Option.map_eq_some_iff.mp member
  exact renames.regions _ (bounded.2.2 original found)

end IdentitySupport
end BoundaryV2.Profile.Source.Machine
