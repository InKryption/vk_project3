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

const shader = @import("shader.zig");

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
    
    

    const DispatchDevice = vk.DeviceWrapper(&[_]vk.DeviceCommand {
        .destroyDevice,
        .getDeviceQueue,
        .createImageView,
        .destroyImageView,
        .createSwapchainKHR,
        .destroySwapchainKHR,
        .getSwapchainImagesKHR,
        .createShaderModule,
        .destroyShaderModule,
    });
    
    
    const Instance = InstanceAndDispatch(&.{
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
    const instance: Instance = instance: {
        var local_aa_state = std.heap.ArenaAllocator.init(allocator_main);
        defer local_aa_state.deinit();
        const local_aa_allocator: *mem.Allocator = &local_aa_state.allocator;
        
        const handle: Instance.Handle = handle: {
            const base_dispatch = try vk.BaseWrapper(comptime enums.values(vk.BaseCommand)).load(@ptrCast(vk.PfnGetInstanceProcAddr, glfw.getInstanceProcAddress));
            
            const desired_instance_layer_names: []const []const u8 = &.{
                //"VK_LAYER_NV_optimus",
                //"VK_MIRILLIS_LAYER",
                //"VK_LAYER_VALVE_steam_overlay",
                //"VK_LAYER_VALVE_steam_fossilize",
                //"VK_LAYER_LUNARG_api_dump",
                //"VK_LAYER_LUNARG_device_simulation",
                //"VK_LAYER_LUNARG_gfxreconstruct",
                //"VK_LAYER_KHRONOS_synchronization2",
                //"VK_LAYER_KHRONOS_validation",
                //"VK_LAYER_LUNARG_monitor",
                //"VK_LAYER_LUNARG_screenshot",
            };
            
            const available_instance_layer_properties: []const vk.LayerProperties = available_instance_layer_properties: {
                if (!debug.runtime_safety) {
                    break :available_instance_layer_properties &.{};
                }
                
                var count: u32 = undefined;
                assert(base_dispatch.enumerateInstanceLayerProperties(&count, null) catch unreachable == .success);
                
                const slice = try local_aa_allocator.alloc(vk.LayerProperties, count);
                errdefer local_aa_allocator.free(slice);
                
                assert(base_dispatch.enumerateInstanceLayerProperties(&count, slice.ptr) catch unreachable == .success);
                assert(slice.len == count);
                
                break :available_instance_layer_properties slice;
            };
            defer local_aa_allocator.free(available_instance_layer_properties);
            
            const enabled_layer_names: []const [*:0]const u8 = enabled_layer_names: {
                if (!debug.runtime_safety) {
                    break :enabled_layer_names &.{};
                }
                
                var result = try std.ArrayList([*:0]const u8).initCapacity(local_aa_allocator, available_instance_layer_properties.len);
                errdefer result.deinit();
                
                outer: for (desired_instance_layer_names) |desired_layer_name| {
                    for (available_instance_layer_properties) |*instance_layer_properties| {
                        const found_match = mem.eql(u8, mem.span(@ptrCast([*:0]const u8, &instance_layer_properties.layer_name)), desired_layer_name);
                        if (found_match) {
                            result.appendAssumeCapacity(desired_layer_name.ptr);
                            continue :outer;
                        }
                    }
                }
                
                break :enabled_layer_names result.toOwnedSlice();
            };
            defer local_aa_allocator.free(enabled_layer_names);
            
            const enabled_extension_names: []const [*:0]const u8 = enabled_extension_names: {
                var result = std.ArrayList([*:0]const u8).init(local_aa_allocator);
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
        
        const instance_dispatch: Instance.Dispatch = try Instance.Dispatch.load(handle, @ptrCast(vk.PfnGetInstanceProcAddr, glfw.getInstanceProcAddress));
        
        break :instance .{
            .handle = handle,
            .dispatch = instance_dispatch,
        };
    };
    defer instance.deinit(null);
    
    
    
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
    
    
    
    const device: struct {
        handle: vk.Device,
        dispatch: DispatchDevice,
    } = device: {
        const graphics_and_present_queues_equal = queue_family_indices.get(.graphics) == queue_family_indices.get(.present);
        
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
    
    
    
    const calculateSwapchainExtent = struct {
        fn calculateSwapchainExtent(
            params: struct {
                current_extent: vk.Extent2D,
                min_image_extent: vk.Extent2D,
                max_image_extent: vk.Extent2D,
                framebuffer_size: glfw.Window.Size,
            },
        ) vk.Extent2D {
            if (params.current_extent.width != math.maxInt(u32) and params.current_extent.height != math.maxInt(u32)) {
                break :selected_extent params.current_extent;
            }
            
            const clamped_width = math.clamp(params.framebuffer_size.width, params.min_image_extent.width, params.max_image_extent.width);
            const clamped_height = math.clamp(params.framebuffer_size.height, params.min_image_extent.height, params.max_image_extent.height);
            
            return .{
                .width = @truncate(u32, clamped_width),
                .height = @truncate(u32, clamped_height),
            };
        }
    }.calculateSwapchainExtent;
    
    const swapchain: struct {
        handle: vk.SwapchainKHR,
        capabilities: vk.SurfaceCapabilitiesKHR,
        format: vk.SurfaceFormatKHR,
        present_mode: vk.PresentModeKHR,
        
        _heap: []const u8,
        images: []const vk.Image,
        views: []const vk.ImageView,
    } = swapchain: {
        const handle_and_properties: struct {
            handle: vk.SwapchainKHR,
            capabilities: vk.SurfaceCapabilitiesKHR,
            format: vk.SurfaceFormatKHR,
            present_mode: vk.PresentModeKHR,
            
        } = handle_and_properties: {
            var local_aa_state = std.heap.ArenaAllocator.init(allocator_main);
            defer local_aa_state.deinit();
            const local_aa_allocator: *mem.Allocator = &local_aa_state.allocator;
            
            const selected_surface_format: vk.SurfaceFormatKHR = selected_surface_format: {
                const all_surface_formats: []const vk.SurfaceFormatKHR = all_surface_formats: {
                    var count: u32 = undefined;
                    assert(instance.dispatch.getPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &count, null) catch unreachable == .success);
                    
                    const slice = local_aa_allocator.alloc(vk.SurfaceFormatKHR, count) catch unreachable;
                    errdefer local_aa_allocator.free(slice);
                    
                    assert(instance.dispatch.getPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &count, slice.ptr) catch unreachable == .success);
                    assert(slice.len == count);
                    
                    break :all_surface_formats slice;
                };
                defer local_aa_allocator.free(all_surface_formats);
                
                if (all_surface_formats.len == 0) return error.NoAvailableVulkanSurfaceFormats;
                for (all_surface_formats) |surface_format| {
                    if (surface_format.format == .b8g8r8a8_srgb and surface_format.color_space == .srgb_nonlinear_khr) {
                        break :selected_surface_format surface_format;
                    }
                }
                
                break :selected_surface_format all_surface_formats[0];
            };
            
            const selected_present_mode: vk.PresentModeKHR = selected_present_mode: {
                const all_present_modes: []const vk.PresentModeKHR = all_present_modes: {
                    var count: u32 = undefined;
                    assert(instance.dispatch.getPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &count, null) catch unreachable == .success);
                    
                    const slice = local_aa_allocator.alloc(vk.PresentModeKHR, count) catch unreachable;
                    errdefer local_aa_allocator.free(slice);
                    
                    assert(instance.dispatch.getPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &count, slice.ptr) catch unreachable == .success);
                    assert(slice.len == count);
                    
                    break :all_present_modes slice;
                };
                defer local_aa_allocator.free(all_present_modes);
                
                for (all_present_modes) |present_mode| {
                    if (present_mode == .mailbox_khr) {
                        break :selected_present_mode present_mode;
                    }
                }
                
                assert(mem.count(vk.PresentModeKHR, all_present_modes, &.{ .fifo_khr }) == 1);
                break :selected_present_mode .fifo_khr;
            };
            
            const capabilities: vk.SurfaceCapabilitiesKHR = try instance.dispatch.getPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, surface);
            const selected_extent: vk.Extent2D = calculateSwapchainExtent(.{
                .current_extent = capabilities.current_extent,
                .min_image_extent = capabilities.min_image_extent,
                .max_image_extent = capabilities.max_image_extent,
                .framebuffer_size = try window.getFramebufferSize(),
            });
            
            const graphics_and_present_queues_equal = queue_family_indices.get(.graphics) == queue_family_indices.get(.present);
            const handle: vk.SwapchainKHR = try device.dispatch.createSwapchainKHR(device.handle, vk.SwapchainCreateInfoKHR {
                //.s_type = undefined,
                //.p_next = undefined,
                .flags = vk.SwapchainCreateFlagsKHR {},
                .surface = surface,
                .min_image_count = min_image_count: {
                    const min_image_count = capabilities.min_image_count;
                    const max_image_count = if (capabilities.max_image_count == 0) math.maxInt(u32) else capabilities.max_image_count;
                    break :min_image_count math.clamp(min_image_count + 1, min_image_count, max_image_count);
                },
                
                .image_format = selected_surface_format.format,
                .image_color_space = selected_surface_format.color_space,
                .image_extent = selected_extent,
                .image_array_layers = 1,
                .image_usage = vk.ImageUsageFlags { .color_attachment_bit = true },
                
                .image_sharing_mode = if (graphics_and_present_queues_equal) .exclusive else .concurrent,
                .queue_family_index_count = if (graphics_and_present_queues_equal) 0 else @intCast(u32, queue_family_indices.values.len),
                .p_queue_family_indices = if (graphics_and_present_queues_equal) mem.span(&[_]u32{}).ptr else &[_]u32{ queue_family_indices.get(.graphics), queue_family_indices.get(.present) },
                
                .pre_transform = capabilities.current_transform,
                .composite_alpha = vk.CompositeAlphaFlagsKHR { .opaque_bit_khr = true },
                .present_mode = selected_present_mode,
                .clipped = vk.TRUE,
                .old_swapchain = .null_handle,
            }, null);
            
            break :handle_and_properties .{
                .handle = handle,
                .capabilities = capabilities,
                .format = selected_surface_format,
                .present_mode = selected_present_mode,
            };
        };
        errdefer device.dispatch.destroySwapchainKHR(device.handle, handle_and_properties.handle, null);
        
        const image_count = image_count: {
            var count: u32 = undefined;
            assert(device.dispatch.getSwapchainImagesKHR(device.handle, handle_and_properties.handle, &count, null) catch unreachable == .success);
            break :image_count count;
        };
        const views_count = image_count;
        
        const _heap = try allocator_main.alloc(
            u8,
            (image_count * @sizeOf(vk.Image)) +
            (views_count * @sizeOf(vk.ImageView)),
        );
        errdefer allocator_main.free(_heap);
        
        var local_heap_fba_state = std.heap.FixedBufferAllocator.init(_heap);
        const local_heap_fba_allocator: *mem.Allocator = &local_heap_fba_state.allocator;
        
        const images: []const vk.Image = images: {
            const slice = local_heap_fba_allocator.alloc(vk.Image, image_count) catch unreachable;
            errdefer local_heap_fba_allocator.free(slice);
            
            var count: u32 = image_count;
            assert(device.dispatch.getSwapchainImagesKHR(device.handle, handle_and_properties.handle, &count, slice.ptr) catch unreachable == .success);
            assert(slice.len == count and count == image_count);
            
            break :images slice;
        };
        errdefer local_heap_fba_allocator.free(images);
        
        const views: []const vk.ImageView = views: {
            const slice = local_heap_fba_allocator.alloc(vk.ImageView, views_count) catch unreachable;
            errdefer local_heap_fba_allocator.free(slice);
            
            for (slice) |*image_view, idx| {
                image_view.* = try device.dispatch.createImageView(device.handle, vk.ImageViewCreateInfo {
                    // .s_type = undefined,
                    // .p_next = undefined,
                    .flags = vk.ImageViewCreateFlags {},
                    .image = images[idx],
                    
                    .view_type = .@"2d",
                    .format = handle_and_properties.format.format,
                    
                    .components = vk.ComponentMapping {
                        .r = vk.ComponentSwizzle.identity,
                        .g = vk.ComponentSwizzle.identity,
                        .b = vk.ComponentSwizzle.identity,
                        .a = vk.ComponentSwizzle.identity,
                    },
                    
                    .subresource_range = vk.ImageSubresourceRange {
                        .aspect_mask = vk.ImageAspectFlags { .color_bit = true },
                        .base_mip_level = 0,
                        .level_count = 1,
                        .base_array_layer = 0,
                        .layer_count = 1,
                    },
                }, null);
            }
            
            break :views slice;
        };
        errdefer local_heap_fba_allocator.free(views);
        
        break :swapchain .{
            .handle = handle_and_properties.handle,
            .capabilities = handle_and_properties.capabilities,
            .format = handle_and_properties.format,
            .present_mode = handle_and_properties.present_mode,
            
            ._heap = _heap,
            .images = images,
            .views = views,
        };
    };
    defer {
        for (swapchain.views) |image_view| {
            device.dispatch.destroyImageView(device.handle, image_view, null);
        }
        allocator_main.free(swapchain._heap);
        device.dispatch.destroySwapchainKHR(device.handle, swapchain.handle, null);
    }
    
    const triangle_frag: vk.ShaderModule = try device.dispatch.createShaderModule(device.handle, vk.ShaderModuleCreateInfo {
        // .s_type = undefined,
        // .p_next = undefined,
        .flags = vk.ShaderModuleCreateFlags {},
        .code_size = shader.bin.triangle_frag.len,
        .p_code = @ptrCast([*]const u32, shader.bin.triangle_frag.ptr),
    }, null);
    defer device.dispatch.destroyShaderModule(device.handle, triangle_frag, null);
    
    const triangle_vert: vk.ShaderModule = try device.dispatch.createShaderModule(device.handle, vk.ShaderModuleCreateInfo {
        // .s_type = undefined,
        // .p_next = undefined,
        .flags = vk.ShaderModuleCreateFlags {},
        .code_size = shader.bin.triangle_vert.len,
        .p_code = @ptrCast([*]const u32, shader.bin.triangle_vert.ptr),
    }, null);
    defer device.dispatch.destroyShaderModule(device.handle, triangle_vert, null);
    
    
    
    {
        const pipeline_shader_stage_create_info_triangle_vert = vk.PipelineShaderStageCreateInfo {
            // .s_type = undefined,
            // .p_next = undefined,
            .flags = vk.PipelineShaderStageCreateFlags {},
            .stage = vk.ShaderStageFlags { .vertex_bit = true },
            .module = triangle_vert,
            .p_name = "main",
            .p_specialization_info = @as(?*const vk.SpecializationInfo, null),
        };
        
        const pipeline_shader_stage_create_info_triangle_frag = vk.PipelineShaderStageCreateInfo {
            // .s_type = undefined,
            // .p_next = undefined,
            .flags = vk.PipelineShaderStageCreateFlags {},
            .stage = vk.ShaderStageFlags { .fragment_bit = true },
            .module = triangle_frag,
            .p_name = "main",
            .p_specialization_info = @as(?*const vk.SpecializationInfo, null),
        };
        
        
        
        const shader_stage_create_infos: []const vk.PipelineShaderStageCreateInfo = &.{
            pipeline_shader_stage_create_info_triangle_vert,
            pipeline_shader_stage_create_info_triangle_frag,
        };
        
        
        
        const pipeline_vertex_input_state_create_info = vk.PipelineVertexInputStateCreateInfo {
            // .s_type = undefined,
            // .p_next = undefined,
            .flags = vk.PipelineVertexInputStateCreateFlags {},
            
            .vertex_binding_description_count = 0,
            .p_vertex_binding_descriptions = &[_]vk.VertexInputBindingDescription {},
            
            .vertex_attribute_description_count = 0,
            .p_vertex_attribute_descriptions = &[_]vk.VertexInputAttributeDescription {},
        };
        
        
        
        const pipeline_input_assembly_state_create_info = vk.PipelineInputAssemblyStateCreateInfo {
            // .s_type = undefined,
            // .p_next = undefined,
            .flags = vk.PipelineInputAssemblyStateCreateFlags {},
            .topology = vk.PrimitiveTopology.triangle_list,
            .primitive_restart_enable = vk.FALSE,
        };
        
        
        
        const swapchain_extent: vk.Extent2D = calculateSwapchainExtent(.{
            .current_extent = swapchain.capabilities.current_extent,
            .min_image_extent = swapchain.capabilities.min_image_extent,
            .max_image_extent = swapchain.capabilities.max_image_extent,
            .framebuffer_size = window.getFramebufferSize() catch unreachable,
        });
        const viewports: []const vk.Viewport = &[_]vk.Viewport {
            .{
                .x = 0.0,
                .y = 0.0,
                .width = @intToFloat(f32, swapchain_extent.width),
                .height = @intToFloat(f32, swapchain_extent.height),
                .min_depth = 0.0,
                .max_depth = 1.0,
            },
        };
        const scissors: []const vk.Rect2D = &[_]vk.Rect2D {
            .{
                .offset = vk.Offset2D {
                    .x = 0,
                    .y = 0,
                },
                .extent = swapchain_extent,
            },
        };
        
        assert(viewports.len == scissors.len);
        const viewport_state_create_info = vk.PipelineViewportStateCreateInfo {
            // .s_type = undefined,
            // .p_next = undefined,
            .flags = vk.PipelineViewportStateCreateFlags {},
            
            .viewport_count = @intCast(u32, viewports.len),
            .p_viewports = viewports.ptr,
            
            .scissor_count = @intCast(u32, scissors.len),
            .p_scissors = scissors.ptr,
        };
        
        
        
        const pipeline_rasterization_state_create_info = vk.PipelineRasterizationStateCreateInfo {
            // .s_type = undefined,
            // .p_next = undefined,
            .flags = vk.PipelineRasterizationStateCreateFlags {},
            .depth_clamp_enable = vk.FALSE,
            .rasterizer_discard_enable = vk.FALSE,
            .polygon_mode = vk.PolygonMode.fill,
            .cull_mode = vk.CullModeFlags { .back_bit = true },
            .front_face = vk.FrontFace.clockwise,
            .depth_bias_enable = vk.FALSE,
            .depth_bias_constant_factor = 0.0,
            .depth_bias_clamp = 0.0,
            .depth_bias_slope_factor = 0.0,
            .line_width = 1.0,
        };
        
        const pipeline_multisample_state_create_info = vk.PipelineMultisampleStateCreateInfo {
            // .sType = undefined,
            // .p_next = undefined,
            .flags = vk.PipelineMultisampleStateCreateFlags {},
            .rasterization_samples = vk.SampleCountFlags { .@"1_bit" = true },
            .sample_shading_enable = vk.FALSE,
            .min_sample_shading = 1.0,
            .p_sample_mask = null,
            .alpha_to_coverage_enable = vk.FALSE,
            .alpha_to_one_enable = vk.FALSE,
        };
    }
    
    
    
    var timer = try time.Timer.start();
    while (!window.shouldClose()) {
        glfw.pollEvents() catch continue;
        if (timer.read() < 16 * time.ns_per_ms) continue else timer.reset();
        
        
    }
}

pub fn InstanceAndDispatch(comptime cmds: []const vk.InstanceCommand) type {
    return struct {
        const Self = @This();
        handle: Handle,
        dispatch: Dispatch,
        
        pub const Handle = vk.Instance;
        pub const Dispatch = vk.InstanceWrapper(cmds);
        
        pub fn deinit(self: Self, p_allocator: ?*const vk.AllocationCallbacks) {
            if (comptime mem.count(vk.InstanceCommand, cmds, &.{ .destroyInstance }) == 1) {
                self.dispatch.destroyInstance(self.handle, p_allocator);
            }
            unreachable;
        }
    };
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
