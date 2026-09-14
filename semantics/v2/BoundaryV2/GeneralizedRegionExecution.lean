import BoundaryV2.GeneralizedStateExecution

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

theorem Target.fresh_region_avoids_live_and_supported_names
    (table : Target.Definitions signature algebra program)
    (code : Target.Code signature algebra program context operands input)
    (bindings : Target.RuntimeEnvironment signature algebra program context)
    (values : Target.RuntimeEnvironment signature algebra program operands)
    (outside : Target.Stack signature algebra program input result) (store : Target.ControlHeap signature algebra program)
    (cells : Cells signature algebra (fun context result => Target.Code signature algebra program context [] result))
    (regions : List (Id .region)) (extra : List Reference) :
    let identity := Target.freshRegion table code bindings values outside store cells regions extra
    identity ∉ regions ∧
      identity ∉ referenceNames (Target.installationSupport table code bindings values outside store cells extra) .region := by
  have fresh := UseScope.fresh_name_not_supported
    (regions ++ referenceNames (Target.installationSupport table code bindings values outside store cells extra) .region)
  exact ⟨fun member => fresh (List.mem_append_left _ member),
    fun member => fresh (List.mem_append_right _ member)⟩

theorem Target.region_entry_preserves_distinct_liveness
    (table : Target.Definitions signature algebra program)
    (code : Target.Code signature algebra program context operands input)
    (bindings : Target.RuntimeEnvironment signature algebra program context)
    (values : Target.RuntimeEnvironment signature algebra program operands)
    (outside : Target.Stack signature algebra program input result) (store : Target.ControlHeap signature algebra program)
    (cells : Cells signature algebra (fun context result => Target.Code signature algebra program context [] result))
    (regions : List (Id .region)) (extra : List Reference) (unique : regions.Nodup) :
    (Target.freshRegion table code bindings values outside store cells regions extra :: regions).Nodup :=
  List.nodup_cons.mpr ⟨(Target.fresh_region_avoids_live_and_supported_names table code bindings values outside store cells regions extra).1, unique⟩

namespace Defunctionalization

variable [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]

variable {retained : List Reference}

/-- Region entry creates liveness and gives the body its typed region value.
Existing control/cell owners remain in place, and the region frame retains the
close boundary under the caller's continuation. -/
theorem compiled_region_entry
    (table : Source.Definitions signature algebra program)
    (body : Source.Computation signature algebra program (.region :: context) answer)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    {sourceOutside : Source.Context signature algebra program answer result}
    {targetOutside : Target.Stack signature algebra program answer result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    {sourceStore : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (stores : ControlHeapRelated sourceStore targetStore)
    (sourceCells : Cells signature algebra (Source.Computation signature algebra program))
    (regions : List (Id .region)) (extra : List Reference) :
    let identity := Target.freshRegion (definitions table) (computation (.withRegion body))
      (environment bindings) .nil targetOutside targetStore (cells sourceCells) regions (retained ++ extra)
    Source.ExecutionStep (retained := retained) table
      ⟨⟨sourceStore, sourceOutside.plug (.evaluate (.withRegion body) bindings)⟩, sourceCells, regions⟩
      ⟨⟨sourceStore, sourceOutside.plug (.region identity (.evaluate body (.cons (.datum (.region identity)) bindings)))⟩,
        sourceCells, identity :: regions⟩ ∧
    Target.ExecutionSteps (retained := retained) (definitions table)
      ⟨⟨targetStore, .code (computation (.withRegion body)) (environment bindings) .nil targetOutside⟩, cells sourceCells, regions⟩ 1
      ⟨⟨targetStore, .code (computation body) (.cons (.datum (.region identity)) (environment bindings)) .nil
        (.push (.region identity) (.push (.returnTo .ret (environment bindings) .nil) targetOutside))⟩,
        cells sourceCells, identity :: regions⟩ ∧
    CellStateRelated
      ⟨⟨sourceStore, sourceOutside.plug (.region identity (.evaluate body (.cons (.datum (.region identity)) bindings)))⟩,
        sourceCells, identity :: regions⟩
      ⟨⟨targetStore, .code (computation body) (.cons (.datum (.region identity)) (environment bindings)) .nil
        (.push (.region identity) (.push (.returnTo .ret (environment bindings) .nil) targetOutside))⟩,
        cells sourceCells, identity :: regions⟩ := by
  dsimp only
  have same := fresh_region_corresponds table (.withRegion body) bindings targetOutside targetStore sourceCells regions (retained ++ extra)
  refine ⟨.enterRegion extra (context_installation_support outside) (store_installation_support stores) same.symm,
    .single (.enterRegion extra rfl), ?_⟩
  let identity := Target.freshRegion (definitions table) (computation (.withRegion body))
    (environment bindings) .nil targetOutside targetStore (cells sourceCells) regions (retained ++ extra)
  refine ⟨⟨stores, ?_⟩, rfl, rfl⟩
  simpa only [identity, Source.Context.plug, Source.Frame.plug, environment, Environment.map, Value.map] using
    EntryRelated.evaluate body (.cons (.datum (.region identity)) bindings)
      (.push (.region identity) (.passthrough bindings outside))

end Defunctionalization
end BoundaryV2.Generalized
