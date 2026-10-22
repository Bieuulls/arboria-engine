#include "arboria_indirect_command_manager.h"

namespace Arboria {

ArboriaIndirectCommandManager& ArboriaIndirectCommandManager::instance() {
    static ArboriaIndirectCommandManager s_inst;
    return s_inst;
}

bool ArboriaIndirectCommandManager::validate_command(const GPUIndirectArgsAndCounters& cmd, uint32_t max_clusters) const {
    if (cmd.vertex_count != 384) return false;
    if (cmd.instance_count > max_clusters && max_clusters > 0) return false;
    if (cmd.first_vertex != 0) return false;
    return true;
}

} // namespace Arboria
