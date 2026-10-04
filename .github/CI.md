# CI feedback and focused qualification

`Zig 0.17 qualification` has a cheap formatting/source preflight followed by
separate `installation` and `contracts` jobs. The complete native/portable
contract command and independent public-package consumer remain unchanged.
No test deletion is part of this feedback change.

Routine PR/push runs gate compilation on the source result and use matrix
fail-fast between the two jobs. A manual `lane` selects `source`, `installation`,
`contracts`, or `all`; `collect_all=true` explicitly permits independent evidence
collection after failures. Failures still fail. The old `native` status name is
an all-lanes gate and is not reported as a passing full check by focused runs.
Existing branch protections are not changed.

Use GitHub's Re-run job for the same commit. To test a fix at a new commit,
start a new run for that ref. Local focused commands remain:

```sh
node test/package_authoring.mjs --zig-exe "$(command -v zig)" --authoring-only
zig build check -Doptimize=safe --summary all
```

The compiler setup action no longer owns compilation-cache save/pruning.
Explicit cache restore/save uses a namespace per OS/architecture, Zig version,
qualification lane and package manifest. `zig-cache.mjs` reports restored keys,
logical bytes and top-level contents before and after the build. Empty or
metadata-only caches are not saved. Above the existing four-GiB budget, skip
upload without deleting local objects or replacing the prior remote cache.
The external consumer retains its deliberately isolated caches. Authentication
and correctness checks do not use cache existence as evidence of qualification.
