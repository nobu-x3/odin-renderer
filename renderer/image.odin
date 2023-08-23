package renderer

import log "../logger"
import "core:os"
import vk "vendor:vulkan"

image_create :: proc(ctx: ^Context, using image_info: ^ImageInfo) -> Image {
	image: Image
	image_ci: vk.ImageCreateInfo
	image_ci.sType = .IMAGE_CREATE_INFO
	image_ci.imageType = .D2
	image_ci.extent.width = width
	image_ci.extent.height = height
	image_ci.extent.depth = 1 // TODO: make this configurable
	image_ci.mipLevels = 4 // TODO: make this configurable
	image_ci.arrayLayers = 1
	image_ci.format = format
	image_ci.tiling = tiling
	image_ci.initialLayout = .UNDEFINED
	image_ci.usage = usage_flags
	image_ci.samples = {._1} // TODO: make this configurable
	image_ci.sharingMode = .EXCLUSIVE // TODO: make this configurable
	image.width = width
	image.height = height
	if res := vk.CreateImage(ctx.device, &image_ci, nil, &image.handle);
	   res != .SUCCESS {
		log.fatal("Failed to create image.")
		os.exit(1)
	}
	mem_reqs: vk.MemoryRequirements
	vk.GetImageMemoryRequirements(ctx.device, image.handle, &mem_reqs)
	mem_type := find_memory_index(ctx, mem_reqs.memoryTypeBits, memory_flags)
	if mem_type == -1 {
		log.fatal("Failed to find required memory type to create an image.")
		os.exit(1)
	}
	mem_alloc_info: vk.MemoryAllocateInfo
	mem_alloc_info.sType = .MEMORY_ALLOCATE_INFO
	mem_alloc_info.allocationSize = mem_reqs.size
	mem_alloc_info.memoryTypeIndex = cast(u32)mem_type
	if res := vk.AllocateMemory(
		ctx.device,
		&mem_alloc_info,
		nil,
		&image.memory,
	); res != .SUCCESS {
		log.fatal("Failed to allocate image memory.")
		os.exit(1)
	}
	if res := vk.BindImageMemory(ctx.device, image.handle, image.memory, 0);
	   res != .SUCCESS {
		log.fatal("Failed to bind image memory.")
		os.exit(1)
	}
	if create_view {
		image.view = 0
		image.view = image_view_create(ctx, format, view_aspect_flags, &image)
	}
	return image
}

image_destroy :: proc(ctx: ^Context, using image: ^Image) {
	if view > 0 {
		vk.DestroyImageView(ctx.device, view, nil)
		view = 0
	}
	if memory > 0 {
		vk.FreeMemory(ctx.device, memory, nil)
		memory = 0
	}
	if handle > 0 {
		vk.DestroyImage(ctx.device, handle, nil)
		handle = 0
	}
}

image_view_create :: proc(
	ctx: ^Context,
	format: vk.Format,
	aspect_flags: vk.ImageAspectFlags,
    image: ^Image
) -> vk.ImageView {
	image_view: vk.ImageView
	view_ci: vk.ImageViewCreateInfo
	view_ci.sType = .IMAGE_VIEW_CREATE_INFO
    view_ci.image = image.handle
	view_ci.viewType = .D2
	view_ci.format = format
	view_ci.subresourceRange = {
		baseMipLevel   = 0,
		levelCount     = 1,
		baseArrayLayer = 0,
		layerCount     = 1,
        aspectMask = aspect_flags,
	}
	if res := vk.CreateImageView(ctx.device, &view_ci, nil, &image_view);
	   res != .SUCCESS {
		log.fatal("Failed to create image.")
		os.exit(1)
	}
	return image_view
}

