const build_metadata = @import("boundary_build_metadata");

/// Boundary package version advertised by the sealed v0 protocol artifacts.
pub const boundary_package_version = build_metadata.boundary_package_version;

/// Minimum Zig version advertised by the sealed v0 protocol artifacts.
pub const minimum_zig_version = build_metadata.minimum_zig_version;
