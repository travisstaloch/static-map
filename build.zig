const std = @import("std");

pub fn build(b: *std.Build) void {
    const mod = b.addModule("static_map", .{
        .root_source_file = b.path("src/root.zig"),
    });
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const bench = b.addExecutable(.{
        .name = "bench",
        .root_source_file = b.path(b.option([]const u8, "bench-file", "benchmark file") orelse "src/bench.zig"),
        .target = target,
        .optimize = optimize,
    });
    bench.root_module.addImport("static-map", mod);
    b.installArtifact(bench);
    const run_cmd = b.addRunArtifact(bench);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("bench", "Run the benchmark app");
    run_step.dependOn(&run_cmd.step);

    const tests = b.addTest(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    tests.root_module.addImport("static-map", mod);
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run the unit tests");
    test_step.dependOn(&run_tests.step);
}
