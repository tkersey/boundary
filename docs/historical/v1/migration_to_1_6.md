# Migration to Boundary 1.6

Existing users may continue calling `Program.compile(options)`. Machine ABI v2,
`ABL_RNF2` version 1, effect semantics, and existing Machine v2 semantic and contract digests are
unchanged for unchanged source and options.

To publish a reified artifact:

```zig
const Image = Program.image();
const Profile = Program.machineV2Profile(options);
const bytes = Image.bytes;
```

To use the fixed kernel through the typed Machine interface:

```zig
const Machine = Program.kernelMachineV2(options);
```

Direct and kernel v2 Machines have the same Manifest identity. State bytes may be
decoded by either engine. Artifact SHA-256 identifies exact image/kernel bytes;
it does not replace semantic or Machine identity.

BPI1 identity is independent of fuel and deployment capacity. It is a compiler artifact and has no automatic migration promise to future
image versions. Live State migration across changed Program meaning remains an
explicit non-feature.

No public raw evaluator is introduced. Repository-internal clause evaluation
exists only to prove BPI1/direct equivalence; external execution remains the
typed or byte-level Machine ABI v2 compatibility surface.
