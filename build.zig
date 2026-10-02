const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSafe });

    const module = b.createModule(.{
        .root_source_file = b.path("src/pam_jev.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .pic = true,
    });
    module.linkSystemLibrary("pam", .{});
    const lib = b.addLibrary(.{ .name = "pam_jev", .linkage = .dynamic, .root_module = module });
    // PAM modules are named pam_*.so, without the lib prefix.
    const install_lib = b.addInstallFileWithDir(lib.getEmittedBin(), .{ .custom = "lib/security" }, "pam_jev.so");
    b.getInstallStep().dependOn(&install_lib.step);

    const cli = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const exe = b.addExecutable(.{ .name = "jev", .root_module = cli });
    exe.pie = true;
    b.installArtifact(exe);

    const test_step = b.step("test", "Run unit tests");
    for ([_]*std.Build.Module{ module, cli }) |m| {
        test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = m })).step);
    }
}
