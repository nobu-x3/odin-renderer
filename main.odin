package odin_renderer

import log "logger"
import "core:os"
import "core:strings"
import "vendor:glfw"
import vk "vendor:vulkan"
import rd "renderer"


main :: proc() {
	glfw.Init()
	defer glfw.Terminate()
	ctx: rd.Context
	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.RESIZABLE, 0)
	ctx.window = glfw.CreateWindow(800, 600, "Context", nil, nil)
	defer glfw.DestroyWindow(ctx.window)
	glfw.SetWindowUserPointer(ctx.window, &ctx)
	glfw.SetFramebufferSizeCallback(ctx.window, rd.framebuffer_size_callback)
	context.user_ptr = &ctx.instance
	get_proc_address :: proc(p: rawptr, name: cstring) {
		(cast(^rawptr)p)^ = glfw.GetInstanceProcAddress(
			(^vk.Instance)(context.user_ptr)^,
			name,
		)
	}
	vk.load_proc_addresses(get_proc_address)
	create_instance(&ctx)
	defer vk.DestroyInstance(ctx.instance, nil)
	vk.load_proc_addresses(get_proc_address)
	if glfw.CreateWindowSurface(ctx.instance, ctx.window, nil, &ctx.surface) !=
	   .SUCCESS {
		log.fatal("ERROR: Failed to create gltf window surface\n")
		os.exit(1)
	}
	defer vk.DestroySurfaceKHR(ctx.instance, ctx.surface, nil)
	extensions := get_extensions()
	for ext in &extensions {
		log.info(cstring(&ext.extensionName[0]))
	}
	rd.device_create(&ctx)
	defer vk.DestroyDevice(ctx.device, nil)
	ctx.swapchain = rd.swapchain_create(&ctx)
    defer rd.swapchain_cleanup(&ctx)
    ctx.main_render_pass = rd.render_pass_create(&ctx, {0.0, 0.0, 0.0, 1.0}, {0.0, 0.0, 800.0, 600.0}, 1.0, 0)
    defer rd.render_pass_destroy(&ctx, &ctx.main_render_pass)
	ctx.pipeline = rd.graphics_pipeline_create(
		&ctx,
        &ctx.main_render_pass,
        vk.Viewport{x = 0, y = 0, width = 800, height = 600, minDepth = 0, maxDepth = 1},
        vk.Rect2D{},
		"bin/assets/shaders/shader_builtin.vert.spv",
		"bin/assets/shaders/shader_builtin.frag.spv",
	)
	defer vk.DestroyPipelineLayout(ctx.device, ctx.pipeline.layout, nil)
	defer vk.DestroyPipeline(ctx.device, ctx.pipeline.handle, nil)
	rd.recreate_framebuffers(&ctx, &ctx.swapchain, &ctx.main_render_pass)
	rd.command_pool_create(&ctx)
	defer vk.DestroyCommandPool(ctx.device, ctx.command_pool, nil)
	vertices := [?]rd.Vertex{
		{{-0.5, -0.5}, {0.0, 0.0, 1.0}},
		{{0.5, -0.5}, {1.0, 0.0, 0.0}},
		{{0.5, 0.5}, {0.0, 1.0, 0.0}},
		{{-0.5, 0.5}, {1.0, 0.0, 0.0}},
	}
	indices := [?]u16{0, 1, 2, 2, 3, 0}
	rd.vertex_buffer_create(&ctx, vertices[:])
	defer vk.DestroyBuffer(ctx.device, ctx.vertex_buffer.buffer, nil)
	defer vk.FreeMemory(ctx.device, ctx.vertex_buffer.memory, nil)
	rd.index_buffer_create(&ctx, indices[:])
	defer vk.DestroyBuffer(ctx.device, ctx.index_buffer.buffer, nil)
	defer vk.FreeMemory(ctx.device, ctx.index_buffer.memory, nil)
	rd.command_buffer_create(&ctx)
	defer rd.swapchain_cleanup(&ctx)
	create_sync_objects(&ctx)
	defer {
		for i in 0 ..< rd.MAX_FRAMES_IN_FLIGHT {
			vk.DestroySemaphore(ctx.device, ctx.image_available[i], nil)
			vk.DestroySemaphore(ctx.device, ctx.render_finished[i], nil)
			vk.DestroyFence(ctx.device, ctx.in_flight[i], nil)

		}
	}
	for (!glfw.WindowShouldClose(ctx.window)) {
		glfw.PollEvents()
		draw_frame(&ctx, vertices[:], indices[:])
	}
	vk.DeviceWaitIdle(ctx.device)
}

