package renderer

import log "../logger"
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
		log.fatal("Error: Could not create shader module!\n")
		os.exit(1)
	}
    log.info("Shader module created.")
	return shader
}

