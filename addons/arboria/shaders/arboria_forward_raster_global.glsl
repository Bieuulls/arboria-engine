#[vertex]
#version 450

// ============================================================================
// ARBORIA VIRTUAL GEOMETRY — GLOBAL FORWARD+ RASTER PASS (VERTEX SHADER)
// Desempacota (instance_id, cluster_id) de VisibleClusterItem[]
// Zero limite 2048x2048, 1 Desenho Indireto Agrupado para Toda a Cena
// ============================================================================

layout(location = 0) out vec3 v_world_normal;
layout(location = 1) out vec2 v_uv;
layout(location = 2) out flat uint v_cluster_id;
layout(location = 3) out vec3 v_world_pos;
layout(location = 4) out flat uint v_instance_id;

struct GPUCluster {
    vec4 center_radius;
    vec4 cone_axis_cutoff;
    vec4 group_bounds_error;
    vec4 refined_bounds_error;
    uvec4 data_offsets;        // x = vertex_offset, y = vertex_count, z = triangle_offset, w = triangle_count
    uvec4 cluster_info;
};

struct GPUInstanceData {
    mat4 model_matrix;
    mat4 normal_matrix;
    vec4 bounding_sphere;
    vec4 aabb_min;
    vec4 aabb_max;
    vec4 material_albedo_rough;
    vec4 material_metal_spec;
    uint instance_id;
    uint mesh_id;
    uint visibility_flags;
    uint resource_generation;
    uint cluster_offset;
    uint cluster_count;
    uint root_cluster_offset;
    uint lod_count;
};

struct VisibleClusterItem {
    uint instance_id;
    uint cluster_id;
};

// 0: Buffer de clusters de geometria compartilhada
layout(set = 0, binding = 0, std430) readonly buffer InClusters {
    GPUCluster clusters[];
};

// 1: Buffer compacto de itens visíveis selecionados pelo Compute Culling
layout(set = 0, binding = 1, std430) readonly buffer InVisibleItems {
    VisibleClusterItem visible_items[];
};

// 3: Uniforms globais da cena
layout(set = 0, binding = 3, std140) uniform GlobalSceneUniforms {
    mat4 view_proj;
    vec4 frustum_planes[6];
    vec4 camera_pos_fov;
    vec4 viewport_params;
    uvec4 count_params;
    uvec4 render_params;        // x = shading_mode, y = enable_hiz, z = max_visible_items, w = wind_enabled
    vec4 wind_params;           // x = time, y = strength, z = freq, w = gust
    vec4 wind_direction;        // xyz = dir_norm, w = unused
} ubo;

// 4: Buffer de instâncias globais
layout(set = 0, binding = 4, std430) readonly buffer InInstances {
    GPUInstanceData instances[];
};

// 5: Buffer de vértices compactados compartilhado
layout(set = 0, binding = 5, std430) readonly buffer InVertices {
    vec4 packed_vertices[];
};

// 6: Buffer de triângulos indexados compartilhado
layout(set = 0, binding = 6, std430) readonly buffer InTriangles {
    uint packed_triangles[];
};