draw_frame :: proc(
	using ctx: ^rd.Context,
	vertices: []rd.Vertex,
	indices: []u16,
) {
	vk.WaitForFences(device, 1, &in_flight[curr_frame], true, max(u64))
	image_index: u32
	res := vk.AcquireNextImageKHR(
		device,
		swapchain.handle,
		max(u64),
		image_available[curr_frame],
		{},
		&image_index,
	)
	if res == .ERROR_OUT_OF_DATE_KHR ||
	   res == .SUBOPTIMAL_KHR ||
	   framebuffer_resized {
		framebuffer_resized = false
		rd.swapchain_recreate(ctx)
		return
	} else if res != .SUCCESS {
		log.fatal("Error: Failed tp acquire swap chain image!\n")
		os.exit(1)
	}
	vk.ResetFences(device, 1, &in_flight[curr_frame])
	vk.ResetCommandBuffer(command_buffers[curr_frame], {})
	record_command_buffer(ctx, command_buffers[curr_frame], image_index)
	submit_info: vk.SubmitInfo
	submit_info.sType = .SUBMIT_INFO
	wait_semaphores := [?]vk.Semaphore{image_available[curr_frame]}
	wait_stages := [?]vk.PipelineStageFlags{{.COLOR_ATTACHMENT_OUTPUT}}
	submit_info.waitSemaphoreCount = 1
	submit_info.pWaitSemaphores = &wait_semaphores[0]
	submit_info.pWaitDstStageMask = &wait_stages[0]
	submit_info.commandBufferCount = 1
	submit_info.pCommandBuffers = &command_buffers[curr_frame]
	signal_semaphores := [?]vk.Semaphore{render_finished[curr_frame]}
	submit_info.signalSemaphoreCount = 1
	submit_info.pSignalSemaphores = &signal_semaphores[0]
	if res := vk.QueueSubmit(
		queues[.Graphics],
		1,
		&submit_info,
		in_flight[curr_frame],
	); res != .SUCCESS {
		log.fatal("Error: Failed to submit draw command buffer!\n")
		os.exit(1)
	}
	present_info: vk.PresentInfoKHR
	present_info.sType = .PRESENT_INFO_KHR
	present_info.waitSemaphoreCount = 1
	present_info.pWaitSemaphores = &signal_semaphores[0]
	swapchains := [?]vk.SwapchainKHR{swapchain.handle}
	present_info.swapchainCount = 1
	present_info.pSwapchains = &swapchains[0]
	present_info.pImageIndices = &image_index
	present_info.pResults = nil
	vk.QueuePresentKHR(queues[.Present], &present_info)
	curr_frame = (curr_frame + 1) % rd.MAX_FRAMES_IN_FLIGHT
}

