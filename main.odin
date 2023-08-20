package renderer

import "core:fmt"
import "core:os"
import "vendor:glfw"
import vk "vendor:vulkan"

Renderer :: struct {
	window:          glfw.WindowHandle,
	instance:        vk.Instance,
	device:          vk.Device,
	surface:         vk.SurfaceKHR,
	physical_device: vk.PhysicalDevice,
	queue_indices:   [QueueFamily]int,
	queues:          [QueueFamily]vk.Queue,
	swapchain:       Swapchain,
}

Swapchain :: struct {
	handle:       vk.SwapchainKHR,
	images:       []vk.Image,
	image_views:  []vk.ImageView,
	format:       vk.SurfaceFormatKHR,
	extent:       vk.Extent2D,
	present_mode: vk.PresentModeKHR,
	image_count:  u32,
	support:      SwapchainDescription,
	framebuffers: []vk.Framebuffer,
}

SwapchainDescription :: struct {
	capabilities:  vk.SurfaceCapabilitiesKHR,
	formats:       []vk.SurfaceFormatKHR,
	present_modes: []vk.PresentModeKHR,
}


QueueFamily :: enum {
	Graphics,
	Present,
}

DEVICE_EXTENSIONS := [?]cstring{"VK_KHR_swapchain"}
VALIDATION_LAYERS := [?]cstring{"VK_LAYER_KHRONOS_validation"}

main :: proc() {
	glfw.Init()
	defer glfw.Terminate()
	renderer: Renderer
	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.RESIZABLE, 0)
	renderer.window = glfw.CreateWindow(800, 600, "Renderer", nil, nil)
	defer glfw.DestroyWindow(renderer.window)
	context.user_ptr = &renderer.instance
	get_proc_address :: proc(p: rawptr, name: cstring) {
		(cast(^rawptr)p)^ = glfw.GetInstanceProcAddress((^vk.Instance)(context.user_ptr)^, name)
	}
	vk.load_proc_addresses(get_proc_address)
	create_instance(&renderer)
	defer vk.DestroyInstance(renderer.instance, nil)
	vk.load_proc_addresses(get_proc_address)
	if glfw.CreateWindowSurface(renderer.instance, renderer.window, nil, &renderer.surface) !=
	   .SUCCESS {
		fmt.eprintf("ERROR: Failed to create gltf window surface\n")
		os.exit(1)
	}
	defer vk.DestroySurfaceKHR(renderer.instance, renderer.surface, nil)
	extensions := get_extensions()
	for ext in &extensions {
		fmt.println(cstring(&ext.extensionName[0]))
	}
	get_suitable_device(&renderer)
	find_queue_families(&renderer)
	fmt.println("Queue Indices:")
	for q, f in renderer.queue_indices do fmt.printf("  %v: %d\n", f, q)
	create_device(&renderer)
	defer vk.DestroyDevice(renderer.device, nil)
	for q, f in &renderer.queues {
		vk.GetDeviceQueue(renderer.device, u32(renderer.queue_indices[f]), 0, &q)
	}
	create_swapchain(&renderer)
	for (!glfw.WindowShouldClose(renderer.window)) {
		glfw.PollEvents()
		glfw.SwapBuffers(renderer.window)
	}
}

create_instance :: proc(renderer: ^Renderer) {
	app_info: vk.ApplicationInfo
	app_info.sType = .APPLICATION_INFO
	app_info.pApplicationName = "Hello Triangle"
	app_info.applicationVersion = vk.MAKE_VERSION(0, 0, 1)
	app_info.pEngineName = "No Engine"
	app_info.engineVersion = vk.MAKE_VERSION(1, 0, 0)
	app_info.apiVersion = vk.API_VERSION_1_0
	create_info: vk.InstanceCreateInfo
	create_info.sType = .INSTANCE_CREATE_INFO
	create_info.pApplicationInfo = &app_info
	glfw_ext := glfw.GetRequiredInstanceExtensions()
	create_info.ppEnabledExtensionNames = raw_data(glfw_ext)
	create_info.enabledExtensionCount = cast(u32)len(glfw_ext)
	when ODIN_DEBUG 
	{
		layer_count: u32
		vk.EnumerateInstanceLayerProperties(&layer_count, nil)
		layers := make([]vk.LayerProperties, layer_count)
		vk.EnumerateInstanceLayerProperties(&layer_count, raw_data(layers))
		outer: for name in VALIDATION_LAYERS {
			for layer in &layers {
				if name == cstring(&layer.layerName[0]) do continue outer
			}
			fmt.eprintf("ERROR: validation layer %q not available\n", name)
			os.exit(1)
		}
		create_info.ppEnabledLayerNames = &VALIDATION_LAYERS[0]
		create_info.enabledLayerCount = len(VALIDATION_LAYERS)
		fmt.println("Validation Layers Loaded")
	} else {
		create_info.enabledLayerCount = 0
	}
	if (vk.CreateInstance(&create_info, nil, &renderer.instance) != .SUCCESS) {
		fmt.eprintf("ERROR: Failed to create instance\n")
		return
	}
	fmt.println("Instance Created")
}

