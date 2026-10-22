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
    uint pad0;
    uint pad1;
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
    uvec4 render_params;
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
    uvec4 render_params;
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

void main() {
    GPUInstanceData inst = instances[v_instance_id];
    vec3 N = normalize(v_world_normal);

    uint shading_mode = ubo.render_params.x;

    if (shading_mode == 3u) {
        // Cluster Debug View
        out_color = vec4(cluster_color(v_cluster_id), 1.0);
        return;
    }

    if (shading_mode == 1u) {
        // Normal View
        out_color = vec4(N * 0.5 + 0.5, 1.0);
        return;
    }

    // PBR Shading
    vec3 albedo = inst.material_albedo_rough.rgb;
    float roughness = inst.material_albedo_rough.w;
    float metallic = inst.material_metal_spec.x;

    vec3 L = normalize(vec3(0.5, 0.8, 0.6));
    float NdotL = max(dot(N, L), 0.0);
    vec3 ambient = vec3(0.2) * albedo;
    vec3 diffuse = albedo * NdotL;

    vec3 final_rgb = ambient + diffuse;
    out_color = vec4(final_rgb, 1.0);
}
