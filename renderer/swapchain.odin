package renderer

import log "../logger"
import "core:os"
import vk "vendor:vulkan"
import "vendor:glfw"


swapchain_create :: proc(
	using ctx: ^Context,
	out_swapchain: ^Swapchain,
	width: u32 = 0,
	height: u32 = 0,
) {
	using out_swapchain.support
	out_swapchain.support = device_query_swapchain_details(
		ctx,
		physical_device,
	)
	out_swapchain.format = choose_surface_format(&out_swapchain.support)
	out_swapchain.depth_format = choose_depth_format(ctx)
	out_swapchain.present_mode = choose_present_mode(&out_swapchain.support)
	if width == 0 || height == 0 {
		out_swapchain.extent = choose_swap_extent(ctx, &out_swapchain.support)
	} else {
		out_swapchain.extent = vk.Extent2D {
			width  = width,
			height = height,
		}
	}
	out_swapchain.image_count =
		out_swapchain.support.capabilities.minImageCount + 1
	if out_swapchain.support.capabilities.maxImageCount > 0 &&
	   out_swapchain.image_count >
		   out_swapchain.support.capabilities.maxImageCount {
		out_swapchain.image_count =
			out_swapchain.support.capabilities.maxImageCount
	}
	out_swapchain.image_count =
		out_swapchain.image_count > 3 ? 3 : out_swapchain.image_count
	out_swapchain.max_frames_in_flight = out_swapchain.image_count - 1
	create_info: vk.SwapchainCreateInfoKHR
	create_info.sType = .SWAPCHAIN_CREATE_INFO_KHR
	create_info.surface = surface
	create_info.minImageCount = out_swapchain.image_count
	create_info.imageFormat = out_swapchain.format.format
	create_info.imageColorSpace = out_swapchain.format.colorSpace
	create_info.imageExtent = out_swapchain.extent
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
	create_info.preTransform =
		out_swapchain.support.capabilities.currentTransform
	create_info.compositeAlpha = {.OPAQUE}
	create_info.presentMode = out_swapchain.present_mode
	create_info.clipped = true
	create_info.oldSwapchain = vk.SwapchainKHR{}
	if res := vk.CreateSwapchainKHR(
		device,
		&create_info,
		nil,
		&out_swapchain.handle,
	); res != .SUCCESS {
		log.fatal("Error: failed to create swap chain!\n")
		os.exit(1)
	}
	log.info("Swapchain created.")
	curr_frame = 0
	out_swapchain.image_count = 0
	vk.GetSwapchainImagesKHR(
		device,
		out_swapchain.handle,
		&out_swapchain.image_count,
		nil,
	)
	out_swapchain.images = make([]vk.Image, out_swapchain.image_count)
	vk.GetSwapchainImagesKHR(
		device,
		out_swapchain.handle,
		&out_swapchain.image_count,
		raw_data(out_swapchain.images),
	)
	log.info("Swapchain images received: %d.", out_swapchain.image_count)
	out_swapchain.image_views = make([]vk.ImageView, out_swapchain.image_count)
	for i in 0 ..< out_swapchain.image_count {
		view_ci: vk.ImageViewCreateInfo
		view_ci.sType = .IMAGE_VIEW_CREATE_INFO
		view_ci.viewType = .D2
		view_ci.image = out_swapchain.images[i]
		view_ci.format = out_swapchain.format.format
		view_ci.subresourceRange.aspectMask = {.COLOR}
		view_ci.subresourceRange.baseMipLevel = 0
		view_ci.subresourceRange.levelCount = 1
		view_ci.subresourceRange.baseArrayLayer = 0
		view_ci.subresourceRange.layerCount = 1
		if res := vk.CreateImageView(
			device,
			&view_ci,
			nil,
			&out_swapchain.image_views[i],
		); res != .SUCCESS {
			log.fatal("Error: failed to create swap chain image views!\n")
			os.exit(1)
		}
	}
	log.info("Swapchain image views created.")
	out_swapchain.support.depth_format = choose_depth_format(ctx)
	out_swapchain.depth_format = choose_depth_format(ctx)
	image_info: ImageInfo
	image_info.width = out_swapchain.extent.width
	image_info.height = out_swapchain.extent.height
	image_info.format = out_swapchain.depth_format
	image_info.tiling = .OPTIMAL
	image_info.usage_flags = {.DEPTH_STENCIL_ATTACHMENT}
	image_info.memory_flags = {.DEVICE_LOCAL}
	image_info.create_view = true
	image_info.view_aspect_flags = {.DEPTH}
	out_swapchain.depth_attachment = image_create(ctx, &image_info)
	log.info("Swapchain depth attachment created.")
}

