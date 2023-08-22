package renderer

import "core:mem"
import "core:fmt"
import "core:os"
import vk "vendor:vulkan"

shader_module_create :: proc(
	using ctx: ^Context,
	code: []u8,
) -> vk.ShaderModule {
	create_info: vk.ShaderModuleCreateInfo
	create_info.sType = .SHADER_MODULE_CREATE_INFO
	create_info.codeSize = len(code)
	create_info.pCode = cast(^u32)raw_data(code)
	shader: vk.ShaderModule
	if res := vk.CreateShaderModule(device, &create_info, nil, &shader);
	   res != .SUCCESS {
		fmt.eprintf("Error: Could not create shader module!\n")
		os.exit(1)
	}
	return shader
}

