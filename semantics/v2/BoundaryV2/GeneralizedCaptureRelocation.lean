import BoundaryV2.GeneralizedSourceRelocation
import BoundaryV2.GeneralizedSourceTemplates

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

namespace Source

def relocateValue (relocation : UseScope.Relocation) (value : RuntimeValue signature algebra program type) :
    RuntimeValue signature algebra program type := value.relocate relocation (fun _ _ body => body.relocate relocation)

def relocateEnvironment (relocation : UseScope.Relocation) (bindings : RuntimeEnvironment signature algebra program context) :
    RuntimeEnvironment signature algebra program context := bindings.relocate relocation (fun _ _ body => body.relocate relocation)

def Capture.relocate (relocation : UseScope.Relocation) : Capture signature algebra program input result → Capture signature algebra program input result
  | .done => .done
  | .bind body bindings rest => .bind (body.relocate relocation) (relocateEnvironment relocation bindings) (rest.relocate relocation)
  | .handler effect mode identity returned clauses bindings rest =>
      .handler effect mode (relocation.name .attachment identity) (returned.relocate relocation)
        (clauses.relocate relocation) (relocateEnvironment relocation bindings) (rest.relocate relocation)
  | .region identity rest => .region (relocation.name .region identity) (rest.relocate relocation)
  | .protection identity cleanup bindings rest =>
      .protection (relocation.name .obligation identity) (cleanup.relocate relocation)
        (relocateEnvironment relocation bindings) (rest.relocate relocation)

def relocateCell (relocation : UseScope.Relocation) (cell : Cell signature algebra (Computation signature algebra program)) :
    Cell signature algebra (Computation signature algebra program) :=
  ⟨relocation.name .cell cell.identity, relocation.name .region cell.region, cell.type, relocateValue relocation cell.value⟩

def Multi.Future.relocate (relocation : UseScope.Relocation) (future : Multi.Future signature algebra program shape) :
    Multi.Future signature algebra program shape := ⟨relocation.name .attachment future.attachment, future.capture.relocate relocation⟩

mutual
  def Multi.Record.relocate (relocation : UseScope.Relocation) : Multi.Record signature algebra program → Multi.Record signature algebra program
    | .mk identity shape saved cells dormant attachments regions scopes =>
      ⟨relocation.name .control identity, shape, saved.relocate relocation,
        cells.map (relocateCell relocation), Multi.relocateRecords relocation dormant,
        attachments.map (relocation.name .attachment), regions.map (relocation.name .region),
        scopes.map (relocation.name .scope)⟩
  def Multi.relocateRecords (relocation : UseScope.Relocation) : List (Multi.Record signature algebra program) → List (Multi.Record signature algebra program)
    | [] => []
    | first :: rest => first.relocate relocation :: Multi.relocateRecords relocation rest
end

end Source

namespace Defunctionalization

mutual
  theorem value_relocation_commutes (relocation : UseScope.Relocation)
      {type : TypeOf signature} (source : Source.RuntimeValue signature algebra program type) :
      Target.relocateValue relocation (value source) = value (Source.relocateValue relocation source) := by
    cases source with
    | datum datum | continuation identity authority | cell identity region | exit information => rfl
    | pair first second =>
      exact (congrArg (Value.pair · (Target.relocateValue relocation (value second))) (value_relocation_commutes relocation first)).trans
        (congrArg (Value.pair (value (Source.relocateValue relocation first))) (value_relocation_commutes relocation second))
    | left item => exact congrArg Value.left (value_relocation_commutes relocation item)
    | right item => exact congrArg Value.right (value_relocation_commutes relocation item)
    | closure body captured authority =>
      simp only [Target.relocateValue, value, Value.map, Value.relocate, Source.relocateValue]
      rw [computation_relocation_commutes]
      exact congrArg (fun bindings => Value.closure (computation (body.relocate relocation)) bindings (relocateAuthority relocation authority))
        (environment_relocation_commutes relocation captured)
    | package token owner item =>
      exact congrArg (Value.package (relocation.name .custody token) (relocation.owner owner))
        (value_relocation_commutes relocation item)
  termination_by sizeOf source

  theorem environment_relocation_commutes (relocation : UseScope.Relocation)
      {types : List (TypeOf signature)} (source : Source.RuntimeEnvironment signature algebra program types) :
      Target.relocateEnvironment relocation (environment source) = environment (Source.relocateEnvironment relocation source) := by
    cases source with
    | nil => rfl
    | cons first rest =>
      exact (congrArg (Environment.cons · (Target.relocateEnvironment relocation (environment rest)))
        (value_relocation_commutes relocation first)).trans
        (congrArg (Environment.cons (value (Source.relocateValue relocation first))) (environment_relocation_commutes relocation rest))
  termination_by sizeOf source
