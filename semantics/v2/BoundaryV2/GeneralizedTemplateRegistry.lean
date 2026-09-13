import BoundaryV2.GeneralizedSourceFreeze
import BoundaryV2.GeneralizedSourceActivation

namespace BoundaryV2.Generalized

namespace TemplateRegistry

variable {signature : Signature} {Before After : ControlShape signature → Type}

structure Binding (Payload : ControlShape signature → Type) where
  identity : Id .control
  payload : Sigma Payload

abbrev Registry (Payload : ControlShape signature → Type) := List (Binding Payload)

def identities (registry : Registry Before) : List (Id .control) := registry.map Binding.identity

def find (identity : Id .control) : Registry Before → Option (Sigma Before)
  | [] => none
  | first :: rest => if identity = first.identity then some first.payload else find identity rest

def lookup [DecidableEq (ControlShape signature)] (shape : ControlShape signature)
    (identity : Id .control) (registry : Registry Before) : Option (Before shape) :=
  (find identity registry).bind (UseScope.unpackControl shape)

/-- A retained reference cannot silently acquire another template through an
overwrite, even when the replacement has the same type. -/
def insert (identity : Id .control) (payload : Before shape) (registry : Registry Before) : Option (Registry Before) :=
  if identity ∈ identities registry then none else some (⟨identity, ⟨shape, payload⟩⟩ :: registry)

def map (convert : ∀ shape, Before shape → After shape) (registry : Registry Before) : Registry After :=
  registry.map fun binding => ⟨binding.identity, UseScope.mapPacked convert binding.payload⟩

theorem map_identities (convert : ∀ shape, Before shape → After shape) (registry : Registry Before) :
    identities (map convert registry) = identities registry := by
  simp only [identities, map, List.map_map, Function.comp_def]

theorem inserted_lookup [DecidableEq (ControlShape signature)]
    (fresh : identity ∉ identities registry) (payload : Before shape) :
    (insert identity payload registry).bind (lookup shape identity) = some payload := by
  simp only [insert, if_neg fresh, Option.bind_some, lookup, find, ↓reduceIte, Option.bind_some,
    UseScope.unpack_control_exact]

theorem insert_preserves_unique_identities (unique : (identities registry).Nodup)
    (inserted : insert identity payload registry = some after) : (identities after).Nodup := by
  unfold insert at inserted
  split at inserted
  · cases inserted
  · rename_i fresh
    cases inserted
    exact List.nodup_cons.mpr ⟨fresh, unique⟩

theorem insert_refuses_rebinding (present : identity ∈ identities registry) (payload : Before shape) :
    insert identity payload registry = none := by simp only [insert, if_pos present]

theorem inserted_other_lookup [DecidableEq (ControlShape signature)]
    {registry after : Registry Before} {payload : Before original} (different : other ≠ identity)
    (inserted : insert identity payload registry = some after) :
    lookup shape other after = lookup shape other registry := by
  unfold insert at inserted
  split at inserted
  · cases inserted
  · cases inserted
    simp only [lookup, find, if_neg different]

theorem lookup_after_insert [DecidableEq (ControlShape signature)] {payload : Before shape}
    (inserted : insert identity payload registry = some after) : lookup shape identity after = some payload := by
  unfold insert at inserted
  split at inserted
  · cases inserted
  · cases inserted
    simp only [lookup, find, ↓reduceIte, Option.bind_some, UseScope.unpack_control_exact]

theorem find_absent (registry : Registry Before) (absent : identity ∉ identities registry) : find identity registry = none := by
  induction registry with
  | nil => rfl
  | cons first rest induction =>
    have parts : identity ≠ first.identity ∧ identity ∉ identities rest := by simpa [identities] using absent
    simp only [find, if_neg parts.1, induction parts.2]

theorem inserted_lookup_preserves_existing [DecidableEq (ControlShape signature)]
    {registry after : Registry Before} {payload : Before original} {old : Before shape}
    (inserted : insert identity payload registry = some after) (present : lookup shape wanted registry = some old) :
    lookup shape wanted after = some old := by
  unfold insert at inserted
  split at inserted
  · cases inserted
  · rename_i fresh
    cases inserted
    have different : wanted ≠ identity := by
      intro same
      subst wanted
      simp only [lookup, find_absent registry fresh, Option.bind_none] at present
      cases present
    simpa only [lookup, find, if_neg different] using present

theorem find_map (convert : ∀ shape, Before shape → After shape) (registry : Registry Before) :
    find identity (map convert registry) = (find identity registry).map (UseScope.mapPacked convert) := by
  induction registry with
  | nil => rfl
  | cons first rest induction =>
    simp only [map, List.map_cons, find]
    split
    · rfl
    · exact induction

theorem unpack_map [DecidableEq (ControlShape signature)] (convert : ∀ shape, Before shape → After shape)
    (packed : Sigma Before) (shape : ControlShape signature) :
    UseScope.unpackControl shape (UseScope.mapPacked convert packed) =
      (UseScope.unpackControl shape packed).map (convert shape) := by
  rcases packed with ⟨original, payload⟩
  by_cases same : original = shape
  · subst original
    simp only [UseScope.mapPacked, UseScope.unpack_control_exact, Option.map_some]
  · simp only [UseScope.mapPacked, UseScope.unpack_control_wrong_shape same, Option.map_none]

theorem lookup_map [DecidableEq (ControlShape signature)] (convert : ∀ shape, Before shape → After shape)
    (registry : Registry Before) (shape : ControlShape signature) :
    lookup shape identity (map convert registry) = (lookup shape identity registry).map (convert shape) := by
  unfold lookup
  rw [find_map]
  cases find identity registry with
  | none => rfl
  | some payload => exact unpack_map convert payload shape

theorem insert_map (convert : ∀ shape, Before shape → After shape) (registry : Registry Before)
    (payload : Before shape) :
    insert identity (convert shape payload) (map convert registry) = (insert identity payload registry).map (map convert) := by
  simp only [insert, map_identities]
  split <;> rfl

end TemplateRegistry

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

abbrev Source.Multi.Registry (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) :=
  TemplateRegistry.Registry (Source.Multi.Template signature algebra program)

abbrev Target.Multi.Registry (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) :=
  TemplateRegistry.Registry (Target.Multi.Template signature algebra program)

def Defunctionalization.templateRegistry (source : Source.Multi.Registry signature algebra program) :
    Target.Multi.Registry signature algebra program := TemplateRegistry.map (fun _ => Defunctionalization.template) source

def Source.Multi.registryReferences (registry : Registry signature algebra program) : List Reference :=
  registry.flatMap fun binding => .name .control binding.identity :: binding.payload.snd.image.references

def Target.Multi.registryReferences (registry : Registry signature algebra program) : List Reference :=
  registry.flatMap fun binding => .name .control binding.identity :: binding.payload.snd.image.references

theorem Defunctionalization.registry_reference_support (source : Source.Multi.Registry signature algebra program) :
    Target.Multi.registryReferences (templateRegistry source) = Source.Multi.registryReferences source := by
  simp only [templateRegistry, TemplateRegistry.map, Target.Multi.registryReferences, Source.Multi.registryReferences,
    List.flatMap_map, UseScope.mapPacked, template, template_image_references]

end BoundaryV2.Generalized
