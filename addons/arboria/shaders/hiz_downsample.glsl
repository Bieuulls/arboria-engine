#[compute]
#version 450 core

// ARBORIA ENGINE — HIERARCHICAL-Z (Hi-Z) DOWNSAMPLE COMPUTE SHADER
// Gera pirâmide de profundidade conservadora para Reversed-Z (Vulkan 1.4 / Godot Forward+)
// Utiliza filtro MIN conservador: o valor mais distante dos 4 pixels fonte é preservado.

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D u_src_depth;
layout(set = 0, binding = 1, r32f) uniform writeonly image2D u_dst_depth;

layout(push_constant) uniform HiZPushConstants {
    vec2 dst_size;
    vec2 src_texel_size;
    int src_mip_level;
} push_consts;

void main() {
    ivec2 dst_coord = ivec2(gl_GlobalInvocationID.xy);
    if (dst_coord.x >= int(push_consts.dst_size.x) || dst_coord.y >= int(push_consts.dst_size.y)) {
        return;
    }

    // Coordenada UV central do texel de destino mapeada na textura de origem
    vec2 uv = (vec2(dst_coord) + 0.5) / push_consts.dst_size;

    // Amostragem conservadora 2x2 do mip anterior (Gather 4 texels)
    vec2 offset = push_consts.src_texel_size * 0.5;

    float d0 = textureLod(u_src_depth, uv + vec2(-offset.x, -offset.y), float(push_consts.src_mip_level)).r;
    float d1 = textureLod(u_src_depth, uv + vec2( offset.x, -offset.y), float(push_consts.src_mip_level)).r;
    float d2 = textureLod(u_src_depth, uv + vec2(-offset.x,  offset.y), float(push_consts.src_mip_level)).r;
    float d3 = textureLod(u_src_depth, uv + vec2( offset.x,  offset.y), float(push_consts.src_mip_level)).r;

    // CONTRATO REVERSED-Z: Menor valor representa o ponto mais afastado (mais próximo de Far/Sky)
    // Para descarte conservador, usamos min(): se o cluster estiver atrás do ponto mais distante,
    // ele está garantidamente ocluído por toda a área da célula 2x2.
    float min_depth = min(min(d0, d1), min(d2, d3));

    imageStore(u_dst_depth, dst_coord, vec4(min_depth, 0.0, 0.0, 0.0));
}
