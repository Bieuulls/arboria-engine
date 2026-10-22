#[vertex]
#version 450

layout(location = 0) out vec3 v_world_normal;
layout(location = 1) out vec2 v_uv;
layout(location = 2) out flat uint v_cluster_id;
layout(location = 3) out vec3 v_world_pos;

struct GPUCluster {
    vec4 center_radius;
    vec4 cone_axis_cutoff;
    vec4 group_bounds_error;
    vec4 refined_bounds_error;
    uvec4 data_offsets;
    uvec4 cluster_info;
};

layout(set = 0, binding = 0, std430) readonly buffer InClusters {
    GPUCluster clusters[];
};

layout(set = 0, binding = 1, std430) readonly buffer OutVisibleClusters {
    uint visible_cluster_ids[];
};

layout(set = 0, binding = 3, std140) uniform CameraUniforms {
    mat4 view_proj;
    vec4 frustum_planes[6];
    vec4 camera_pos_fov;
    vec4 viewport_params;
    uvec4 count_params;
    uvec4 render_params;
} ubo;

layout(set = 0, binding = 5, std430) readonly buffer InVertices {
    vec4 packed_vertices[];
};

layout(set = 0, binding = 6, std430) readonly buffer InTriangles {
    uint packed_triangles[];
};

layout(set = 0, binding = 7, std140) uniform InstanceUniforms {
    mat4 model_matrix;
    vec4 material_albedo_rough; // xyz = albedo, w = roughness
    vec4 material_metal_spec;   // x = metallic, y = specular, z = material_id, w = unused
    vec4 light_direction_energy;// xyz = light_dir, w = light_energy
    vec4 light_color;           // rgb = light_color, w = ambient_intensity
} instance_ubo;

void main() {
    uint slot = gl_InstanceIndex;
    if (slot >= ubo.count_params.x) {
        gl_Position = vec4(0.0, 0.0, 2.0, 1.0);
        return;
    }

    uint cluster_id = visible_cluster_ids[slot];
    if (cluster_id >= ubo.count_params.x) {
        gl_Position = vec4(0.0, 0.0, 2.0, 1.0);
        return;
    }

    GPUCluster c = clusters[cluster_id];

    uint tri_idx = gl_VertexIndex / 3;
    if (tri_idx >= c.data_offsets.w) {
        gl_Position = vec4(0.0, 0.0, 2.0, 1.0);
        return;
    }

    // Consulta do byte local no array compacto de triangulos
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

    // Transformacao de espaco de objeto para espaco de mundo e clip-space
    vec4 world_p = instance_ubo.model_matrix * vec4(pos_u.xyz, 1.0);
    mat3 normal_matrix = transpose(inverse(mat3(instance_ubo.model_matrix)));
    vec3 world_n = normalize(normal_matrix * norm_v.xyz);

    gl_Position = ubo.view_proj * world_p;
    v_world_pos = world_p.xyz;
    v_world_normal = world_n;
    v_uv = vec2(pos_u.w, norm_v.w);
    v_cluster_id = cluster_id;
}

#[fragment]
#version 450

layout(location = 0) in vec3 v_world_normal;
layout(location = 1) in vec2 v_uv;
layout(location = 2) in flat uint v_cluster_id;
layout(location = 3) in vec3 v_world_pos;

layout(location = 0) out vec4 out_color;

layout(set = 0, binding = 3, std140) uniform CameraUniforms {
    mat4 view_proj;
    vec4 frustum_planes[6];
    vec4 camera_pos_fov;
    vec4 viewport_params;
    uvec4 count_params;
    uvec4 render_params;
} ubo;

layout(set = 0, binding = 7, std140) uniform InstanceUniforms {
    mat4 model_matrix;
    vec4 material_albedo_rough;
    vec4 material_metal_spec;
    vec4 light_direction_energy;
    vec4 light_color;
} instance_ubo;

void main() {
    uint mode = ubo.render_params.x;
    vec3 n = normalize(v_world_normal);

    if (mode == 0u) {
        // Modo PBR Forward+ Real
        vec3 albedo = instance_ubo.material_albedo_rough.rgb;
        float roughness = instance_ubo.material_albedo_rough.w;
        float metallic = instance_ubo.material_metal_spec.x;
        float specular = instance_ubo.material_metal_spec.y;

        vec3 l_dir = normalize(instance_ubo.light_direction_energy.xyz);
        vec3 l_col = instance_ubo.light_color.rgb * instance_ubo.light_direction_energy.w;
        vec3 v_dir = normalize(ubo.camera_pos_fov.xyz - v_world_pos);

        // Termo difuso Lambertiano
        float n_dot_l = max(dot(n, l_dir), 0.0);
        vec3 diffuse = albedo * (1.0 - metallic) * n_dot_l;

        // Termo especular Blinn-Phong/GGX
        vec3 h = normalize(l_dir + v_dir);
        float n_dot_h = max(dot(n, h), 0.0);
        float spec_power = max(2.0, (1.0 - roughness) * 128.0);
        float spec_factor = pow(n_dot_h, spec_power) * specular;
        vec3 spec_color = mix(vec3(0.04), albedo, metallic);
        vec3 specular_term = spec_color * spec_factor * n_dot_l;

        // Luz ambiente hemisferica suave
        float sky_factor = n.y * 0.5 + 0.5;
        vec3 ambient_sky = vec3(0.12, 0.14, 0.18);
        vec3 ambient_ground = vec3(0.04, 0.04, 0.03);
        vec3 ambient = mix(ambient_ground, ambient_sky, sky_factor) * albedo * (1.0 - metallic);

        vec3 final_color = ambient + (diffuse + specular_term) * l_col;
        out_color = vec4(final_color, 1.0);

    } else if (mode == 1u) {
        // Diagnostico: Normais de Superficie
        out_color = vec4(n * 0.5 + 0.5, 1.0);

    } else if (mode == 2u) {
        // Diagnostico: Unshaded / Albedo Puro
        out_color = vec4(instance_ubo.material_albedo_rough.rgb, 1.0);

    } else {
        // Diagnostico: Cluster Colors com tonalidade dourada/gradiente
        float hue = fract(float(v_cluster_id) * 0.618033988749895);
        vec3 rgb = clamp(abs(fract(hue + vec3(0.0, 2.0/3.0, 1.0/3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
        vec3 cluster_col = mix(rgb, vec3(1.0), 0.15);

        vec3 l_dir = normalize(instance_ubo.light_direction_energy.xyz);
        float diff = max(dot(n, l_dir), 0.25);
        out_color = vec4(cluster_col * diff, 1.0);
    }
}