void main() {
    uint slot = gl_InstanceIndex;
    if (slot >= ubo.render_params.z) {
        gl_Position = vec4(0.0, 0.0, 2.0, 1.0);
        return;
    }

    VisibleClusterItem item = visible_items[slot];
    if (item.instance_id >= ubo.count_params.x) {
        gl_Position = vec4(0.0, 0.0, 2.0, 1.0);
        return;
    }

    GPUInstanceData inst = instances[item.instance_id];
    GPUCluster c = clusters[item.cluster_id];

    uint tri_idx = gl_VertexIndex / 3;
    if (tri_idx >= c.data_offsets.w) {
        gl_Position = vec4(0.0, 0.0, 2.0, 1.0);
        return;
    }

    // Leitura do triângulo local
    uint byte_offset = c.data_offsets.z + gl_VertexIndex;
    uint word_idx = byte_offset / 4;
    uint byte_in_word = byte_offset % 4;
    uint word = packed_triangles[word_idx];
    uint local_v_idx = (word >> (byte_in_word * 8)) & 0xFFu;

    if (local_v_idx >= c.data_offsets.y) {
        gl_Position = vec4(0.0, 0.0, 2.0, 1.0);
        return;
    }

    uint global_v_idx = c.data_offsets.x + local_v_idx;
    uint vert_entry_idx = global_v_idx * 2;

    vec4 pos_u = packed_vertices[vert_entry_idx + 0];
    vec4 norm_v = packed_vertices[vert_entry_idx + 1];

    // Transformação com a model_matrix e normal_matrix da instância correspondente
    vec4 world_p = inst.model_matrix * vec4(pos_u.xyz, 1.0);
    vec3 world_n = normalize(mat3(inst.normal_matrix) * norm_v.xyz);

    // Deslocamento de Vento Físico / Procedural na GPU
    if (ubo.render_params.w != 0u) {
        float h = max(0.0, pos_u.y);
        float time_val = ubo.wind_params.x;
        float strength = ubo.wind_params.y;
        float freq = ubo.wind_params.z;
        float gust = ubo.wind_params.w;

        float phase = time_val * freq + dot(world_p.xyz, vec3(0.12, 0.05, 0.09));
        float wave = sin(phase) + cos(phase * 0.7) * gust;
        vec3 wind_disp = ubo.wind_direction.xyz * (wave * strength * (h * h * 0.02));
        world_p.xyz += wind_disp;
    }

    gl_Position = ubo.view_proj * world_p;
    v_world_pos = world_p.xyz;
    v_world_normal = world_n;
    v_uv = vec2(pos_u.w, norm_v.w);
    v_cluster_id = item.cluster_id;
    v_instance_id = item.instance_id;
}

#[fragment]
#version 450

// ============================================================================
// ARBORIA VIRTUAL GEOMETRY — GLOBAL FORWARD+ RASTER PASS (FRAGMENT SHADER)
// ============================================================================

layout(location = 0) in vec3 v_world_normal;
layout(location = 1) in vec2 v_uv;
layout(location = 2) in flat uint v_cluster_id;
layout(location = 3) in vec3 v_world_pos;
layout(location = 4) in flat uint v_instance_id;

layout(location = 0) out vec4 out_color;

struct GPUInstanceData {
    mat4 model_matrix;
    mat4 normal_matrix;
    vec4 bounding_sphere;
    vec4 aabb_min;
    vec4 aabb_max;
    vec4 material_albedo_rough;
    vec4 material_metal_spec;
    uint instance_id;
    uint mesh_id;
    uint visibility_flags;
    uint resource_generation;
    uint cluster_offset;
    uint cluster_count;
    uint pad0;
    uint pad1;
};

layout(set = 0, binding = 3, std140) uniform GlobalSceneUniforms {
    mat4 view_proj;
    vec4 frustum_planes[6];
    vec4 camera_pos_fov;
    vec4 viewport_params;
    uvec4 count_params;
    uvec4 render_params;        // x = shading_mode, y = enable_hiz, z = max_visible_items, w = wind_enabled
    vec4 wind_params;           // x = time, y = strength, z = freq, w = gust
    vec4 wind_direction;        // xyz = dir_norm, w = unused
} ubo;

layout(set = 0, binding = 4, std430) readonly buffer InInstances {
    GPUInstanceData instances[];
};

// Paleta pseudo-aleatória determinística para Cluster Debug View
vec3 cluster_color(uint id) {
    uint n = id * 1664525u + 1013904223u;
    n ^= (n >> 16);
    n *= 1664525u;
    float r = float(n & 0xFFu) / 255.0;
    float g = float((n >> 8) & 0xFFu) / 255.0;
    float b = float((n >> 16) & 0xFFu) / 255.0;
    return max(vec3(r, g, b), vec3(0.15));
}

// Cook-Torrance GGX PBR functions
const float PI = 3.141592653589793;

float D_GGX(float NoH, float roughness) {
    float a = max(0.04, roughness * roughness);
    float a2 = a * a;
    float d = (NoH * a2 - NoH) * NoH + 1.0;
    return a2 / (PI * d * d + 1e-5);
}

