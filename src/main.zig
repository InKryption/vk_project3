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



pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{ .verbose_log = true }) {};
    defer _ = gpa_state.deinit();
    
    const allocator_main: *mem.Allocator = &gpa_state.allocator;
    _ = allocator_main;
    
    try glfw.init();
    defer glfw.terminate();
    
    try glfw.Window.hint(.resizable, false);
    try glfw.Window.hint(.client_api, glfw.no_api);
    const window = try glfw.Window.create(600, 600, "vk_project3", null, null);
    defer window.destroy();
    
    
    const DispatchInstance = vk.InstanceWrapper(&[_]vk.InstanceCommand {
        .destroyInstance,
        .enumeratePhysicalDevices,
        .getDeviceProcAddr,
        .getPhysicalDeviceProperties,
        .getPhysicalDeviceQueueFamilyProperties,
        
        .getPhysicalDeviceFeatures,
        .getPhysicalDeviceFormatProperties,
        
        .createDevice,
        
        .destroySurfaceKHR,
        .getPhysicalDeviceSurfaceSupportKHR,
        .getPhysicalDeviceSurfaceFormatsKHR,
        .getPhysicalDeviceSurfacePresentModesKHR,
        .getPhysicalDeviceSurfaceCapabilitiesKHR,
    });

    const DispatchDevice = vk.DeviceWrapper(&[_]vk.DeviceCommand {
        .destroyDevice,
        .getDeviceQueue,
        .createImageView,
        .destroyImageView,
        .createSwapchainKHR,
        .destroySwapchainKHR,
        .getSwapchainImagesKHR,
    });
    
    const instance: struct {
        handle: vk.Instance,
        dispatch: DispatchInstance,
    } = instance: {
        var local_aa_state = std.heap.ArenaAllocator.init(allocator_main);
        defer local_aa_state.deinit();
        
        const handle: vk.Instance = handle: {
            const base_dispatch = try vk.BaseWrapper(comptime enums.values(vk.BaseCommand)).load(@ptrCast(vk.PfnGetInstanceProcAddr, glfw.getInstanceProcAddress));
            const enabled_layer_names: []const [*:0]const u8 = enabled_layer_names: {
                break :enabled_layer_names &.{};
            };
            defer local_aa_state.allocator.free(enabled_layer_names);
            
            const enabled_extension_names: []const [*:0]const u8 = enabled_extension_names: {
                var result = std.ArrayList([*:0]const u8).init(&local_aa_state.allocator);
                errdefer result.deinit();
                
                try result.appendSlice(glfw_extensions: {
                    var glfw_extensions_result: []const [*:0]const u8 = undefined;
                    const slice_of_cptr = try glfw.getRequiredInstanceExtensions();
                    glfw_extensions_result.len = slice_of_cptr.len;
                    glfw_extensions_result.ptr = @ptrCast([*]const [*:0]const u8, slice_of_cptr.ptr);
                    break :glfw_extensions glfw_extensions_result;
                });
                
                break :enabled_extension_names result.toOwnedSlice();
            };
            defer local_aa_state.allocator.free(enabled_extension_names);
            
            break :handle try base_dispatch.createInstance(vk.InstanceCreateInfo {
                .s_type = .instance_create_info,
                .p_next = null,
                
                .flags = vk.InstanceCreateFlags {},
                .p_application_info = null,
                
                .enabled_layer_count = @intCast(u32, enabled_layer_names.len),
                .pp_enabled_layer_names = enabled_layer_names.ptr,
                
                .enabled_extension_count = @intCast(u32, enabled_extension_names.len),
                .pp_enabled_extension_names = enabled_extension_names.ptr,
            }, null);
        };
        errdefer destroy_instance: {
            const mbd = vk.InstanceWrapper(&[_]vk.InstanceCommand { .destroyInstance }).load(handle, @ptrCast(vk.PfnGetInstanceProcAddr, glfw.getInstanceProcAddress)) catch |err| {
                log.err("Encountered problem '{}' when trying to load function to destroy instance; instance will remain undestroyed.\n", .{err});
                break :destroy_instance;
            };
            mbd.destroyInstance(handle, null);
        }
        
        const instance_dispatch: DispatchInstance = try DispatchInstance.load(handle, @ptrCast(vk.PfnGetInstanceProcAddr, glfw.getInstanceProcAddress));
        
        break :instance .{
            .handle = handle,
            .dispatch = instance_dispatch,
        };
    };
    defer instance.dispatch.destroyInstance(instance.handle, null);
    
    
    
    const surface: vk.SurfaceKHR = surface: {
        var surface_result: vk.SurfaceKHR = .null_handle;
        
        const result = @intToEnum(vk.Result, try glfw.createWindowSurface(instance.handle, window, null, &surface_result));
        if (result != .success) {
            inline for (comptime enums.values(vk.Result)) |possible_value| {
                @setEvalBranchQuota(10_000);
                if (possible_value == result) comptime {
                    const tag_name = @tagName(possible_value);
                    var err_name: [snakecaseToCamelCaseBufferSize(tag_name)]u8 = undefined;
                    _ = snakecaseToCamelCase(err_name[0..], tag_name);
                    
                    const real_err_name: []const u8 = if (mem.startsWith(u8, &err_name, "error")) err_name["error".len..] else err_name[0..];
                    return @field(@Type(.{ .ErrorSet = &.{ .{ .name = real_err_name } } }), real_err_name);
                };
            }
        }
        
        assert(surface_result != .null_handle);
        break :surface surface_result;
    };
    defer instance.dispatch.destroySurfaceKHR(instance.handle, surface, null);
    
    
    
    const physical_device: vk.PhysicalDevice = physical_device: {
        const all_physical_devices: []const vk.PhysicalDevice = all_physical_devices: {
            var count: u32 = undefined;
            assert(instance.dispatch.enumeratePhysicalDevices(instance.handle, &count, null) catch unreachable == .success);
            
            const slice = try allocator_main.alloc(vk.PhysicalDevice, count);
            errdefer allocator_main.free(slice);
            
            assert(instance.dispatch.enumeratePhysicalDevices(instance.handle, &count, slice.ptr) catch unreachable == .success);
            assert(slice.len == count);
            
            break :all_physical_devices slice;
        };
        defer allocator_main.free(all_physical_devices);
        
        if (all_physical_devices.len == 0) return error.NoSupportedVulkanPhysicalDevices;
        if (all_physical_devices.len == 1) {
            break :physical_device all_physical_devices[0];
        } else {
            unreachable;
        }
    };
    
    
    
    const QueueFamilyIndices = enums.EnumArray(
        enum {
            graphics,
            present,
        },
        u32,
    );
    
    const queue_family_indices: QueueFamilyIndices = queue_family_indices: {
        const queue_family_properties: []const vk.QueueFamilyProperties = queue_family_properties: {
            var count: u32 = undefined;
            instance.dispatch.getPhysicalDeviceQueueFamilyProperties(physical_device, &count, null);
            
            const slice = try allocator_main.alloc(vk.QueueFamilyProperties, count);
            errdefer allocator_main.free(slice);
            
            instance.dispatch.getPhysicalDeviceQueueFamilyProperties(physical_device, &count, slice.ptr);
            assert(slice.len == count);
            
            break :queue_family_properties slice;
        };
        defer allocator_main.free(queue_family_properties);
        
        var graphics_index: ?u32 = null;
        var present_index: ?u32 = null;
        
        for (queue_family_properties) |qfamily_properties, idx| {
            const surface_support: bool = (instance.dispatch.getPhysicalDeviceSurfaceSupportKHR(
                physical_device,
                @intCast(u32, idx),
                surface,
            ) catch vk.FALSE) == vk.TRUE;
            
            if (qfamily_properties.queue_flags.graphics_bit and surface_support) {
                graphics_index = @intCast(u32, idx);
                present_index = @intCast(u32, idx);
                break;
            }
            
            if (qfamily_properties.queue_flags.graphics_bit) {
                graphics_index = @intCast(u32, idx);
                if (present_index != null) break;
            }
            
            if (surface_support) {
                present_index = @intCast(u32, idx);
                if (graphics_index != null) break;
            }
        }
        
        var result = QueueFamilyIndices.initUndefined();
        result.set(.graphics, graphics_index orelse return error.FailedToFindGraphicsQueue);
        result.set(.present, present_index orelse return error.FailedToFindPresentQueue);
        break :queue_family_indices result;
    };
    
    const graphics_and_present_queues_equal = queue_family_indices.get(.graphics) == queue_family_indices.get(.present);
    
    const device: struct {
        handle: vk.Device,
        dispatch: DispatchDevice,
    } = device: {
        const queue_priorities: []const f32 = if (graphics_and_present_queues_equal) &[_]f32 { 1.0 } else &[_]f32 { 1.0, 1.0 };
        
        const queue_create_infos: []const vk.DeviceQueueCreateInfo = queue_create_infos: {
            var queue_create_infos = try std.ArrayList(vk.DeviceQueueCreateInfo).initCapacity(allocator_main, 2);
            errdefer queue_create_infos.deinit();
          
            try queue_create_infos.append(vk.DeviceQueueCreateInfo {
                // .s_type = undefined,
                // .p_next = undefined,
                .flags = vk.DeviceQueueCreateFlags {},
                .queue_family_index = queue_family_indices.get(.graphics),
                .queue_count = @intCast(u32, queue_priorities.len),
                .p_queue_priorities = queue_priorities.ptr,
            });
          
            if (!graphics_and_present_queues_equal) try queue_create_infos.append(vk.DeviceQueueCreateInfo {
                // .s_type = undefined,
                // .p_next = undefined,
                .flags = vk.DeviceQueueCreateFlags {},
                .queue_family_index = queue_family_indices.get(.present),
                .queue_count = @intCast(u32, queue_priorities.len),
                .p_queue_priorities = queue_priorities.ptr,
            });
            
            break :queue_create_infos queue_create_infos.toOwnedSlice();
        };
        defer allocator_main.free(queue_create_infos);
        
        const enabled_extension_names: []const [*:0]const u8 = &.{
            vk.extension_info.khr_swapchain.name.ptr,
        };
      
        const handle = try instance.dispatch.createDevice(physical_device, vk.DeviceCreateInfo {
            // .s_type = undefined,
            // .p_next = undefined,
            .flags = vk.DeviceCreateFlags {},
          
            .queue_create_info_count = @intCast(u32, queue_create_infos.len),
            .p_queue_create_infos = queue_create_infos.ptr,
          
            .enabled_layer_count = 0,
            .pp_enabled_layer_names = mem.span(&[_][*:0]const u8{}).ptr,
          
            .enabled_extension_count = @intCast(u32, enabled_extension_names.len),
            .pp_enabled_extension_names = enabled_extension_names.ptr,
          
            .p_enabled_features = null,
        }, null);
        errdefer destroy_device: {
            const mdd = vk.DeviceWrapper(&[_]vk.DeviceCommand { .destroyDevice }).load(handle, instance.dispatch.dispatch.vkGetDeviceProcAddr) catch |err| {
                log.err("Failed to load function to destroy device; vulkan device will not be destroyed. Error: {}\n", .{ err });
                break :destroy_device;
            };
            mdd.destroyDevice(handle, null);
        }
        const device_dispatch: DispatchDevice = try DispatchDevice.load(handle, instance.dispatch.dispatch.vkGetDeviceProcAddr);
        
        break :device .{
            .handle = handle,
            .dispatch = device_dispatch,
        };
    };
    defer device.dispatch.destroyDevice(device.handle, null);
    
    
    
    var timer = try time.Timer.start();
    while (!window.shouldClose()) {
        glfw.pollEvents() catch continue;
        if (timer.read() < 16 * time.ns_per_ms) continue else timer.reset();
        
        
    }
}



fn snakecaseToCamelCaseBufferSize(snake_case: []const u8) usize {
    return snake_case.len - mem.count(u8, snake_case, "_");
}

fn snakecaseToCamelCase(camel_case: []u8, snake_case: []const u8) []u8 {
    const underscore_count = mem.count(u8, snake_case, "_");
    assert(camel_case.len >= snake_case.len - underscore_count);
    
    var index: usize = 0;
    var offset: usize = 0;
    
    while (index + offset < snake_case.len) : (index += 1) {
        const char = snake_case[index + offset];
        if (char == '_') {
            offset += 1;
            if (index + offset > snake_case.len) break;
            camel_case[index] = std.ascii.toUpper(snake_case[index + offset]);
            continue;
        }
        camel_case[index] = snake_case[index + offset];
    }
    
    assert(offset == underscore_count);
    return camel_case[0..index];
}
