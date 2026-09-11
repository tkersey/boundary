import BoundaryV2.GraphAncestry
import BoundaryV2.ProtocolIdentity

namespace BoundaryV2.Profile.Graph.Admission

def rootsValid (state : State) : Bool := state.roots.detached.isEmpty &&
  match state.status with
  | .active | .yielded => state.roots.pending.isNone && state.roots.current.any (fun reference =>
      match node state reference with | some (.control control) => control.evidence == state.roots.evidence | _ => false)
  | .parked => state.roots.current.isNone && state.roots.pending.any (fun reference =>
      match node state reference with
      | some (.pending _ _ continuation _) => match node state continuation with
        | some (.continuation saved) => saved.evidence == state.roots.evidence
        | _ => false
      | _ => false)
  | .unwinding => state.roots.pending.isNone && state.roots.evidence.isNone && state.roots.exit.isSome &&
      state.roots.current.any (fun reference => match node state reference with | some (.unwind ..) => true | _ => false)

def capturedDelimiters (state : State) : List (NodeId × SchemaId .target) := state.nodes.filterMap fun record =>
  match record with | .oneShot capture | .multiTemplate capture => some (capture.delimiter, capture.schema) | _ => none

def capturesUnique (state : State) : Bool :=
  let delimiters := (capturedDelimiters state).map Prod.fst
  decide delimiters.Nodup && delimiters.all (fun reference =>
    match node state reference with | some (.attachment ..) => true | _ => false) &&
  state.nodes.zipIdx.all (fun (record, index) => match record with
    | .attachment _ _ _ .suspended _ => delimiters.contains ⟨index⟩
    | _ => true)

def returning (state : State) : Option NodeId := match state.status with
  | .active | .yielded => state.roots.current
  | .parked => state.roots.pending.bind fun reference => match node state reference with
    | some (.pending _ _ saved _) => some saved
    | _ => none
  | .unwinding => none

def exitParent : Node → Option NodeId
  | .exit exit => exit.outer | _ => none
def isExit : Node → Bool
  | .exit _ => true | _ => false

def exitPath (state : State) : Option (List NodeId) :=
  chain state exitParent isExit (inventory state) state.roots.exit

/-- Exit records must form the complete acyclic chain rooted at roots.exit.
Every cleanup return points into it, and an interrupted unwind must have a
running cleanup continuation. Dead exit records are not silently ignored. -/
def exitsValid (state : State) : Bool := (exitPath state).any fun path =>
  state.nodes.zipIdx.all (fun (record, index) => match record with
    | .exit _ => path.contains ⟨index⟩
    | .cleanupReturn _ _ exit => path.contains exit
    | _ => true) &&
  (state.roots.exit.isNone || state.status == .unwinding ||
    state.nodes.any (fun record => match record with | .cleanupReturn .. => true | _ => false))

def pendingCount (state : State) : Nat := state.nodes.countP fun record => match record with
  | .pending .. => true | _ => false

/-- Program-relative positional admission, before record typing and lexical
borrow checks. Physical custody counts each field once, including dormant
captures, rather than counting each path by which a shared record is reached. -/
def positionValidWithIdentity (program : Target.Program) (identity : Digest) (state : State) : Bool :=
  state.programIdentity == identity && rootsValid state &&
  custody program state && forestValid state && capturesUnique state &&
  (returning state).all (normalReturning state) && exitsValid state &&
  pendingCount state == (if state.roots.pending.isSome then 1 else 0)

def positionValid (program : Target.Program) (state : State) : Bool :=
  positionValidWithIdentity program (Protocol.programIdentity program) state

/-- A checker that retains this program's computed digest can share the hash
across a complete segment. This equality permits no change to any state check. -/
theorem position_identity_sharing_exact (program : Target.Program) (state : State) :
    positionValidWithIdentity program (Protocol.programIdentity program) state = positionValid program state := rfl

theorem position_exact_identity (program : Target.Program) (state : State)
    (accepted : positionValid program state = true) : state.programIdentity = Protocol.programIdentity program := by
  simp only [positionValid, positionValidWithIdentity, Bool.and_eq_true, beq_iff_eq] at accepted
  exact accepted.1.1.1.1.1.1.1

theorem captured_delimiters_have_one_capturer (state : State)
    (accepted : capturesUnique state = true) : ((capturedDelimiters state).map Prod.fst).Nodup := by
  simp only [capturesUnique, Bool.and_eq_true, decide_eq_true_eq] at accepted
  exact accepted.1.1

theorem every_suspended_delimiter_is_captured (state : State)
    (accepted : capturesUnique state = true) (index : Nat) (handler : NodeId)
    (outer parent region : Option NodeId)
    (actual : state.nodes[index]? = some (.attachment handler outer parent .suspended region)) :
    ⟨index⟩ ∈ (capturedDelimiters state).map Prod.fst := by
  simp only [capturesUnique, Bool.and_eq_true] at accepted
  have member : (.attachment handler outer parent .suspended region, index) ∈ state.nodes.zipIdx := by
    exact List.mem_zipIdx_iff_getElem?.mpr actual
  simpa using List.all_eq_true.mp accepted.2 _ member

theorem exit_path_acyclic (state : State) (path : List NodeId)
    (accepted : exitPath state = some path) : path.Nodup :=
  chain_distinct state exitParent isExit _ _ path (inventory_distinct state) accepted

theorem parked_state_has_exactly_one_request (program : Target.Program) (state : State)
    (accepted : positionValid program state = true) (parked : state.status = .parked) : pendingCount state = 1 := by
  simp only [positionValid, positionValidWithIdentity, Bool.and_eq_true] at accepted
  have roots := accepted.1.1.1.1.1.1.2
  have present : state.roots.pending.isSome = true := by
    simp only [rootsValid, parked, Bool.and_eq_true] at roots
    obtain ⟨reference, found, _⟩ := (Option.any_eq_true _ _).mp roots.2.2
    simp [found]
  simpa [present] using accepted.2

end BoundaryV2.Profile.Graph.Admission
