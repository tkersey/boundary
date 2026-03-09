# Zero-Cost Contract

`shift` uses comptime to generate typed control families while keeping runtime work explicit and measurable.

Guaranteed by design:

- Prompt tokens are zero-sized marker types.
- `ControlSpec` performs shape validation and adapter generation at comptime.
- No-capture starts do not allocate.
- Operation dispatch is a tagged-union switch, not a runtime registry or string lookup.

Allowed runtime costs:

- One-time `Session.create` allocation up front.
- Heap boxing only after the first real suspension.
- One-shot terminal-state checks on resume or discard plus explicit `clone()` / `release()` refcount traffic when callers duplicate continuation handles.
- Prompt or continuation replay through precomputed static descriptors.
- Intrusive active continuation bookkeeping in `Session` and separate continuation control blocks that can outlive session destruction.
