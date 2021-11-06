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


pub usingnamespace struct {
    pub const Window = @import("mach-glfw").Window;
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
    
    const vk_base = try VulkanBase.init(@ptrCast(vk.PfnGetInstanceProcAddr, glfw.getInstanceProcAddress), .{}, null, .{});
    defer vk_base.deinit(null);
    
    const selected_physical_device: vk.PhysicalDevice = selected_physical_device: {
        var selected_idx: usize = 0;
        
        const all_physical_devices: []const vk.PhysicalDevice = try vk_base.enumeratePhysicalDevicesAlloc(allocator_main);
        defer allocator_main.free(all_physical_devices);
        
        if (all_physical_devices.len == 0) return error.NoSupportedVulkanPhysicalDevices;
        if (all_physical_devices.len == 1) break :selected_physical_device all_physical_devices[0];
        
        break :selected_physical_device all_physical_devices[selected_idx];
    };
    
    var timer = try time.Timer.start();
    while (!window.shouldClose()) {
        glfw.pollEvents() catch continue;
        if (timer.read() < 16 * time.ns_per_ms)
            continue
        else {
            timer.reset();
        }
        
    }
}

const VulkanBase = struct {
    const Self = @This();
    dispatch_base: DispatchBase,
    dispatch_instance: DispatchInstance,
    instance: vk.Instance,
    
    pub const DispatchBase = vk.BaseWrapper(&.{
        .createInstance,
        .getInstanceProcAddr,
        .enumerateInstanceVersion,
        .enumerateInstanceLayerProperties,
        .enumerateInstanceExtensionProperties,
    });

    pub const DispatchInstance = vk.InstanceWrapper(&.{
        .destroyInstance,
        .enumeratePhysicalDevices,
        .getDeviceProcAddr,
        .getPhysicalDeviceProperties,
        .getPhysicalDeviceQueueFamilyProperties,
        .getPhysicalDeviceMemoryProperties,
        .getPhysicalDeviceFeatures,
        .getPhysicalDeviceFormatProperties,
        .getPhysicalDeviceImageFormatProperties,
        .createDevice,
    });
    
    pub const InstanceCreateInfo = struct {
        s_type: vk.StructureType = meta.fieldInfo(VkType, .s_type).default_value.?,
        p_next: ?*const c_void = meta.fieldInfo(VkType, .p_next).default_value.?,
        
        flags: vk.InstanceCreateFlags = vk.InstanceCreateFlags.fromInt(0),
        application_info: ?vk.ApplicationInfo = null,
        
        enabled_layer_names: []const [*:0]const u8 = &.{},
        enabled_extension_names: []const [*:0]const u8 = &.{},
        
        pub const VkType = vk.InstanceCreateInfo;
        
        pub fn asVkType(self: *const @This()) VkType {
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
    
    pub fn init(
        getInstanceProcAddress: anytype,
        instance_create_info: InstanceCreateInfo,
        p_allocator: ?*const vk.AllocationCallbacks,
        comptime options: struct {
            loadGetInstanceProcAddress: bool = false,
        },
    ) !Self {
        var result: Self = .{
            .dispatch_base = undefined,
            .dispatch_instance = undefined,
            .instance = undefined,
        };
        
        result.dispatch_base = try DispatchBase.load(getInstanceProcAddress);
        
        const cannonical_loader = if (options.loadGetInstanceProcAddress) cannonical_loader: {
            comptime assert(trait.hasField(vk.BaseCommand.symbol(.getInstanceProcAddr)));
            break :cannonical_loader result.dispatch_base.getInstanceProcAddr;
        } else getInstanceProcAddress;
        
        result.instance = try result.dispatch_base.createInstance(instance_create_info.asVkType(), p_allocator);
        errdefer cleanup_instance: {
            const min_inst_dispatch = vk.InstanceWrapper(&.{ .destroyInstance }).load(result.instance, cannonical_loader) catch |err| {
                log.err("Failed to load instance destroy function; unable to cleanup instance after error '{s}'.", .{@errorName(err)});
                break :cleanup_instance;
            };
            min_inst_dispatch.destroyInstance(result.instance, p_allocator);
        }
        
        result.dispatch_instance = try DispatchInstance.load(result.instance, cannonical_loader);
        return result;
    }
    
    pub fn deinit(self: Self, p_allocator: ?*const vk.AllocationCallbacks) void {
        self.dispatch_instance.destroyInstance(self.instance, p_allocator);
    }
    
    
    
    pub inline fn enumerateInstanceLayerPropertiesAlloc(self: Self, allocator: *mem.Allocator) ![]vk.LayerProperties {
        var count: u32 = undefined;
        assert(self.dispatch_base.enumerateInstanceLayerProperties(&count, null) catch unreachable == .success);
        
        const slice = try allocator.alloc(vk.LayerProperties, count);
        errdefer allocator.free(slice);
        
        assert(self.dispatch_base.enumerateInstanceLayerProperties(&count, slice.ptr) catch unreachable == .success);
        assert(slice.len == count);
        
        return slice;
    }
    
    pub inline fn enumerateInstanceLayerPropertiesArrayList(self: Self, array_list: *std.ArrayList(vk.LayerProperties)) !void {
        var count: u32 = undefined;
        assert(self.dispatch_base.enumerateInstanceLayerProperties(&count, null) catch unreachable == .success);
        
        try array_list.resize(count);
        assert(self.dispatch_base.enumerateInstanceLayerProperties(&count, array_list.items.ptr) catch unreachable == .success);
        assert(array_list.items.len == count);
    }
    
    
    
    pub inline fn enumerateInstanceExtensionPropertiesAlloc(self: Self, p_layer_name: ?[*:0]const u8, allocator: *mem.Allocator) ![]vk.ExtensionProperties {
        var count: u32 = undefined;
        assert(self.dispatch_base.enumerateInstanceExtensionProperties(p_layer_name, &count, null) catch unreachable == .success);
        
        const slice = try allocator.alloc(vk.ExtensionProperties, count);
        errdefer allocator.free(slice);
        
        assert(self.dispatch_base.enumerateInstanceExtensionProperties(p_layer_name, &count, slice.ptr) catch unreachable == .success);
        assert(slice.len == count);
        
        return slice;
    }
    
    pub inline fn enumerateInstanceExtensionPropertiesArrayList(self: Self, p_layer_name: ?[*:0]const u8, array_list: std.ArrayList(vk.ExtensionProperties)) !void {
        var count: u32 = undefined;
        assert(self.dispatch_base.enumerateInstanceExtensionProperties(p_layer_name, &count, null) catch unreachable == .success);
        
        try array_list.resize(count);
        assert(self.dispatch_base.enumerateInstanceExtensionProperties(p_layer_name, &count, array_list.items.ptr) catch unreachable == .success);
        assert(array_list.items.len == count);
    }
    
    
    
    pub inline fn enumeratePhysicalDevicesAlloc(self: Self, allocator: *mem.Allocator) ![]vk.PhysicalDevice {
        var count: u32 = undefined;
        assert(self.dispatch_instance.enumeratePhysicalDevices(self.instance, &count, null) catch unreachable == .success);
        
        const slice = try allocator.alloc(vk.PhysicalDevice, count);
        errdefer allocator.free(slice);
        
        assert(self.dispatch_instance.enumeratePhysicalDevices(self.instance, &count, null) catch unreachable == .success);
        assert(slice.len == count);
        
        return slice;
    }
    
    pub inline fn enumeratePhysicalDevicesArrayList(self: Self, array_list: *std.ArrayList(vk.PhysicalDevice)) !void {
        var count: u32 = undefined;
        assert(self.dispatch_instance.enumeratePhysicalDevices(self.instance, &count, null) catch unreachable == .success);
        
        try array_list.resize(count);
        assert(self.dispatch_instance.enumeratePhysicalDevices(self.instance, &count, array_list.items.ptr) catch unreachable == .success);
        assert(array_list.items.len == count);
    }
};