float G_SmithGGXCorrelated(float NoV, float NoL, float roughness) {
    float a = max(0.04, roughness * roughness);
    float a2 = a * a;
    float lambdaV = NoL * sqrt((NoV - a2 * NoV) * NoV + a2);
    float lambdaL = NoV * sqrt((NoL - a2 * NoL) * NoL + a2);
    return 0.5 / (lambdaV + lambdaL + 1e-5);
}

vec3 F_Schlick(float VoH, vec3 f0) {
    float f = pow(clamp(1.0 - VoH, 0.0, 1.0), 5.0);
    return f0 + (vec3(1.0) - f0) * f;
}

// Fast deterministic 3D hash
float hash3D(vec3 p) {
    p = fract(p * 0.3183099 + 0.1);
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// 3D Value Noise com interpolação cúbica suave
float noise3D(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(mix(hash3D(i + vec3(0,0,0)), hash3D(i + vec3(1,0,0)), f.x),
            mix(hash3D(i + vec3(0,1,0)), hash3D(i + vec3(1,1,0)), f.x), f.y),
        mix(mix(hash3D(i + vec3(0,0,1)), hash3D(i + vec3(1,0,1)), f.x),
            mix(hash3D(i + vec3(0,1,1)), hash3D(i + vec3(1,1,1)), f.x), f.y), f.z);
}

// FBM para granulação geológica e erosão milenar de pedra
float stoneFBM(vec3 p) {
    float v = 0.0;
    float a = 0.5;
    vec3 shift = vec3(100.0);
    for (int i = 0; i < 3; ++i) {
        v += a * noise3D(p);
        p = p * 2.08 + shift;
        a *= 0.5;
    }
    return v;
}

