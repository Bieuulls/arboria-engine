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
    vec4 material_metal_spec;   // x = metallic, y = specular, z = material_id, w = use_textures
    vec4 light_direction_energy;// xyz = light_dir, w = light_energy
    vec4 light_color;           // rgb = light_color, w = ambient_intensity
    vec4 texture_params;        // xy = uv_scale, z = normal_scale, w = unused
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
    vec4 material_albedo_rough; // xyz = albedo, w = roughness
    vec4 material_metal_spec;   // x = metallic, y = specular, z = material_id, w = use_textures (1.0 = on, 0.0 = procedural)
    vec4 light_direction_energy;// xyz = light_dir, w = light_energy
    vec4 light_color;           // rgb = light_color, w = ambient_intensity
    vec4 texture_params;        // xy = uv_scale, z = normal_scale, w = unused
} instance_ubo;

layout(set = 0, binding = 8) uniform sampler2D albedo_map;
layout(set = 0, binding = 9) uniform sampler2D normal_map;
layout(set = 0, binding = 10) uniform sampler2D orm_map; // r = ao, g = roughness, b = metallic

const float PI = 3.141592653589793;

// Funcao analitica de ruido pseudo-aleatorio para micro-relevo mineral
float ARB_Hash31(vec3 p) {
    p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float ARB_SmoothNoise(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    vec3 u = f * f * (3.0 - 2.0 * f);

    float n000 = ARB_Hash31(i + vec3(0.0, 0.0, 0.0));
    float n100 = ARB_Hash31(i + vec3(1.0, 0.0, 0.0));
    float n010 = ARB_Hash31(i + vec3(0.0, 1.0, 0.0));
    float n110 = ARB_Hash31(i + vec3(1.0, 1.0, 0.0));
    float n001 = ARB_Hash31(i + vec3(0.0, 0.0, 1.0));
    float n101 = ARB_Hash31(i + vec3(1.0, 0.0, 1.0));
    float n011 = ARB_Hash31(i + vec3(0.0, 1.0, 1.0));
    float n111 = ARB_Hash31(i + vec3(1.0, 1.0, 1.0));

    float nx00 = mix(n000, n100, u.x);
    float nx10 = mix(n010, n110, u.x);
    float nx01 = mix(n001, n101, u.x);
    float nx11 = mix(n011, n111, u.x);

    float nxy0 = mix(nx00, nx10, u.y);
    float nxy1 = mix(nx01, nx11, u.y);

    return mix(nxy0, nxy1, u.z);
}

// Micro-relevo geologico fbm (veios de rocha, poros e lascas minerais)
float ARB_RockDetailHeight(vec3 p) {
    float h = 0.0;
    h += ARB_SmoothNoise(p * 8.0) * 0.50;
    h += ARB_SmoothNoise(p * 24.0) * 0.30;
    h += ARB_SmoothNoise(p * 72.0) * 0.20;
    return h;
}

// Cook-Torrance GGX microfacet functions
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

void main() {
    uint mode = ubo.render_params.x;
    vec3 geom_n = normalize(v_world_normal);

    if (mode == 0u) {
        // =====================================================================
        // MODO PBR CINEMATOGRAFICO FORWARD+ (COOK-TORRANCE GGX + ROCK DETAIL)
        // =====================================================================
        
        bool use_tex = (instance_ubo.material_metal_spec.w > 0.5);
        vec2 uv = v_uv * instance_ubo.texture_params.xy;

        // Calculo de base normal e tangentes de tela
        vec3 dPdx = dFdx(v_world_pos);
        vec3 dPdy = dFdy(v_world_pos);
        vec3 surf_tangent = normalize(dPdx);
        vec3 surf_bitangent = normalize(cross(geom_n, surf_tangent));
        surf_tangent = cross(surf_bitangent, geom_n);
        mat3 tbn = mat3(surf_tangent, surf_bitangent, geom_n);

        vec3 n = geom_n;
        vec3 albedo = instance_ubo.material_albedo_rough.rgb;
        float roughness = clamp(instance_ubo.material_albedo_rough.w, 0.04, 0.98);
        float metallic = clamp(instance_ubo.material_metal_spec.x, 0.0, 1.0);
        float specular_intensity = instance_ubo.material_metal_spec.y;
        float cavity_ao = 1.0;

        if (use_tex) {
            // Amostragem de texturas PBR externas
            vec4 tex_albedo = texture(albedo_map, uv);
            albedo = tex_albedo.rgb * instance_ubo.material_albedo_rough.rgb;

            vec3 tex_n = texture(normal_map, uv).rgb * 2.0 - 1.0;
            tex_n.xy *= instance_ubo.texture_params.z; // Normal Scale
            n = normalize(tbn * tex_n);

            vec4 tex_orm = texture(orm_map, uv);
            cavity_ao = tex_orm.r;
            roughness = clamp(tex_orm.g * instance_ubo.material_albedo_rough.w, 0.04, 0.98);
            metallic = clamp(tex_orm.b * instance_ubo.material_metal_spec.x, 0.0, 1.0);

        } else {
            // Micro-relevo Geologico Procedural (Modo Mineral sem textura)
            vec3 p_surf = v_world_pos * 1.8;
            float h_center = ARB_RockDetailHeight(p_surf);
            float eps = 0.02;
            float h_x = ARB_RockDetailHeight(p_surf + surf_tangent * eps);
            float h_y = ARB_RockDetailHeight(p_surf + surf_bitangent * eps);
            vec2 bump_grad = vec2(h_x - h_center, h_y - h_center) / eps;

            float bump_strength = 0.045;
            n = normalize(geom_n - (surf_tangent * bump_grad.x + surf_bitangent * bump_grad.y) * bump_strength);

            float vein_tint = smoothstep(0.2, 0.8, h_center);
            albedo = mix(instance_ubo.material_albedo_rough.rgb * 0.72, instance_ubo.material_albedo_rough.rgb * 1.08, vein_tint);
            cavity_ao = clamp(0.55 + 0.45 * h_center, 0.0, 1.0);
        }

        // Vetores de iluminacao e camera
        vec3 l_dir = normalize(instance_ubo.light_direction_energy.xyz);
        vec3 l_col = instance_ubo.light_color.rgb * instance_ubo.light_direction_energy.w;
        vec3 v_dir = normalize(ubo.camera_pos_fov.xyz - v_world_pos);
        vec3 h = normalize(l_dir + v_dir);

        float NoL = clamp(dot(n, l_dir), 0.0, 1.0);
        float NoV = clamp(abs(dot(n, v_dir)), 1e-4, 1.0);
        float NoH = clamp(dot(n, h), 0.0, 1.0);
        float VoH = clamp(dot(v_dir, h), 0.0, 1.0);

        // F0 (Reflectancia na incidencia normal)
        vec3 f0 = mix(vec3(0.04 * specular_intensity), albedo, metallic);

        // Cook-Torrance Specular BRDF
        float D = D_GGX(NoH, roughness);
        float G = G_SmithGGXCorrelated(NoV, NoL, roughness);
        vec3 F = F_Schlick(VoH, f0);

        vec3 specular_brdf = (D * G) * F;

        // Diffuse BRDF (Energy conserving Lambertian)
        vec3 kd = (vec3(1.0) - F) * (1.0 - metallic);
        vec3 diffuse_brdf = kd * (albedo / PI);

        // Luz direta
        vec3 direct_light = (diffuse_brdf + specular_brdf) * l_col * (NoL * PI);

        // Luz ambiente hemisferica IBL aproximada com gradiente celeste
        float sky_factor = n.y * 0.5 + 0.5;
        vec3 ambient_sky = vec3(0.18, 0.22, 0.28) * 1.1;
        vec3 ambient_ground = vec3(0.05, 0.04, 0.03) * 0.9;
        vec3 ambient_env = mix(ambient_ground, ambient_sky, sky_factor);

        // Fresnel de borda ambiente (Rim light)
        vec3 ambient_fresnel = F_Schlick(NoV, f0) * 0.25;
        vec3 ambient_light = (albedo * ambient_env * (1.0 - metallic) + ambient_fresnel) * cavity_ao;

        // Cor final PBR
        vec3 final_color = direct_light + ambient_light;
        out_color = vec4(final_color, 1.0);

    } else if (mode == 1u) {
        // Diagnostico: Normais de Superficie
        out_color = vec4(geom_n * 0.5 + 0.5, 1.0);

    } else if (mode == 2u) {
        // Diagnostico: Unshaded / Albedo Puro
        out_color = vec4(instance_ubo.material_albedo_rough.rgb, 1.0);

    } else {
        // Diagnostico: Cluster Colors com tonalidade distinta por Cluster ID
        float hue = fract(float(v_cluster_id) * 0.618033988749895);
        vec3 rgb = clamp(abs(fract(hue + vec3(0.0, 2.0/3.0, 1.0/3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
        vec3 cluster_col = mix(rgb, vec3(1.0), 0.12);

        vec3 l_dir = normalize(instance_ubo.light_direction_energy.xyz);
        float diff = max(dot(geom_n, l_dir), 0.25);
        out_color = vec4(cluster_col * diff, 1.0);
    }
}
