#include "arboria_visibility_manager.h"
#include <algorithm>

namespace Arboria {

ArboriaVisibilityManager& ArboriaVisibilityManager::instance() {
    static ArboriaVisibilityManager s_inst;
    return s_inst;
}

void ArboriaVisibilityManager::set_capacity(uint32_t max_visible_items) {
    m_max_capacity = std::max(1024u, max_visible_items);
}

} // namespace Arboria
