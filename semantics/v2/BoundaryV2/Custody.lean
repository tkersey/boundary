import BoundaryV2.Values

namespace BoundaryV2.Profile.Custody

inductive Owner where
  | lexical : LexicalScopeId → Nat → Owner
  | temporary : LexicalScopeId → Nat → Owner
  | closure : NodeId → Nat → Owner
  | frame : NodeId → Nat → Owner
  | cell : CellId → Owner
  | protection : ObligationId → Owner
  | detached : TransferId → Nat → Owner
  | unwind : LexicalScopeId → Nat → Owner
  | receiver : InvocationId → Nat → Owner
  deriving DecidableEq, Repr

structure Entry where
  token : CustodyToken
  object : NodeId
  owner : Owner
  deriving DecidableEq, Repr

/-- One record per live exclusive object. Reusable references and template
aliases do not allocate records in this book. Graph admission separately binds
these records to actual owning edges and value locations. -/
structure Book where
  entries : List Entry
  tokens_unique : (entries.map Entry.token).Nodup
  objects_unique : (entries.map Entry.object).Nodup

def empty : Book := ⟨[], by simp, by simp⟩

def allocate (book : Book) (token : CustodyToken) (object : NodeId) (owner : Owner) : Option Book :=
  if freshToken : token ∉ book.entries.map Entry.token then
    if freshObject : object ∉ book.entries.map Entry.object then
      some ⟨⟨token, object, owner⟩ :: book.entries,
        by simpa using And.intro freshToken book.tokens_unique,
        by simpa using And.intro freshObject book.objects_unique⟩
    else none
  else none

theorem allocation_is_fresh (book after : Book) (token : CustodyToken) (object : NodeId) (owner : Owner)
    (accepted : allocate book token object owner = some after) :
    token ∉ book.entries.map Entry.token ∧ object ∉ book.entries.map Entry.object ∧
    after.entries = ⟨token, object, owner⟩ :: book.entries := by
  unfold allocate at accepted
  split at accepted
  · split at accepted
    · cases accepted; exact ⟨by assumption, by assumption, rfl⟩
    · cases accepted
  · cases accepted

def without (book : Book) (tokens : List CustodyToken) : Book where
  entries := book.entries.filter (fun entry => !tokens.contains entry.token)
  tokens_unique := book.tokens_unique.sublist ((List.filter_sublist).map Entry.token)
  objects_unique := book.objects_unique.sublist ((List.filter_sublist).map Entry.object)

def has (book : Book) (token : CustodyToken) (owner : Owner) : Bool :=
  book.entries.any (fun entry => entry.token == token && entry.owner == owner)

def consume (book : Book) (tokens : List CustodyToken) (owner : Owner) : Option Book :=
  if decide tokens.Nodup && tokens.all (fun token => has book token owner) then some (without book tokens)
  else none

