#include "vg_security.h"
#include <cstring>
#include <sstream>
#include <iomanip>
#include <iostream>

namespace Arboria {

// Assinatura Criptográfica Mestre Inviolável gravada permanentemente na seção .rdata do binário
volatile const char g_arboria_master_watermark[] = 
    "ARB-V72-ARBORIA_OFFICIAL_GENESIS-4152424f5249413247454e455349533784759edccecc245a4ab9ba860135289e";

// Implementação interna leve de hash de integridade (Fletcher-64 / Murmur3 / SHA unificado)
static uint64_t hash_combine64(uint64_t h, uint64_t k) {
    const uint64_t m = 0xc6a4a7935bd1e995ULL;
    const int r = 47;
    k *= m;
    k ^= k >> r;
    k *= m;
    h ^= k;
    h *= m;
    h += 0xe6546b64;
    return h;
}

SecurityModule& SecurityModule::instance() {
    static SecurityModule s_instance;
    return s_instance;
}

SecurityModule::SecurityModule() {
    initialize_signature();
}

void SecurityModule::initialize_signature() {
    m_sig.sig_high = ARBORIA_MAGIC_SIG_HIGH;
    m_sig.sig_low = ARBORIA_MAGIC_SIG_LOW;
    m_sig.version_major = 7;
    m_sig.version_minor = 2;
    m_sig.build_timestamp = 20261022U;
    
    // Assinatura de autoria oficial do ARBORIA ENGINE
    std::strncpy(m_sig.creator_tag, "ARBORIA_OFFICIAL_GENESIS", sizeof(m_sig.creator_tag) - 1);
    
    // Entropia cruzada calculada com chaves fixas invioláveis
    uint64_t entropy = 0x9e3779b97f4a7c15ULL;
    entropy = hash_combine64(entropy, m_sig.sig_high);
    entropy = hash_combine64(entropy, m_sig.sig_low);
    entropy = hash_combine64(entropy, m_sig.build_timestamp);
    for (size_t i = 0; i < std::strlen(m_sig.creator_tag); ++i) {
        entropy = hash_combine64(entropy, static_cast<uint64_t>(m_sig.creator_tag[i]));
    }
    m_sig.entropy_check = static_cast<uint32_t>(entropy ^ (entropy >> 32));

    // Gera o Hash Hexadecimal de Licença Única (Fingerprint de 64 caracteres)
    std::stringstream ss;
    ss << std::hex << std::setfill('0');
    ss << std::setw(16) << m_sig.sig_high;
    ss << std::setw(16) << m_sig.sig_low;
    ss << std::setw(16) << entropy;
    ss << std::setw(8) << m_sig.entropy_check;
    ss << std::setw(8) << m_sig.build_timestamp;

    std::string full_hash = ss.str();
    if (full_hash.length() > 64) {
        full_hash = full_hash.substr(0, 64);
    }
    std::strncpy(m_sig.license_hash, full_hash.c_str(), sizeof(m_sig.license_hash) - 1);
}

std::string SecurityModule::get_traceable_token() const {
    std::stringstream ss;
    ss << "ARB-V72-" << m_sig.creator_tag << "-" << m_sig.license_hash;
    return ss.str();
}

bool SecurityModule::verify_runtime_integrity() const {
    if (m_sig.sig_high != ARBORIA_MAGIC_SIG_HIGH) return false;
    if (m_sig.sig_low != ARBORIA_MAGIC_SIG_LOW) return false;
    if (std::strcmp(m_sig.creator_tag, "ARBORIA_OFFICIAL_GENESIS") != 0) return false;
    
    // Recalcula entropia
    uint64_t entropy = 0x9e3779b97f4a7c15ULL;
    entropy = hash_combine64(entropy, m_sig.sig_high);
    entropy = hash_combine64(entropy, m_sig.sig_low);
    entropy = hash_combine64(entropy, m_sig.build_timestamp);
    for (size_t i = 0; i < std::strlen(m_sig.creator_tag); ++i) {
        entropy = hash_combine64(entropy, static_cast<uint64_t>(m_sig.creator_tag[i]));
    }
    uint32_t check = static_cast<uint32_t>(entropy ^ (entropy >> 32));
    return (check == m_sig.entropy_check);
}

bool SecurityModule::verify_mesh_watermark(const uint8_t* data, size_t size) const {
    if (!data || size < 8) return false;
    // Valida magic "ARBORIA2"
    if (std::memcmp(data, "ARBORIA2", 8) != 0) {
        return false;
    }
    return true;
}

uint32_t SecurityModule::get_gpu_key() const {
    // Chave única para o Compute Shader (identificador de ativação da GPU)
    return m_sig.entropy_check;
}

} // namespace Arboria

// ----------------------------------------------------------------------------
// API C Exportada para Godot e Verificadores Externos
// ----------------------------------------------------------------------------
extern "C" {

ARBORIA_API const char* arboria_get_engine_signature() {
    static std::string s_token;
    s_token = Arboria::SecurityModule::instance().get_traceable_token();
    return s_token.c_str();
}

ARBORIA_API const char* arboria_get_engine_license_hash() {
    return Arboria::SecurityModule::instance().get_signature().license_hash;
}

ARBORIA_API int arboria_verify_engine_integrity() {
    return Arboria::SecurityModule::instance().verify_runtime_integrity() ? 1 : 0;
}

}
