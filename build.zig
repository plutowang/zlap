const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zap = b.addModule("zap", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const basic_exe = b.addExecutable(.{
        .name = "basic",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/basic.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zap", .module = zap },
            },
        }),
    });
    b.installArtifact(basic_exe);

    // Create run step for `zig build run`
    const run_cmd = b.addRunArtifact(basic_exe);
    const run_step = b.step("run", "Run the setup tool");
    run_step.dependOn(&run_cmd.step);

    // Allow passing arguments: `zig build run -- --help`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const test_step = b.step("test", "Run tests");

    const zap_tests = b.addTest(.{
        .root_module = zap,
    });
    const run_zap_tests = b.addRunArtifact(zap_tests);
    test_step.dependOn(&run_zap_tests.step);

    const integration_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/zap_tests.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zap", .module = zap },
            },
        }),
    });
    const run_integration_tests = b.addRunArtifact(integration_tests);
    test_step.dependOn(&run_integration_tests.step);
}
