import BoundaryV2.GeneralizedFieldRelocation
import BoundaryV2.GeneralizedCode

namespace BoundaryV2.Generalized

/-- Only explicit logical references move. Leaf values, faults, reasons, type
indices, primitive identities, and positions in finite code tables stay fixed. -/
def Datum.relocate (relocation : UseScope.Relocation) :
    {type : Ty Data Effect} → Datum (Effect := Effect) algebra type → Datum algebra type
  | _, .leaf value => .leaf value
  | _, .unit => .unit
  | _, .pair first second => .pair (first.relocate relocation) (second.relocate relocation)
  | _, .left value => .left (value.relocate relocation)
  | _, .right value => .right (value.relocate relocation)
  | _, .capability identity => .capability (relocation.name .attachment identity)
  | _, .region identity => .region (relocation.name .region identity)
  | _, .resource identity token owner =>
    .resource (relocation.name .resource identity) (relocation.name .custody token) (relocation.owner owner)
  | _, .borrowed identity scope => .borrowed (relocation.name .resource identity) (relocation.name .scope scope)

namespace Target

/- Code constants and dormant bodies participate in the same relocation as
live operands. Moving only the active environment would leave their aliases stale. -/
mutual
  def Code.relocate (relocation : UseScope.Relocation) :
      Code signature algebra program context operands result → Code signature algebra program context operands result
    | .ret => .ret
    | .push datum next => .push (datum.relocate relocation) (next.relocate relocation)
    | .load reference next => .load reference (next.relocate relocation)
    | .pair next => .pair (next.relocate relocation)
    | .first next => .first (next.relocate relocation)
    | .second next => .second (next.relocate relocation)
    | .left next => .left (next.relocate relocation)
    | .right next => .right (next.relocate relocation)
    | .close body next => .close (body.relocate relocation) (next.relocate relocation)
    | .enter body => .enter (body.relocate relocation)
    | .callBlock body next => .callBlock (body.relocate relocation) (next.relocate relocation)
    | .callNamed reference next => .callNamed reference (next.relocate relocation)
    | .callClosure next => .callClosure (next.relocate relocation)
    | .primitive operation next => .primitive operation (next.relocate relocation)
    | .branch left right => .branch (left.relocate relocation) (right.relocate relocation)
    | .dispatch operation next => .dispatch operation (next.relocate relocation)
    | .attach effect mode returned clauses body next =>
      .attach effect mode (returned.relocate relocation) (clauses.relocate relocation)
        (body.relocate relocation) (next.relocate relocation)
    | .resume next => .resume (next.relocate relocation)
    | .replaceHandler effect returned clauses next =>
      .replaceHandler effect (returned.relocate relocation) (clauses.relocate relocation) (next.relocate relocation)
    | .inject next => .inject (next.relocate relocation)
    | .enterRegion body next => .enterRegion (body.relocate relocation) (next.relocate relocation)
    | .cellNew next => .cellNew (next.relocate relocation)
    | .cellRead next => .cellRead (next.relocate relocation)
    | .cellWrite next => .cellWrite (next.relocate relocation)
    | .protect cleanup body next => .protect (cleanup.relocate relocation) (body.relocate relocation) (next.relocate relocation)
    | .dispose next => .dispose (next.relocate relocation)
    | .clone next => .clone (next.relocate relocation)
    | .package next => .package (next.relocate relocation)
    | .unpackage next => .unpackage (next.relocate relocation)
    | .fault fault => .fault fault
    | .yieldThen next => .yieldThen (next.relocate relocation)

  def Clauses.relocate (relocation : UseScope.Relocation) :
      Clauses signature algebra program effect mode context body answer → Clauses signature algebra program effect mode context body answer
    | .nil => .nil
    | .cons operation use code rest => .cons operation use (code.relocate relocation) (rest.relocate relocation)
end

def relocateDefinitions (relocation : UseScope.Relocation) (table : Definitions signature algebra program) :
    Definitions signature algebra program := table.map (fun _ body => body.relocate relocation)

end Target
end BoundaryV2.Generalized
