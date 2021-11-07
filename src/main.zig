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
const glfw = @import("mach-glfw");



const DispatchBase = vk.BaseWrapper(&[_]vk.BaseCommand {
    .createInstance,
    .getInstanceProcAddr,
    //.enumerateInstanceVersion,
    .enumerateInstanceLayerProperties,
    .enumerateInstanceExtensionProperties,
});

const DispatchInstance = vk.InstanceWrapper(&[_]vk.InstanceCommand {
    .destroyInstance,
    .enumeratePhysicalDevices,
    .getDeviceProcAddr,
    .getPhysicalDeviceProperties,
    .getPhysicalDeviceQueueFamilyProperties,
    //.getPhysicalDeviceMemoryProperties,
    .getPhysicalDeviceFeatures,
    .getPhysicalDeviceFormatProperties,
    //.getPhysicalDeviceImageFormatProperties,
    .createDevice,
});

fn DispatchDevice(comptime dispatch_type: @Type(.EnumLiteral)) type {
    const cmds: []const vk.DeviceCommand = &switch (dispatch_type) {
        .default => .{
            .destroyDevice,
            .getDeviceQueue,
        },
        else => unreachable,
    };
    return vk.DeviceWrapper(cmds);
}

const QueueFamilyIndices = struct {
    graphics: ?u32,
};

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{ .verbose_log = true }) {};
    defer _ = gpa_state.deinit();
    
    var aa_state = std.heap.ArenaAllocator.init(&gpa_state.allocator);
    defer aa_state.deinit();
    
    const allocator_main: *mem.Allocator = &gpa_state.allocator;
    _ = allocator_main;
    
    try glfw.init();
    defer glfw.terminate();
    
    try glfw.Window.hint(.resizable, false);
    try glfw.Window.hint(.client_api, glfw.no_api);
    const window = try glfw.Window.create(600, 600, "vk_project3", null, null);
    defer window.destroy();
    
    const dispatch_base: DispatchBase = try DispatchBase.load(@ptrCast(vk.PfnGetInstanceProcAddr, glfw.getInstanceProcAddress));
    const instance = try dispatch_base.createInstance((InstanceCreateInfo {}).asVkType(), null);
    defer destroy_instance: {
        const MinInstanceDispatch = vk.InstanceWrapper(&[_]vk.InstanceCommand { .destroyInstance });
        const mid = MinInstanceDispatch.load(instance, dispatch_base.dispatch.vkGetInstanceProcAddr) catch |err| {
            log.err("Failed to load function to destroy instance; vulkan instance will not be destroyed. Error: {}\n", .{ err });
            break :destroy_instance;
        };
        mid.destroyInstance(instance, null);
    }
    const dispatch_instance: DispatchInstance = try DispatchInstance.load(instance, dispatch_base.dispatch.vkGetInstanceProcAddr);
    
    const selected_physical_device: vk.PhysicalDevice = selected_physical_device: {
        var selected_idx: usize = 0;
        
        const all_physical_devices: []const vk.PhysicalDevice = try enumeratePhysicalDevicesAlloc(allocator_main, dispatch_instance, instance);
        defer allocator_main.free(all_physical_devices);
        
        if (all_physical_devices.len == 0) return error.NoSupportedVulkanPhysicalDevices;
        if (all_physical_devices.len == 1) break :selected_physical_device all_physical_devices[0];
        
        break :selected_physical_device all_physical_devices[selected_idx];
    };
    
    const queue_family_indices: QueueFamilyIndices = queue_family_indices: {
        var result: QueueFamilyIndices = .{
            .graphics = null,
        };
        
        const queue_family_properties_list: []const vk.QueueFamilyProperties = try getPhysicalDeviceQueueFamilyPropertiesAlloc(
            allocator_main,
            dispatch_instance,
            selected_physical_device,
        );
        
        for (queue_family_properties_list) |qfamily_properties, idx| {
            if (qfamily_properties.queue_flags.graphics_bit) {
                result.graphics = @intCast(u32, idx);
                break;
            }
        }
        
        break :queue_family_indices result;
    };
    
    const device: vk.Device = device: {
        const create_info = DeviceCreateInfo {
            .queue_create_infos = &[_]vk.DeviceQueueCreateInfo {
                .{
                    .flags = vk.DeviceQueueCreateFlags.fromInt(0),
                    .queue_family_index = queue_family_indices.graphics orelse return error.FailedToFindGraphicsQueue,
                    .queue_count = 1,
                    .p_queue_priorities =  mem.span(&[_]f32{ 1.0 }).ptr,
                },
            },
            .enabled_extension_names = &.{},
            .enabled_features = .{},
        };
        
        const as_vk_type = create_info.asVkType();
        @breakpoint();
        break :device try dispatch_instance.createDevice(selected_physical_device, as_vk_type, null);
    };
    defer destroy_device: {
        const MinDeviceDispatch = vk.DeviceWrapper(&[_]vk.DeviceCommand { .destroyDevice });
        const mdd = MinDeviceDispatch.load(device, dispatch_instance.dispatch.vkGetDeviceProcAddr) catch |err| {
            log.err("Failed to load function to destroy device; vulkan device will not be destroyed. Error: {}\n", .{ err });
            break :destroy_device;
        };
        mdd.destroyDevice(device, null);
    }
    const dispatch_device = try DispatchDevice(.default).load(device, dispatch_instance.dispatch.vkGetDeviceProcAddr);
    _ = dispatch_device;
    
    var timer = try time.Timer.start();
    while (!window.shouldClose()) {
        glfw.pollEvents() catch continue;
        if (timer.read() < 16 * time.ns_per_ms) continue else timer.reset();
        
        
    }
}

