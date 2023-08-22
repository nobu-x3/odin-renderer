package renderer

import "core:mem"
import log "../logger"
import "core:os"
import vk "vendor:vulkan"

vertex_buffer_create :: proc(using ctx: ^Context, vertices: []Vertex) {
	vertex_buffer.length = len(vertices)
	vertex_buffer.size = cast(vk.DeviceSize)(len(vertices) * size_of(Vertex))
	staging: Buffer
	buffer_create(
		ctx,
		size_of(Vertex),
		len(vertices),
		{.TRANSFER_SRC},
		{.HOST_VISIBLE, .HOST_COHERENT},
		&staging,
	)
	data: rawptr
	vk.MapMemory(device, staging.memory, 0, vertex_buffer.size, {}, &data)
	mem.copy(data, raw_data(vertices), cast(int)vertex_buffer.size)
	vk.UnmapMemory(device, staging.memory)
	buffer_create(
		ctx,
		size_of(Vertex),
		len(vertices),
		{.VERTEX_BUFFER, .TRANSFER_DST},
		{.DEVICE_LOCAL},
		&vertex_buffer,
	)
	buffer_copy(ctx, staging, vertex_buffer, vertex_buffer.size)
	vk.FreeMemory(device, staging.memory, nil)
	vk.DestroyBuffer(device, staging.buffer, nil)
}

index_buffer_create :: proc(using ctx: ^Context, indices: []u16) {
	index_buffer.length = len(indices)
	index_buffer.size = cast(vk.DeviceSize)(len(indices) * size_of(indices[0]))
	staging: Buffer
	buffer_create(
		ctx,
		size_of(indices[0]),
		len(indices),
		{.TRANSFER_SRC},
		{.HOST_VISIBLE, .HOST_COHERENT},
		&staging,
	)
	data: rawptr
	vk.MapMemory(device, staging.memory, 0, index_buffer.size, {}, &data)
	mem.copy(data, raw_data(indices), cast(int)index_buffer.size)
	vk.UnmapMemory(device, staging.memory)
	buffer_create(
		ctx,
		size_of(Vertex),
		len(indices),
		{.INDEX_BUFFER, .TRANSFER_DST},
		{.DEVICE_LOCAL},
		&index_buffer,
	)
	buffer_copy(ctx, staging, index_buffer, index_buffer.size)
	vk.FreeMemory(device, staging.memory, nil)
	vk.DestroyBuffer(device, staging.buffer, nil)
}

buffer_copy :: proc(
	using ctx: ^Context,
	src, dst: Buffer,
	size: vk.DeviceSize,
) {
	alloc_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		level              = .PRIMARY,
		commandPool        = command_pool,
		commandBufferCount = 1,
	}
	cmd_buffer: vk.CommandBuffer
	vk.AllocateCommandBuffers(device, &alloc_info, &cmd_buffer)
	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}
	vk.BeginCommandBuffer(cmd_buffer, &begin_info)
	copy_region := vk.BufferCopy {
		srcOffset = 0,
		dstOffset = 0,
		size      = size,
	}
	vk.CmdCopyBuffer(cmd_buffer, src.buffer, dst.buffer, 1, &copy_region)
	vk.EndCommandBuffer(cmd_buffer)
	submit_info := vk.SubmitInfo {
		sType              = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers    = &cmd_buffer,
	}
	vk.QueueSubmit(queues[.Graphics], 1, &submit_info, {})
	vk.QueueWaitIdle(queues[.Graphics])
	vk.FreeCommandBuffers(device, command_pool, 1, &cmd_buffer)
}

buffer_create :: proc(
	using ctx: ^Context,
	member_size: int,
	count: int,
	usage: vk.BufferUsageFlags,
	properties: vk.MemoryPropertyFlags,
	buffer: ^Buffer,
) {
	buffer_info := vk.BufferCreateInfo {
		sType       = .BUFFER_CREATE_INFO,
		size        = cast(vk.DeviceSize)(member_size * count),
		usage       = usage,
		sharingMode = .EXCLUSIVE,
	}
	if res := vk.CreateBuffer(device, &buffer_info, nil, &buffer.buffer);
	   res != .SUCCESS {
		log.fatal("Error: failed to create buffer\n")
		os.exit(1)
	}
	mem_requirements: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(device, buffer.buffer, &mem_requirements)
	alloc_info := vk.MemoryAllocateInfo {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = mem_requirements.size,
		memoryTypeIndex = device_find_memory_type(
			ctx,
			mem_requirements.memoryTypeBits,
			{.HOST_VISIBLE, .HOST_COHERENT},
		),
	}
	if res := vk.AllocateMemory(device, &alloc_info, nil, &buffer.memory);
	   res != .SUCCESS {
		log.fatal("Error: Failed to allocate buffer memory!\n")
		os.exit(1)
	}
	vk.BindBufferMemory(device, buffer.buffer, buffer.memory, 0)
}
