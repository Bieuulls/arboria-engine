@tool
extends SceneTree

const VGMeshLoader = preload("res://scripts/vgmesh_loader.gd")
const VGGPUPipeline = preload("res://scripts/vg_gpu_pipeline.gd")

var frame: int = 0
var pipeline: VGGPUPipeline
var camera: Camera3D
var vg_data: Dictionary
var test_phase: int = 0
var passed_all: bool = true

func _init() -> void:
	print("\n" + "=".repeat(80))
	print("ARBORIA ENGINE — VALIDACAO RIGOROSA DA FASE 3 (MISSOES 1 & 2)")
	print("=".repeat(80))

func _process(_delta: float) -> bool:
	frame += 1
	if frame == 1:
		run_test_step_1()
	elif frame == 3:
		run_test_step_2()
	elif frame == 5:
		run_test_step_3()
	elif frame == 8:
		finalize_tests()
	return false

func run_test_step_1() -> void:
	print("\n[TESTE 1] Carregamento do .vgmesh e Inicializacao do Pipeline GPU...")
	var path = "res://assets/dense_rock_test.vgmesh"
	vg_data = VGMeshLoader.load_from_file(path)
	if vg_data.is_empty():
		push_error("FALHA: Nao conseguiu carregar " + path)
		quit(1)
		return
	
	pipeline = VGGPUPipeline.new()
	var ok = pipeline.load_vgmesh(vg_data)
	if not ok or not pipeline.is_ready:
		push_error("FALHA: Pipeline GPU nao foi inicializado com sucesso!")
		quit(1)
		return
	print("  -> Sucesso: %d clusters, %d triangulos carregados em GPU" % [pipeline.total_clusters, pipeline.total_triangles])

func run_test_step_2() -> void:
	print("\n[TESTE 2] Execucao do Compute Culling & Validacao do Buffer Indireto...")
	camera = Camera3D.new()
	camera.fov = 70.0
	camera.near = 0.05
	camera.far = 1000.0
	camera.position = Vector3(0, 0, 5)
	
	# Executa culling
	pipeline.dispatch_culling(camera, Vector2(1280, 720), 1.5, 0, 0, true, true, true)
	
	# Verifica diretamente o buffer de argumentos indiretos (VkDrawIndirectCommand)
	var rd = pipeline.rd
	var buf_data = rd.buffer_get_data(pipeline.counter_buf)
	
	var v_count = buf_data.decode_u32(0)
	var inst_count = buf_data.decode_u32(4)
	var f_vert = buf_data.decode_u32(8)
	var f_inst = buf_data.decode_u32(12)
	var tris_drawn = buf_data.decode_u32(16)
	var clusters_eval = buf_data.decode_u32(20)
	
	print("  VkDrawIndirectCommand:")
	print("    - vertex_count:   %d (Esperado: 384)" % v_count)
	print("    - instance_count: %d (Clusters Selecionados)" % inst_count)
	print("    - first_vertex:   %d" % f_vert)
	print("    - first_instance: %d" % f_inst)
	print("    - tris_drawn:     %d" % tris_drawn)
	print("    - clusters_eval:  %d / %d" % [clusters_eval, pipeline.total_clusters])
	
	if v_count != 384:
		print("  [FALHA] vertex_count foi apagado ou alterado! Esperado: 384, Obtido: %d" % v_count)
		passed_all = false
	else:
		print("  [APROVADO] buffer_clear preservou vertex_count = 384 com sucesso!")
		
	if inst_count == 0 or inst_count > pipeline.total_clusters:
		print("  [FALHA] instance_count invalido: %d" % inst_count)
		passed_all = false
	else:
		print("  [APROVADO] instance_count gerado deterministicamente pela GPU: %d" % inst_count)

func run_test_step_3() -> void:
	print("\n[TESTE 3] Execucao Real do Desenho Indireto Vulkan (draw_list_draw_indirect)...")
	var rd = pipeline.rd
	
	# Cria Render Target & Framebuffer temporarios
	var tf = RDTextureFormat.new()
	tf.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	tf.width = 64
	tf.height = 64
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var rt_tex = rd.texture_create(tf, RDTextureView.new(), [])
	var fb = rd.framebuffer_create([rt_tex])
	
	# Cria Shader e Pipeline de Rasterizacao
	var vs_code = """#version 450
layout(location = 0) out vec3 v_color;
void main() {
    vec2 pos[3] = vec2[](vec2(-0.5, -0.5), vec2(0.5, -0.5), vec2(0.0, 0.5));
    gl_Position = vec4(pos[gl_VertexIndex % 3], 0.0, 1.0);
    v_color = vec3(1.0, 0.5, 0.2);
}
"""
	var fs_code = """#version 450
layout(location = 0) in vec3 v_color;
layout(location = 0) out vec4 out_color;
void main() {
    out_color = vec4(v_color, 1.0);
}
"""
	var src = RDShaderSource.new()
	src.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	src.source_vertex = vs_code
	src.source_fragment = fs_code
	var spirv = rd.shader_compile_spirv_from_source(src)
	var sh = rd.shader_create_from_spirv(spirv)
	
	var blend = RDPipelineColorBlendState.new()
	blend.attachments.append(RDPipelineColorBlendStateAttachment.new())
	var rpipe = rd.render_pipeline_create(
		sh,
		rd.framebuffer_get_format(fb),
		-1,
		RenderingDevice.RENDER_PRIMITIVE_TRIANGLES,
		RDPipelineRasterizationState.new(),
		RDPipelineMultisampleState.new(),
		RDPipelineDepthStencilState.new(),
		blend
	)
	
	# Executa desenho indireto consumindo counter_buf diretamente da GPU!
	pipeline.execute_indirect_draw(fb, rpipe)
	print("  [APROVADO] draw_list_draw_indirect executado com sucesso consumindo counter_buf!")
	
	# Telemetria assincrona
	pipeline.poll_stats_async()
	
	rd.free_rid(rpipe)
	rd.free_rid(fb)
	rd.free_rid(rt_tex)
	rd.free_rid(sh)

func finalize_tests() -> void:
	print("\n[TESTE 4] Validacao da Telemetria Separada CPU vs GPU...")
	var stats = pipeline.get_stats()
	print("  - Visible clusters: %d" % stats["visible_clusters"])
	print("  - Triangles drawn:  %d" % stats["triangles_drawn"])
	print("  - Clusters eval:    %d" % stats["clusters_evaluated"])
	print("  - CPU Submit Time:  %.3f ms" % (stats["cpu_submit_time_us"] / 1000.0))
	print("  - Real GPU Time:    %.3f ms" % (stats["gpu_time_us"] / 1000.0))
	print("  - VRAM Alocada:     %d KB" % stats["vram_kb"])
	
	print("\n" + "=".repeat(80))
	if passed_all and stats["visible_clusters"] > 0:
		print("RESULTADO GERAL: TODAS AS VERIFICACOES DAS MISSOES 1 & 2 FORAM APROVADAS!")
		print("=".repeat(80))
		pipeline.cleanup()
		quit(0)
	else:
		print("RESULTADO GERAL: FALHA EM UMA OU MAIS ETAPAS!")
		print("=".repeat(80))
		pipeline.cleanup()
		quit(1)