void main() {
    GPUInstanceData inst = instances[v_instance_id];
    vec3 N_geom = normalize(v_world_normal);
    bool is_mirrored = (inst.visibility_flags & 4u) != 0u;
    bool front = is_mirrored ? !gl_FrontFacing : gl_FrontFacing;
    if (!front) {
        N_geom = -N_geom;
    }

    uint shading_mode = ubo.render_params.x;

    if (shading_mode == 3u) {
        // Cluster Debug View
        out_color = vec4(cluster_color(v_cluster_id), 1.0);
        return;
    }

    if (shading_mode == 1u) {
        // Normal View
        out_color = vec4(N_geom * 0.5 + 0.5, 1.0);
        return;
    }

    if (shading_mode == 2u) {
        // Unshaded Albedo View
        out_color = vec4(inst.material_albedo_rough.rgb, 1.0);
        return;
    }

    // =========================================================================
    // ARBORIA ULTRA PBR — SÍNTESE DE MATERIAIS DE PEDRA ARQUITETÔNICA CLÁSSICA
    // =========================================================================
    vec3 wp = v_world_pos;
    bool is_floor = (wp.y < 0.25 && N_geom.y > 0.65);

    // 1. Textura e Albedo de Pedra (Istrian Stone / Travertino Ancestral)
    vec3 base_stone_col = inst.material_albedo_rough.rgb;
    float grain = stoneFBM(wp * 1.2);
    float fine_grain = noise3D(vec3(v_uv * 40.0, wp.y * 2.0)) * 0.10;

    // Paleta de pedra nobre clássica: tons de mármore quente e calcário travertino (Reflectância física real 38%)
    vec3 warm_limestone = mix(vec3(0.48, 0.44, 0.38), vec3(0.38, 0.34, 0.29), grain);
    vec3 ochre_patina   = mix(vec3(0.44, 0.40, 0.34), vec3(0.34, 0.30, 0.26), grain * 0.6 + fine_grain);
    vec3 albedo = mix(warm_limestone, ochre_patina, 0.45) * (base_stone_col * 0.85);

    // Pavimentação de lajes de pedra no pátio central
    if (is_floor) {
        vec2 floor_tile = fract(wp.xz * 0.5);
        float border = step(0.02, floor_tile.x) * step(0.02, floor_tile.y) * step(floor_tile.x, 0.98) * step(floor_tile.y, 0.98);
        vec3 tile_shade = (mod(floor(wp.x * 0.5) + floor(wp.z * 0.5), 2.0) > 0.5) ? vec3(0.42, 0.39, 0.34) : vec3(0.35, 0.32, 0.28);
        albedo = mix(vec3(0.24, 0.22, 0.19), tile_shade, border) * base_stone_col;
    }

    // 2. Perturbação de Normais (Micro-relevo natural da pedra)
    float h_c = stoneFBM(wp * 3.0);
    float h_x = stoneFBM((wp + vec3(0.015, 0.0, 0.0)) * 3.0) - h_c;
    float h_y = stoneFBM((wp + vec3(0.0, 0.015, 0.0)) * 3.0) - h_c;
    float h_z = stoneFBM((wp + vec3(0.0, 0.0, 0.015)) * 3.0) - h_c;
    vec3 stone_relief = vec3(h_x, h_y, h_z) * 0.5;
    vec3 N = normalize(N_geom - stone_relief);

    // 3. Rugosidade (Roughness) e Metálico
    float roughness = is_floor ? 0.38 : mix(0.55, 0.85, grain);
    float metallic = clamp(inst.material_metal_spec.x, 0.0, 1.0);
    float specular_intensity = max(0.04, inst.material_metal_spec.y);

    // Se o objeto for configurado como metal/escultura antiga (ex: Dragão de Bronze, Elmo, Relíquia)
    if (inst.material_metal_spec.x > 0.15) {
        albedo = inst.material_albedo_rough.rgb * (grain * 0.25 + 0.85);
        metallic = inst.material_metal_spec.x;
        roughness = clamp(inst.material_albedo_rough.a, 0.20, 0.90);
        specular_intensity = max(0.5, inst.material_metal_spec.y);
    }

    // 4. Iluminação Cook-Torrance GGX PBR
    vec3 L = normalize(vec3(0.55, 0.75, 0.35)); // Luz solar descendente com ângulo cinematográfico
    vec3 V = normalize(ubo.camera_pos_fov.xyz - v_world_pos);
    vec3 H = normalize(L + V);

    float NoL = clamp(dot(N, L), 0.0, 1.0);
    float NoV = clamp(abs(dot(N, V)), 1e-4, 1.0);
    float NoH = clamp(dot(N, H), 0.0, 1.0);
    float VoH = clamp(dot(V, H), 0.0, 1.0);

    vec3 f0 = mix(vec3(0.04 * specular_intensity), albedo, metallic);
    float D = D_GGX(NoH, roughness);
    float G = G_SmithGGXCorrelated(NoV, NoL, roughness);
    vec3 F = F_Schlick(VoH, f0);

    vec3 specular_brdf = (D * G) * F;
    vec3 k_dielectric = (vec3(1.0) - F) * (1.0 - metallic);
    vec3 kd = k_dielectric * 0.95;

    vec3 diffuse_brdf = kd * (albedo / PI);
    vec3 direct_light = (diffuse_brdf + specular_brdf) * vec3(0.95) * (NoL * PI);

    // Iluminação Ambiente Hemisférica Realista com Oclusão de Contato
    float hemi = clamp(N.y * 0.5 + 0.5, 0.0, 1.0);
    vec3 ambient_sky = vec3(0.38, 0.46, 0.58) * 0.40;
    vec3 ambient_ground = vec3(0.24, 0.20, 0.17) * 0.35;
    vec3 ambient_col = mix(ambient_ground, ambient_sky, hemi);
    float contact_ao = clamp(0.55 + 0.45 * N.y, 0.35, 1.0);
    vec3 ambient_light = albedo * ambient_col * contact_ao * (1.0 - metallic * 0.8);

    vec3 final_rgb = direct_light + ambient_light;

    // 5. Tonemapping Filmic ACES + Correção Gamma (Evita estouro de branco)
    vec3 x = max(vec3(0.0), final_rgb);
    vec3 aces = (x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14);
    aces = clamp(aces, 0.0, 1.0);
    vec3 srgb = pow(aces, vec3(1.0 / 2.2));

    out_color = vec4(srgb, 1.0);
}
