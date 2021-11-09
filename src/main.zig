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

fn DispatchDevice(comptime dispatch_type: @Type(.EnumLiteral)) type {
    const cmds: []const vk.DeviceCommand = &switch (dispatch_type) {
        .default => .{
            .destroyDevice,
            .getDeviceQueue,
            .createSwapchainKHR,
            .destroySwapchainKHR,
        },
        .destroyDevice => .{
            .destroyDevice,
        },
        else => unreachable,
    };
    return vk.DeviceWrapper(cmds);
}

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
    
    const basic_vulkan_components: struct {
        instance: vk.Instance,
        dispatch_instance: DispatchInstance,
        
        surface: vk.SurfaceKHR,
        
        device: vk.Device,
        dispatch_device: DispatchDevice(.default),
        
        queue_graphics: vk.Queue,
        queue_present: vk.Queue,
        
        swapchain: vk.SwapchainKHR,
        
    } = basic_vulkan_components: {
        
        var local_aa_state = std.heap.ArenaAllocator.init(allocator_main);
        defer local_aa_state.deinit();
        const local_arena_allocator: *mem.Allocator = &local_aa_state.allocator;
        
        const instance: vk.Instance = instance: {
            const DispatchBase = vk.BaseWrapper(comptime enums.values(vk.BaseCommand));
            const dispatch_base: DispatchBase = try DispatchBase.load(@ptrCast(vk.PfnGetInstanceProcAddr, glfw.getInstanceProcAddress));
            
            const enabled_layer_names: []const [*:0]const u8 = enabled_layer_names: {
                break :enabled_layer_names &.{};
            };
            defer local_arena_allocator.free(enabled_layer_names);
            
            const enabled_extension_names: []const [*:0]const u8 = enabled_extension_names: {
                var result = std.ArrayList([*:0]const u8).init(local_arena_allocator);
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
            defer local_arena_allocator.free(enabled_extension_names);
            
            break :instance try dispatch_base.createInstance(vk.InstanceCreateInfo {
                // .s_type = undefined,
                // .p_next = undefined,
                .flags = vk.InstanceCreateFlags.fromInt(0),
                .p_application_info = null,
                
                .enabled_layer_count = @intCast(u32, enabled_layer_names.len),
                .pp_enabled_layer_names = enabled_layer_names.ptr,
                
                .enabled_extension_count = @intCast(u32, enabled_extension_names.len),
                .pp_enabled_extension_names = enabled_extension_names.ptr,
            }, null);
        };
        errdefer destroy_instance: {
            const MinInstanceDispatch = vk.InstanceWrapper(&[_]vk.InstanceCommand { .destroyInstance });
            const mid = MinInstanceDispatch.load(instance, @ptrCast(vk.PfnGetInstanceProcAddr, glfw.getInstanceProcAddress)) catch |err| {
                log.err("Failed to load function to destroy instance; vulkan instance will not be destroyed. Error: {}\n", .{ err });
                break :destroy_instance;
            };
            mid.destroyInstance(instance, null);
        }
        const dispatch_instance: DispatchInstance = try DispatchInstance.load(instance, @ptrCast(vk.PfnGetInstanceProcAddr, glfw.getInstanceProcAddress));
        
        
        
        const surface: vk.SurfaceKHR = surface: {
            var surface_result: vk.SurfaceKHR = .null_handle;
            
            const result = @intToEnum(vk.Result, try glfw.createWindowSurface(instance, window, null, &surface_result));
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
        errdefer dispatch_instance.destroySurfaceKHR(instance, surface, null);
        
        
        
        const all_physical_devices: []const vk.PhysicalDevice = all_physical_devices: {
            var count: u32 = undefined;
            assert(dispatch_instance.enumeratePhysicalDevices(instance, &count, null) catch unreachable == .success);
            
            const slice = try local_arena_allocator.alloc(vk.PhysicalDevice, count);
            errdefer local_arena_allocator.free(slice);
            
            assert(dispatch_instance.enumeratePhysicalDevices(instance, &count, slice.ptr) catch unreachable == .success);
            assert(slice.len == count);
            
            break :all_physical_devices slice;
        };
        defer local_arena_allocator.free(all_physical_devices);
        if (all_physical_devices.len == 0) return error.NoSupportedVulkanPhysicalDevices;
        
        
        
        const selected_physical_device: vk.PhysicalDevice = selected_physical_device: {
            var selected_idx: usize = 0;
            
            if (all_physical_devices.len > 1) {
                unreachable;
            }
            
            break :selected_physical_device all_physical_devices[selected_idx];
        };
        
        
        
        const queue_family_properties: []const vk.QueueFamilyProperties = queue_family_properties: {
            var count: u32 = undefined;
            dispatch_instance.getPhysicalDeviceQueueFamilyProperties(selected_physical_device, &count, null);
            
            const slice = try local_arena_allocator.alloc(vk.QueueFamilyProperties, count);
            errdefer local_arena_allocator.free(slice);
            dispatch_instance.getPhysicalDeviceQueueFamilyProperties(selected_physical_device, &count, slice.ptr);
            assert(slice.len == count);
            
            break :queue_family_properties slice;
        };
        defer local_arena_allocator.free(queue_family_properties);
        if (queue_family_properties.len == 0) return error.NoVulkanQueueFamilyProperties;
        
        
        
        const QueueFamilyIndices = struct {
            _indexes: [meta.fields(@This().IndexName).len]u32,
            
            const IndexName = enum(usize) {
                graphics = 0,
                present = 1,
            };
            
            const InitEntry = meta.Tuple(&[_]type { IndexName, u32 });
            fn init(values: []const InitEntry) @This() {
                var this: @This() = undefined;
                assert(values.len == this.array().len);
                assert(assertion: for (values) |entry, idx| (for (values) |other_entry, other_idx| if (idx != other_idx and entry.@"0" == other_entry.@"0") break :assertion false) else true);
                
                for (values) |entry| {
                    this.getPtr(entry.@"0").* = entry.@"1";
                }
                
                return this;
            }
            
            fn array(this: @This()) [meta.fields(@This().IndexName).len]u32 {
                return this._indexes;
            }
            
            fn get(this: @This(), index_name: @This().IndexName) u32 {
                var copy = this;
                return copy.getPtr(index_name).*;
            }
            
            fn getPtr(this: *@This(), index_name: @This().IndexName) *u32 {
                return &this._indexes[@enumToInt(index_name)];
            }
        };
        
        const selected_queue_family_indices: QueueFamilyIndices = selected_queue_family_indices: {
            var graphics_index: ?u32 = null;
            var present_index: ?u32 = null;
            
            for (queue_family_properties) |qfamily_properties, idx| {
                const surface_support: bool = (dispatch_instance.getPhysicalDeviceSurfaceSupportKHR(
                    selected_physical_device,
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
            
            if (graphics_index == null) return error.FailedToFindGraphicsQueue;
            if (present_index == null) return error.FailedToFindPresentQueue;
            
            break :selected_queue_family_indices QueueFamilyIndices.init(&[_]QueueFamilyIndices.InitEntry {
                .{ .graphics, graphics_index.? },
                .{ .present, present_index.? },
            });
        };
        
        
        
        const device: vk.Device = device: {
            
            const queue_priorities = [_]f32 { 1.0 };
            //const queue_priorities = [_]f32 { 1.0, 1.0 };
            const flags = vk.DeviceQueueCreateFlags {};
            
            var queue_create_infos = try std.ArrayList(vk.DeviceQueueCreateInfo).initCapacity(local_arena_allocator, 2);
            defer queue_create_infos.deinit();
            
            try queue_create_infos.append(vk.DeviceQueueCreateInfo {
                // .s_type = undefined,
                // .p_next = undefined,
                .flags = flags,
                .queue_family_index = selected_queue_family_indices.get(.graphics),
                .queue_count = queue_priorities.len,
                .p_queue_priorities = @as([]const f32, &queue_priorities).ptr,
            });
            
            if (selected_queue_family_indices.get(.graphics) != selected_queue_family_indices.get(.present)) {
                try queue_create_infos.append(vk.DeviceQueueCreateInfo {
                    // .s_type = undefined,
                    // .p_next = undefined,
                    .flags = flags,
                    .queue_family_index = selected_queue_family_indices.get(.present),
                    .queue_count = queue_priorities.len,
                    .p_queue_priorities = @as([]const f32, &queue_priorities).ptr,
                });
            }
            
            const enabled_extension_names = [_][*:0]const u8 {
                vk.extension_info.khr_swapchain.name.ptr,
            };
            
            break :device try dispatch_instance.createDevice(selected_physical_device, vk.DeviceCreateInfo {
                // .s_type = undefined,
                // .p_next = undefined,
                .flags = vk.DeviceCreateFlags.fromInt(0),
                
                .queue_create_info_count = @intCast(u32, queue_create_infos.items.len),
                .p_queue_create_infos = queue_create_infos.items.ptr,
                
                .enabled_layer_count = 0,
                .pp_enabled_layer_names = mem.span(&[_][*:0]const u8{}).ptr,
                
                .enabled_extension_count = @intCast(u32, enabled_extension_names.len),
                .pp_enabled_extension_names = mem.span(&enabled_extension_names).ptr,
                
                .p_enabled_features = null,
            }, null);
        };
        errdefer destroy_device: {
            const mdd = DispatchDevice(.destroyDevice).load(device, dispatch_instance.dispatch.vkGetDeviceProcAddr) catch |err| {
                log.err("Failed to load function to destroy device; vulkan device will not be destroyed. Error: {}\n", .{ err });
                break :destroy_device;
            };
            mdd.destroyDevice(device, null);
        }
        const dispatch_device: DispatchDevice(.default) = try DispatchDevice(.default).load(device, dispatch_instance.dispatch.vkGetDeviceProcAddr);
        
        
        
        const queue_graphics: vk.Queue = dispatch_device.getDeviceQueue(device, selected_queue_family_indices.get(.graphics), 0);
        const queue_present: vk.Queue = dispatch_device.getDeviceQueue(device, selected_queue_family_indices.get(.present), @boolToInt(selected_queue_family_indices.get(.graphics) != selected_queue_family_indices.get(.present)));
        
        
                
        const swapchain: vk.SwapchainKHR = swapchain: {
            const capabilities = try dispatch_instance.getPhysicalDeviceSurfaceCapabilitiesKHR(selected_physical_device, surface);
            
            const all_formats: []const vk.SurfaceFormatKHR = all_formats: {
                var count: u32 = undefined;
                assert(dispatch_instance.getPhysicalDeviceSurfaceFormatsKHR(selected_physical_device, surface, &count, null) catch unreachable == .success);
                
                const slice = try local_arena_allocator.alloc(vk.SurfaceFormatKHR, count);
                assert(dispatch_instance.getPhysicalDeviceSurfaceFormatsKHR(selected_physical_device, surface, &count, slice.ptr) catch unreachable == .success);
                assert(slice.len == count);
                
                break :all_formats slice;
            };
            
            const all_present_modes: []const vk.PresentModeKHR = all_present_modes: {
                var count: u32 = undefined;
                assert(dispatch_instance.getPhysicalDeviceSurfacePresentModesKHR(selected_physical_device, surface, &count, null) catch unreachable == .success);
                
                const slice = try local_arena_allocator.alloc(vk.PresentModeKHR, count);
                assert(dispatch_instance.getPhysicalDeviceSurfacePresentModesKHR(selected_physical_device, surface, &count, slice.ptr) catch unreachable == .success);
                assert(slice.len == count);
                
                break :all_present_modes slice;
            };
            
            
            
            const selected_swap_extent: vk.Extent2D = selected_swap_extent: {
                if (capabilities.current_extent.width != math.maxInt(u32) and capabilities.current_extent.height != math.maxInt(u32)) {
                    break :selected_swap_extent capabilities.current_extent;
                } else {
                    const fb_size = try window.getFramebufferSize();
                    break :selected_swap_extent .{
                        .width = @intCast(u32, math.clamp(fb_size.width, capabilities.min_image_extent.width, capabilities.max_image_extent.width)),
                        .height = @intCast(u32, math.clamp(fb_size.height, capabilities.min_image_extent.height, capabilities.max_image_extent.height)),
                    };
                }
            };
            
            const selected_format: vk.SurfaceFormatKHR = selected_format: for (all_formats) |format| {
                if (format.format == .b8g8r8a8_srgb and format.color_space == .srgb_nonlinear_khr)
                    break :selected_format format;
            } else all_formats[0];
            
            const selected_present_mode: vk.PresentModeKHR = selected_present_mode: for (all_present_modes) |present_mode| {
                if (present_mode == .mailbox_khr)
                    break :selected_present_mode present_mode;
            } else .fifo_khr;
            
            const image_count = math.clamp(capabilities.min_image_count + 1, capabilities.min_image_count, if (capabilities.max_image_count == 0) math.maxInt(u32) else capabilities.max_image_count);
            
            const qfamily_indices_array: []const u32 = &.{
                selected_queue_family_indices.get(.graphics),
                selected_queue_family_indices.get(.present),
            };
            
            break :swapchain try dispatch_device.createSwapchainKHR(device, vk.SwapchainCreateInfoKHR {
                // .s_type = undefined,
                // .p_next = undefined,
                .flags = vk.SwapchainCreateFlagsKHR.fromInt(0),
                .surface = surface,
                .min_image_count = image_count,
                .image_format = selected_format.format,
                .image_color_space = selected_format.color_space,
                .image_extent = selected_swap_extent,
                .image_array_layers = 1,
                .image_usage = vk.ImageUsageFlags { .color_attachment_bit = true },
                .image_sharing_mode = if (qfamily_indices_array[0] == qfamily_indices_array[1]) .exclusive else .concurrent,
                .queue_family_index_count = if (qfamily_indices_array[0] == qfamily_indices_array[1]) 0 else @intCast(u32, qfamily_indices_array.len),
                .p_queue_family_indices = qfamily_indices_array.ptr,
                .pre_transform = capabilities.current_transform,
                .composite_alpha = vk.CompositeAlphaFlagsKHR { .opaque_bit_khr = true },
                .present_mode = selected_present_mode,
                .clipped = vk.TRUE,
                .old_swapchain = .null_handle,
            }, null);
        };
        errdefer dispatch_device.destroySwapchainKHR(device, swapchain, null);
        
        
        
        break :basic_vulkan_components .{
            .instance = instance,
            .dispatch_instance = dispatch_instance,
            
            .surface = surface,
            
            .device = device,
            .dispatch_device = dispatch_device,
            
            .queue_graphics = queue_graphics,
            .queue_present = queue_present,
            
            .swapchain = swapchain,
        };
    };
    
    const instance: vk.Instance = basic_vulkan_components.instance;
    const dispatch_instance: DispatchInstance = basic_vulkan_components.dispatch_instance;
    defer dispatch_instance.destroyInstance(instance, null);
    
    const surface: vk.SurfaceKHR = basic_vulkan_components.surface;
    defer dispatch_instance.destroySurfaceKHR(instance, surface, null);
    
    const device: vk.Device = basic_vulkan_components.device;
    const dispatch_device: DispatchDevice(.default) = basic_vulkan_components.dispatch_device;
    defer dispatch_device.destroyDevice(device, null);
    
    const queue_graphics: vk.Queue = basic_vulkan_components.queue_graphics;
    const queue_present: vk.Queue = basic_vulkan_components.queue_present;
    
    _ = queue_graphics;
    _ = queue_present;
    
    const swapchain: vk.SwapchainKHR = basic_vulkan_components.swapchain;
    defer dispatch_device.destroySwapchainKHR(device, swapchain, null);
    
    
    
    var timer = try time.Timer.start();
    while (!window.shouldClose()) {
        glfw.pollEvents() catch continue;
        if (timer.read() < 16 * time.ns_per_ms) continue else timer.reset();
        
        
    }
}



fn MakeSlice(comptime Ptr: type) type {
    comptime assert(trait.is(.Pointer)(Ptr));
    const Child = meta.Child(Ptr);
    
    const ptr_info: builtin.TypeInfo.Pointer = @typeInfo(Ptr).Pointer;
    
    const Attributes = packed struct {
        is_const: bool,
        is_volatile: bool,
        is_allowzero: bool,
        
        fn toInt(self: @This()) meta.Int(.unsigned, meta.fields(@This()).len) {
            return @bitCast(meta.Int(.unsigned, meta.fields(@This()).len), self);
        }
    };
    
    const attributes = Attributes {
        .is_const = ptr_info.is_const,
        .is_volatile = ptr_info.is_volatile,
        .is_allowzero = ptr_info.is_allowzero,
    };
    
    return if (@as(?Child, ptr_info.sentinel)) |sentinel| switch (attributes.toInt()) {
        (Attributes { .is_const = false, .is_volatile = false, .is_allowzero = false }).toInt() => [:sentinel]Child,
        (Attributes { .is_const = false, .is_volatile = false, .is_allowzero = true  }).toInt() => [:sentinel]allowzero Child,
        (Attributes { .is_const = false, .is_volatile = true,  .is_allowzero = false }).toInt() => [:sentinel]volatile Child,
        (Attributes { .is_const = false, .is_volatile = true,  .is_allowzero = true  }).toInt() => [:sentinel]volatile allowzero Child,
        (Attributes { .is_const = true,  .is_volatile = false, .is_allowzero = false }).toInt() => [:sentinel]const Child,
        (Attributes { .is_const = true,  .is_volatile = false, .is_allowzero = true  }).toInt() => [:sentinel]const allowzero Child,
        (Attributes { .is_const = true,  .is_volatile = true,  .is_allowzero = false }).toInt() => [:sentinel]const volatile Child,
        (Attributes { .is_const = true,  .is_volatile = true,  .is_allowzero = true  }).toInt() => [:sentinel]const volatile allowzero Child,
    } else switch (attributes.toInt()) {
        (Attributes { .is_const = false, .is_volatile = false, .is_allowzero = false }).toInt() => []Child,
        (Attributes { .is_const = false, .is_volatile = false, .is_allowzero = true  }).toInt() => []allowzero Child,
        (Attributes { .is_const = false, .is_volatile = true,  .is_allowzero = false }).toInt() => []volatile Child,
        (Attributes { .is_const = false, .is_volatile = true,  .is_allowzero = true  }).toInt() => []volatile allowzero Child,
        (Attributes { .is_const = true,  .is_volatile = false, .is_allowzero = false }).toInt() => []const Child,
        (Attributes { .is_const = true,  .is_volatile = false, .is_allowzero = true  }).toInt() => []const allowzero Child,
        (Attributes { .is_const = true,  .is_volatile = true,  .is_allowzero = false }).toInt() => []const volatile Child,
        (Attributes { .is_const = true,  .is_volatile = true,  .is_allowzero = true  }).toInt() => []const volatile allowzero Child,
    };
}

fn makeSlice(ptr: anytype, len: usize) MakeSlice(@TypeOf(ptr)) {
    const Result = MakeSlice(@TypeOf(ptr));
    var result: Result = undefined;
    result.ptr = @ptrCast(@TypeOf(result.ptr), ptr);
    result.len = len;
    return result;
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
