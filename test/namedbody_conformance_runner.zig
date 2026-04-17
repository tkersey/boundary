const registry = @import("namedbody_conformance_registry.zig");

test "repo-owned NamedBody conformance registry executes all cases" {
    inline for (registry.smoke_cases) |case| {
        try case.run();
    }
}
