#ifndef VG_GPU_DRIVER_H
#define VG_GPU_DRIVER_H

#include "../core/arboria_types.h"
#include "../core/gdextension_interface.h"

namespace Arboria {

typedef bool (*GPUCallMethodFunc)(
    GDExtensionVariantPtr target,
    const char* method_name,
    const GDExtensionConstVariantPtr* args,
    int arg_count,
    GDExtensionVariantPtr r_ret
);

typedef void (*VariantGetIndexedFunc)(
    GDExtensionConstVariantPtr self,
    GDExtensionInt index,
    GDExtensionUninitializedVariantPtr ret,
    GDExtensionBool* valid,
    GDExtensionBool* oob
);

struct GPUDriverContext {
    GPUCallMethodFunc call_method = nullptr;
    VariantGetIndexedFunc get_indexed = nullptr;
    GDExtensionVariantFromTypeConstructorFunc from_int = nullptr;
    GDExtensionVariantFromTypeConstructorFunc from_bool = nullptr;
    GDExtensionTypeFromVariantConstructorFunc to_int = nullptr;
    GDExtensionVariantPtr rd = nullptr;
};

} // namespace Arboria

#endif // VG_GPU_DRIVER_H
