package renderer

import "core:mem"
import "core:fmt"
import "core:os"
import vk "vendor:vulkan"
import "vendor:glfw"


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

swapchain_create :: proc(using renderer: ^Renderer) {
	using renderer.swapchain.support
	swapchain.format = choose_surface_format(renderer)
	swapchain.present_mode = choose_present_mode(renderer)
	swapchain.extent = choose_swap_extent(renderer)
	swapchain.image_count = capabilities.minImageCount + 1
	if capabilities.maxImageCount > 0 &&
	   swapchain.image_count > capabilities.maxImageCount {
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
	if res := vk.CreateSwapchainKHR(
		device,
		&create_info,
		nil,
		&swapchain.handle,
	); res != .SUCCESS {
		fmt.eprintf("Error: failed to create swap chain!\n")
		os.exit(1)
	}
	vk.GetSwapchainImagesKHR(
		device,
		swapchain.handle,
		&swapchain.image_count,
		nil,
	)
	swapchain.images = make([]vk.Image, swapchain.image_count)
	vk.GetSwapchainImagesKHR(
		device,
		swapchain.handle,
		&swapchain.image_count,
		raw_data(swapchain.images),
	)
}

swapchain_recreate :: proc(using renderer: ^Renderer) {
	width, height := glfw.GetFramebufferSize(window)
	for width == 0 && height == 0 {
		width, height = glfw.GetFramebufferSize(window)
		glfw.WaitEvents()
	}
	vk.DeviceWaitIdle(device)
	swapchain_cleanup(renderer)
	swapchain_create(renderer)
	create_image_views(renderer)
	create_framebuffers(renderer)
}

swapchain_cleanup :: proc(using renderer: ^Renderer) {
	for f in swapchain.framebuffers {
		vk.DestroyFramebuffer(device, f, nil)
	}
	for view in swapchain.image_views {
		vk.DestroyImageView(device, view, nil)
	}
	vk.DestroySwapchainKHR(device, swapchain.handle, nil)
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
		if res := vk.CreateImageView(
			device,
			&create_info,
			nil,
			&image_views[i],
		); res != .SUCCESS {
			fmt.eprintf("Error: failed to create image view!")
			os.exit(1)
		}
	}
}

create_framebuffers :: proc(using renderer: ^Renderer) {
	swapchain.framebuffers = make([]vk.Framebuffer, len(swapchain.image_views))
	for v, i in swapchain.image_views {
		attachments := [?]vk.ImageView{v}
		framebuffer_info: vk.FramebufferCreateInfo
		framebuffer_info.sType = .FRAMEBUFFER_CREATE_INFO
		framebuffer_info.renderPass = pipeline.render_pass
		framebuffer_info.attachmentCount = 1
		framebuffer_info.pAttachments = &attachments[0]
		framebuffer_info.width = swapchain.extent.width
		framebuffer_info.height = swapchain.extent.height
		framebuffer_info.layers = 1
		if res := vk.CreateFramebuffer(
			device,
			&framebuffer_info,
			nil,
			&swapchain.framebuffers[i],
		); res != .SUCCESS {
			fmt.eprintf("Error: Failed to create framebuffer #%d!\n", i)
			os.exit(1)
		}
	}
}

framebuffer_size_callback :: proc "c" (
	window: glfw.WindowHandle,
	width, height: i32,
) {
	using renderer := cast(^Renderer)glfw.GetWindowUserPointer(window)
	framebuffer_resized = true
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
