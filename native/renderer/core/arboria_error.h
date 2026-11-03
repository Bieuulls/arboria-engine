#ifndef ARBORIA_ERROR_H
#define ARBORIA_ERROR_H

#include <cstdint>
#include <string>
#include <utility>

namespace Arboria {

// Códigos de erro estruturados para o ARBORIA ENGINE.
// Substitui retornos bool genéricos por códigos específicos,
// permitindo que chamadores saibam exatamente por que uma operação falhou.
enum class ArboriaError : uint32_t {
    OK = 0,
    InvalidHandle = 1,          // Handle inválido ou já liberado
    MeshNotFound = 2,           // Malha não encontrada no registry
    RegistryFull = 3,           // Pool geracional atingiu capacidade
    VulkanCallFailed = 4,       // Chamada RenderingDevice/Vulkan falhou
    OutOfMemory = 5,            // Falha de alocação (VRAM ou sistema)
    FileNotFound = 6,           // Arquivo .vgmesh ou asset não encontrado
    InvalidData = 7,            // Dados corrompidos ou formato inválido
    AlreadyInitialized = 8,     // Componente já inicializado
    NotInitialized = 9,         // Componente não foi inicializado
    OutOfBounds = 10,           // Índice ou offset fora do intervalo
    ShaderCompilationFailed = 11, // Falha na compilação de shader GLSL
    PageFault = 12,             // Página de streaming não residente
    InternalError = 13          // Erro interno não categorizado
};

// Resultado tipado: encapsula ou um valor de sucesso ou um erro + mensagem.
// Uso: Result<Handle> r = registry.register_mesh(path); if (!r) { ... }
template <typename T>
struct Result {
    T value{};
    ArboriaError error = ArboriaError::OK;
    std::string message;

    constexpr bool ok() const { return error == ArboriaError::OK; }
    constexpr explicit operator bool() const { return ok(); }

    static Result<T> success(T v) {
        Result<T> r;
        r.value = std::move(v);
        return r;
    }

    static Result<T> failure(ArboriaError e, std::string msg = "") {
        Result<T> r;
        r.error = e;
        r.message = std::move(msg);
        return r;
    }
};

// Resultado sem valor associado (apenas sucesso ou erro).
// Uso: Status s = streaming_manager.initialize(); if (!s) { ... }
struct Status {
    ArboriaError error = ArboriaError::OK;
    std::string message;

    constexpr bool ok() const { return error == ArboriaError::OK; }
    constexpr explicit operator bool() const { return ok(); }

    static Status success() { return Status{}; }

    static Status failure(ArboriaError e, std::string msg = "") {
        Status s;
        s.error = e;
        s.message = std::move(msg);
        return s;
    }
};

} // namespace Arboria

#endif // ARBORIA_ERROR_H
