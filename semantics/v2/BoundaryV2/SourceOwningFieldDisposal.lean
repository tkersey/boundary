import BoundaryV2.SourceOwningFields

namespace BoundaryV2.Profile.Source.Machine
namespace OwningFields.DisposalWitness

def child : Located := ⟨.reference ⟨0⟩ ⟨0⟩ (some ⟨0⟩), .closure ⟨1⟩ 0⟩
def closure : Located := ⟨.reference ⟨1⟩ ⟨1⟩ (some ⟨1⟩), .temporary ⟨0⟩ 0⟩
def result : Located := ⟨.scalar ⟨2⟩ 0, .temporary ⟨0⟩ 1⟩
def book : Custody.Book := ⟨[⟨⟨0⟩, ⟨0⟩, child.owner⟩, ⟨⟨1⟩, ⟨1⟩, closure.owner⟩], by decide, by decide⟩
def before : State := {
  control := .discard [closure] (.deliver result)
  stack := []
  heap := {
    objects := [some (.resource ⟨0⟩ ⟨.scalar ⟨2⟩ 0, .closure ⟨0⟩ 0⟩),
      some (.closure ⟨1⟩ ⟨0⟩ [⟨⟨0⟩, child⟩])]
    scopes := [⟨⟨0⟩, ⟨0⟩, none, 2, [closure, result]⟩]
    custody := book
    nextCustody := 2
    nextScope := 1 }
  scope := ⟨0⟩
  invocation := ⟨0⟩ }
def after : State := { before with
  control := .discard [child] (.deliver result)
  heap := { before.heap with
    objects := [before.heap.objects[0]!, none]
    custody := Custody.without book [⟨1⟩] } }

theorem heap_covers_before : heapEntries before.heap = book.entries := by
  simp [heapEntries, heap, object, live, before, child, closure, result, book, ownedReferences, Custody.has]
theorem closure_disposal_step (context : Context) : discardValues before context = .ok ⟨after, []⟩ := by
  simp [discardValues, before, after, child, closure, result, lookupObject, current, ownedTokens, liveOwned, liveOwnedValue, require, fromOption, Heap.lookup, retireObject, consumeValue, Custody.consume, Custody.without, Custody.has, book, bind, Except.bind, pure, Except.pure]
theorem child_remains_owned : after.heap.custody.entries = [⟨⟨0⟩, ⟨0⟩, child.owner⟩] := by rfl
theorem heap_only_loses_live_child : heapEntries after.heap = [] := by
  simp [heapEntries, heap, object, live, after, before, child, closure, result, book, ownedReferences, Custody.has, Custody.without]

/-- The source takes a real disposal step whose still-live child has moved
from a heap field into the control queue. Both custody endpoints are exact. -/
theorem closure_disposal_preserves_physical_entries :
    entries before = book.entries ∧ entries after = after.heap.custody.entries := by
  constructor
  · simp [entries, state, control, queue, detached, captured, heap, object, live,
      before, child, closure, result, book, ownedReferences, Custody.has]
  · simp [entries, state, control, queue, detached, captured, heap, object, live,
      after, before, child, closure, result, book, ownedReferences, Custody.has, Custody.without, Heap.lookup]

/-- A suspended disposal keeps the same child in its return frame. -/
theorem disposal_frame_keeps_child :
    entries {after with
      control := .delivered result
      stack := [.disposalReturn [child] (.deliver result) 0 0]} = after.heap.custody.entries := by
  simp [entries, state, control, queue, detached, frame, captured, heap, object, live,
    after, before, child, closure, result, book, ownedReferences, Custody.has, Custody.without, Heap.lookup]

end OwningFields.DisposalWitness
end BoundaryV2.Profile.Source.Machine
