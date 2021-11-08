const std = @import("std");
const vulkan_zig = @import("dependencies/vulkan-zig/generator/index.zig");
const mach_glfw = @import("dependencies/mach-glfw/build.zig");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{
        .default_target = std.zig.CrossTarget {},
    });
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("vk_project3", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();
    
    mach_glfw.link(b, exe, .{});
    exe.addPackagePath("mach-glfw", "dependencies/mach-glfw/src/main.zig");

    const generate_vk_zig = vulkan_zig.VkGenerateStep.init(b, "dependencies/Vulkan-Docs/xml/vk.xml", "gen/vk.zig");
    exe.step.dependOn(&generate_vk_zig.step);
    // work around for ZLS to see where vk.zig is, so I can use hover for and GOTO definition
    exe.addPackagePath("vulkan", "zig-cache/gen/vk.zig");

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest("src/main.zig");
    exe_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}
