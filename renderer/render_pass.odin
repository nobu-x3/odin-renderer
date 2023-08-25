package renderer

import log "../logger"
import "core:os"
import vk "vendor:vulkan"

// TODO: config
render_pass_create :: proc(using ctx: ^Context, color: Color, extent_window: Extent2D, depth: f32, stencil: u32, out_render_pass: ^RenderPass) {
    out_render_pass.stencil = stencil;
    out_render_pass.depth = depth;
    out_render_pass.color = color;
    out_render_pass.extent = extent_window;

	color_attachment: vk.AttachmentDescription
	color_attachment.format = swapchain.format.format
	color_attachment.samples = {._1}
	color_attachment.loadOp = .CLEAR
	color_attachment.storeOp = .STORE
	color_attachment.stencilLoadOp = .DONT_CARE
	color_attachment.stencilStoreOp = .DONT_CARE
	color_attachment.initialLayout = .UNDEFINED
	color_attachment.finalLayout = .PRESENT_SRC_KHR

	color_attachment_ref: vk.AttachmentReference
	color_attachment_ref.attachment = 0
	color_attachment_ref.layout = .COLOR_ATTACHMENT_OPTIMAL

	depth_attachment: vk.AttachmentDescription
	depth_attachment.format = swapchain.depth_format 
	depth_attachment.samples = {._1}
	depth_attachment.loadOp = .CLEAR
	depth_attachment.storeOp = .DONT_CARE
	depth_attachment.stencilLoadOp = .DONT_CARE
	depth_attachment.stencilStoreOp = .DONT_CARE
	depth_attachment.initialLayout = .UNDEFINED
	depth_attachment.finalLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL

	depth_attachment_ref: vk.AttachmentReference
	depth_attachment_ref.attachment = 1
	depth_attachment_ref.layout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL


    //TODO: other attachments
	subpass: vk.SubpassDescription
	subpass.pipelineBindPoint = .GRAPHICS
	subpass.colorAttachmentCount = 1
	subpass.pColorAttachments = &color_attachment_ref
	subpass.pDepthStencilAttachment = &depth_attachment_ref
    
	dependency: vk.SubpassDependency
	dependency.srcSubpass = vk.SUBPASS_EXTERNAL
	dependency.dstSubpass = 0
	dependency.srcStageMask = {.COLOR_ATTACHMENT_OUTPUT}
	dependency.srcAccessMask = {}
	dependency.dstStageMask = {.COLOR_ATTACHMENT_OUTPUT}
	dependency.dstAccessMask = {
		.COLOR_ATTACHMENT_READ, .COLOR_ATTACHMENT_WRITE
	}

    // TODO: other attachment types
	attachments := [?]vk.AttachmentDescription{
		color_attachment,
		depth_attachment,
	}

	render_pass_info: vk.RenderPassCreateInfo
	render_pass_info.sType = .RENDER_PASS_CREATE_INFO
	render_pass_info.attachmentCount = 2
	render_pass_info.pAttachments = &attachments[0]
	render_pass_info.subpassCount = 1
	render_pass_info.pSubpasses = &subpass
	render_pass_info.dependencyCount = 1
	render_pass_info.pDependencies = &dependency
	if res := vk.CreateRenderPass(
		device,
		&render_pass_info,
		nil,
		&out_render_pass.handle,
	); res != .SUCCESS {
		log.fatal("Error: Failed to create render pass!\n")
		os.exit(1)
	}
}

render_pass_destroy :: proc(using ctx: ^Context, render_pass: ^RenderPass) {
	if (render_pass != nil) {
		vk.DestroyRenderPass(ctx.device, render_pass.handle, nil)
	}
}

render_pass_begin :: proc(
	render_pass: ^RenderPass,
	command_buffer: vk.CommandBuffer,
	target_fb: vk.Framebuffer,
) {
	render_pass_info: vk.RenderPassBeginInfo
	render_pass_info.sType = .RENDER_PASS_BEGIN_INFO
	render_pass_info.renderPass = render_pass.handle
	render_pass_info.framebuffer = target_fb
	render_pass_info.renderArea.offset = {
		cast(i32)render_pass.extent.x,
		cast(i32)render_pass.extent.y,
	}
	render_pass_info.renderArea.extent = {
		cast(u32)render_pass.extent.w,
		cast(u32)render_pass.extent.h,
	}
	clear_vals: [2]vk.ClearValue
	clear_vals[0].color.float32[0] = render_pass.color.r
	clear_vals[0].color.float32[1] = render_pass.color.g
	clear_vals[0].color.float32[2] = render_pass.color.b
	clear_vals[0].color.float32[3] = render_pass.color.a
	clear_vals[1].depthStencil.depth = render_pass.depth
	clear_vals[1].depthStencil.stencil = render_pass.stencil
	render_pass_info.clearValueCount = 2
	render_pass_info.pClearValues = raw_data(&clear_vals)
	vk.CmdBeginRenderPass(command_buffer, &render_pass_info, .INLINE)
}

render_pass_end :: proc(render_pass: ^RenderPass, command_buffer: vk.CommandBuffer){
    vk.CmdEndRenderPass(command_buffer)
}
