package renderer

import log "../logger"
import "core:os"
import vk "vendor:vulkan"

device_create :: proc(using ctx: ^Context) {
	device_get_suitable_device(ctx)
	find_queue_families(ctx)
	log.info("Queue Indices:")
	for q, f in ctx.queue_indices do log.info("  %v: %d\n", f, q)
	unique_indices: map[int]b8
	defer delete(unique_indices)
	for i in queue_indices do unique_indices[i] = true
	queue_priority := f32(1.0)
	queue_create_infos: [dynamic]vk.DeviceQueueCreateInfo
	defer delete(queue_create_infos)
	for k, _ in unique_indices {
		queue_create_info: vk.DeviceQueueCreateInfo
		queue_create_info.sType = .DEVICE_QUEUE_CREATE_INFO
		queue_create_info.queueFamilyIndex = u32(queue_indices[.Graphics])
		queue_create_info.queueCount = 1
		queue_create_info.pQueuePriorities = &queue_priority
		append(&queue_create_infos, queue_create_info)
	}
	device_features: vk.PhysicalDeviceFeatures
	device_create_info: vk.DeviceCreateInfo
	device_create_info.sType = .DEVICE_CREATE_INFO
	device_create_info.enabledExtensionCount = u32(len(DEVICE_EXTENSIONS))
	device_create_info.ppEnabledExtensionNames = &DEVICE_EXTENSIONS[0]
	device_create_info.pQueueCreateInfos = raw_data(queue_create_infos)
	device_create_info.queueCreateInfoCount = u32(len(queue_create_infos))
	device_create_info.pEnabledFeatures = &device_features
	device_create_info.enabledLayerCount = 0
	if vk.CreateDevice(physical_device, &device_create_info, nil, &device) !=
	   .SUCCESS {
		log.fatal("ERROR: Failed to create logical device\n")
		os.exit(1)
	}
	for q, f in &ctx.queues {
		vk.GetDeviceQueue(ctx.device, u32(ctx.queue_indices[f]), 0, &q)
	}
}

device_get_suitable_device :: proc(using ctx: ^Context) {
	device_count: u32
	vk.EnumeratePhysicalDevices(instance, &device_count, nil)
	if device_count == 0 {
		log.fatal("ERROR: Failed to find GPUs with Vulkan support\n")
		os.exit(1)
	}
	devices := make([]vk.PhysicalDevice, device_count)
	vk.EnumeratePhysicalDevices(instance, &device_count, raw_data(devices))
	suitability :: proc(ctx: ^Context, dev: vk.PhysicalDevice) -> int {
		props: vk.PhysicalDeviceProperties
		features: vk.PhysicalDeviceFeatures
		vk.GetPhysicalDeviceProperties(dev, &props)
		vk.GetPhysicalDeviceFeatures(dev, &features)
		score := 0
		if props.deviceType == .DISCRETE_GPU do score += 1000
		score += cast(int)props.limits.maxImageDimension2D
		if !device_check_extension_support(dev) do return 0
		details := device_query_swapchain_details(ctx, dev)
		if len(details.formats) == 0 || len(details.present_modes) == 0 do return 0
		return score
	}
	hiscore := 0
	for dev in devices {
		score := suitability(ctx, dev)
		if score > hiscore {
			physical_device = dev
			hiscore = score
		}
	}
	if (hiscore == 0) {
		log.fatal("ERROR: Failed to find a suitable GPU\n")
		os.exit(1)
	}
}

device_check_extension_support :: proc(
	physical_device: vk.PhysicalDevice,
) -> bool {
	ext_count: u32
	vk.EnumerateDeviceExtensionProperties(
		physical_device,
		nil,
		&ext_count,
		nil,
	)
	available_extensions := make([]vk.ExtensionProperties, ext_count)
	vk.EnumerateDeviceExtensionProperties(
		physical_device,
		nil,
		&ext_count,
		raw_data(available_extensions),
	)
	for ext in DEVICE_EXTENSIONS {
		found: b32
		for available in &available_extensions {
			if cstring(&available.extensionName[0]) == ext {
				found = true
				break
			}
		}
		if !found do return false
	}
	return true
}