swapchain_acquire_next_image_index :: proc(
	ctx: ^Context,
	swapchain: ^Swapchain,
	semaphore: vk.Semaphore,
	fence: vk.Fence,
	timeout_ns: u64,
	out_image_index: ^u32,
) {
	res := vk.AcquireNextImageKHR(
		ctx.device,
		swapchain.handle,
		timeout_ns,
		semaphore,
		fence,
		out_image_index,
	)
	if (res == .ERROR_OUT_OF_DATE_KHR) {
		swapchain_recreate(ctx)
	} else if (res != .SUCCESS && res == .SUBOPTIMAL_KHR) {
		log.fatal("Failed to acquire the next image index.")
		os.exit(1)
	}
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
	recreate_framebuffers(ctx, &ctx.swapchain, &ctx.main_render_pass)
}

swapchain_cleanup :: proc(using ctx: ^Context) {
	for f in swapchain.framebuffers {
		vk.DestroyFramebuffer(device, f.handle, nil)
	}
	for view in swapchain.image_views {
		vk.DestroyImageView(device, view, nil)
	}
	vk.DestroySwapchainKHR(device, swapchain.handle, nil)
}

swapchain_present :: proc(ctx: ^Context, swapchain: ^Swapchain, queue: vk.Queue, render_complete_sem: vk.Semaphore, preset_image_index: u32){
    render_complete_sem := render_complete_sem
    preset_image_index := preset_image_index
    present_info:vk.PresentInfoKHR
    present_info.sType = .PRESENT_INFO_KHR
    present_info.swapchainCount = 1
    present_info.pSwapchains = &swapchain.handle
    present_info.waitSemaphoreCount = 1
    present_info.pWaitSemaphores = &render_complete_sem
    present_info.pImageIndices = &preset_image_index
    res := vk.QueuePresentKHR(queue, &present_info)
    if res == .ERROR_OUT_OF_DATE_KHR || res == .SUBOPTIMAL_KHR{
        swapchain_recreate(ctx)
    }
    else if res != .SUCCESS{
        log.error("Failed to present swapchain image.")
    }
    ctx.curr_frame = (ctx.curr_frame + 1) % swapchain.max_frames_in_flight
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

choose_depth_format :: proc(using ctx: ^Context) -> vk.Format {
	priorities := [?]vk.Format{
		.D32_SFLOAT,
		.D32_SFLOAT_S8_UINT,
		.D24_UNORM_S8_UINT,
	}
	flags := vk.FormatFeatureFlags.DEPTH_STENCIL_ATTACHMENT
	for i in 0 ..< 3 {
		props: vk.FormatProperties
		vk.GetPhysicalDeviceFormatProperties(
			physical_device,
			priorities[i],
			&props,
		)
		if (flags in props.linearTilingFeatures) ||
		   (flags in props.optimalTilingFeatures) {
			return priorities[i]
		}
	}
	log.fatal("Failed to identify depth format")
	return vk.Format.UNDEFINED
}

choose_surface_format :: proc(
	swapchain_desc: ^SwapchainDescription,
) -> vk.SurfaceFormatKHR {
	for v in swapchain_desc.formats {
		if v.format == .B8G8R8A8_SRGB && v.colorSpace == .SRGB_NONLINEAR do return v
	}
	return swapchain_desc.formats[0]
}

choose_present_mode :: proc(
	swapchain_desc: ^SwapchainDescription,
) -> vk.PresentModeKHR {
	for v in swapchain_desc.present_modes {
		if v == .MAILBOX do return v
	}
	return .FIFO
}

choose_swap_extent :: proc(
	ctx: ^Context,
	swapchain_desc: ^SwapchainDescription,
) -> vk.Extent2D {
	if (swapchain_desc.capabilities.currentExtent.width != max(u32)) {
		return swapchain_desc.capabilities.currentExtent
	} else {
		width, height := glfw.GetFramebufferSize(ctx.window)
		extent := vk.Extent2D{u32(width), u32(height)}
		extent.width = clamp(
			extent.width,
			swapchain_desc.capabilities.minImageExtent.width,
			swapchain_desc.capabilities.maxImageExtent.width,
		)
		extent.height = clamp(
			extent.height,
			swapchain_desc.capabilities.minImageExtent.height,
			swapchain_desc.capabilities.maxImageExtent.height,
		)
		return extent
	}
}
