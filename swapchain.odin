package renderer

import log "logger"
import "core:os"
import vk "vendor:vulkan"
import "vendor:glfw"


swapchain_create :: proc(using ctx: ^Context, out_swapchain: ^Swapchain, width :u32 = 0, height :u32 =0) {
	using ctx.swapchain.support
	swapchain.format = choose_surface_format(ctx)
	swapchain.present_mode = choose_present_mode(ctx)
	if width == 0 || height == 0{
		swapchain.extent = choose_swap_extent(ctx)
	}
	else{
		swapchain.extent = vk.Extent2D{width = width, height = height}
	}
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
		log.fatal("Error: failed to create swap chain!\n")
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

swapchain_recreate :: proc(using ctx: ^Context) {
	width, height := glfw.GetFramebufferSize(window)
	for width == 0 && height == 0 {
		width, height = glfw.GetFramebufferSize(window)
		glfw.WaitEvents()
	}
	vk.DeviceWaitIdle(device)
	swapchain_cleanup(ctx)
	swapchain_create(ctx, &ctx.swapchain)
	create_image_views(ctx)
	create_framebuffers(ctx)
}

swapchain_cleanup :: proc(using ctx: ^Context) {
	for f in swapchain.framebuffers {
		vk.DestroyFramebuffer(device, f, nil)
	}
	for view in swapchain.image_views {
		vk.DestroyImageView(device, view, nil)
	}
	vk.DestroySwapchainKHR(device, swapchain.handle, nil)
}

create_image_views :: proc(using ctx: ^Context) {
	using ctx.swapchain
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
			log.fatal("Error: failed to create image view!")
			os.exit(1)
		}
	}
}

create_framebuffers :: proc(using ctx: ^Context) {
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
			log.fatal("Error: Failed to create framebuffer #%d!\n", i)
			os.exit(1)
		}
	}
}

framebuffer_create :: proc(ctx: ^Context, render_pass: ^RenderPass, width, height: u32, attachments: []vk.ImageView, out_framebuffer: ^Framebuffer){
	out_framebuffer.attachments = make([]vk.ImageView, len(attachments))
	for v, i in attachments{
		attach := [?]vk.ImageView{v}
		framebuffer_info: vk.FramebufferCreateInfo
		framebuffer_info.sType = .FRAMEBUFFER_CREATE_INFO
		framebuffer_info.renderPass = render_pass.handle
		framebuffer_info.attachmentCount = 1
		framebuffer_info.pAttachments = &attachments[0]
		framebuffer_info.width = width
		framebuffer_info.height = height
		framebuffer_info.layers = 1
		if res := vk.CreateFramebuffer(ctx.device, &framebuffer_info, nil, &out_framebuffer.handle); res != .SUCCESS {
			log.fatal("Error: Failed to create framebuffer #%d!\n", i)
			os.exit(1)
		}
	}
}

framebuffer_destroy :: proc(ctx: ^Context, framebuffer: ^Framebuffer){

}

framebuffer_size_callback :: proc "c" (
	window: glfw.WindowHandle,
	width, height: i32,
) {
	using ctx := cast(^Context)glfw.GetWindowUserPointer(window)
	framebuffer_resized = true
}

choose_surface_format :: proc(
	using ctx: ^Context,
) -> vk.SurfaceFormatKHR {
	for v in swapchain.support.formats {
		if v.format == .B8G8R8A8_SRGB && v.colorSpace == .SRGB_NONLINEAR do return v
	}
	return swapchain.support.formats[0]
}

choose_present_mode :: proc(using ctx: ^Context) -> vk.PresentModeKHR {
	for v in swapchain.support.present_modes {
		if v == .MAILBOX do return v
	}
	return .FIFO
}

choose_swap_extent :: proc(using ctx: ^Context) -> vk.Extent2D {
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
