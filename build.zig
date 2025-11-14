const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const version = b.option([]const u8, "version", "The version string to embed in the binary") orelse "0.0.0";
    const jailbreak = b.option(bool, "jailbreak", "Enable jailbreak features") orelse false;

    const screen_width = b.option(u32, "screen_width", "Screen width for the application") orelse 800;
    const screen_height = b.option(u32, "screen_height", "Screen height for the application") orelse 600;

    const options = b.addOptions();
    options.addOption([]const u8, "version", version);
    options.addOption(bool, "jailbreak", jailbreak);
    options.addOption(u32, "screen_width", screen_width);
    options.addOption(u32, "screen_height", screen_height);

    const exe = b.addExecutable(.{
        .name = "3bp",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    exe.root_module.addAnonymousImport("style", .{
        .root_source_file = b.path("assets/style_genesis.rgs"),
    });

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });
    const raylib = raylib_dep.module("raylib");
    const raygui = raylib_dep.module("raygui");
    const raylib_artifact = raylib_dep.artifact("raylib");

    exe.linkLibrary(raylib_artifact);
    exe.root_module.addImport("raylib", raylib);
    exe.root_module.addImport("raygui", raygui);

    exe.root_module.addOptions("config", options);

    b.installArtifact(exe);

    // === Add run step ===
    const run_cmd = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the 3bp executable");

    run_step.dependOn(&run_cmd.step);
}
