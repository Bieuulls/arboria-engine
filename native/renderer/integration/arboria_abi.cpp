#include "arboria_abi.h"

namespace Arboria {

GDExtensionInterfaceGetProcAddress ABI::get_proc_address = nullptr;
GDExtensionClassLibraryPtr ABI::library = nullptr;

GDExtensionInterfaceStringNameNewWithUtf8Chars ABI::string_name_new_utf8 = nullptr;
GDExtensionInterfaceStringNewWithUtf8Chars ABI::string_new_utf8 = nullptr;
GDExtensionInterfaceStringToUtf8Chars ABI::string_to_utf8 = nullptr;

GDExtensionInterfaceGetVariantFromTypeConstructor ABI::get_variant_from_type_c = nullptr;
GDExtensionInterfaceGetVariantToTypeConstructor ABI::get_variant_to_type_c = nullptr;
GDExtensionInterfaceVariantGetPtrConstructor ABI::variant_get_ptr_constructor = nullptr;
GDExtensionInterfaceVariantGetPtrDestructor ABI::variant_get_ptr_destructor = nullptr;
GDExtensionInterfaceVariantDestroy ABI::variant_destroy = nullptr;
GDExtensionInterfaceVariantSetNamed ABI::variant_set_named = nullptr;
GDExtensionInterfaceVariantGetNamed ABI::variant_get_named = nullptr;
GDExtensionInterfaceVariantCall ABI::variant_call = nullptr;
GDExtensionInterfaceVariantGetIndexed ABI::variant_get_indexed = nullptr;

GDExtensionVariantFromTypeConstructorFunc ABI::from_bool = nullptr;
GDExtensionVariantFromTypeConstructorFunc ABI::from_int = nullptr;
GDExtensionVariantFromTypeConstructorFunc ABI::from_float = nullptr;
GDExtensionVariantFromTypeConstructorFunc ABI::from_string = nullptr;
GDExtensionVariantFromTypeConstructorFunc ABI::from_dictionary = nullptr;

GDExtensionTypeFromVariantConstructorFunc ABI::to_bool = nullptr;
GDExtensionTypeFromVariantConstructorFunc ABI::to_int = nullptr;
GDExtensionTypeFromVariantConstructorFunc ABI::to_float = nullptr;
GDExtensionTypeFromVariantConstructorFunc ABI::to_string = nullptr;
GDExtensionTypeFromVariantConstructorFunc ABI::to_transform3d = nullptr;
GDExtensionTypeFromVariantConstructorFunc ABI::to_projection = nullptr;
GDExtensionTypeFromVariantConstructorFunc ABI::to_vector3 = nullptr;
GDExtensionTypeFromVariantConstructorFunc ABI::to_vector2 = nullptr;

GDExtensionPtrDestructor ABI::string_name_destructor = nullptr;
GDExtensionPtrDestructor ABI::string_destructor = nullptr;
GDExtensionPtrDestructor ABI::dictionary_destructor = nullptr;
GDExtensionPtrConstructor ABI::dictionary_default_constructor = nullptr;

} // namespace Arboria
