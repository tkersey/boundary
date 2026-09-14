import BoundaryV2.GeneralizedExitCorrespondence

namespace BoundaryV2.Generalized.Defunctionalization

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

theorem RegionHandoffRelated.offer
    {source : Source.RegionHandoff signature algebra program input result}
    {target : ExitComposition.RegionHandoff signature algebra program input result}
    (related : RegionHandoffRelated source target) :
    Option.Rel (fun sourceAfter targetAfter =>
      targetAfter.1 = ⟨sourceAfter.1.fst, value sourceAfter.1.snd⟩ ∧ RegionHandoffRelated sourceAfter.2 targetAfter.2)
      source.offerNext target.offerNext := by
  rcases source with ⟨identity, sourceRuntime, sourceOutside, kept⟩
  rcases target with ⟨targetIdentity, targetRuntime, targetOutside, targetKept⟩
  cases related with
  | same identity kept runtime outside =>
    rcases sourceRuntime with ⟨sourceId, completion, sourceStore, sourceCells, regions, exit⟩
    rcases targetRuntime with ⟨targetId, phase, targetStore, targetCells, targetRegions, targetExit⟩
    rcases runtime with ⟨sameId, completed, stores, storage, live, sameExit⟩
    dsimp only at sameId completed stores storage live sameExit
    subst targetId phase targetCells targetRegions targetExit
    have mapped := Cells.take_oldest_commutes_with_body_mapping
      (fun _ _ body => computation body) identity sourceCells kept
    change Cells.takeOldest identity (cells sourceCells) kept =
      (Cells.takeOldest identity sourceCells kept).map
        (fun selected => (selected.1.map (fun _ _ body => computation body), cells selected.2)) at mapped
    simp only [Source.RegionHandoff.offerNext, ExitComposition.RegionHandoff.offerNext, mapped]
    cases selected : Cells.takeOldest identity sourceCells kept with
    | none => simp only [Option.map_none]; exact .none
    | some pair =>
      rcases pair with ⟨cell, remaining⟩
      simp only [Option.map_some, Cell.map, Value.map_preserves_owning_fields]
      split
      · exact .some ⟨rfl, .same identity _ ⟨rfl, rfl, stores, rfl, rfl, rfl⟩ outside⟩
      · refine .some ⟨rfl, .same identity kept ⟨rfl, rfl, ?_, rfl, rfl, rfl⟩ outside⟩
        exact { stores with fields := by simp only [stores.fields] }

/-- Each side checks its own surviving control and current cells before
removing storage. The shared predicate concerns only typed support data. -/
theorem unwound_region_retirement_corresponds
    (identity : Id .region) (external : List Reference)
    {source : Source.ExitRuntime signature algebra program} {target : ExitComposition.Runtime signature algebra program}
    (runtime : ExitRuntimeRelated source target)
    {sourceOutside : Source.Context signature algebra program input result}
    {targetOutside : Target.Stack signature algebra program input result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside) :
    Option.Rel ExitResolutionRelated (Source.retireUnwoundRegion identity source sourceOutside external)
      ((ExitComposition.Resolution.unwind target targetOutside).retireRegions [identity] external) := by
  rcases source with ⟨sourceId, completion, sourceStore, sourceCells, regions, exit⟩
  rcases target with ⟨targetId, phase, targetStore, targetCells, targetRegions, targetExit⟩
  rcases runtime with ⟨sameId, completed, stores, storage, live, sameExit⟩
  dsimp only at sameId completed stores storage live sameExit
  subst targetId phase targetCells targetRegions targetExit
  have remaining := Cells.outside_regions_commutes_with_body_mapping
    (fun _ _ body => computation body) [identity] sourceCells
  change Cells.outsideRegions [identity] (cells sourceCells) = cells (Cells.outsideRegions [identity] sourceCells) at remaining
  simp only [Source.retireUnwoundRegion, ExitComposition.Resolution.retireRegions,
    ExitComposition.Resolution.cleanupFinished, ExitComposition.Resolution.withoutRegions,
    ExitComposition.Resolution.withStorage, ExitComposition.Resolution.regions, ExitComposition.Resolution.cells,
    ExitComposition.Resolution.referenceSupport, Bool.true_and, remaining,
    store_reference_support stores, cell_installation_support, context_reference_support outside, List.append_assoc]
  rw [show canRetireStorage [identity] regions (cells sourceCells) _ = canRetireStorage [identity] regions sourceCells _ from
    storage_retirement_check_commutes_with_body_mapping (fun _ _ body => computation body) [identity] regions sourceCells _]
  split
  · exact .some (.unwind ⟨rfl, rfl, stores, rfl, rfl, rfl⟩ outside)
  · exact .none