end

theorem capture_relocation_commutes (relocation : UseScope.Relocation) (source : Source.Capture signature algebra program input result) :
    (capture source).relocate relocation = capture (source.relocate relocation) := by
  induction source with
  | done => rfl
  | bind body bindings rest induction =>
      simp only [capture, Source.Capture.relocate, Target.Stack.relocate, Target.Frame.relocate,
        Target.Code.relocate, computation_relocation_commutes, environment_relocation_commutes, induction]
      rfl
  | handler effect mode identity returned clauses bindings rest induction =>
      simp only [capture, Source.Capture.relocate, Target.Stack.relocate, Target.Frame.relocate,
        computation_relocation_commutes, clauses_relocation_commutes, environment_relocation_commutes, induction]
  | region identity rest induction => exact congrArg (Target.Stack.push (.region (relocation.name .region identity))) induction
  | protection identity cleanup bindings rest induction =>
      simp only [capture, Source.Capture.relocate, Target.Stack.relocate, Target.Frame.relocate,
        computation_relocation_commutes, environment_relocation_commutes, induction]

theorem template_future_relocation (relocation : UseScope.Relocation) (source : Source.Multi.Future signature algebra program shape) :
    (templateFuture source).relocate relocation = templateFuture (source.relocate relocation) := by
  simp only [templateFuture, Target.Resumption.relocate, Source.Multi.Future.relocate, capture_relocation_commutes]

theorem cell_relocation_commutes (relocation : UseScope.Relocation)
    (source : Cell signature algebra (Source.Computation signature algebra program)) :
    Target.relocateCell relocation (source.map (fun _ _ body => computation body)) =
      (Source.relocateCell relocation source).map (fun _ _ body => computation body) := by
  change Cell.mk _ _ _ (Target.relocateValue relocation (value source.value)) = Cell.mk _ _ _ (value (Source.relocateValue relocation source.value))
  rw [value_relocation_commutes]
  rfl

mutual
  theorem template_record_relocation (relocation : UseScope.Relocation) (source : Source.Multi.Record signature algebra program) :
      (templateRecord source).relocate relocation = templateRecord (source.relocate relocation) := by
    cases source with
    | mk identity shape saved localCells dormant attachments regions scopes =>
      simp only [templateRecord, Target.Multi.Record.relocate, Source.Multi.Record.relocate, template_future_relocation,
        cells, Cells.mapBodies, List.map_map, Function.comp_def, cell_relocation_commutes,
        template_records_relocation relocation dormant]
  termination_by sizeOf source
  decreasing_by cases source; simp_all; omega

  theorem template_records_relocation (relocation : UseScope.Relocation) (records : List (Source.Multi.Record signature algebra program)) :
      Target.Multi.relocateRecords relocation (templateRecords records) = templateRecords (Source.Multi.relocateRecords relocation records) := by
    cases records with
    | nil => rfl
    | cons first rest => simp only [templateRecords, Target.Multi.relocateRecords, Source.Multi.relocateRecords,
        template_record_relocation relocation first, template_records_relocation relocation rest]
  termination_by sizeOf records
end

end Defunctionalization
end BoundaryV2.Generalized
