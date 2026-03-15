const survey_resume_transform_executes = @import("survey_resume_transform_executes");

test "runtime-success survey fixture executes through the lowered runtime seam" {
    try survey_resume_transform_executes.main();
}
