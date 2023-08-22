package renderer

import log "logger"
import "core:os"
import vk "vendor:vulkan"

render_pass_create :: proc(using ctx: ^Context) {
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
	subpass: vk.SubpassDescription
	subpass.pipelineBindPoint = .GRAPHICS
	subpass.colorAttachmentCount = 1
	subpass.pColorAttachments = &color_attachment_ref
	dependency: vk.SubpassDependency
	dependency.srcSubpass = vk.SUBPASS_EXTERNAL
	dependency.dstSubpass = 0
	dependency.srcStageMask = {.COLOR_ATTACHMENT_OUTPUT}
	dependency.srcAccessMask = {}
	dependency.dstStageMask = {.COLOR_ATTACHMENT_OUTPUT}
	dependency.dstAccessMask = {.COLOR_ATTACHMENT_WRITE}
	render_pass_info: vk.RenderPassCreateInfo
	render_pass_info.sType = .RENDER_PASS_CREATE_INFO
	render_pass_info.attachmentCount = 1
	render_pass_info.pAttachments = &color_attachment
	render_pass_info.subpassCount = 1
	render_pass_info.pSubpasses = &subpass
	render_pass_info.dependencyCount = 1
	render_pass_info.pDependencies = &dependency
	if res := vk.CreateRenderPass(
		device,
		&render_pass_info,
		nil,
		&pipeline.render_pass,
	); res != .SUCCESS {
		log.fatal("Error: Failed to create render pass!\n")
		os.exit(1)
	}
}
