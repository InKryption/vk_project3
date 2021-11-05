const std = @import("std");
const io = std.io;
const fmt = std.fmt;
const log = std.log;
const mem = std.mem;
const math = std.math;
const time = std.time;
const meta = std.meta;
const trait = meta.trait;
const enums = std.enums;
const debug = std.debug;
const builtin = std.builtin;

const assert = debug.assert;
const print = debug.print;

const vk = @import("vulkan");

pub const InstanceCreateInfo = struct {
    s_type: vk.StructureType = meta.fieldInfo(VkType, .s_type).default_value.?,
    p_next: ?*const c_void = meta.fieldInfo(VkType, .p_next).default_value.?,
    
    flags: vk.InstanceCreateFlags = vk.InstanceCreateFlags.fromInt(0),
    application_info: ?vk.ApplicationInfo = null,
    
    enabled_layer_names: []const [*:0]const u8 = &.{},
    enabled_extension_names: []const [*:0]const u8 = &.{},
    
    const VkType = vk.InstanceCreateInfo;
    
    fn asVkType(self: *const @This()) VkType {
        return vk.InstanceCreateInfo {
            .s_type = self.s_type,
            .p_next = self.p_next,
            
            .flags = self.flags,
            .p_application_info = if (self.application_info) |*application_info| application_info else null,
            
            .enabled_layer_count = @intCast(u32, self.enabled_layer_names.len),
            .pp_enabled_layer_names = self.enabled_layer_names.ptr,
            
            .enabled_extension_count = @intCast(u32, self.enabled_extension_names.len),
            .pp_enabled_extension_names = self.enabled_extension_names.ptr,
        };
    }
};



pub fn loadBaseDispatch(loader: anytype, comptime cmds: []const vk.BaseCommand) !vk.BaseWrapper(cmds[0..]) {
    return try vk.BaseWrapper(cmds[0..]).load(loader);
}

pub fn loadInstanceDispatch(instance: vk.Instance, loader: anytype, comptime cmds: []const vk.InstanceCommand) !vk.InstanceWrapper(cmds[0..]) {
    return try vk.InstanceWrapper(cmds[0..]).load(instance, loader);
}

pub fn loadDeviceDispatch(device: vk.Device, loader: anytype, comptime cmds: []const vk.DeviceCommand) !vk.DeviceWrapper(cmds[0..]) {
    return try vk.DeviceWrapper(cmds[0..]).load(device, loader);
}
