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
    lib.build_id = .sha1;
    // PAM modules are named pam_*.so, without the lib prefix, in <libdir>/security.
    const install_lib = b.addInstallFileWithDir(lib.getEmittedBin(), .lib, "security/pam_jev.so");
    b.getInstallStep().dependOn(&install_lib.step);

    const cli = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    // Not installed: `zig build run -- [options] USER`.
    const run = b.addRunArtifact(b.addExecutable(.{ .name = "jev", .root_module = cli }));
    if (b.args) |args| run.addArgs(args);
    b.step("run", "Ask Jev from the command line").dependOn(&run.step);

    const test_step = b.step("test", "Run unit tests");
    for ([_]*std.Build.Module{ module, cli }) |m| {
        test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = m })).step);
    }
}
