#ifndef VG_SECURITY_H
#define VG_SECURITY_H

#include "arboria_types.h"
#include <cstdint>
#include <string>

namespace Arboria {

// Identificador Mestre Criptográfico do ARBORIA ENGINE
// Imutável, embutido no binário C++ nativo e exigido pelos shaders e malhas .vgmesh
constexpr uint64_t ARBORIA_MAGIC_SIG_HIGH = 0x4152424F52494132ULL; // "ARBORIA2" em ASCII
constexpr uint64_t ARBORIA_MAGIC_SIG_LOW  = 0x47454E4553495337ULL; // "GENESIS7" em ASCII

struct EngineSignature {
    uint64_t sig_high;
    uint64_t sig_low;
    uint32_t version_major;
    uint32_t version_minor;
    uint32_t build_timestamp;
    uint32_t entropy_check;
    char creator_tag[32];
    char license_hash[65]; // Hash SHA-256 hexadecimal da assinatura
};

class ARBORIA_CLASS SecurityModule {
public:
    static SecurityModule& instance();

    // Retorna a assinatura criptográfica completa embutida no binário
    const EngineSignature& get_signature() const { return m_sig; }

    // Retorna o token rastreável único do motor
    std::string get_traceable_token() const;

    // Valida se os dados da malha .vgmesh possuem a marca d'água legítima do motor
    bool verify_mesh_watermark(const uint8_t* data, size_t size) const;

    // Valida integridade em tempo de execução
    bool verify_runtime_integrity() const;

    // Gera a chave de decodificação de cluster para o compute shader
    uint32_t get_gpu_key() const;

private:
    SecurityModule();
    ~SecurityModule() = default;

    EngineSignature m_sig{};
    void initialize_signature();
};

} // namespace Arboria

// API C Exportada para Godot / Verificador Forense Externo
ARBORIA_API const char* arboria_get_engine_signature();
ARBORIA_API const char* arboria_get_engine_license_hash();
ARBORIA_API int arboria_verify_engine_integrity();

#endif // VG_SECURITY_H
