pub fn FamilyLegacy(comptime generated_family: type) type {
    return struct {
        pub const Generated = generated_family;
    };
}

pub fn ProgramLegacy(comptime internal_manifest: type) type {
    return struct {
        pub const InternalManifest = internal_manifest;
    };
}
