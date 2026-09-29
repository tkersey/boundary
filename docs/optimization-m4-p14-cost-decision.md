# P14 measured cost decision

Candidate: checked forwarding-thunk elimination, including direct return of a
captured thunk when its wrapper would be returned immediately. Base is Boundary
`4ecb91769e7b0f0ed82e700dad07fa410d678cbd`; exact source, image, tool and runtime
hashes are in `performance/m4-p14.json`. The World kernel remains unchanged.

## Required costs

All 58 final native/WASM timing cells completed under §9.4. Three exceed §9.5's
five-window confirmation threshold:

| WASM fixture / phase | Paired median increase | Ratio |
| --- | ---: | ---: |
| Identity, true / complete checkpoint cycle | 236.17 µs | 1.0962 |
| Ignored divergent peer / admission | 3.16 µs | 1.1405 |
| Ignored failing argument / admission | 2.07 µs | 1.0881 |

Suspended reciprocal execution also raises WASM fresh peak from 29,303 to 30,542
bytes: **+1,239 bytes (4.23%)**, exceeding its 1,024-byte threshold. Other measured
native/WASM memory increases remain within threshold; checkpoints do not grow.
No native timing or WASM fresh-execution slowdown is confirmed. Fresh runs resume
public yields; cycle runs additionally encode/restore at quantum one.

The first candidate used a move in forwarding factories. Returning the exact
capture directly improves its emitted layouts and removes the reentrant retained-
memory threshold violation. Initial measurements remain recorded separately.
One subsequent timing launch accidentally overlapped the aggregate build; it was
terminated and receives no gate credit. The final matrix ran after builds stopped.

## Proof and scope

Final aggregate: 319/319 steps and 727/727 tests. Focused pass: 23/23. The refined
cross-engine matrix passes 55 cases over 62 boundaries, plus 39 malformed inputs,
39 restores and 33 applicable wrong-image rejections. It covers actual generated
hyper helpers, reciprocal/yielded control, unused divergence/failure, different
Step bodies from the same host type, memo sharing and busy-cell failure. The
existing multi-shot example still emits its two distinct branch observations.

Original reentrant component borrow-summary inference rejects a fresh-region
write; that source-free exclusion remains explicit. The other linked fixtures
pass original and candidate admission. All 18 Agent images remain unchanged.

Disposition: the user explicitly accepted these three timing increases and the
bounded suspended-execution memory increase. This decision covers only the P14
candidate identified above. The separate M3 and P13 decisions remain open.
