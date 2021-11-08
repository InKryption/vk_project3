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
    
    .getPhysicalDeviceFeatures,
    .getPhysicalDeviceFormatProperties,
    
    .createDevice,
    
    .destroySurfaceKHR,
    .getPhysicalDeviceSurfaceFormatsKHR,
    .getPhysicalDeviceSurfacePresentModesKHR,
    .getPhysicalDeviceSurfaceCapabilitiesKHR,
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
    present: ?u32,
};

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{ .verbose_log = true }) {};
    defer _ = gpa_state.deinit();
    
    const allocator_main: *mem.Allocator = &gpa_state.allocator;
    _ = allocator_main;
    
    try glfw.init();
    defer glfw.terminate();
    
    const dispatch_base: DispatchBase = try DispatchBase.load(@ptrCast(vk.PfnGetInstanceProcAddr, glfw.getInstanceProcAddress));
    const instance = instance: {
        const create_info = InstanceCreateInfo {
            .enabled_extension_names = enabled_extension_names: {
                const slice_of_cptr = try glfw.getRequiredInstanceExtensions();
                break :enabled_extension_names makeSlice(@ptrCast([*]const [*:0]const u8, slice_of_cptr.ptr), slice_of_cptr.len);
            },
        };
        
        break :instance try dispatch_base.createInstance(create_info.asVkType(), null);
    };
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
        if (all_physical_devices.len > 1) {
            unreachable;
        }
        
        break :selected_physical_device all_physical_devices[selected_idx];
    };
    
    
    
    try glfw.Window.hint(.resizable, false);
    try glfw.Window.hint(.client_api, glfw.no_api);
    const window = try glfw.Window.create(600, 600, "vk_project3", null, null);
    defer window.destroy();
    
    const window_surface: vk.SurfaceKHR = window_surface: {
        var window_surface_result: vk.SurfaceKHR = .null_handle;
        
        const result = @intToEnum(vk.Result, try glfw.createWindowSurface(instance, window, null, &window_surface_result));
        if (result != .success) {
            inline for (comptime enums.values(vk.Result)) |possible_value| {
                if (result == possible_value) {
                    @setEvalBranchQuota(10_000);
                    
                    const tag_name = @tagName(possible_value);
                    
                    comptime var error_name_buffer: [snakecaseToCamelCaseBufferSize(tag_name)]u8 = undefined;
                    const error_name: []const u8 = comptime snakecaseToCamelCase(error_name_buffer[0..], tag_name);
                    
                    return @field(@Type(.{ .ErrorSet = &[_]builtin.TypeInfo.Error { .{ .name =  error_name } } }), error_name);
                }
            }
        }
        
        break :window_surface window_surface_result;
    };
    defer dispatch_instance.destroySurfaceKHR(instance, window_surface, null);
    
    
    
    const queue_family_indices: QueueFamilyIndices = queue_family_indices: {
        var result: QueueFamilyIndices = .{
            .graphics = null,
            .present = null,
        };
        
        const queue_family_properties_list: []const vk.QueueFamilyProperties = try getPhysicalDeviceQueueFamilyPropertiesAlloc(
            allocator_main,
            dispatch_instance,
            selected_physical_device,
        );
        defer allocator_main.free(queue_family_properties_list);
        
        for (queue_family_properties_list) |qfamily_properties, idx| {
            const present_support = try dispatch_instance.getPhysicalDeviceSurfaceSupportKHR(selected_physical_device, @intCast(u32, idx), window_surface);
            if (qfamily_properties.queue_flags.graphics_bit and present_support == vk.TRUE) {
                result.graphics = @intCast(u32, idx);
                result.present = @intCast(u32, idx);
                break;
            }
            
            if (qfamily_properties.queue_flags.graphics_bit) {
                result.graphics = @intCast(u32, idx);
                if (result.present != null) break;
            }
            
            if (present_support == vk.TRUE) {
                result.present = @intCast(u32, idx);
                if (result.graphics != null) break;
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
            .enabled_extension_names = &.{
                vk.extension_info.khr_swapchain.name,
            },
            .enabled_features = .{},
        };
        
        const as_vk_type = create_info.asVkType();
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
    
    const graphics_queue = dispatch_device.getDeviceQueue(device, queue_family_indices.graphics.?, 0);
    _ = graphics_queue;
    
    const swapchain: vk.SwapchainKHR = swapchain: {
        const swapchain_details = try SwapChainSupportInfo.init(allocator_main, dispatch_instance, selected_physical_device, window_surface);
        defer swapchain_details.deinit(allocator_main);
        
        if (swapchain_details.formats.len == 0) return error.NoAvailableVulkanSurfaceSwapchainFormats;
        const selected_format: vk.SurfaceFormatKHR = selected_format: {
            for (swapchain_details.formats) |format| {
                if (format.format == .b8g8r8a8_srgb and format.color_space == .srgb_nonlinear_khr) {
                    break :selected_format format;
                }
            }
            
            break :selected_format swapchain_details.formats[0];
        };
        
        if (swapchain_details.present_modes.len == 0) return error.NoAvailableVulkanSurfaceSwapchainPresentModes;
        const selected_present_mode: vk.PresentModeKHR = selected_present_mode: {
            for (swapchain_details.present_modes) |present_mode| {
                if (present_mode == .mailbox_khr ) break :selected_present_mode present_mode;
            }
            assert(mem.count(vk.PresentModeKHR, swapchain_details.present_modes, &.{ .fifo_khr }) >= 1);
            break :selected_present_mode .fifo_khr;
        };
        
        const selected_swap_extent: vk.Extent2D = selected_swap_extent: {
            if (swapchain_details.capabilities.current_extent.width != math.maxInt(u32)) {
                break :selected_swap_extent swapchain_details.capabilities.current_extent;
            } else {
                const frame_buffer_size = try window.getFramebufferSize();
                break :selected_swap_extent .{
                    .width = @truncate(u32, frame_buffer_size.width),
                    .height = @truncate(u32, frame_buffer_size.height),
                };
            }
        };
        
        const image_count: u32 = image_count: {
            const min = swapchain_details.capabilities.min_image_count;
            const max = if (swapchain_details.capabilities.max_image_count == 0) math.maxInt(u32) else swapchain_details.capabilities.max_image_count;
            break :image_count math.clamp(min + 1, min, max);
        };
        
        //const create_info = vk.SwapchainCreateInfoKHR {
        //    //.s_type = undefined,
        //    //.p_next = undefined,
        //    .flags = vk.SwapchainCreateFlagsKHR.fromInt(0),
        //    .surface = window_surface,
        //    .min_image_count = image_count,
        //    .image_format = selected_format.format,
        //    .image_color_space = selected_format.color_space,
        //    .image_extent = selected_swap_extent,
        //    .image_array_layers = 1,
        //    .image_usage = vk.ImageUsageFlags { .color_attachment_bit = true },
        //    .image_sharing_mode = if (queue_family_indices.present.? == queue_family_indices.graphics.?) .exclusive else .concurrent,
        //    .queue_family_index_count = if (queue_family_indices.present.? == queue_family_indices.graphics.?) 0 else queue_family_indices.present.?,
        //    .p_queue_family_indices = if (queue_family_indices.present.? == queue_family_indices.graphics.?) .exclusive else .concurrent,
        //    .pre_transform = undefined,
        //    .composite_alpha = undefined,
        //    .present_mode = undefined,
        //    .clipped = undefined,
        //    .old_swapchain = undefined,
        //};
    };
    
    
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



const SwapChainSupportInfo = struct {
    const Self = @This();
    _mem: []const u8,
    formats: []const vk.SurfaceFormatKHR,
    present_modes: []const vk.PresentModeKHR,
    capabilities: vk.SurfaceCapabilitiesKHR,
    
    pub fn init(allocator: *mem.Allocator, dispatch: DispatchInstance, physical_device: vk.PhysicalDevice, surface: vk.SurfaceKHR) !Self {
        const formats_count: u32 = formats_count: {
            var count: u32 = undefined;
            assert(dispatch.getPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &count, null) catch unreachable == .success);
            break :formats_count count;
        };
        
        const present_modes_count: u32 = present_modes_count: {
            var count: u32 = undefined;
            assert(dispatch.getPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &count, null) catch unreachable == .success);
            break :present_modes_count count;
        };
        
        const bytes = try allocator.alloc(u8, bytes_len: {
            const formats_byte_len: usize = @sizeOf(vk.SurfaceFormatKHR) * formats_count;
            const present_modes_bytes_len: usize = @sizeOf(vk.PresentModeKHR) * present_modes_count;
            break :bytes_len formats_byte_len + present_modes_bytes_len;
        });
        errdefer allocator.free(bytes);
        
        var fba = std.heap.FixedBufferAllocator.init(bytes);
        
        const formats = fba.allocator.alloc(vk.SurfaceFormatKHR, formats_count) catch unreachable;
        const present_modes = fba.allocator.alloc(vk.PresentModeKHR, present_modes_count) catch unreachable;
        assert(meta.isError(fba.allocator.alloc(u8, 1)));
        
        return Self {
            ._mem = bytes,
            .formats = formats,
            .present_modes = present_modes,
            .capabilities = try dispatch.getPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, surface),
        };
    }
    
    pub fn deinit(self: Self, allocator: *mem.Allocator) void {
        allocator.free(self._mem);
    }
};



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
