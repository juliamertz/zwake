const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zwake",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const clap = b.dependency("clap", .{});
    exe.root_module.addImport("clap", clap.module("clap"));

    b.installArtifact(exe);

    // run step
    {
        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());

        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);
    }

    // tests
    {
        const test_step = b.step("test", "Run unit tests");
        const files = .{
            "src/main.zig",
            "src/net.zig",
        };

        inline for (files) |path| {
            const exe_unit_tests = b.addTest(.{
                .root_source_file = b.path(path),
                .target = target,
                .optimize = optimize,
            });

            const unit_tests = b.addRunArtifact(exe_unit_tests);
            test_step.dependOn(&unit_tests.step);
        }
    }
}