create_device :: proc(using renderer: ^Renderer) {
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
	if vk.CreateDevice(physical_device, &device_create_info, nil, &device) != .SUCCESS {
		fmt.eprintf("ERROR: Failed to create logical device\n")
		os.exit(1)
	}
}
create_swapchain :: proc(using renderer: ^Renderer) {
	using renderer.swapchain.support
	swapchain.format = choose_surface_format(renderer)
	swapchain.present_mode = choose_present_mode(renderer)
	swapchain.extent = choose_swap_extent(renderer)
	swapchain.image_count = capabilities.minImageCount + 1
	if capabilities.maxImageCount > 0 && swapchain.image_count > capabilities.maxImageCount {
		swapchain.image_count = capabilities.maxImageCount
	}
	create_info: vk.SwapchainCreateInfoKHR
	create_info.sType = .SWAPCHAIN_CREATE_INFO_KHR
	create_info.surface = surface
	create_info.minImageCount = swapchain.image_count
	create_info.imageFormat = swapchain.format.format
	create_info.imageColorSpace = swapchain.format.colorSpace
	create_info.imageExtent = swapchain.extent
	create_info.imageArrayLayers = 1
	create_info.imageUsage = {.COLOR_ATTACHMENT}
	queue_family_indices := [len(QueueFamily)]u32{
		u32(queue_indices[.Graphics]),
		u32(queue_indices[.Present]),
	}
	if queue_indices[.Graphics] != queue_indices[.Present] {
		create_info.imageSharingMode = .CONCURRENT
		create_info.queueFamilyIndexCount = 2
		create_info.pQueueFamilyIndices = &queue_family_indices[0]
	} else {
		create_info.imageSharingMode = .EXCLUSIVE
		create_info.queueFamilyIndexCount = 0
		create_info.pQueueFamilyIndices = nil
	}
	create_info.preTransform = capabilities.currentTransform
	create_info.compositeAlpha = {.OPAQUE}
	create_info.presentMode = swapchain.present_mode
	create_info.clipped = true
	create_info.oldSwapchain = vk.SwapchainKHR{}
	if res := vk.CreateSwapchainKHR(device, &create_info, nil, &swapchain.handle);
	   res != .SUCCESS {
		fmt.eprintf("Error: failed to create swap chain!\n")
		os.exit(1)
	}
	vk.GetSwapchainImagesKHR(device, swapchain.handle, &swapchain.image_count, nil)
	swapchain.images = make([]vk.Image, swapchain.image_count)
	vk.GetSwapchainImagesKHR(
		device,
		swapchain.handle,
		&swapchain.image_count,
		raw_data(swapchain.images),
	)
}

create_image_views :: proc(using renderer: ^Renderer) {
	using renderer.swapchain
	image_views = make([]vk.ImageView, len(images))
	for _, i in images {
		create_info: vk.ImageViewCreateInfo
		create_info.sType = .IMAGE_VIEW_CREATE_INFO
		create_info.image = images[i]
		create_info.viewType = .D2
		create_info.format = format.format
		create_info.components.r = .IDENTITY
		create_info.components.g = .IDENTITY
		create_info.components.b = .IDENTITY
		create_info.components.a = .IDENTITY
		create_info.subresourceRange.aspectMask = {.COLOR}
		create_info.subresourceRange.baseMipLevel = 0
		create_info.subresourceRange.levelCount = 1
		create_info.subresourceRange.baseArrayLayer = 0
		create_info.subresourceRange.layerCount = 1

		if res := vk.CreateImageView(device, &create_info, nil, &image_views[i]); res != .SUCCESS {
			fmt.eprintf("Error: failed to create image view!")
			os.exit(1)
		}
	}
}

