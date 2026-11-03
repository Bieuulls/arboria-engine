#ifndef ARBORIA_ABI_H
#define ARBORIA_ABI_H

#include "../core/arboria_types.h"
#include "../core/arboria_handle.h"
#include "../core/gdextension_interface.h"
#include <cstring>
#include <string>
#include <vector>
#include <iostream>

namespace Arboria {

class ABI {
public:
    static GDExtensionInterfaceGetProcAddress get_proc_address;
    static GDExtensionClassLibraryPtr library;

    // String & StringName
    static GDExtensionInterfaceStringNameNewWithUtf8Chars string_name_new_utf8;
    static GDExtensionInterfaceStringNewWithUtf8Chars string_new_utf8;
    static GDExtensionInterfaceStringToUtf8Chars string_to_utf8;

    // Variant constructors / destructors
    static GDExtensionInterfaceGetVariantFromTypeConstructor get_variant_from_type_c;
    static GDExtensionInterfaceGetVariantToTypeConstructor get_variant_to_type_c;
    static GDExtensionInterfaceVariantGetPtrConstructor variant_get_ptr_constructor;
    static GDExtensionInterfaceVariantGetPtrDestructor variant_get_ptr_destructor;
    static GDExtensionInterfaceVariantDestroy variant_destroy;
    static GDExtensionInterfaceVariantSetNamed variant_set_named;
    static GDExtensionInterfaceVariantGetNamed variant_get_named;
    static GDExtensionInterfaceVariantCall variant_call;
    static GDExtensionInterfaceVariantGetIndexed variant_get_indexed;

    // Type converters
    static GDExtensionVariantFromTypeConstructorFunc from_bool;
    static GDExtensionVariantFromTypeConstructorFunc from_int;
    static GDExtensionVariantFromTypeConstructorFunc from_float;
    static GDExtensionVariantFromTypeConstructorFunc from_string;
    static GDExtensionVariantFromTypeConstructorFunc from_dictionary;

    static GDExtensionTypeFromVariantConstructorFunc to_bool;
    static GDExtensionTypeFromVariantConstructorFunc to_int;
    static GDExtensionTypeFromVariantConstructorFunc to_float;
    static GDExtensionTypeFromVariantConstructorFunc to_string;
    static GDExtensionTypeFromVariantConstructorFunc to_transform3d;
    static GDExtensionTypeFromVariantConstructorFunc to_projection;
    static GDExtensionTypeFromVariantConstructorFunc to_vector3;
    static GDExtensionTypeFromVariantConstructorFunc to_vector2;

    // Type destructors
    static GDExtensionPtrDestructor string_name_destructor;
    static GDExtensionPtrDestructor string_destructor;
    static GDExtensionPtrDestructor dictionary_destructor;
    static GDExtensionPtrConstructor dictionary_default_constructor;