fn enumeratePhysicalDevicesAlloc(allocator: *mem.Allocator, dispatch: DispatchInstance, instance: vk.Instance) ![]vk.PhysicalDevice {
    var count: u32 = undefined;
    assert(dispatch.enumeratePhysicalDevices(instance, &count, null) catch unreachable == .success);
    
    const slice = try allocator.alloc(vk.PhysicalDevice, count);
    errdefer allocator.free(slice);
    
    assert(dispatch.enumeratePhysicalDevices(instance, &count, slice.ptr) catch unreachable == .success);
    assert(slice.len == count);
    
    return slice;
}

fn getPhysicalDeviceQueueFamilyPropertiesAlloc(allocator: *mem.Allocator, dispatch: DispatchInstance, physical_device: vk.PhysicalDevice) ![]vk.QueueFamilyProperties {
    var count: u32 = undefined;
    dispatch.getPhysicalDeviceQueueFamilyProperties(physical_device, &count, null);
    
    const slice = try allocator.alloc(vk.QueueFamilyProperties, count);
    errdefer allocator.free(slice);
    
    dispatch.getPhysicalDeviceQueueFamilyProperties(physical_device, &count, slice.ptr);
    assert(slice.len == count);
    
    return slice;
}

const InstanceCreateInfo = struct {
    s_type: vk.StructureType = meta.fieldInfo(VkType, .s_type).default_value.?,
    p_next: ?*const c_void = meta.fieldInfo(VkType, .p_next).default_value.?,
    
    flags: vk.InstanceCreateFlags = vk.InstanceCreateFlags.fromInt(0),
    application_info: ?vk.ApplicationInfo = null,
    
    enabled_layer_names: []const [*:0]const u8 = &.{},
    enabled_extension_names: []const [*:0]const u8 = &.{},
    
    pub const VkType = vk.InstanceCreateInfo;
    
    pub fn asVkType(self: *const @This()) VkType {
        return VkType {
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

const DeviceCreateInfo = struct {
    s_type: vk.StructureType = meta.fieldInfo(VkType, .s_type).default_value.?,
    p_next: ?*const c_void = meta.fieldInfo(VkType, .p_next).default_value.?,
    flags: vk.DeviceCreateFlags = vk.DeviceCreateFlags.fromInt(0),
    queue_create_infos: []const vk.DeviceQueueCreateInfo = &.{},
    enabled_layer_names: []const [*:0]const u8 = &.{},
    enabled_extension_names: []const [*:0]const u8 = &.{},
    enabled_features: ?vk.PhysicalDeviceFeatures = null,
    
    pub const VkType = vk.DeviceCreateInfo;
    
    pub fn asVkType(self: *const @This()) VkType {
        return VkType {
            .s_type = self.s_type,
            .p_next = self.p_next,
            .flags = self.flags,
            
            .queue_create_info_count = @intCast(u32, self.queue_create_infos.len),
            .p_queue_create_infos = self.queue_create_infos.ptr,
            
            .enabled_layer_count = @intCast(u32, self.enabled_layer_names.len),
            .pp_enabled_layer_names = self.enabled_layer_names.ptr,
            
            .enabled_extension_count = @intCast(u32, self.enabled_extension_names.len),
            .pp_enabled_extension_names = self.enabled_extension_names.ptr,
            
            .p_enabled_features = if (self.enabled_features) |*enabled_features| enabled_features else null,
        };
    }
};
