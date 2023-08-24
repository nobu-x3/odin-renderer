package renderer
import "core:os"
import vk "vendor:vulkan"
import "vendor:glfw"
import log "../logger"

framebuffer_create :: proc(
	ctx: ^Context,
	render_pass: ^RenderPass,
	width, height: u32,
	attachments: []vk.ImageView,
) -> Framebuffer {
	out_framebuffer: Framebuffer
	out_framebuffer.attachments = make([]vk.ImageView, len(attachments))
	copy(out_framebuffer.attachments, attachments)
	for v, i in attachments {
		framebuffer_info: vk.FramebufferCreateInfo
		framebuffer_info.sType = .FRAMEBUFFER_CREATE_INFO
		framebuffer_info.renderPass = render_pass.handle
		framebuffer_info.attachmentCount = cast(u32)len(attachments)
		framebuffer_info.pAttachments = &out_framebuffer.attachments[0]
		framebuffer_info.width = width
		framebuffer_info.height = height
		framebuffer_info.layers = 1
		if res := vk.CreateFramebuffer(
			ctx.device,
			&framebuffer_info,
			nil,
			&out_framebuffer.handle,
		); res != .SUCCESS {
			log.fatal("Error: Failed to create framebuffer #%d!\n", i)
			os.exit(1)
		}
	}
	return out_framebuffer
}

framebuffer_destroy :: proc(ctx: ^Context, framebuffer: ^Framebuffer) {
	vk.DestroyFramebuffer(ctx.device, framebuffer.handle, nil)
	framebuffer.handle = 0
	delete(framebuffer.attachments)
	framebuffer.attachments = nil
	framebuffer.render_pass = nil
}

recreate_framebuffers :: proc(
	ctx: ^Context,
	swapchain: ^Swapchain,
	render_pass: ^RenderPass,
) {
	for i in 0 ..< swapchain.image_count {
		attachments := [?]vk.ImageView{
			swapchain.image_views[i],
			swapchain.depth_attachment.view,
		}
		if (len(swapchain.framebuffers) > 0) do framebuffer_destroy(ctx, &swapchain.framebuffers[i])
		else {
			swapchain.framebuffers = make([]Framebuffer, swapchain.image_count)
		}
		swapchain.framebuffers[i] = framebuffer_create(
			ctx,
			render_pass,
			swapchain.extent.width,
			swapchain.extent.height,
			attachments[:],
		)
	}
}

framebuffer_size_callback :: proc "c" (
	window: glfw.WindowHandle,
	width, height: i32,
) {
	using ctx := cast(^Context)glfw.GetWindowUserPointer(window)
	framebuffer_resized = true
}
