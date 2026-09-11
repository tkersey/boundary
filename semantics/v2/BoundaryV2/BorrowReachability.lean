import BoundaryV2.BorrowGraph
import BoundaryV2.FiniteReachability

namespace BoundaryV2.Profile.Target.Borrow

def successors (program : Program) (source : BlockId) : List BlockId :=
  ((program.blocks[source.value]?).map fun code => (outgoing source code.terminator).map Prod.fst).getD []

theorem incoming_iff_successor (program : Program) (source target : BlockId) :
    source ∈ (incoming program target).map Incoming.source ↔ target ∈ successors program source := by
  constructor
  · intro member
    obtain ⟨edge, member, edgeSource⟩ := List.mem_map.mp member
    obtain ⟨⟨code, index⟩, atCode, member⟩ := List.mem_flatMap.mp member
    obtain ⟨⟨destination, actual⟩, out, selected⟩ := List.mem_filterMap.mp member
    by_cases atTarget : destination == target
    · simp only [atTarget, ↓reduceIte, Option.some.injEq] at selected
      subst edge
      have targetEq : destination = target := beq_iff_eq.mp atTarget
      subst destination
      have sourceEq : source = ⟨index⟩ := edgeSource.symm.trans (outgoing_source _ _ _ out)
      have found : program.blocks[index]? = some code := List.mk_mem_zipIdx_iff_getElem?.mp atCode
      rw [sourceEq]
      simp only [successors, found, Option.map_some, Option.getD_some]
      exact List.mem_map.mpr ⟨(target, actual), out, rfl⟩
    · simp [atTarget] at selected
  · intro member
    cases found : program.blocks[source.value]? with
    | none => simp [successors, found] at member
    | some code =>
      simp only [successors, found, Option.map_some, Option.getD_some] at member
      obtain ⟨⟨destination, edge⟩, out, destinationEq⟩ := List.mem_map.mp member
      simp only at destinationEq
      subst destination
      refine List.mem_map.mpr ⟨edge, ?_, outgoing_source _ _ _ out⟩
      apply List.mem_flatMap.mpr
      refine ⟨(code, source.value), List.mk_mem_zipIdx_iff_getElem?.mpr found, ?_⟩
      exact List.mem_filterMap.mpr ⟨(target, edge), out, by simp⟩

private theorem incoming_parent_inside (program : Program) (source target : BlockId)
    (member : source ∈ (incoming program target).map Incoming.source) : source ∈ blockIds program := by
  obtain ⟨edge, atEdge, same⟩ := List.mem_map.mp member
  rw [← same]
  exact (blockIds_member _ _).mpr (incoming_source_bounded _ _ _ atEdge)

theorem forward_reach_iff_dependency (program : Program) (start target : BlockId)
    (inside : target ∈ blockIds program) :
    FiniteReachability.ReachIn (successors program) (blockIds program) [start] target ↔
      FiniteDependency.Depends (fun block => block == start)
        (fun block => (incoming program block).map Incoming.source) target := by
  constructor
  · intro reached
    induction reached with
    | root _ seed => exact .here (by simpa using seed)
    | edge prior _ next ih => exact .through ((incoming_iff_successor _ _ _).mpr next) (ih prior.inside)
  · intro dependent
    revert inside
    induction dependent with
    | here exposed =>
      intro inside
      exact .root inside (by simpa using exposed)
    | @through target source member _ ih =>
      intro inside
      exact .edge (ih (incoming_parent_inside _ _ _ member)) inside ((incoming_iff_successor _ _ _).mp member)

/-- Only reachable nodes enter the worklist. Filtering the original catalog
retains exactly the established ascending block order. -/
def reachableFast (program : Program) (start : BlockId) : List BlockId :=
  (blockIds program).filter (FiniteReachability.gather (successors program) (blockIds program) [start]).contains

theorem reachable_fast_exact (program : Program) (start target : BlockId)
    (inside : target.value < program.blocks.length) :
    target ∈ reachableFast program start ↔
      FiniteDependency.Depends (fun block => block == start)
        (fun block => (incoming program block).map Incoming.source) target := by
  have member := (blockIds_member program target).mpr inside
  simp only [reachableFast, List.mem_filter, member, true_and, List.contains_iff_mem]
  rw [FiniteReachability.gather_exact]
  exact forward_reach_iff_dependency _ _ _ member

/-- This equality includes malformed graphs, dangling edges, out-of-range
starts, duplicate edges and cycles. No admission premise changes the domain. -/
theorem reachable_fast_eq (program : Program) (start : BlockId) :
    reachableFast program start = reachable program start := by
  unfold reachableFast reachable
  apply List.filter_congr
  intro target inside
  apply Bool.eq_iff_iff.mpr
  have inRange := (blockIds_member program target).mp inside
  have fast := reachable_fast_exact program start target inRange
  have old := reachable_exact program start target inRange
  simpa only [reachableFast, reachable, List.mem_filter, inside, true_and] using fast.trans old.symm

theorem reachable_forward (program : Program) (start : BlockId) :
    reachable program start = reachableFast program start := (reachable_fast_eq program start).symm

end BoundaryV2.Profile.Target.Borrow
