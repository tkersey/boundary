/// Duplicate top-level NamedBody symbol used to prove repo-owned ambiguity fails closed.
pub fn namedBodyRepoSourceCollision(_: anytype) anyerror!i32 {
    return 1;
}
