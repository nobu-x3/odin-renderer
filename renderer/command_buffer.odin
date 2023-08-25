package renderer
import log "../logger"
import "core:os"
import vk "vendor:vulkan"

command_pool_create :: proc(using ctx: ^Context) {
	pool_info: vk.CommandPoolCreateInfo
	pool_info.sType = .COMMAND_POOL_CREATE_INFO
	pool_info.flags = {.RESET_COMMAND_BUFFER}
	pool_info.queueFamilyIndex = u32(queue_indices[.Graphics])
	if res := vk.CreateCommandPool(device, &pool_info, nil, &command_pool);
	   res != .SUCCESS {
		log.fatal("Error: Failed to create command pool!\n")
		os.exit(1)
	}
}

command_buffer_create :: proc(
	ctx: ^Context,
	command_pool: vk.CommandPool,
	out_buffer: ^vk.CommandBuffer,
) {
	alloc_info: vk.CommandBufferAllocateInfo
	alloc_info.sType = .COMMAND_BUFFER_ALLOCATE_INFO
	alloc_info.commandPool = command_pool
	alloc_info.level = .PRIMARY
	alloc_info.commandBufferCount = 1
	if res := vk.AllocateCommandBuffers(ctx.device, &alloc_info, out_buffer);
	   res != .SUCCESS {
		log.fatal("Error: Failed to allocate command buffers!\n")
		os.exit(1)
	}
}

command_buffer_destroy :: proc(
	ctx: ^Context,
	command_pool: vk.CommandPool,
	buffer: ^vk.CommandBuffer,
) {
	vk.FreeCommandBuffers(ctx.device, command_pool, 1, buffer)
}

RenderPassBeginInfo :: struct {
	single_use:           bool,
	render_pass_continue: bool,
	simultaneous_use:     bool,
}

command_buffer_begin :: proc(
	command_buffer: vk.CommandBuffer,
	begin_info: RenderPassBeginInfo,
) {
	ci: vk.CommandBufferBeginInfo
	ci.sType = .COMMAND_BUFFER_BEGIN_INFO
	ci.flags = {}
	if (begin_info.single_use) {
		ci.flags += {.ONE_TIME_SUBMIT}
	}
	if (begin_info.simultaneous_use) {
		ci.flags += {.SIMULTANEOUS_USE}
	}
	if (begin_info.render_pass_continue) {
		ci.flags += {.RENDER_PASS_CONTINUE}
	}
	if res := vk.BeginCommandBuffer(command_buffer, &ci); res != .SUCCESS {
		log.fatal("Failed to begin command buffer.")
		os.exit(1)
	}
    log.info("start")
}

command_buffer_end :: proc(command_buffer: vk.CommandBuffer) {
	if res := vk.EndCommandBuffer(command_buffer); res != .SUCCESS {
		log.fatal("Failed to end command buffer.")
		os.exit(1)
	}
}
