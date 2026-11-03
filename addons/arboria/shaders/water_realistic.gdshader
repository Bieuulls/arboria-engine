shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 shallow_color : source_color = vec4(0.18, 0.72, 0.86, 0.82);
uniform vec4 deep_color : source_color = vec4(0.06, 0.28, 0.52, 0.95);
uniform float depth_distance : hint_range(0.1, 50.0) = 3.5;

uniform vec4 foam_color : source_color = vec4(0.96, 0.98, 1.0, 1.0);
uniform float foam_distance : hint_range(0.01, 10.0) = 0.85;
uniform float foam_speed : hint_range(0.0, 10.0) = 1.2;
uniform float foam_intensity : hint_range(0.0, 5.0) = 1.8;

uniform vec2 wave_speed_1 = vec2(0.03, 0.02);
uniform vec2 wave_speed_2 = vec2(-0.025, 0.035);
uniform float wave_scale_1 : hint_range(0.001, 2.0) = 0.08;
uniform float wave_scale_2 : hint_range(0.001, 2.0) = 0.16;

uniform float normal_strength : hint_range(0.0, 5.0) = 1.2;
uniform float roughness : hint_range(0.0, 1.0) = 0.04;
uniform float metallic : hint_range(0.0, 1.0) = 0.1;
uniform float refraction_strength : hint_range(0.0, 0.5) = 0.035;

uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

void vertex() {
	vec2 uv_w1 = UV * wave_scale_1 + wave_speed_1 * TIME;
	vec2 uv_w2 = UV * wave_scale_2 + wave_speed_2 * TIME;
	float wave_height = (sin(uv_w1.x * 20.0 + uv_w1.y * 15.0) + cos(uv_w2.x * 15.0 + uv_w2.y * 25.0)) * 0.08;
	VERTEX.y += wave_height;
}

void fragment() {
	vec2 uv1 = UV * wave_scale_1 + wave_speed_1 * TIME;
	vec2 uv2 = UV * wave_scale_2 + wave_speed_2 * TIME;

	// Normal wave simulation
	vec3 n1 = vec3(cos(uv1.x * 25.0 + uv1.y * 20.0), sin(uv1.x * 20.0 - uv1.y * 25.0), 1.0);
	vec3 n2 = vec3(sin(uv2.x * 30.0 - uv2.y * 18.0), cos(uv2.x * 18.0 + uv2.y * 30.0), 1.0);
	vec3 wave_normal = normalize(n1 + n2);
	NORMAL = mix(NORMAL, wave_normal, clamp(normal_strength * 0.1, 0.0, 1.0));

	// Scene depth calculation
	float depth_raw = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
	vec4 view_pos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_pos.xyz /= view_pos.w;
	float linear_depth = -view_pos.z;
	float water_depth = max(0.0, linear_depth + VERTEX.z);

	// Water absorption gradient
	float depth_factor = clamp(water_depth / max(depth_distance, 0.001), 0.0, 1.0);
	vec4 water_col = mix(shallow_color, deep_color, depth_factor);

	// Shore foam
	float foam_wave = sin(TIME * foam_speed + UV.x * 30.0) * 0.5 + 0.5;
	float foam_factor = clamp(1.0 - (water_depth / max(foam_distance, 0.001)), 0.0, 1.0) * foam_wave * foam_intensity;
	foam_factor = clamp(foam_factor, 0.0, 1.0);

	vec3 final_color = mix(water_col.rgb, foam_color.rgb, foam_factor);

	ALBEDO = final_color;
	ALPHA = mix(water_col.a, 1.0, foam_factor);
	ROUGHNESS = roughness;
	METALLIC = metallic;
	SPECULAR = 0.5;
}
