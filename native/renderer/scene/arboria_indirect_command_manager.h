#ifndef ARBORIA_INDIRECT_COMMAND_MANAGER_H
#define ARBORIA_INDIRECT_COMMAND_MANAGER_H

#include "../core/arboria_types.h"
#include "arboria_gpu_scene_types.h"
#include <cstdint>

namespace Arboria {

class ARBORIA_CLASS ArboriaIndirectCommandManager {
public:
    static ArboriaIndirectCommandManager& instance();

    // Valida comando indireto recebido da GPU
    bool validate_command(const GPUIndirectArgsAndCounters& cmd, uint32_t max_clusters) const;

    // Retorna o tamanho em bytes do buffer de comando indireto VkDrawIndirectCommand
    size_t get_command_buffer_size() const {
        return sizeof(GPUIndirectArgsAndCounters);
    }

private:
    ArboriaIndirectCommandManager() = default;
    ~ArboriaIndirectCommandManager() = default;
};

} // namespace Arboria

#endif // ARBORIA_INDIRECT_COMMAND_MANAGER_H
