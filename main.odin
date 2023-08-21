package renderer

import "core:fmt"
import "core:os"
import "core:mem"
import "core:strings"
import "vendor:glfw"
import vk "vendor:vulkan"

MAX_FRAMES_IN_FLIGHT :: 2

Renderer :: struct {
	window:              glfw.WindowHandle,
	instance:            vk.Instance,
	device:              vk.Device,
	surface:             vk.SurfaceKHR,
	physical_device:     vk.PhysicalDevice,
	queue_indices:       [QueueFamily]int,
	queues:              [QueueFamily]vk.Queue,
	swapchain:           Swapchain,
	pipeline:            Pipeline,
	command_pool:        vk.CommandPool,
	command_buffers:     [MAX_FRAMES_IN_FLIGHT]vk.CommandBuffer,
	vertex_buffer:       Buffer,
	index_buffer:        Buffer,
	image_available:     [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
	render_finished:     [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
	in_flight:           [MAX_FRAMES_IN_FLIGHT]vk.Fence,
	curr_frame:          u32,
	framebuffer_resized: bool,
}

Vertex :: struct {
	pos:   [2]f32,
	color: [3]f32,
}

QueueFamily :: enum {
	Graphics,
	Present,
}

DEVICE_EXTENSIONS := [?]cstring{"VK_KHR_swapchain"}
VALIDATION_LAYERS := [?]cstring{"VK_LAYER_KHRONOS_validation"}

VERTEX_BINDING := vk.VertexInputBindingDescription {
	binding   = 0,
	stride    = size_of(Vertex),
	inputRate = .VERTEX,
}

VERTEX_ATTRIBUTES := [?]vk.VertexInputAttributeDescription{
	{
		binding = 0,
		location = 0,
		format = .R32G32_SFLOAT,
		offset = cast(u32)offset_of(Vertex, pos),
	},
	{
		binding = 0,
		location = 1,
		format = .R32G32B32_SFLOAT,
		offset = cast(u32)offset_of(Vertex, color),
	},
}


main :: proc() {
	glfw.Init()
	defer glfw.Terminate()
	renderer: Renderer
	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.RESIZABLE, 0)
	renderer.window = glfw.CreateWindow(800, 600, "Renderer", nil, nil)
	defer glfw.DestroyWindow(renderer.window)
	glfw.SetWindowUserPointer(renderer.window, &renderer)
	glfw.SetFramebufferSizeCallback(renderer.window, framebuffer_size_callback)
	context.user_ptr = &renderer.instance
	get_proc_address :: proc(p: rawptr, name: cstring) {
		(cast(^rawptr)p)^ = glfw.GetInstanceProcAddress(
			(^vk.Instance)(context.user_ptr)^,
			name,
		)
	}
	vk.load_proc_addresses(get_proc_address)
	create_instance(&renderer)
	defer vk.DestroyInstance(renderer.instance, nil)
	vk.load_proc_addresses(get_proc_address)
	if glfw.CreateWindowSurface(
		   renderer.instance,
		   renderer.window,
		   nil,
		   &renderer.surface,
	   ) !=
	   .SUCCESS {
		fmt.eprintf("ERROR: Failed to create gltf window surface\n")
		os.exit(1)
	}
	defer vk.DestroySurfaceKHR(renderer.instance, renderer.surface, nil)
	extensions := get_extensions()
	for ext in &extensions {
		fmt.println(cstring(&ext.extensionName[0]))
	}
	device_get_suitable_device(&renderer)
	find_queue_families(&renderer)
	fmt.println("Queue Indices:")
	for q, f in renderer.queue_indices do fmt.printf("  %v: %d\n", f, q)
	device_create(&renderer)
	defer vk.DestroyDevice(renderer.device, nil)
	for q, f in &renderer.queues {
		vk.GetDeviceQueue(
			renderer.device,
			u32(renderer.queue_indices[f]),
			0,
			&q,
		)
	}
	swapchain_create(&renderer)
	create_image_views(&renderer)
	graphics_pipeline_create(
		&renderer,
		"bin/assets/shaders/shader_builtin.vert.spv",
		"bin/assets/shaders/shader_builtin.frag.spv",
	)
	defer vk.DestroyRenderPass(
		renderer.device,
		renderer.pipeline.render_pass,
		nil,
	)
	defer vk.DestroyPipelineLayout(
		renderer.device,
		renderer.pipeline.layout,
		nil,
	)
	defer vk.DestroyPipeline(renderer.device, renderer.pipeline.handle, nil)
	create_framebuffers(&renderer)
	command_pool_create(&renderer)
	defer vk.DestroyCommandPool(renderer.device, renderer.command_pool, nil)
	vertices := [?]Vertex{
		{{-0.5, -0.5}, {0.0, 0.0, 1.0}},
		{{0.5, -0.5}, {1.0, 0.0, 0.0}},
		{{0.5, 0.5}, {0.0, 1.0, 0.0}},
		{{-0.5, 0.5}, {1.0, 0.0, 0.0}},
	}
	indices := [?]u16{0, 1, 2, 2, 3, 0}
	vertex_buffer_create(&renderer, vertices[:])
	defer vk.DestroyBuffer(renderer.device, renderer.vertex_buffer.buffer, nil)
	defer vk.FreeMemory(renderer.device, renderer.vertex_buffer.memory, nil)
	index_buffer_create(&renderer, indices[:])
	defer vk.DestroyBuffer(renderer.device, renderer.index_buffer.buffer, nil)
	defer vk.FreeMemory(renderer.device, renderer.index_buffer.memory, nil)
	command_buffers_create(&renderer)
	defer swapchain_cleanup(&renderer)
	create_sync_objects(&renderer)
	for (!glfw.WindowShouldClose(renderer.window)) {
		glfw.PollEvents()
		draw_frame(&renderer, vertices[:], indices[:])
		glfw.SwapBuffers(renderer.window)
	}
	vk.DeviceWaitIdle(renderer.device)
}

draw_frame :: proc(
	using renderer: ^Renderer,
	vertices: []Vertex,
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
		swapchain_recreate(renderer)
		return
	} else if res != .SUCCESS {
		fmt.eprintf("Error: Failed tp acquire swap chain image!\n")
		os.exit(1)
	}
	vk.ResetFences(device, 1, &in_flight[curr_frame])
	vk.ResetCommandBuffer(command_buffers[curr_frame], {})
	record_command_buffer(renderer, command_buffers[curr_frame], image_index)
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
		fmt.eprintf("Error: Failed to submit draw command buffer!\n")
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
	curr_frame = (curr_frame + 1) % MAX_FRAMES_IN_FLIGHT
}