    static void init(GDExtensionInterfaceGetProcAddress p_get_proc_address, GDExtensionClassLibraryPtr p_library) {
        get_proc_address = p_get_proc_address;
        library = p_library;

        if (!get_proc_address) return;

        string_name_new_utf8 = (GDExtensionInterfaceStringNameNewWithUtf8Chars)get_proc_address("string_name_new_with_utf8_chars");
        string_new_utf8 = (GDExtensionInterfaceStringNewWithUtf8Chars)get_proc_address("string_new_with_utf8_chars");
        string_to_utf8 = (GDExtensionInterfaceStringToUtf8Chars)get_proc_address("string_to_utf8_chars");

        get_variant_from_type_c = (GDExtensionInterfaceGetVariantFromTypeConstructor)get_proc_address("get_variant_from_type_constructor");
        get_variant_to_type_c = (GDExtensionInterfaceGetVariantToTypeConstructor)get_proc_address("get_variant_to_type_constructor");
        variant_get_ptr_constructor = (GDExtensionInterfaceVariantGetPtrConstructor)get_proc_address("variant_get_ptr_constructor");
        variant_get_ptr_destructor = (GDExtensionInterfaceVariantGetPtrDestructor)get_proc_address("variant_get_ptr_destructor");
        variant_destroy = (GDExtensionInterfaceVariantDestroy)get_proc_address("variant_destroy");
        variant_set_named = (GDExtensionInterfaceVariantSetNamed)get_proc_address("variant_set_named");
        variant_get_named = (GDExtensionInterfaceVariantGetNamed)get_proc_address("variant_get_named");
        variant_call = (GDExtensionInterfaceVariantCall)get_proc_address("variant_call");
        variant_get_indexed = (GDExtensionInterfaceVariantGetIndexed)get_proc_address("variant_get_indexed");

        if (get_variant_from_type_c) {
            from_bool = get_variant_from_type_c(GDEXTENSION_VARIANT_TYPE_BOOL);
            from_int = get_variant_from_type_c(GDEXTENSION_VARIANT_TYPE_INT);
            from_float = get_variant_from_type_c(GDEXTENSION_VARIANT_TYPE_FLOAT);
            from_string = get_variant_from_type_c(GDEXTENSION_VARIANT_TYPE_STRING);
            from_dictionary = get_variant_from_type_c(GDEXTENSION_VARIANT_TYPE_DICTIONARY);
        }

        if (get_variant_to_type_c) {
            to_bool = get_variant_to_type_c(GDEXTENSION_VARIANT_TYPE_BOOL);
            to_int = get_variant_to_type_c(GDEXTENSION_VARIANT_TYPE_INT);
            to_float = get_variant_to_type_c(GDEXTENSION_VARIANT_TYPE_FLOAT);
            to_string = get_variant_to_type_c(GDEXTENSION_VARIANT_TYPE_STRING);
            to_transform3d = get_variant_to_type_c(GDEXTENSION_VARIANT_TYPE_TRANSFORM3D);
            to_projection = get_variant_to_type_c(GDEXTENSION_VARIANT_TYPE_PROJECTION);
            to_vector3 = get_variant_to_type_c(GDEXTENSION_VARIANT_TYPE_VECTOR3);
            to_vector2 = get_variant_to_type_c(GDEXTENSION_VARIANT_TYPE_VECTOR2);
        }

        if (variant_get_ptr_destructor) {
            string_name_destructor = variant_get_ptr_destructor(GDEXTENSION_VARIANT_TYPE_STRING_NAME);
            string_destructor = variant_get_ptr_destructor(GDEXTENSION_VARIANT_TYPE_STRING);
            dictionary_destructor = variant_get_ptr_destructor(GDEXTENSION_VARIANT_TYPE_DICTIONARY);
        }

        if (variant_get_ptr_constructor) {
            dictionary_default_constructor = variant_get_ptr_constructor(GDEXTENSION_VARIANT_TYPE_DICTIONARY, 0);
        }
    }
};

// RAII StringName tipado e imune a memory leak
class StringName {
public:
    alignas(8) uint8_t raw[8] = {0};

    StringName() {
        if (ABI::string_name_new_utf8) {
            ABI::string_name_new_utf8(raw, "");
        }
    }

    explicit StringName(const char* utf8) {
        if (ABI::string_name_new_utf8) {
            ABI::string_name_new_utf8(raw, utf8 ? utf8 : "");
        }
    }

    ~StringName() {
        if (ABI::string_name_destructor && *(uint64_t*)raw != 0) {
            ABI::string_name_destructor(raw);
        }
    }

    StringName(const StringName&) = delete;
    StringName& operator=(const StringName&) = delete;

    StringName(StringName&& other) noexcept {
        std::memcpy(raw, other.raw, sizeof(raw));
        std::memset(other.raw, 0, sizeof(other.raw));
    }

    StringName& operator=(StringName&& other) noexcept {
        if (this != &other) {
            if (ABI::string_name_destructor && *(uint64_t*)raw != 0) {
                ABI::string_name_destructor(raw);
            }
            std::memcpy(raw, other.raw, sizeof(raw));
            std::memset(other.raw, 0, sizeof(other.raw));
        }
        return *this;
    }

    GDExtensionStringNamePtr ptr() { return raw; }
    GDExtensionConstStringNamePtr ptr() const { return raw; }
};

// RAII String tipada
class String {
public:
    alignas(8) uint8_t raw[8] = {0};

    String() {
        if (ABI::string_new_utf8) {
            ABI::string_new_utf8(raw, "");
        }
    }

    explicit String(const char* utf8) {
        if (ABI::string_new_utf8) {
            ABI::string_new_utf8(raw, utf8 ? utf8 : "");
        }
    }

    ~String() {
        if (ABI::string_destructor && *(uint64_t*)raw != 0) {
            ABI::string_destructor(raw);
        }
    }

    String(const String&) = delete;
    String& operator=(const String&) = delete;

    String(String&& other) noexcept {
        std::memcpy(raw, other.raw, sizeof(raw));
        std::memset(other.raw, 0, sizeof(other.raw));
    }

    String& operator=(String&& other) noexcept {
        if (this != &other) {
            if (ABI::string_destructor && *(uint64_t*)raw != 0) {
                ABI::string_destructor(raw);
            }
            std::memcpy(raw, other.raw, sizeof(raw));
            std::memset(other.raw, 0, sizeof(other.raw));
        }
        return *this;
    }

