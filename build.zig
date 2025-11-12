const std = @import("std");

const targets: []const std.Target.Query = &.{
    .{ .cpu_arch = .aarch64, .os_tag = .macos },
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl },
    .{ .cpu_arch = .x86_64, .os_tag = .windows },
    .{ .cpu_arch = .aarch64, .os_tag = .linux },
};

pub fn build(b: *std.Build) !void {
    const make_all_targets = b.option(bool, "all", "Build for all supported targets") orelse false;

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const version = b.option([]const u8, "version", "The version string to embed in the binary") orelse "0.0.0";

    const options = b.addOptions();
    options.addOption([]const u8, "version", version);

    var reqd_exe: *std.Build.Step.Compile = undefined;

    if (make_all_targets) {
        for (targets) |t| {
            const exe = b.addExecutable(.{
                .name = "3bp",
                .root_module = b.createModule(.{
                    .root_source_file = b.path("src/main.zig"),
                    .target = b.resolveTargetQuery(t),
                    .optimize = optimize,
                }),
            });

            exe.root_module.addOptions("config", options);

            const triple: []const u8 = try t.zigTriple(b.allocator);

            const target_output = b.addInstallArtifact(exe, .{
                .dest_dir = .{
                    .override = .{
                        .custom = triple,
                    },
                },
            });

            b.getInstallStep().dependOn(&target_output.step);

            const curr_target = exe.root_module.resolved_target.?.result;

            if (curr_target.cpu.arch == target.result.cpu.arch and
                curr_target.os.tag == target.result.os.tag and
                curr_target.abi == target.result.abi)
            {
                reqd_exe = exe;
            }
        }
    } else {
        const exe = b.addExecutable(.{
            .name = "3bp",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });

        exe.root_module.addOptions("config", options);

        b.installArtifact(exe);

        reqd_exe = exe;
    }

    // === Add run step ===
    const run_cmd = b.addRunArtifact(reqd_exe);
    const run_step = b.step("run", "Run the 3bp executable");

    run_step.dependOn(&run_cmd.step);
}