record_command_buffer :: proc(
	using renderer: ^Renderer,
	buffer: vk.CommandBuffer,
	image_index: u32,
) {
	begin_info: vk.CommandBufferBeginInfo
	begin_info.sType = .COMMAND_BUFFER_BEGIN_INFO
	begin_info.flags = {}
	begin_info.pInheritanceInfo = nil
	if res := vk.BeginCommandBuffer(buffer, &begin_info); res != .SUCCESS {
		fmt.eprintf("Error: Failed to begin recording command buffer!\n")
		os.exit(1)
	}
	render_pass_info: vk.RenderPassBeginInfo
	render_pass_info.sType = .RENDER_PASS_BEGIN_INFO
	render_pass_info.renderPass = pipeline.render_pass
	render_pass_info.framebuffer = swapchain.framebuffers[image_index]
	render_pass_info.renderArea.offset = {0, 0}
	render_pass_info.renderArea.extent = swapchain.extent
	clear_color: vk.ClearValue
	clear_color.color.float32 = [4]f32{0.0, 0.0, 0.0, 1.0}
	render_pass_info.clearValueCount = 1
	render_pass_info.pClearValues = &clear_color
	vk.CmdBeginRenderPass(buffer, &render_pass_info, .INLINE)
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
	if res := vk.EndCommandBuffer(buffer); res != .SUCCESS {
		fmt.eprintf("Error: Failed to record command buffer!\n")
		os.exit(1)
	}
}

create_instance :: proc(renderer: ^Renderer) {
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
		outer: for name in VALIDATION_LAYERS {
			for layer in &layers {
				if name == cstring(&layer.layerName[0]) do continue outer
			}
			fmt.eprintf("ERROR: validation layer %q not available\n", name)
			os.exit(1)
		}
		create_info.ppEnabledLayerNames = &VALIDATION_LAYERS[0]
		create_info.enabledLayerCount = len(VALIDATION_LAYERS)
		fmt.println("Validation Layers Loaded")
	} else {
		create_info.enabledLayerCount = 0
	}
	if (vk.CreateInstance(&create_info, nil, &renderer.instance) != .SUCCESS) {
		fmt.eprintf("ERROR: Failed to create instance\n")
		return
	}
	fmt.println("Instance Created")
}

create_sync_objects :: proc(using renderer: ^Renderer) {
	semaphore_info: vk.SemaphoreCreateInfo
	semaphore_info.sType = .SEMAPHORE_CREATE_INFO
	fence_info: vk.FenceCreateInfo
	fence_info.sType = .FENCE_CREATE_INFO
	fence_info.flags = {.SIGNALED}
	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		res := vk.CreateSemaphore(
			device,
			&semaphore_info,
			nil,
			&image_available[i],
		)
		if res != .SUCCESS {
			fmt.eprintf(
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
			fmt.eprintf(
				"Error: Failed to create \"render_finished\" semaphore\n",
			)
			os.exit(1)
		}
		res = vk.CreateFence(device, &fence_info, nil, &in_flight[i])
		if res != .SUCCESS {
			fmt.eprintf("Error: Failed to create \"in_flight\" fence\n")
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

choose_surface_format :: proc(
	using renderer: ^Renderer,
) -> vk.SurfaceFormatKHR {
	for v in swapchain.support.formats {
		if v.format == .B8G8R8A8_SRGB && v.colorSpace == .SRGB_NONLINEAR do return v
	}
	return swapchain.support.formats[0]
}

