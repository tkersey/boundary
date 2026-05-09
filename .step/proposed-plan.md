# Structured Schema Refs for LowerBinding

## Summary
Add an explicit caller-owned schema-index map to `ability.ir.schema.LowerBinding`
so built-in schema metadata can lower product/sum payload, resume, and output
refs without inventing a hidden registry. Keep scalar lowering source-compatible,
keep value schema tables caller-owned, and do not change ProgramPlan execution or
serialized ProgramPlan shape.

The branch migrates plan-native exception and resource examples away from
hand-authored requirement/op metadata. Resource `release` becomes built-in
schema metadata only; runtime/interpreter behavior must remain unchanged.

## Acceptance
- `ability.ir.schema.ref(T, schema_index)` and
  `ability.ir.schema.SchemaRefs(.{ ... })` provide a comptime exact-type map.
- `ability.ir.schema.BindingOffsets` accepts `schema_refs` with a default empty
  map so existing scalar `LowerBinding` callers do not change.
- Product/sum payload, resume, and output refs lower with the mapped schema
  index; missing or invalid mappings fail closed at comptime.
- `effect_schema.resource_bracket` emits metadata for both `acquire` and
  `release` without changing resource execution semantics.
- `examples/plan_native_exception.zig`,
  `examples/plan_native_resource.zig`, and the plan-native contract matrix use
  schema-lowered requirement/op metadata while keeping explicit value schema
  tables and locals.
- Docs describe explicit structured schema refs and no longer present the
  feature as future-only.

## Non-Goals
- No ProgramPlan interpreter/runtime execution changes.
- No serialized ProgramPlan schema-version or wire-shape changes.
- No hidden value-schema registry allocation or schema table reordering.
- No public custom-effect authoring surface.
- No removal of raw `ability.ir.plan.*` rows.
- No duplicate same-type multi-index support in this v1 map.

## Proof
```sh
zig build compile-fail
zig build test -- --test-filter "schema lowerer"
zig build test -- --test-filter "plan-native contract conformance matrix"
zig build run-plan-native-exception
zig build run-plan-native-resource
git diff --check
zig build lint -- --max-warnings 0
zig build test
```

## Implementation Brief
1. step=add_schema_refs_api; owner=implementer; success_criteria=`ability.ir.schema.ref` and `SchemaRefs` exist, `BindingOffsets.schema_refs` defaults to empty, scalar callers remain unchanged, and focused lowerer tests pass.
2. step=add_fail_closed_schema_ref_tests; owner=implementer; success_criteria=compile-fail fixtures cover missing structured map, scalar map entry, duplicate type entry, and invalid structured map usage. (deps: st-4006)
3. step=extend_resource_schema_metadata; owner=implementer; success_criteria=`effect_schema.resource_bracket` lowers both `acquire` and `release` metadata without edits to ProgramPlan interpreter/runtime resource execution. (deps: st-4006)
4. step=migrate_exception_resource_examples; owner=implementer; success_criteria=exception/resource examples and contract matrix use `LowerBinding` for requirement/op metadata while retaining explicit value schema tables and locals. (deps: st-4006, st-4008)
5. step=update_schema_ref_docs; owner=implementer; success_criteria=docs describe explicit `SchemaRefs` and raw-row escape hatches, and stale future-only structured-ref wording is removed. (deps: st-4009)
6. step=run_fixed_point_closure; owner=implementer; success_criteria=fixed-point review, one-change challenge, and all proof commands pass with no material findings. (deps: st-4007, st-4009, st-4010)
7. step=ship_schema_refs_pr; owner=implementer; success_criteria=validated branch is pushed and a PR is opened with concise proof summary after all gates pass. (deps: st-4011)