record_command_buffer :: proc(
	using ctx: ^rd.Context,
	buffer: vk.CommandBuffer,
	image_index: u32,
) {
	begin_info: vk.CommandBufferBeginInfo
	begin_info.sType = .COMMAND_BUFFER_BEGIN_INFO
	begin_info.flags = {}
	begin_info.pInheritanceInfo = nil
	if res := vk.BeginCommandBuffer(buffer, &begin_info); res != .SUCCESS {
		log.fatal("Error: Failed to begin recording command buffer!\n")
		os.exit(1)
	}
	vk.CmdBindPipeline(buffer, .GRAPHICS, pipeline.handle)
	vertex_buffers := [?]vk.Buffer{vertex_buffer.buffer}
	offsets := [?]vk.DeviceSize{0}
	vk.CmdBindVertexBuffers(buffer, 0, 1, &vertex_buffers[0], &offsets[0])
	vk.CmdBindIndexBuffer(buffer, index_buffer.buffer, 0, .UINT16)
	viewport: vk.Viewport
	viewport.x = 0.0
	viewport.y = 0.0
	viewport.width = f32(swapchain.extent.width)
	viewport.height = f32(swapchain.extent.height)
	viewport.minDepth = 0.0
	viewport.maxDepth = 1.0
	vk.CmdSetViewport(buffer, 0, 1, &viewport)
	scissor: vk.Rect2D
	scissor.offset = {0, 0}
	scissor.extent = swapchain.extent
	vk.CmdSetScissor(buffer, 0, 1, &scissor)
	vk.CmdDrawIndexed(buffer, cast(u32)index_buffer.length, 1, 0, 0, 0)
	vk.CmdEndRenderPass(buffer)
    rd.render_pass_begin(&main_render_pass, buffer, swapchain.framebuffers[curr_frame].handle)
	if res := vk.EndCommandBuffer(buffer); res != .SUCCESS {
		log.fatal("Error: Failed to record command buffer!\n")
		os.exit(1)
	}
}

create_instance :: proc(ctx: ^rd.Context) {
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
		outer: for name in rd.VALIDATION_LAYERS {
			for layer in &layers {
				if name == cstring(&layer.layerName[0]) do continue outer
			}
			log.fatal("ERROR: validation layer %q not available\n", name)
			os.exit(1)
		}
		create_info.ppEnabledLayerNames = &rd.VALIDATION_LAYERS[0]
		create_info.enabledLayerCount = len(rd.VALIDATION_LAYERS)
		log.info("Validation Layers Loaded")
	} else {
		create_info.enabledLayerCount = 0
	}
	if (vk.CreateInstance(&create_info, nil, &ctx.instance) != .SUCCESS) {
		log.error("ERROR: Failed to create instance\n")
		return
	}
	log.info("Instance Created")
}

create_sync_objects :: proc(using ctx: ^rd.Context) {
	semaphore_info: vk.SemaphoreCreateInfo
	semaphore_info.sType = .SEMAPHORE_CREATE_INFO
	fence_info: vk.FenceCreateInfo
	fence_info.sType = .FENCE_CREATE_INFO
	fence_info.flags = {.SIGNALED}
	for i in 0 ..< rd.MAX_FRAMES_IN_FLIGHT {
		res := vk.CreateSemaphore(
			device,
			&semaphore_info,
			nil,
			&image_available[i],
		)
		if res != .SUCCESS {
			log.fatal(
				"Error: Failed to create \"image_available\" semaphore\n",
			)
			os.exit(1)
		}
		res = vk.CreateSemaphore(
			device,
			&semaphore_info,
			nil,
			&render_finished[i],
		)
		if res != .SUCCESS {
			log.fatal(
				"Error: Failed to create \"render_finished\" semaphore\n",
			)
			os.exit(1)
		}
		res = vk.CreateFence(device, &fence_info, nil, &in_flight[i])
		if res != .SUCCESS {
			log.fatal("Error: Failed to create \"in_flight\" fence\n")
			os.exit(1)
		}
	}
}

get_extensions :: proc() -> []vk.ExtensionProperties {
	n_ext: u32
	vk.EnumerateInstanceExtensionProperties(nil, &n_ext, nil)
	extensions := make([]vk.ExtensionProperties, n_ext)
	vk.EnumerateInstanceExtensionProperties(nil, &n_ext, raw_data(extensions))
	return extensions
}