device_query_swapchain_details :: proc(
	using ctx: ^Context,
	dev: vk.PhysicalDevice,
) -> SwapchainDescription {
	desc: SwapchainDescription
	if res := vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(
		dev,
		surface,
		&desc.capabilities,
	); res != .SUCCESS {
		log.fatal("Failed to query physical device surface capabilities")
		os.exit(1)
	}
	format_count: u32
	if res := vk.GetPhysicalDeviceSurfaceFormatsKHR(
		dev,
		surface,
		&format_count,
		nil,
	); res != .SUCCESS {
		log.fatal("Failed to query physical device surface formats")
		os.exit(1)
	}
	if format_count > 0 {
		desc.formats = make([]vk.SurfaceFormatKHR, format_count)
		if res := vk.GetPhysicalDeviceSurfaceFormatsKHR(
			dev,
			surface,
			&format_count,
			raw_data(desc.formats),
		); res != .SUCCESS {
			log.fatal(
				"Failed to query physical device surface formats 2nd time",
			)
			os.exit(1)
		}
	}
	present_mode_count: u32
	if res := vk.GetPhysicalDeviceSurfacePresentModesKHR(
		dev,
		surface,
		&present_mode_count,
		nil,
	); res != .SUCCESS {
		log.fatal("Failed to query physical device surface present modes")
		os.exit(1)
	}
	if present_mode_count > 0 {
		desc.present_modes = make([]vk.PresentModeKHR, present_mode_count)
		if res := vk.GetPhysicalDeviceSurfacePresentModesKHR(
			dev,
			surface,
			&present_mode_count,
			raw_data(desc.present_modes),
		); res != .SUCCESS {
			log.fatal(
				"Failed to query physical device surface present modes 2nd time"
			)
			os.exit(1)
		}
	}
	return desc
}

find_queue_families :: proc(using ctx: ^Context) {
	queue_count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(
		physical_device,
		&queue_count,
		nil,
	)
	available_queues := make([]vk.QueueFamilyProperties, queue_count)
	vk.GetPhysicalDeviceQueueFamilyProperties(
		physical_device,
		&queue_count,
		raw_data(available_queues),
	)
	for v, i in available_queues {
		if .GRAPHICS in v.queueFlags && queue_indices[.Graphics] == -1 do queue_indices[.Graphics] = i
		present_support: b32
		vk.GetPhysicalDeviceSurfaceSupportKHR(
			physical_device,
			u32(i),
			surface,
			&present_support,
		)
		if present_support && queue_indices[.Present] == -1 do queue_indices[.Present] = i
		for q in queue_indices do if q == -1 do continue
		break
	}
}

device_find_memory_type :: proc(
	using ctx: ^Context,
	type_filter: u32,
	properties: vk.MemoryPropertyFlags,
) -> u32 {
	mem_properties: vk.PhysicalDeviceMemoryProperties
	vk.GetPhysicalDeviceMemoryProperties(physical_device, &mem_properties)
	for i in 0 ..< mem_properties.memoryTypeCount {
		if (type_filter & (1 << i) != 0) &&
		   (mem_properties.memoryTypes[i].propertyFlags & properties) ==
			   properties {
			return i
		}
	}
	log.fatal("Error: Failed to find suitable memory type!\n")
	os.exit(1)
}

find_memory_index :: proc(
	ctx: ^Context,
	types_filter: u32,
	mem_flags: vk.MemoryPropertyFlags,
) -> i32 {
	mem_props: vk.PhysicalDeviceMemoryProperties
	vk.GetPhysicalDeviceMemoryProperties(ctx.physical_device, &mem_props)
	for i in 0 ..= mem_props.memoryTypeCount {
		if (types_filter & (1 << i) != 0) &&
		   mem_props.memoryTypes[i].propertyFlags == mem_flags {
			return cast(i32)i
		}
	}
	return -1
}

get_surface_capabilities :: proc(
	physical_device: vk.PhysicalDevice,
	surface: vk.SurfaceKHR,
) -> vk.SurfaceCapabilitiesKHR {
	capabilities: vk.SurfaceCapabilitiesKHR
	if res := vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(
		physical_device,
		surface,
		&capabilities,
	); res != .SUCCESS {
		log.fatal("Failed to query physical device surface capabilites")
		os.exit(1)
	}
	return capabilities
}

