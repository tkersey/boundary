const registry = @import("namedbody_conformance_registry.zig");

test "repo-owned NamedBody full conformance registry executes all cases" {
    inline for (registry.full_cases) |case| {
        try case.run();
    }
}
