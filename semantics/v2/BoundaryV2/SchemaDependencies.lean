import BoundaryV2.ProgramDeclarations
import BoundaryV2.DependencyAdmission

namespace BoundaryV2.Profile.Target.Admission

def ambientEffect (program : Program) (effect : EffectId .target) : Bool :=
  program.blocks.any (fun block => match block.terminator with
    | .perform operation => operation.effect == effect && operation.capability.isNone
    | _ => false)

def dependencyContext (program : Program) : DependencyAdmission.Context .target :=
  ⟨program.schemas, program.effects.length, ambientEffect program⟩

def schemaIds (program : Program) := DependencyAdmission.schemaIds (dependencyContext program)
def effectDirect (program : Program) := DependencyAdmission.effectDirect (dependencyContext program)
def schemaDirect (program : Program) := DependencyAdmission.schemaDirect (dependencyContext program)
def schemaChildren (program : Program) := DependencyAdmission.schemaChildren (dependencyContext program)
def effectSafeSchemas (program : Program) := DependencyAdmission.effectSafeSchemas (dependencyContext program)
def regionSafeSchemas (program : Program) := DependencyAdmission.regionSafeSchemas (dependencyContext program)
def EffectDependency (program : Program) := DependencyAdmission.EffectDependency (dependencyContext program)
def RegionDependency (program : Program) := DependencyAdmission.RegionDependency (dependencyContext program)
abbrev effectChildren := @DependencyAdmission.effectChildren .target
abbrev regionDirect := @DependencyAdmission.regionDirect .target
abbrev regionChildren := @DependencyAdmission.regionChildren .target

abbrev schemaIds_member (program : Program) := DependencyAdmission.schemaIds_member (dependencyContext program)

abbrev schema_references_in_bounds (program : Program) := DependencyAdmission.schema_references_in_bounds (dependencyContext program)

abbrev schemaChildren_bounded (program : Program) := DependencyAdmission.schemaChildren_bounded (dependencyContext program)

abbrev effectSafe_exact (program : Program) := DependencyAdmission.effectSafe_exact (dependencyContext program)

abbrev regionSafe_exact (program : Program) := DependencyAdmission.regionSafe_exact (dependencyContext program)

abbrev effectChildren_references := @DependencyAdmission.effectChildren_references .target

abbrev regionChildren_references := @DependencyAdmission.regionChildren_references .target

abbrev EffectFacts := DependencyAdmission.EffectFacts .target

def effectFacts (program : Program) : EffectFacts := DependencyAdmission.effectFacts (dependencyContext program)

def EffectFacts.contains (facts : EffectFacts) := DependencyAdmission.EffectFacts.contains facts

def discharged (facts : EffectFacts) := DependencyAdmission.discharged facts

end BoundaryV2.Profile.Target.Admission
