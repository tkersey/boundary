# Control Lab

`shift` now has an executable control-lab layer for advanced users.
The lab does not replace the runtime, the research packet, or the existing examples.
It turns the core semantic claims into named witnesses with locked transcripts.

Run it with:

```bash
zig build run-control-studio -- list
zig build run-control-studio -- run pending_loop
zig build run-control-studio -- run terminal_cancel
zig build run-control-studio -- run driver_discontinue
zig build run-control-studio -- run escape_redelimit
```

The machine-readable witness set lives in `src/control_lab/registry.zig`.
The dedicated runner lives in `examples/control_studio/main.zig`.
The transcript lock lives in `test/control_studio_test.zig`.

## Witnesses

<a id="pending-loop"></a>
### Pending Loop

Witness id: `pending_loop`

- Surface: pending-owner first
- Why it exists: proves the ordinary `Outcome.pending` -> `proceed()` loop without involving driver or delayed escape
- See also: `docs/semantics.md`, `examples/generator.zig`

Expected transcript:

```text
yield=1
yield=2
yield=3
done=3
```

<a id="terminal-cancel"></a>
### Terminal Cancel

Witness id: `terminal_cancel`

- Surface: pending-owner first
- Why it exists: shows library-owned cancellation as a terminal branch
- See also: `docs/semantics.md`, `examples/effect_state.zig`

Expected transcript:

```text
cancelled=yes resumed=0
```

<a id="driver-discontinue"></a>
### Driver Discontinue

Witness id: `driver_discontinue`

- Surface: additive driver
- Why it exists: proves `shift.driver` remains a helper layered over the same semantic core
- See also: `docs/job_workflow.md`, `examples/effect_handlers.zig`

Expected transcript:

```text
aborted=yes trace=[enter, before-abort]
```

<a id="escape-redelimit"></a>
### Escape Redelimit

Witness id: `escape_redelimit`

- Surface: escaped owner
- Why it exists: proves delayed escape still resumes into the same delimiter and can suspend again later
- See also: `docs/research_laws.md`, `docs/research_machine.md`, `src/raw_surface.zig`

Expected transcript:

```text
first_request=41
escaped=yes
second_request=42
result=43
```

## Reading Order

1. Start with `pending_loop` for the ordinary direct-style path.
2. Use `terminal_cancel` to see the library-owned terminal branch.
3. Use `driver_discontinue` to see the additive helper surface.
4. Use `escape_redelimit` for the advanced delayed-escape witness.

Once you know which witness you are looking at, return to the research packet:

- `docs/research_laws.md`
- `docs/research_machine.md`
- `docs/research_decision.md`