    std::string to_utf8() const {
        if (!ABI::string_to_utf8) return "";
        char buf[2048] = {0};
        ABI::string_to_utf8(const_cast<uint8_t*>(raw), buf, sizeof(buf) - 1);
        return std::string(buf);
    }

    GDExtensionStringPtr ptr() { return raw; }
    GDExtensionConstStringPtr ptr() const { return raw; }
};

// RAII Dictionary tipado
class Dictionary {
public:
    alignas(8) uint8_t raw[8] = {0};

    Dictionary() {
        if (ABI::dictionary_default_constructor) {
            ABI::dictionary_default_constructor(raw, nullptr);
        }
    }

    ~Dictionary() {
        if (ABI::dictionary_destructor && *(uint64_t*)raw != 0) {
            ABI::dictionary_destructor(raw);
        }
    }

    Dictionary(const Dictionary&) = delete;
    Dictionary& operator=(const Dictionary&) = delete;

    Dictionary(Dictionary&& other) noexcept {
        std::memcpy(raw, other.raw, sizeof(raw));
        std::memset(other.raw, 0, sizeof(other.raw));
    }

    Dictionary& operator=(Dictionary&& other) noexcept {
        if (this != &other) {
            if (ABI::dictionary_destructor && *(uint64_t*)raw != 0) {
                ABI::dictionary_destructor(raw);
            }
            std::memcpy(raw, other.raw, sizeof(raw));
            std::memset(other.raw, 0, sizeof(other.raw));
        }
        return *this;
    }

    void set(const char* key, int64_t val) {
        if (ABI::variant_set_named && ABI::from_int && ABI::from_dictionary) {
            alignas(8) uint8_t dict_variant[24] = {0};
            ABI::from_dictionary(dict_variant, raw);

            StringName sn(key);
            alignas(8) uint8_t val_variant[24] = {0};
            ABI::from_int(val_variant, &val);

            uint8_t valid = 0;
            ABI::variant_set_named(dict_variant, sn.ptr(), val_variant, &valid);

            if (ABI::variant_destroy) {
                ABI::variant_destroy(val_variant);
                ABI::variant_destroy(dict_variant);
            }
        }
    }

    void set(const char* key, double val) {
        if (ABI::variant_set_named && ABI::from_float && ABI::from_dictionary) {
            alignas(8) uint8_t dict_variant[24] = {0};
            ABI::from_dictionary(dict_variant, raw);

            StringName sn(key);
            alignas(8) uint8_t val_variant[24] = {0};
            ABI::from_float(val_variant, &val);

            uint8_t valid = 0;
            ABI::variant_set_named(dict_variant, sn.ptr(), val_variant, &valid);

            if (ABI::variant_destroy) {
                ABI::variant_destroy(val_variant);
                ABI::variant_destroy(dict_variant);
            }
        }
    }

    void set(const char* key, const char* val) {
        if (ABI::variant_set_named && ABI::from_string && ABI::from_dictionary && ABI::string_new_utf8) {
            alignas(8) uint8_t dict_variant[24] = {0};
            ABI::from_dictionary(dict_variant, raw);

            StringName sn(key);
            String str_val(val);
            alignas(8) uint8_t val_variant[24] = {0};
            ABI::from_string(val_variant, str_val.ptr());

            uint8_t valid = 0;
            ABI::variant_set_named(dict_variant, sn.ptr(), val_variant, &valid);

            if (ABI::variant_destroy) {
                ABI::variant_destroy(val_variant);
                ABI::variant_destroy(dict_variant);
            }
        }
    }

    void set(const char* key, bool val) {
        if (ABI::variant_set_named && ABI::from_bool && ABI::from_dictionary) {
            alignas(8) uint8_t dict_variant[24] = {0};
            ABI::from_dictionary(dict_variant, raw);

            StringName sn(key);
            uint8_t b = val ? 1 : 0;
            alignas(8) uint8_t val_variant[24] = {0};
            ABI::from_bool(val_variant, &b);

            uint8_t valid = 0;
            ABI::variant_set_named(dict_variant, sn.ptr(), val_variant, &valid);

            if (ABI::variant_destroy) {
                ABI::variant_destroy(val_variant);
                ABI::variant_destroy(dict_variant);
            }
        }
    }

    void to_variant(GDExtensionVariantPtr r_dest) const {
        if (ABI::from_dictionary) {
            ABI::from_dictionary(r_dest, const_cast<uint8_t*>(raw));
        }
    }

    GDExtensionTypePtr ptr() { return raw; }
    GDExtensionConstTypePtr ptr() const { return raw; }
};

} // namespace Arboria

#endif // ARBORIA_ABI_H
