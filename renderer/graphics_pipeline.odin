package renderer

import log "../logger"
import "core:os"
import vk "vendor:vulkan"

graphics_pipeline_create :: proc(
	using ctx: ^Context,
	render_pass: ^RenderPass,
	viewport: vk.Viewport,
	scissor: vk.Rect2D,
	vs_name: string,
	fs_name: string,
    out_pipeline: ^Pipeline
) {
	//	vs_code := compile_shader(vs_name, .VertexShader)
	//	fs_code := compile_shader(fs_name, .FragmentShader)
	vs_code, _ := os.read_entire_file(vs_name)
	fs_code, _ := os.read_entire_file(fs_name)
	/*
		vs_code, vs_ok := os.read_entire_file(vs_path);
		fs_code, fs_ok := os.read_entire_file(fs_path);
		if !vs_ok
		{
			fmt.eprintf("Error: could not load vertex shader %q\n", vs_path);
			os.exit(1);
		}
		
		if !fs_ok
		{
			fmt.eprintf("Error: could not load fragment shader %q\n", fs_path);
			os.exit(1);
		}
	*/
	defer 
	{
		delete(vs_code)
		delete(fs_code)
	}
	vs_shader := shader_module_create(ctx, vs_code)
	fs_shader := shader_module_create(ctx, fs_code)
	defer 
	{
		vk.DestroyShaderModule(device, vs_shader, nil)
		vk.DestroyShaderModule(device, fs_shader, nil)
	}

	input_assembly: vk.PipelineInputAssemblyStateCreateInfo
	input_assembly.sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO
	input_assembly.topology = .TRIANGLE_LIST
	input_assembly.primitiveRestartEnable = false

	vertex_input: vk.PipelineVertexInputStateCreateInfo
	vertex_input.sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO
	vertex_input.vertexBindingDescriptionCount = 1
	vertex_input.pVertexBindingDescriptions = &VERTEX_BINDING
	vertex_input.vertexAttributeDescriptionCount = len(VERTEX_ATTRIBUTES)
	vertex_input.pVertexAttributeDescriptions = &VERTEX_ATTRIBUTES[0]

	rasterizer: vk.PipelineRasterizationStateCreateInfo
	rasterizer.sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO
	rasterizer.depthClampEnable = false
	rasterizer.rasterizerDiscardEnable = false
	rasterizer.polygonMode = .FILL
	rasterizer.lineWidth = 1.0
	rasterizer.cullMode = {.BACK}
	rasterizer.frontFace = .CLOCKWISE
	rasterizer.depthBiasEnable = false
	rasterizer.depthBiasConstantFactor = 0.0
	rasterizer.depthBiasClamp = 0.0
	rasterizer.depthBiasSlopeFactor = 0.0

	multisampling: vk.PipelineMultisampleStateCreateInfo
	multisampling.sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO
	multisampling.sampleShadingEnable = false
	multisampling.rasterizationSamples = {._1}
	multisampling.minSampleShading = 1.0
	multisampling.pSampleMask = nil
	multisampling.alphaToCoverageEnable = false
	multisampling.alphaToOneEnable = false

    depth_stencil: vk.PipelineDepthStencilStateCreateInfo
    depth_stencil.sType = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO
    depth_stencil.depthTestEnable = true
    depth_stencil.depthWriteEnable = true
    depth_stencil.depthCompareOp = .LESS
    depth_stencil.depthBoundsTestEnable = false
    depth_stencil.stencilTestEnable = false

	color_blend_attachment: vk.PipelineColorBlendAttachmentState
	color_blend_attachment.colorWriteMask = {.R, .G, .B, .A}
	color_blend_attachment.blendEnable = true
	color_blend_attachment.srcColorBlendFactor = .SRC_ALPHA
	color_blend_attachment.dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA
	color_blend_attachment.colorBlendOp = .ADD
	color_blend_attachment.srcAlphaBlendFactor = .SRC_ALPHA
	color_blend_attachment.dstAlphaBlendFactor = .ONE_MINUS_SRC_ALPHA
	color_blend_attachment.alphaBlendOp = .ADD

	color_blending: vk.PipelineColorBlendStateCreateInfo
	color_blending.sType = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO
	color_blending.logicOpEnable = false
	color_blending.logicOp = .COPY
	color_blending.attachmentCount = 1
	color_blending.pAttachments = &color_blend_attachment
	color_blending.blendConstants[0] = 0.0
	color_blending.blendConstants[1] = 0.0
	color_blending.blendConstants[2] = 0.0
	color_blending.blendConstants[3] = 0.0

	dynamic_states := [?]vk.DynamicState{.VIEWPORT, .SCISSOR, .LINE_WIDTH}
	dynamic_state: vk.PipelineDynamicStateCreateInfo
	dynamic_state.sType = .PIPELINE_DYNAMIC_STATE_CREATE_INFO
	dynamic_state.dynamicStateCount = len(dynamic_states)
	dynamic_state.pDynamicStates = raw_data(&dynamic_states)

    viewports := []vk.Viewport{viewport}
    scissors := []vk.Rect2D{scissor}
	viewport_state: vk.PipelineViewportStateCreateInfo
	viewport_state.sType = .PIPELINE_VIEWPORT_STATE_CREATE_INFO
	viewport_state.viewportCount = 1
    viewport_state.pViewports = raw_data(viewports)
	viewport_state.scissorCount = 1
    viewport_state.pScissors = raw_data(scissors)

// TODO: implement descriptor sets and push constants
    /*pipeline_layout_ci : vk.PipelineLayoutCreateInfo
    pipeline_layout_ci.sType = .PIPELINE_LAYOUT_CREATE_INFO
    pipeline_layout_ci.pSetLayouts = 
    pipeline_layout_ci.setLayoutCount = 
    pipeline_layout_ci.pushConstantRangeCount = 
    pipeline_layout_ci.pPushConstantRanges = */
	pipeline_layout_info: vk.PipelineLayoutCreateInfo
	pipeline_layout_info.sType = .PIPELINE_LAYOUT_CREATE_INFO
	pipeline_layout_info.setLayoutCount = 0
	pipeline_layout_info.pSetLayouts = nil
	pipeline_layout_info.pushConstantRangeCount = 0
	pipeline_layout_info.pPushConstantRanges = nil

	vs_info: vk.PipelineShaderStageCreateInfo
	vs_info.sType = .PIPELINE_SHADER_STAGE_CREATE_INFO
	vs_info.stage = {.VERTEX}
	vs_info.module = vs_shader
	vs_info.pName = "main"
	fs_info: vk.PipelineShaderStageCreateInfo
	fs_info.sType = .PIPELINE_SHADER_STAGE_CREATE_INFO
	fs_info.stage = {.FRAGMENT}
	fs_info.module = fs_shader
	fs_info.pName = "main"
	shader_stages := [?]vk.PipelineShaderStageCreateInfo{vs_info, fs_info}
	if res := vk.CreatePipelineLayout(
		device,
		&pipeline_layout_info,
		nil,
		&out_pipeline.layout,
	); res != .SUCCESS {
		log.fatal("Error: Failed to create pipeline layout!\n")
		os.exit(1)
	}
	pipeline_info: vk.GraphicsPipelineCreateInfo
	pipeline_info.sType = .GRAPHICS_PIPELINE_CREATE_INFO
	pipeline_info.stageCount = 2
	pipeline_info.pStages = &shader_stages[0]
	pipeline_info.pVertexInputState = &vertex_input
	pipeline_info.pInputAssemblyState = &input_assembly
	pipeline_info.pViewportState = &viewport_state
	pipeline_info.pRasterizationState = &rasterizer
	pipeline_info.pMultisampleState = &multisampling
	pipeline_info.pDepthStencilState = &depth_stencil
	pipeline_info.pColorBlendState = &color_blending
	pipeline_info.pDynamicState = &dynamic_state
	pipeline_info.layout = out_pipeline.layout
	pipeline_info.renderPass = render_pass.handle
	pipeline_info.subpass = 0
	pipeline_info.basePipelineHandle = vk.Pipeline{}
	pipeline_info.basePipelineIndex = -1
	if res := vk.CreateGraphicsPipelines(
		device,
		0,
		1,
		&pipeline_info,
		nil,
		&out_pipeline.handle,
	); res != .SUCCESS {
		log.fatal("Error: Failed to create graphics pipeline!\n")
		os.exit(1)
	}
}

