pub const DemoError = error{Boom};

pub fn succeed() DemoError!i32 {
    return 42;
}

pub fn fail() DemoError!i32 {
    return error.Boom;
}