get_suitable_device :: proc(using renderer: ^Renderer) {
	device_count: u32
	vk.EnumeratePhysicalDevices(instance, &device_count, nil)
	if device_count == 0 {
		fmt.eprintf("ERROR: Failed to find GPUs with Vulkan support\n")
		os.exit(1)
	}
	devices := make([]vk.PhysicalDevice, device_count)
	vk.EnumeratePhysicalDevices(instance, &device_count, raw_data(devices))
	suitability :: proc(using renderer: ^Renderer, dev: vk.PhysicalDevice) -> int {
		props: vk.PhysicalDeviceProperties
		features: vk.PhysicalDeviceFeatures
		vk.GetPhysicalDeviceProperties(dev, &props)
		vk.GetPhysicalDeviceFeatures(dev, &features)
		score := 0
		if props.deviceType == .DISCRETE_GPU do score += 1000
		score += cast(int)props.limits.maxImageDimension2D
		if !features.geometryShader do return 0
		if !check_device_extension_support(dev) do return 0
		query_swapchain_details(renderer, dev)
		if len(swapchain.support.formats) == 0 || len(swapchain.support.present_modes) == 0 do return 0

		return score
	}

	hiscore := 0
	for dev in devices {
		score := suitability(renderer, dev)
		if score > hiscore {
			physical_device = dev
			hiscore = score
		}
	}

	if (hiscore == 0) {
		fmt.eprintf("ERROR: Failed to find a suitable GPU\n")
		os.exit(1)
	}
}

check_device_extension_support :: proc(physical_device: vk.PhysicalDevice) -> bool {
	ext_count: u32
	vk.EnumerateDeviceExtensionProperties(physical_device, nil, &ext_count, nil)

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


get_extensions :: proc() -> []vk.ExtensionProperties {
	n_ext: u32
	vk.EnumerateInstanceExtensionProperties(nil, &n_ext, nil)
	extensions := make([]vk.ExtensionProperties, n_ext)
	vk.EnumerateInstanceExtensionProperties(nil, &n_ext, raw_data(extensions))
	return extensions
}

find_queue_families :: proc(using renderer: ^Renderer) {
	queue_count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(physical_device, &queue_count, nil)
	available_queues := make([]vk.QueueFamilyProperties, queue_count)
	vk.GetPhysicalDeviceQueueFamilyProperties(
		physical_device,
		&queue_count,
		raw_data(available_queues),
	)

	for v, i in available_queues {
		if .GRAPHICS in v.queueFlags && queue_indices[.Graphics] == -1 do queue_indices[.Graphics] = i

		present_support: b32
		vk.GetPhysicalDeviceSurfaceSupportKHR(physical_device, u32(i), surface, &present_support)
		if present_support && queue_indices[.Present] == -1 do queue_indices[.Present] = i

		for q in queue_indices do if q == -1 do continue
		break
	}
}

choose_surface_format :: proc(using renderer: ^Renderer) -> vk.SurfaceFormatKHR {
	for v in swapchain.support.formats {
		if v.format == .B8G8R8A8_SRGB && v.colorSpace == .SRGB_NONLINEAR do return v
	}

	return swapchain.support.formats[0]
}

choose_present_mode :: proc(using renderer: ^Renderer) -> vk.PresentModeKHR {
	for v in swapchain.support.present_modes {
		if v == .MAILBOX do return v
	}

	return .FIFO
}

choose_swap_extent :: proc(using renderer: ^Renderer) -> vk.Extent2D {
	if (swapchain.support.capabilities.currentExtent.width != max(u32)) {
		return swapchain.support.capabilities.currentExtent
	} else {
		width, height := glfw.GetFramebufferSize(window)

		extent := vk.Extent2D{u32(width), u32(height)}

		extent.width = clamp(
			extent.width,
			swapchain.support.capabilities.minImageExtent.width,
			swapchain.support.capabilities.maxImageExtent.width,
		)
		extent.height = clamp(
			extent.height,
			swapchain.support.capabilities.minImageExtent.height,
			swapchain.support.capabilities.maxImageExtent.height,
		)

		return extent
	}
}

query_swapchain_details :: proc(using renderer: ^Renderer, dev: vk.PhysicalDevice) {
	vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(dev, surface, &swapchain.support.capabilities)

	format_count: u32
	vk.GetPhysicalDeviceSurfaceFormatsKHR(dev, surface, &format_count, nil)
	if format_count > 0 {
		swapchain.support.formats = make([]vk.SurfaceFormatKHR, format_count)
		vk.GetPhysicalDeviceSurfaceFormatsKHR(
			dev,
			surface,
			&format_count,
			raw_data(swapchain.support.formats),
		)
	}

	present_mode_count: u32
	vk.GetPhysicalDeviceSurfacePresentModesKHR(dev, surface, &present_mode_count, nil)
	if present_mode_count > 0 {
		swapchain.support.present_modes = make([]vk.PresentModeKHR, present_mode_count)
		vk.GetPhysicalDeviceSurfacePresentModesKHR(
			dev,
			surface,
			&present_mode_count,
			raw_data(swapchain.support.present_modes),
		)
	}
}