/*compile_shader :: proc(name: string, kind: shaderc.shaderKind) -> []u8 {
	src_path := fmt.tprintf("./shaders/%s", name)
	cmp_path := fmt.tprintf("./shaders/compiled/%s.spv", name)
	src_time, src_err := os.last_write_time_by_name(src_path)
	if (src_err != os.ERROR_NONE) {
		fmt.eprintf("Failed to open shader %q\n", src_path)
		return nil
	}
	cmp_time, cmp_err := os.last_write_time_by_name(cmp_path)
	if cmp_err == os.ERROR_NONE && cmp_time >= src_time {
		code, _ := os.read_entire_file(cmp_path)
		return code
	}
	comp := shaderc.compiler_initialize()
	options := shaderc.compile_options_initialize()
	defer 
	{
		shaderc.compiler_release(comp)
		shaderc.compile_options_release(options)
	}
	shaderc.compile_options_set_optimization_level(options, .Performance)
	code, _ := os.read_entire_file(src_path)
	c_path := strings.clone_to_cstring(src_path, context.temp_allocator)
	res := shaderc.compile_into_spv(
		comp,
		cstring(raw_data(code)),
		len(code),
		kind,
		c_path,
		cstring("main"),
		options,
	)
	defer shaderc.result_release(res)
	status := shaderc.result_get_compilation_status(res)
	if status != .Success {
		fmt.printf("%s: Error: %s\n", name, shaderc.result_get_error_message(res))
		return nil
	}
	length := shaderc.result_get_length(res)
	out := make([]u8, length)
	c_out := shaderc.result_get_bytes(res)
	mem.copy(raw_data(out), c_out, int(length))
	os.write_entire_file(cmp_path, out)
	return out
}*/
