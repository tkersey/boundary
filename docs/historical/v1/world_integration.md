# World integration

World consumes Boundary Machine ABI v2 structurally. It uses the Machine's
state, arguments, result, effect row, manifest, stepping, resumption, and
canonical state codec.

```text
Boundary Machine -> World application -> application.world.wasm
```

World closes a comptime-known acyclic graph of Machines, selects exact internal
providers, subtracts internally handled sites, and packages the remaining
effects into Application ABI v1. A parked provider retains its own RNF state
alongside the parent binding.

The Boundary 1.0 adoption does not require changes to World Application ABI v1,
Frame v1, EffectRequest v1, EffectResult v1, or the one-pending-effect rule.
World Frames may continue to store a dense Machine id, parent binding id, and
canonical nested Boundary state bytes.

The released generic `world-host` remains the persistence owner, policy
membrane, and effect broker. Capability code produces typed EffectResult values;
it cannot author a Boundary state or World Frame.
