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

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);

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