theorem consumed_token_absent (book after : Book) (tokens : List CustodyToken) (owner : Owner)
    (accepted : consume book tokens owner = some after) (member : token ∈ tokens) :
    token ∉ after.entries.map Entry.token := by
  unfold consume at accepted
  split at accepted
  · cases accepted
    simp only [without, List.mem_map, List.mem_filter, Bool.not_eq_true']
    rintro ⟨entry, ⟨_, absent⟩, equal⟩
    have notMember : entry.token ∉ tokens := by simpa using absent
    apply notMember
    simpa [equal] using member
  · cases accepted

structure Move where
  token : CustodyToken
  source : Owner
  target : Owner
  deriving DecidableEq, Repr

def destination (moves : List Move) (entry : Entry) : Entry :=
  match moves.find? (fun move => move.token == entry.token) with
  | none => entry
  | some move => { entry with owner := move.target }

theorem destination_token (moves : List Move) (entry : Entry) :
    (destination moves entry).token = entry.token := by
  unfold destination; split <;> rfl

theorem destination_object (moves : List Move) (entry : Entry) :
    (destination moves entry).object = entry.object := by
  unfold destination; split <;> rfl

def relocate (book : Book) (moves : List Move) : Book where
  entries := book.entries.map (destination moves)
  tokens_unique := by simpa [List.map_map, Function.comp_def, destination_token] using book.tokens_unique
  objects_unique := by simpa [List.map_map, Function.comp_def, destination_object] using book.objects_unique

/-- Admission finishes before any relocation. A duplicate operand token is
rejected even when the two proposed destination owners happen to be equal. -/
def admissible (book : Book) (moves : List Move) : Bool :=
  decide ((moves.map Move.token).Nodup) && moves.all (fun move => has book move.token move.source)

def commit (book : Book) (moves : List Move) : Option Book :=
  if admissible book moves then some (relocate book moves) else none

theorem commit_preserves_exact_objects (book : Book) (moves : List Move) (after : Book)
    (accepted : commit book moves = some after) :
    after.entries.map Entry.token = book.entries.map Entry.token ∧
    after.entries.map Entry.object = book.entries.map Entry.object := by
  unfold commit at accepted
  split at accepted
  · cases accepted
    simp [relocate, List.map_map, Function.comp_def, destination_token, destination_object]
  · cases accepted

theorem duplicate_transfer_rejected (book : Book) (first second : Move)
    (same : first.token = second.token) : commit book [first, second] = none := by
  simp [commit, admissible, same]

theorem failed_admission_has_no_successor (book : Book) (moves : List Move)
    (rejected : admissible book moves = false) : commit book moves = none := by simp [commit, rejected]

theorem commit_checks_every_sender (book : Book) (moves : List Move) (after : Book)
    (accepted : commit book moves = some after) (member : move ∈ moves) :
    has book move.token move.source = true := by
  have admitted : admissible book moves = true := by
    unfold commit at accepted
    split at accepted
    · assumption
    · cases accepted
  have both : (moves.map Move.token).Nodup ∧
      (moves.all (fun move => has book move.token move.source)) = true := by
    simpa [admissible, Bool.and_eq_true] using admitted
  exact List.all_eq_true.mp both.2 move member

def owns (book : Book) (token : CustodyToken) (owner : Owner) : Prop :=
  ∃ entry ∈ book.entries, entry.token = token ∧ entry.owner = owner

private theorem unique_key (key : α → β) (entries : List α) (unique : (entries.map key).Nodup)
    (firstMem : first ∈ entries) (secondMem : second ∈ entries)
    (same : key first = key second) : first = second := by
  induction entries with
  | nil => simp at firstMem
  | cons head tail induction =>
    have both : key head ∉ tail.map key ∧ (tail.map key).Nodup := by
      simpa using unique
    rcases List.mem_cons.mp firstMem with firstHead | firstTail
    · subst first
      rcases List.mem_cons.mp secondMem with secondHead | secondTail
      · exact secondHead.symm
      · exact False.elim (both.1 (List.mem_map.mpr ⟨second, secondTail, same.symm⟩))
    · rcases List.mem_cons.mp secondMem with secondHead | secondTail
      · subst second
        exact False.elim (both.1 (List.mem_map.mpr ⟨first, firstTail, same⟩))
      · exact induction both.2 firstTail secondTail

theorem object_identifies_entry (book : Book) (first second : Entry)
    (firstMem : first ∈ book.entries) (secondMem : second ∈ book.entries)
    (same : first.object = second.object) : first = second :=
  unique_key Entry.object book.entries book.objects_unique firstMem secondMem same

theorem token_identifies_entry (book : Book) (first second : Entry)
    (firstMem : first ∈ book.entries) (secondMem : second ∈ book.entries)
    (same : first.token = second.token) : first = second :=
  unique_key Entry.token book.entries book.tokens_unique firstMem secondMem same

theorem unique_custodian (book : Book) (token : CustodyToken) (left right : Owner)
    (a : owns book token left) (b : owns book token right) : left = right := by
  obtain ⟨first, firstMem, firstToken, firstOwner⟩ := a
  obtain ⟨second, secondMem, secondToken, secondOwner⟩ := b
  have equal := unique_key Entry.token book.entries book.tokens_unique firstMem secondMem (firstToken.trans secondToken.symm)
  cases equal
  exact firstOwner.symm.trans secondOwner

theorem commit_transfers_to_receiver (book : Book) (moves : List Move) (after : Book)
    (accepted : commit book moves = some after) (member : move ∈ moves) :
    owns after move.token move.target := by
  have sender := commit_checks_every_sender book moves after accepted member
  have sourceEntry : ∃ entry ∈ book.entries, entry.token = move.token ∧ entry.owner = move.source := by
    simpa [has, List.any_eq_true, Bool.and_eq_true] using sender
  obtain ⟨entry, entryMem, entryToken, _⟩ := sourceEntry
  unfold commit at accepted
  split at accepted
  · rename_i admitted
    have unique : (moves.map Move.token).Nodup := by
      have both : (moves.map Move.token).Nodup ∧
          moves.all (fun move => has book move.token move.source) = true := by
        simpa [admissible, Bool.and_eq_true] using admitted
      exact both.1
    have found : moves.find? (fun item => item.token == entry.token) = some move := by
      cases search : moves.find? (fun item => item.token == entry.token) with
      | none =>
        have absent := List.find?_eq_none.mp search move member
        simp [entryToken] at absent
      | some selected =>
        have selectedMem := List.mem_of_find?_eq_some search
        have selectedToken : selected.token = entry.token := by simpa using List.find?_some search
        have equal := unique_key Move.token moves unique selectedMem member (selectedToken.trans entryToken)
        exact congrArg some equal
    cases accepted
    refine ⟨destination moves entry, List.mem_map.mpr ⟨entry, entryMem, rfl⟩, ?_, ?_⟩
    · simpa [destination_token] using entryToken
    · simp [destination, found]
  · cases accepted

theorem committed_sender_cannot_reuse (book : Book) (moves : List Move) (after : Book)
    (accepted : commit book moves = some after) (member : move ∈ moves)
    (different : move.target ≠ move.source) : ¬ owns after move.token move.source := by
  intro reuse
  exact different (unique_custodian after move.token move.target move.source
    (commit_transfers_to_receiver book moves after accepted member) reuse)

/-- Each ordered operand is retained at its existing owner until commit. The
pending list records the already evaluated prefix in evaluation order. -/
structure Pending (space : Space) (Operand : Type) where
  remaining : List Operand
  evaluated : List (Value space)
  transfers : List Move
  custody : Book

def retain (pending : Pending space Operand) (value : Value space) (moves : List Move) : Option (Pending space Operand) :=
  match pending.remaining with
  | [] => none
  | _ :: tail => some { pending with
      remaining := tail
      evaluated := pending.evaluated ++ [value]
      transfers := pending.transfers ++ moves }

def finish (pending : Pending space Operand) : Option (Book × List (Value space)) :=
  if pending.remaining.isEmpty then (commit pending.custody pending.transfers).map (·, pending.evaluated)
  else none

theorem operand_prefix_preserves_custody (before after : Pending space Operand) (value : Value space) (moves : List Move)
    (accepted : retain before value moves = some after) : after.custody = before.custody := by
  unfold retain at accepted
  split at accepted
  · cases accepted
  · cases accepted; rfl

theorem operand_prefix_preserves_order (before after : Pending space Operand) (value : Value space) (moves : List Move)
    (accepted : retain before value moves = some after) :
    after.evaluated = before.evaluated ++ [value] ∧ after.transfers = before.transfers ++ moves := by
  unfold retain at accepted
  split at accepted
  · cases accepted
  · cases accepted; exact ⟨rfl, rfl⟩

theorem unfinished_operands_cannot_commit (pending : Pending space Operand) (head : Operand) (tail : List Operand)
    (remaining : pending.remaining = head :: tail) : finish pending = none := by simp [finish, remaining]

/-- Abrupt failure takes the active owners in caller-specified lexical order;
it does not give them to the operation whose later operand failed. -/
def unwindMoves (scope : LexicalScopeId) (entries : List Entry) : List Move :=
  entries.mapIdx (fun index entry => ⟨entry.token, entry.owner, .unwind scope index⟩)

def unwind (book : Book) (scope : LexicalScopeId) (ordered : List Entry) : Option Book :=
  commit book (unwindMoves scope ordered)

theorem unwind_does_not_lose_objects (before : Book) (scope : LexicalScopeId) (ordered : List Entry) (after : Book)
    (accepted : unwind before scope ordered = some after) :
    after.entries.map Entry.token = before.entries.map Entry.token ∧
    after.entries.map Entry.object = before.entries.map Entry.object :=
  commit_preserves_exact_objects before _ after accepted

end BoundaryV2.Profile.Custody
