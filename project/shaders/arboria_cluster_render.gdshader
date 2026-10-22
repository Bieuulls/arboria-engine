shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// ARBORIA VIRTUAL GEOMETRY — CLUSTER VERTEX PULLING RENDER SHADER
// Renderizacao direta na GPU sem leitura de volta para CPU

uniform sampler2D cluster_selection_texture : filter_nearest;
uniform sampler2D vertex_data_texture : filter_nearest;
uniform sampler2D index_data_texture : filter_nearest;
uniform sampler2D cluster_meta_texture : filter_nearest;

uniform int total_active_instances = 0;
uniform bool debug_cluster_colors = true;
uniform bool unshaded_mode = false;
uniform vec3 base_albedo : source_color = vec3(0.8, 0.82, 0.85);

varying vec3 v_cluster_color;

void vertex() {
	// 1. Consulta qual cluster foi alocado neste slot pelo Compute Shader
	vec4 sel = texelFetch(cluster_selection_texture, ivec2(INSTANCE_ID % 2048, INSTANCE_ID / 2048), 0);
	uint cluster_id = uint(sel.x + 0.5);
	uint v_count = uint(sel.y + 0.5);
	uint t_count = uint(sel.z + 0.5);
	uint lod_level = uint(sel.w + 0.5);

	// 2. Se o slot nao foi preenchido pela GPU (t_count == 0) ou o vertice excede os triangulos do cluster, colapsa
	uint tri_index = uint(VERTEX_ID) / 3u;
	if (t_count == 0u || tri_index >= t_count) {
		VERTEX = vec3(0.0);
		v_cluster_color = vec3(0.0);
	} else {
		// 3. Consulta metadados do cluster (offset de vertices e triangulos)
		vec4 meta = texelFetch(cluster_meta_texture, ivec2(int(cluster_id % 2048u), int(cluster_id / 2048u)), 0);
		uint v_offset = uint(meta.x + 0.5);
		uint t_offset = uint(meta.z + 0.5);

		// 4. Consulta indice local do vertice no buffer de triangulos (decodificado de R8 UNORM [0..1] -> [0..255])
		uint tri_byte_pos = t_offset + uint(VERTEX_ID);
		float raw_byte = texelFetch(index_data_texture, ivec2(int(tri_byte_pos % 2048u), int(tri_byte_pos / 2048u)), 0).r;
		uint local_v_idx = uint(raw_byte * 255.0 + 0.5);
		uint global_v_idx = v_offset + local_v_idx;

		// 5. Consulta posicao, normal e UV da textura de geometria compactada (32 bytes = 2 pixels RGBA32F)
		ivec2 p_uv = ivec2(int((global_v_idx * 2u + 0u) % 2048u), int((global_v_idx * 2u + 0u) / 2048u));
		ivec2 n_uv = ivec2(int((global_v_idx * 2u + 1u) % 2048u), int((global_v_idx * 2u + 1u) / 2048u));

		vec4 pos_uv_x = texelFetch(vertex_data_texture, p_uv, 0);
		vec4 norm_uv_y = texelFetch(vertex_data_texture, n_uv, 0);

		VERTEX = pos_uv_x.xyz;
		NORMAL = norm_uv_y.xyz;
		UV = vec2(pos_uv_x.w, norm_uv_y.w);

		// 6. Cor distintiva de cluster para visualizacao ou shading PBR
		if (debug_cluster_colors) {
			float hue = fract(float(cluster_id) * 0.618033988749895);
			vec3 rgb = clamp(abs(fract(hue + vec3(0.0, 2.0/3.0, 1.0/3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
			v_cluster_color = mix(rgb, vec3(1.0), 0.15);
		} else {
			v_cluster_color = base_albedo;
		}
	}
}

void fragment() {
	ALBEDO = v_cluster_color;
	if (unshaded_mode) {
		EMISSION = v_cluster_color;
	} else {
		ROUGHNESS = 0.5;
		METALLIC = 0.05;
		SPECULAR = 0.5;
	}
}