theorem RegionDisposalRelated.begin (related : ExitResolutionRelated source target) :
    Option.Rel RegionDisposalRelated (Source.RegionDisposal.begin source) (ExitComposition.RegionDisposal.begin target) := by
  cases related with
  | reenter states => exact .none
  | unwind runtime outside =>
    have matched := unwind_boundary_corresponds outside
    simp only [Source.RegionDisposal.begin, ExitComposition.RegionDisposal.begin,
      ExitComposition.Resolution.cleanupFinished, runtime.completion, Bool.not_true, Bool.false_eq_true, ↓reduceIte]
    cases first : Source.unwindBoundary _ <;> cases second : Target.unwindBoundary _ <;>
      try simp only [first, second] at matched
    all_goals cases matched
    all_goals first | exact .none | exact .some (.offering (.same _ [] runtime ‹_›))

theorem RegionDisposalRelated.offer (related : RegionDisposalRelated source target) :
    Option.Rel RegionDisposalRelated source.offer target.offer := by
  cases related with
  | disposing => exact .none
  | offering handoff =>
    have offered := handoff.offer
    cases handoff with
    | same identity kept runtime outside =>
      simp only [Source.RegionDisposal.offer, ExitComposition.RegionDisposal.offer,
        ExitComposition.Resolution.cleanupFinished, runtime.completion, Bool.not_true, Bool.false_eq_true, ↓reduceIte]
      apply option_related_map offered _ _
      intro sourceAfter targetAfter matching
      rcases sourceAfter with ⟨⟨type, original⟩, sourceHandoff⟩
      rcases targetAfter with ⟨targetValue, targetHandoff⟩
      rcases matching with ⟨same, handoffs⟩
      dsimp only at same
      subst targetValue
      cases handoffs with
      | same identity kept runtime outside =>
        simpa only [Source.ValueDisposal.start, ExitComposition.ValueDisposal.start,
          disposalValues, List.map_cons, List.map_nil] using
          RegionDisposalRelated.disposing outside (ValueDisposalRelated.ready [⟨type, original⟩] runtime)

theorem RegionDisposalRelated.return_value (related : RegionDisposalRelated source target) :
    Option.Rel RegionDisposalRelated source.returnValue target.returnValue := by
  cases related with
  | offering => exact .none
  | disposing outside values =>
    cases values with
    | control => exact .none
    | ready pending runtime =>
      cases pending with
      | cons => exact .none
      | nil => exact .some (.offering (.same _ _ runtime outside))

theorem RegionDisposalRelated.finish (related : RegionDisposalRelated source target) (external : List Reference) :
    Option.Rel ExitResolutionRelated (source.finish external) (target.finish external) := by
  cases related with
  | disposing => exact .none
  | offering handoff =>
    rename_i sourceHandoff targetHandoff
    have offered := handoff.offer
    have samePresence : sourceHandoff.offerNext.isNone = targetHandoff.offerNext.isNone := by
      cases first : sourceHandoff.offerNext <;> cases second : targetHandoff.offerNext <;>
        simp only [first, second] at offered
      all_goals cases offered <;> rfl
    cases handoff with
    | same identity kept runtime outside =>
      simp only [Source.RegionDisposal.finish, ExitComposition.RegionDisposal.finish, samePresence]
      split
      · exact unwound_region_retirement_corresponds identity external runtime outside
      · exact .none

end BoundaryV2.Generalized.Defunctionalization
