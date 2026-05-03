//! Responsibility: define the package build and test graph.
//! Ownership: repository build configuration surface.
//! Reason: keep compile/test entrypoints explicit and host-neutral.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const mod = b.addModule("vt_core", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("vt_core", mod);
    const fuzz_scrollback_mod = b.createModule(.{
        .root_source_file = b.path("fuzz/scrollback.zig"),
        .target = target,
        .optimize = optimize,
    });
    fuzz_scrollback_mod.addImport("vt_core", mod);
    mod.addImport("fuzz_scrollback", fuzz_scrollback_mod);

    const mod_tests = b.addTest(.{
        .name = "test-unit",
        .root_module = mod,
        .filters = b.args orelse &.{},
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    if (b.args != null) {
        run_mod_tests.has_side_effects = true;
    }

    const test_step = b.step("test", "Run all tests");
    const test_unit_step = b.step("test:unit", "Run unit tests");
    const test_unit_build_step = b.step("test:unit:build", "Build unit tests");
    test_unit_build_step.dependOn(&b.addInstallArtifact(mod_tests, .{}).step);
    test_unit_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(test_unit_step);

    const fuzz_module = b.createModule(.{
        .root_source_file = b.path("fuzz/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    fuzz_module.addImport("fuzz_scrollback", fuzz_scrollback_mod);
    fuzz_module.addImport("vt_core", mod);

    const fuzz_exe = b.addExecutable(.{
        .name = "vt_core_fuzz",
        .root_module = fuzz_module,
    });
    const fuzz_step = b.step("fuzz", "Run fuzzers");
    const fuzz_build_step = b.step("fuzz:build", "Build fuzzers");
    fuzz_build_step.dependOn(&b.addInstallArtifact(fuzz_exe, .{}).step);
    const run_fuzz = b.addRunArtifact(fuzz_exe);
    if (b.args) |args| run_fuzz.addArgs(args);
    fuzz_step.dependOn(&run_fuzz.step);

    const baseline_mod = b.createModule(.{
        .root_source_file = b.path("src/test/vt_core_benchmark.zig"),
        .target = target,
        .optimize = optimize,
    });
    baseline_mod.addImport("vt_core", mod);
    const baseline_exe = b.addExecutable(.{
        .name = "m7_baseline",
        .root_module = baseline_mod,
    });
    const run_baseline = b.addRunArtifact(baseline_exe);
    const baseline_step = b.step("vt-core-benchmark", "Run vt-core benchmark suite");
    baseline_step.dependOn(&run_baseline.step);
}
