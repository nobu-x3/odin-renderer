package renderer
import "core:mem"
import "core:fmt"
import "core:os"
import vk "vendor:vulkan"
import "vendor:glfw"

MAX_FRAMES_IN_FLIGHT :: 2
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

Vertex :: struct {
	pos:   [2]f32,
	color: [3]f32,
}

QueueFamily :: enum {
	Graphics,
	Present,
}

Color :: struct {
	r, g, b, a: f32,
}

Extent2D :: struct {
	x, y, w, h: f32,
}

Context :: struct {
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
	main_render_pass:    RenderPass,
	command_buffers:     [MAX_FRAMES_IN_FLIGHT]vk.CommandBuffer,
	vertex_buffer:       Buffer,
	index_buffer:        Buffer,
	image_available:     [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
	render_finished:     [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
	in_flight:           [MAX_FRAMES_IN_FLIGHT]vk.Fence,
	curr_frame:          u32,
	image_index:         u32,
	framebuffer_resized: bool,
}

Buffer :: struct {
	buffer: vk.Buffer,
	memory: vk.DeviceMemory,
	length: int,
	size:   vk.DeviceSize,
}

Pipeline :: struct {
	handle: vk.Pipeline,
	layout: vk.PipelineLayout,
}

Swapchain :: struct {
	handle:               vk.SwapchainKHR,
	images:               []vk.Image,
	image_views:          []vk.ImageView,
	depth_attachment:     Image,
	format:               vk.SurfaceFormatKHR,
	depth_format:         vk.Format,
	extent:               vk.Extent2D,
	present_mode:         vk.PresentModeKHR,
	image_count:          u32,
	support:              SwapchainDescription,
	framebuffers:         []Framebuffer,
	max_frames_in_flight: u32,
}

RenderPass :: struct {
	handle:  vk.RenderPass,
	depth:   f32,
	color:   Color,
	extent:  Extent2D,
	stencil: u32,
}

Framebuffer :: struct {
	handle:      vk.Framebuffer,
	attachments: []vk.ImageView,
	render_pass: ^RenderPass,
}

SwapchainDescription :: struct {
	capabilities:  vk.SurfaceCapabilitiesKHR,
	formats:       []vk.SurfaceFormatKHR,
	present_modes: []vk.PresentModeKHR,
	depth_format:  vk.Format,
}

ImageInfo :: struct {
	image_type:        vk.ImageType,
	width, height:     u32,
	format:            vk.Format,
	tiling:            vk.ImageTiling,
	usage_flags:       vk.ImageUsageFlags,
	memory_flags:      vk.MemoryPropertyFlags,
	view_aspect_flags: vk.ImageAspectFlags,
	create_view:       bool,
}

Image :: struct {
	handle:        vk.Image,
	memory:        vk.DeviceMemory,
	view:          vk.ImageView,
	width, height: u32,
}

TextureData :: struct {
	image:   Image,
	sampler: vk.Sampler,
}
