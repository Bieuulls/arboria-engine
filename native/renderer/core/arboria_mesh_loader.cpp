#include "arboria_mesh_loader.h"
#include "arboria_logger.h"
#include <fstream>
#include <sstream>
#include <cstring>
#include <cctype>
#include <cmath>
#include <algorithm>
#include <map>

namespace Arboria {

// ============================================================================
// MINI JSON PARSER (suficiente para estrutura de glTF 2.0)
// ============================================================================

class JsonValue {
public:
    enum class Type { Null, Bool, Number, String, Array, Object };

    JsonValue() : type_(Type::Null), num_(0.0) {}
    static JsonValue make_null() { JsonValue v; v.type_ = Type::Null; return v; }
    static JsonValue make_bool(bool b) { JsonValue v; v.type_ = Type::Bool; v.bool_ = b; return v; }
    static JsonValue make_number(double n) { JsonValue v; v.type_ = Type::Number; v.num_ = n; return v; }
    static JsonValue make_string(std::string s) { JsonValue v; v.type_ = Type::String; v.str_ = std::move(s); return v; }
    static JsonValue make_array() { JsonValue v; v.type_ = Type::Array; return v; }
    static JsonValue make_object() { JsonValue v; v.type_ = Type::Object; return v; }

    Type type() const { return type_; }
    bool is_null() const { return type_ == Type::Null; }
    bool is_object() const { return type_ == Type::Object; }
    bool is_array() const { return type_ == Type::Array; }
    bool is_number() const { return type_ == Type::Number; }
    bool is_string() const { return type_ == Type::String; }

    bool as_bool() const { return bool_; }
    double as_number() const { return num_; }
    const std::string& as_string() const { return str_; }

    bool has(const std::string& key) const {
        if (type_ != Type::Object) return false;
        return std::find_if(obj_.begin(), obj_.end(),
            [&](const std::pair<std::string, JsonValue>& p) { return p.first == key; }) != obj_.end();
    }
    const JsonValue& at(const std::string& key) const {
        static const JsonValue null_v;
        if (type_ != Type::Object) return null_v;
        auto it = std::find_if(obj_.begin(), obj_.end(),
            [&](const std::pair<std::string, JsonValue>& p) { return p.first == key; });
        return (it != obj_.end()) ? it->second : null_v;
    }
    const JsonValue& at_index(size_t i) const {
        static const JsonValue null_v;
        return (type_ == Type::Array && i < arr_.size()) ? arr_[i] : null_v;
    }
    size_t size() const {
        if (type_ == Type::Array) return arr_.size();
        if (type_ == Type::Object) return obj_.size();
        return 0;
    }

    void set(const std::string& key, JsonValue v) {
        type_ = Type::Object;
        auto it = std::find_if(obj_.begin(), obj_.end(),
            [&](const std::pair<std::string, JsonValue>& p) { return p.first == key; });
        if (it != obj_.end()) it->second = std::move(v);
        else obj_.push_back({ key, std::move(v) });
    }
    void push(JsonValue v) { type_ = Type::Array; arr_.push_back(std::move(v)); }

private:
    Type type_;
    bool bool_ = false;
    double num_ = 0.0;
    std::string str_;
    std::vector<JsonValue> arr_;
    std::vector<std::pair<std::string, JsonValue>> obj_;
};

struct JsonParser {
    const char* p;
    const char* end;

    static std::string escape_string(const std::string& s) {
        std::string out;
        out.reserve(s.size());
        for (size_t i = 0; i < s.size(); ++i) {
            char c = s[i];
            if (c == '"' || c == '\\') { out.push_back('\\'); out.push_back(c); }
            else if (c == '\n') { out += "\\n"; }
            else if (c == '\r') { out += "\\r"; }
            else if (c == '\t') { out += "\\t"; }
            else { out.push_back(c); }
        }
        return out;
    }

    bool skip_ws() {
        while (p < end && (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r')) ++p;
        return p < end;
    }

    bool parse_string(std::string& out) {
        if (p >= end || *p != '"') return false;
        ++p;
        out.clear();
        while (p < end && *p != '"') {
            if (*p == '\\') {
                ++p;
                if (p >= end) return false;
                switch (*p) {
                    case '"': out.push_back('"'); break;
                    case '\\': out.push_back('\\'); break;
                    case '/': out.push_back('/'); break;
                    case 'b': out.push_back('\b'); break;
                    case 'f': out.push_back('\f'); break;
                    case 'n': out.push_back('\n'); break;
                    case 'r': out.push_back('\r'); break;
                    case 't': out.push_back('\t'); break;
                    case 'u': {
                        if (p + 4 >= end) return false;
                        unsigned int code = 0;
                        for (int k = 0; k < 4; ++k) {
                            char c = p[1 + k];
                            code <<= 4;
                            if (c >= '0' && c <= '9') code += c - '0';
                            else if (c >= 'a' && c <= 'f') code += c - 'a' + 10;
                            else if (c >= 'A' && c <= 'F') code += c - 'A' + 10;
                            else return false;
                        }
                        p += 4;
                        // UTF-16 -> UTF-8 (simplificado: BMP + pares surrogatos basicos)
                        if (code >= 0xD800 && code <= 0xDBFF && p + 1 < end && p[1] == '\\' && p[2] == 'u') {
                            unsigned int low = 0;
                            const char* q = p + 3;
                            for (int k = 0; k < 4; ++k) {
                                char c = q[k];
                                low <<= 4;
                                if (c >= '0' && c <= '9') low += c - '0';
                                else if (c >= 'a' && c <= 'f') low += c - 'a' + 10;
                                else if (c >= 'A' && c <= 'F') low += c - 'A' + 10;
                                else return false;
                            }
                            p += 6;
                            unsigned int cp = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00);
                            if (cp <= 0x7F) out.push_back((char)cp);
                            else if (cp <= 0x7FF) { out.push_back((char)(0xC0 | (cp >> 6))); out.push_back((char)(0x80 | (cp & 0x3F))); }
                            else if (cp <= 0xFFFF) { out.push_back((char)(0xE0 | (cp >> 12))); out.push_back((char)(0x80 | ((cp >> 6) & 0x3F))); out.push_back((char)(0x80 | (cp & 0x3F))); }
                            else { out.push_back((char)(0xF0 | (cp >> 18))); out.push_back((char)(0x80 | ((cp >> 12) & 0x3F))); out.push_back((char)(0x80 | ((cp >> 6) & 0x3F))); out.push_back((char)(0x80 | (cp & 0x3F))); }
                        } else if (code <= 0x7F) {
                            out.push_back((char)code);
                        } else if (code <= 0x7FF) {
                            out.push_back((char)(0xC0 | (code >> 6)));
                            out.push_back((char)(0x80 | (code & 0x3F)));
                        } else if (code <= 0xFFFF) {
                            out.push_back((char)(0xE0 | (code >> 12)));
                            out.push_back((char)(0x80 | ((code >> 6) & 0x3F)));
                            out.push_back((char)(0x80 | (code & 0x3F)));
                        } else {
                            out.push_back((char)(0xF0 | (code >> 18)));
                            out.push_back((char)(0x80 | ((code >> 12) & 0x3F)));
                            out.push_back((char)(0x80 | ((code >> 6) & 0x3F)));
                            out.push_back((char)(0x80 | (code & 0x3F)));
                        }
                        break;
                    }
                    default: return false;
                }
                ++p;
            } else {
                out.push_back(*p);
                ++p;
            }
        }
        if (p >= end || *p != '"') return false;
        ++p;
        return true;
    }

    bool parse_number(double& out) {
        const char* start = p;
        if (p < end && (*p == '-' || *p == '+')) ++p;
        while (p < end && (*p >= '0' && *p <= '9')) ++p;
        if (p < end && *p == '.') { ++p; while (p < end && (*p >= '0' && *p <= '9')) ++p; }
        bool has_exp = false;
        if (p < end && (*p == 'e' || *p == 'E')) {
            has_exp = true;
            ++p;
            if (p < end && (*p == '+' || *p == '-')) ++p;
            if (p >= end || !(*p >= '0' && *p <= '9')) return false;
            while (p < end && (*p >= '0' && *p <= '9')) ++p;
        }
        if (start == p) return false;
        std::string num_str(start, p - start);
        try { out = std::stod(num_str); } catch (...) { return false; }
        return true;
    }

    bool parse_literal(JsonValue& out) {
        if (p + 4 <= end && std::memcmp(p, "null", 4) == 0) { out = JsonValue::make_null(); p += 4; return true; }
        if (p + 4 <= end && std::memcmp(p, "true", 4) == 0) { out = JsonValue::make_bool(true); p += 4; return true; }
        if (p + 5 <= end && std::memcmp(p, "false", 5) == 0) { out = JsonValue::make_bool(false); p += 5; return true; }
        return false;
    }

    bool parse_value(JsonValue& out) {
        skip_ws();
        if (p >= end) return false;
        char c = *p;
        if (c == '"') {
            std::string s;
            if (!parse_string(s)) return false;
            out = JsonValue::make_string(std::move(s));
            return true;
        }
        if (c == '{') {
            ++p;
            JsonValue obj = JsonValue::make_object();
            skip_ws();
            if (p < end && *p == '}') { ++p; out = std::move(obj); return true; }
            while (true) {
                skip_ws();
                if (p >= end) return false;
                if (*p == '}') { ++p; break; }
                std::string key;
                if (!parse_string(key)) return false;
                skip_ws();
                if (p >= end || *p != ':') return false;
                ++p;
                JsonValue val;
                if (!parse_value(val)) return false;
                obj.set(key, std::move(val));
                skip_ws();
                if (p >= end) return false;
                if (*p == ',') { ++p; continue; }
                if (*p == '}') { ++p; break; }
                return false;
            }
            out = std::move(obj);
            return true;
        }
        if (c == '[') {
            ++p;
            JsonValue arr = JsonValue::make_array();
            skip_ws();
            if (p < end && *p == ']') { ++p; out = std::move(arr); return true; }
            while (true) {
                skip_ws();
                if (p < end && *p == ']') { ++p; break; }
                JsonValue val;
                if (!parse_value(val)) return false;
                arr.push(std::move(val));
                skip_ws();
                if (p >= end) return false;
                if (*p == ',') { ++p; continue; }
                if (*p == ']') { ++p; break; }
                return false;
            }
            out = std::move(arr);
            return true;
        }
        if (c == '-' || c == '+' || (c >= '0' && c <= '9')) {
            double n = 0.0;
            if (!parse_number(n)) return false;
            out = JsonValue::make_number(n);
            return true;
        }
        return parse_literal(out);
    }

    static JsonValue parse(const std::string& text) {
        JsonParser parser;
        parser.p = text.data();
        parser.end = text.data() + text.size();
        JsonValue root;
        if (!parser.parse_value(root)) return JsonValue::make_null();
        return root;
    }
};

// ============================================================================
// BASE64 DECODER (para buffers embutidos em glTF via data: URI)
// ============================================================================

static bool base64_decode(const std::string& in, std::vector<uint8_t>& out) {
    static const char* b64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    int val = 0, valb = -8;
    out.clear();
    for (unsigned char c : in) {
        if (c == '=') break;
        const char* pos = std::strchr(b64, c);
        if (!pos) continue;
        val = (val << 6) + (pos - b64);
        valb += 6;
        if (valb >= 0) {
            out.push_back((uint8_t)((val >> valb) & 0xFF));
            valb -= 8;
        }
    }
    return true;
}

// ============================================================================
// UTILITARIOS DE ARQUIVO
// ============================================================================

static std::string file_extension(const std::string& path) {
    size_t dot = path.find_last_of('.');
    if (dot == std::string::npos) return "";
    std::string ext = path.substr(dot + 1);
    std::transform(ext.begin(), ext.end(), ext.begin(), [](unsigned char c){ return (char)std::tolower(c); });
    return ext;
}

static std::string file_dir(const std::string& path) {
    size_t sep = path.find_last_of("/\\");
    if (sep == std::string::npos) return "";
    return path.substr(0, sep + 1);
}

static bool read_file_bytes(const std::string& path, std::vector<uint8_t>& out) {
    std::ifstream f(path, std::ios::binary | std::ios::ate);
    if (!f.is_open()) return false;
    size_t size = (size_t)f.tellg();
    f.seekg(0, std::ios::beg);
    out.resize(size);
    if (size > 0) f.read((char*)out.data(), size);
    return true;
}

static bool read_file_text(const std::string& path, std::string& out) {
    std::vector<uint8_t> bytes;
    if (!read_file_bytes(path, bytes)) return false;
    out.assign(bytes.begin(), bytes.end());
    return true;
}

// ============================================================================
// PARSER OBJ (Wavefront)
// ============================================================================

struct ObjVertexRef {
    int v = -1; // indice de posicao (0-based, -1 = nao informado)
    int vt = -1; // indice de texcoord
    int vn = -1; // indice de normal
};

static bool parse_obj_face_token(const std::string& tok, ObjVertexRef& ref) {
    ref.v = ref.vt = ref.vn = -1;
    size_t i = 0;
    // v
    if (i < tok.size() && tok[i] != '/') {
        size_t end = tok.find('/', i);
        std::string num = (end == std::string::npos) ? tok.substr(i) : tok.substr(i, end - i);
        if (!num.empty()) ref.v = std::stoi(num);
        i = end;
    }
    // vt
    if (i < tok.size() && tok[i] == '/') {
        ++i;
        size_t end = tok.find('/', i);
        std::string num = (end == std::string::npos) ? tok.substr(i) : tok.substr(i, end - i);
        if (!num.empty()) ref.vt = std::stoi(num);
        i = end;
    }
    // vn
    if (i < tok.size() && tok[i] == '/') {
        ++i;
        std::string num = tok.substr(i);
        if (!num.empty()) ref.vn = std::stoi(num);
    }
    return true;
}

static bool load_obj(const std::string& path, LoadedMesh& out) {
    std::string text;
    if (!read_file_text(path, text)) {
        out.error = "Nao foi possivel abrir arquivo OBJ: " + path;
        return false;
    }

    std::vector<float> positions; // 3 por vertice
    std::vector<float> normals;   // 3 por vertice
    std::vector<float> uvs;       // 2 por vertice
    std::vector<uint32_t> indices;

    std::istringstream iss(text);
    std::string line;
    while (std::getline(iss, line)) {
        // trim espacos iniciais
        size_t start = 0;
        while (start < line.size() && (line[start] == ' ' || line[start] == '\t')) ++start;
        if (start >= line.size()) continue;
        if (line[start] == '#') continue;

        // cabecalho de 2 caracteres
        if (line[start] == 'v' && line[start + 1] == ' ') {
            // v x y z [w]
            std::istringstream ls(line.substr(start + 1));
            float x = 0, y = 0, z = 0;
            if (ls >> x >> y >> z) {
                positions.push_back(x);
                positions.push_back(y);
                positions.push_back(z);
            }
        } else if (line[start] == 'v' && line[start + 1] == 'n' && (line[start + 2] == ' ' || line[start + 2] == '\t')) {
            // vn x y z
            std::istringstream ls(line.substr(start + 2));
            float x = 0, y = 0, z = 0;
            if (ls >> x >> y >> z) {
                normals.push_back(x);
                normals.push_back(y);
                normals.push_back(z);
            }
        } else if (line[start] == 'v' && line[start + 1] == 't' && (line[start + 2] == ' ' || line[start + 2] == '\t')) {
            // vt u v [w]
            std::istringstream ls(line.substr(start + 2));
            float u = 0, v = 0;
            if (ls >> u >> v) {
                uvs.push_back(u);
                uvs.push_back(v);
            }
        } else if (line[start] == 'f' && (line[start + 1] == ' ' || line[start + 1] == '\t')) {
            // f v1/vt1/vn1 ...
            std::istringstream ls(line.substr(start + 1));
            std::vector<ObjVertexRef> refs;
            std::string tok;
            while (ls >> tok) {
                ObjVertexRef ref;
                parse_obj_face_token(tok, ref);
                refs.push_back(ref);
            }
            if (refs.size() < 3) continue;
            // triangulacao em fanco (fan triangulation) para poligonos
            for (size_t k = 1; k + 1 < refs.size(); ++k) {
                indices.push_back((uint32_t)refs[0].v);
                indices.push_back((uint32_t)refs[k].v);
                indices.push_back((uint32_t)refs[k + 1].v);
            }
        }
    }

    // Converter indices OBJ (1-based, podendo ser negativos) para 0-based absolutos
    size_t npos = positions.size() / 3;
    for (size_t i = 0; i < indices.size(); ++i) {
        int v = (int)indices[i];
        if (v < 0) v = (int)npos + v + 1; // indice negativo e relativo ao final
        v -= 1; // 1-based -> 0-based
        if (v < 0 || v >= (int)npos) {
            out.error = "Indice de vertice fora do intervalo no OBJ: " + std::to_string(v);
            return false;
        }
        indices[i] = (uint32_t)v;
    }

    out.vertices = std::move(positions);
    out.normals = std::move(normals);
    out.uvs = std::move(uvs);
    out.indices = std::move(indices);
    out.valid = (!out.vertices.empty() && !out.indices.empty());
    if (!out.valid) out.error = "OBJ sem vertices ou indices validos: " + path;
    return out.valid;
}

// ============================================================================
// PARSER GLTF 2.0 (minimo)
// ============================================================================

struct GltfBuffer {
    std::vector<uint8_t> data;
    std::string uri;
};

struct GltfBufferView {
    uint32_t buffer = 0;
    uint32_t byteOffset = 0;
    uint32_t byteLength = 0;
    uint32_t byteStride = 0;
    bool valid = false;
};

struct GltfAccessor {
    uint32_t bufferView = 0;
    uint32_t byteOffset = 0;
    uint32_t componentType = 0; // 5120=BYTE,5121=UNSIGNED_BYTE,5122=SHORT,5123=UNSIGNED_SHORT,5125=UNSIGNED_INT,5126=FLOAT
    uint32_t count = 0;
    std::string type; // SCALAR, VEC2, VEC3, VEC4
    bool valid = false;
};

static uint32_t component_size(uint32_t ct) {
    switch (ct) {
        case 5120: case 5121: return 1;
        case 5122: case 5123: return 2;
        case 5125: return 4;
        case 5126: return 4;
        default: return 0;
    }
}

static uint32_t type_component_count(const std::string& type) {
    if (type == "SCALAR") return 1;
    if (type == "VEC2") return 2;
    if (type == "VEC3") return 3;
    if (type == "VEC4") return 4;
    return 0;
}

static bool load_gltf_buffers(const std::string& dir, const JsonValue& json, std::vector<GltfBuffer>& buffers) {
    if (!json.has("buffers")) return true;
    const JsonValue& arr = json.at("buffers");
    buffers.clear();
    for (size_t i = 0; i < arr.size(); ++i) {
        const JsonValue& b = arr.at_index(i);
        std::string uri = b.has("uri") ? b.at("uri").as_string() : "";
        GltfBuffer buf;
        if (uri.rfind("data:", 0) == 0) {
            // data:application/octet-binary;base64,...
            size_t comma = uri.find(',');
            if (comma != std::string::npos) {
                std::string b64 = uri.substr(comma + 1);
                base64_decode(b64, buf.data);
            }
        } else if (!uri.empty()) {
            std::string full = dir + uri;
            if (!read_file_bytes(full, buf.data)) {
                ARBORIA_LOG_ERROR("[ArboriaMeshLoader] Nao foi possivel ler buffer externo GLTF: " + full);
                return false;
            }
        }
        buffers.push_back(std::move(buf));
    }
    return true;
}

static bool build_buffer_views(const JsonValue& json, const std::vector<GltfBuffer>& buffers, std::vector<GltfBufferView>& views) {
    if (!json.has("bufferViews")) return true;
    const JsonValue& arr = json.at("bufferViews");
    views.clear();
    for (size_t i = 0; i < arr.size(); ++i) {
        const JsonValue& v = arr.at_index(i);
        GltfBufferView bv;
        bv.buffer = (uint32_t)(v.has("buffer") ? v.at("buffer").as_number() : 0);
        bv.byteOffset = (uint32_t)(v.has("byteOffset") ? v.at("byteOffset").as_number() : 0);
        bv.byteLength = (uint32_t)(v.has("byteLength") ? v.at("byteLength").as_number() : 0);
        bv.byteStride = (uint32_t)(v.has("byteStride") ? v.at("byteStride").as_number() : 0);
        bv.valid = (bv.buffer < buffers.size()) && (bv.byteLength > 0);
        views.push_back(bv);
    }
    return true;
}

static bool build_accessors(const JsonValue& json, std::vector<GltfAccessor>& accessors) {
    if (!json.has("accessors")) return true;
    const JsonValue& arr = json.at("accessors");
    accessors.clear();
    for (size_t i = 0; i < arr.size(); ++i) {
        const JsonValue& a = arr.at_index(i);
        GltfAccessor acc;
        acc.bufferView = (uint32_t)(a.has("bufferView") ? a.at("bufferView").as_number() : 0);
        acc.byteOffset = (uint32_t)(a.has("byteOffset") ? a.at("byteOffset").as_number() : 0);
        acc.componentType = (uint32_t)(a.has("componentType") ? a.at("componentType").as_number() : 0);
        acc.count = (uint32_t)(a.has("count") ? a.at("count").as_number() : 0);
        acc.type = a.has("type") ? a.at("type").as_string() : "";
        acc.valid = (acc.componentType != 0) && (acc.count > 0) && component_size(acc.componentType) > 0;
        accessors.push_back(acc);
    }
    return true;
}

// Extrai dados brutos de um accessor em um vector de float (1 componente por float)
static bool accessor_to_floats(const JsonValue& json, const std::vector<GltfBuffer>& buffers,
                               const std::vector<GltfBufferView>& views, const GltfAccessor& acc,
                               std::vector<float>& out) {
    if (!acc.valid) return false;
    if (acc.bufferView >= views.size()) return false;
    const GltfBufferView& bv = views[acc.bufferView];
    if (!bv.valid) return false;
    if (bv.buffer >= buffers.size()) return false;
    const std::vector<uint8_t>& buf = buffers[bv.buffer].data;

    uint32_t comp_size = component_size(acc.componentType);
    uint32_t comp_count = type_component_count(acc.type);
    if (comp_size == 0 || comp_count == 0) return false;

    uint64_t data_start = (uint64_t)bv.byteOffset + (uint64_t)acc.byteOffset;
    uint64_t stride = (bv.byteStride > 0) ? (uint64_t)bv.byteStride : (uint64_t)(comp_size * comp_count);
    uint64_t needed = data_start + (uint64_t)(acc.count - 1) * stride + (uint64_t)(comp_size * comp_count);
    if (needed > buf.size()) return false;

    out.clear();
    out.reserve(acc.count * comp_count);

    // Funcao para ler um componente como double
    auto read_comp = [&](uint64_t offset) -> double {
        if (offset + comp_size > buf.size()) return 0.0;
        switch (acc.componentType) {
            case 5120: return (double)(int8_t)buf[offset];
            case 5121: return (double)buf[offset];
            case 5122: return (double)(int16_t)(buf[offset] | (buf[offset + 1] << 8));
            case 5123: return (double)(uint16_t)(buf[offset] | (buf[offset + 1] << 8));
            case 5125: return (double)(uint32_t)(buf[offset] | (buf[offset + 1] << 8) | (buf[offset + 2] << 16) | (buf[offset + 3] << 24));
            case 5126: {
                float f;
                std::memcpy(&f, &buf[offset], 4);
                return (double)f;
            }
            default: return 0.0;
        }
    };

    for (uint32_t c = 0; c < acc.count; ++c) {
        uint64_t base = data_start + (uint64_t)c * stride;
        for (uint32_t k = 0; k < comp_count; ++k) {
            out.push_back((float)read_comp(base + (uint64_t)k * comp_size));
        }
    }
    return true;
}

// Extrai indices de um accessor SCALAR
static bool accessor_to_indices(const JsonValue& json, const std::vector<GltfBuffer>& buffers,
                                const std::vector<GltfBufferView>& views, const GltfAccessor& acc,
                                std::vector<uint32_t>& out) {
    if (!acc.valid) return false;
    if (acc.type != "SCALAR") return false;
    if (acc.bufferView >= views.size()) return false;
    const GltfBufferView& bv = views[acc.bufferView];
    if (!bv.valid) return false;
    if (bv.buffer >= buffers.size()) return false;
    const std::vector<uint8_t>& buf = buffers[bv.buffer].data;

    uint32_t comp_size = component_size(acc.componentType);
    if (comp_size == 0) return false;

    uint64_t data_start = (uint64_t)bv.byteOffset + (uint64_t)acc.byteOffset;
    uint64_t stride = (bv.byteStride > 0) ? (uint64_t)bv.byteStride : (uint64_t)comp_size;
    uint64_t needed = data_start + (uint64_t)(acc.count - 1) * stride + (uint64_t)comp_size;
    if (needed > buf.size()) return false;

    out.clear();
    out.reserve(acc.count);
    for (uint32_t c = 0; c < acc.count; ++c) {
        uint64_t off = data_start + (uint64_t)c * stride;
        uint32_t idx = 0;
        switch (acc.componentType) {
            case 5120: idx = (uint32_t)(int8_t)buf[off]; break;
            case 5121: idx = (uint32_t)buf[off]; break;
            case 5122: idx = (uint32_t)(int16_t)(buf[off] | (buf[off + 1] << 8)); break;
            case 5123: idx = (uint32_t)(uint16_t)(buf[off] | (buf[off + 1] << 8)); break;
            case 5125: idx = buf[off] | (buf[off + 1] << 8) | (buf[off + 2] << 16) | (buf[off + 3] << 24); break;
            default: return false;
        }
        out.push_back(idx);
    }
    return true;
}

static bool load_gltf(const std::string& path, LoadedMesh& out) {
    std::string text;
    if (!read_file_text(path, text)) {
        out.error = "Nao foi possivel abrir arquivo GLTF: " + path;
        return false;
    }

    JsonValue json = JsonParser::parse(text);
    if (json.is_null() || !json.is_object()) {
        out.error = "JSON invalido no GLTF: " + path;
        return false;
    }

    std::string dir = file_dir(path);

    std::vector<GltfBuffer> buffers;
    if (!load_gltf_buffers(dir, json, buffers)) return false;

    std::vector<GltfBufferView> views;
    build_buffer_views(json, buffers, views);

    std::vector<GltfAccessor> accessors;
    build_accessors(json, accessors);

    // Procurar o primeiro mesh com primitivo que tenha POSITION e INDICES
    if (!json.has("meshes")) {
        out.error = "GLTF sem meshes: " + path;
        return false;
    }
    const JsonValue& meshes = json.at("meshes");
    for (size_t m = 0; m < meshes.size(); ++m) {
        const JsonValue& mesh = meshes.at_index(m);
        if (!mesh.has("primitives")) continue;
        const JsonValue& prims = mesh.at("primitives");
        for (size_t p = 0; p < prims.size(); ++p) {
            const JsonValue& prim = prims.at_index(p);
            if (!prim.has("attributes")) continue;
            const JsonValue& attrs = prim.at("attributes");

            int pos_acc = -1, nor_acc = -1, uv_acc = -1, idx_acc = -1;
            if (attrs.has("POSITION")) pos_acc = (int)attrs.at("POSITION").as_number();
            if (attrs.has("NORMAL")) nor_acc = (int)attrs.at("NORMAL").as_number();
            if (attrs.has("TEXCOORD_0")) uv_acc = (int)attrs.at("TEXCOORD_0").as_number();
            if (prim.has("indices")) idx_acc = (int)prim.at("indices").as_number();

            if (pos_acc < 0 || (size_t)pos_acc >= accessors.size()) continue;
            if (idx_acc < 0 || (size_t)idx_acc >= accessors.size()) continue;

            std::vector<float> positions, normals, uvs;
            std::vector<uint32_t> indices;

            if (!accessor_to_floats(json, buffers, views, accessors[(size_t)pos_acc], positions)) continue;
            if (nor_acc >= 0 && (size_t)nor_acc < accessors.size()) {
                accessor_to_floats(json, buffers, views, accessors[(size_t)nor_acc], normals);
            }
            if (uv_acc >= 0 && (size_t)uv_acc < accessors.size()) {
                accessor_to_floats(json, buffers, views, accessors[(size_t)uv_acc], uvs);
            }
            if (!accessor_to_indices(json, buffers, views, accessors[(size_t)idx_acc], indices)) continue;

            if (positions.empty() || indices.empty()) continue;

            out.vertices = std::move(positions);
            out.normals = std::move(normals);
            out.uvs = std::move(uvs);
            out.indices = std::move(indices);
            out.valid = true;
            return true;
        }
    }

    out.error = "Nenhum mesh com POSITION + indices encontrado no GLTF: " + path;
    return false;
}

// ============================================================================
// PARSER GLB 2.0 (binario) — reutiliza a infraestrutura do GLTF texto
// ============================================================================

static bool load_glb(const std::string& path, LoadedMesh& out) {
    std::vector<uint8_t> bytes;
    if (!read_file_bytes(path, bytes)) {
        out.error = "Nao foi possivel abrir arquivo GLB: " + path;
        return false;
    }
    if (bytes.size() < 12) {
        out.error = "Arquivo GLB muito pequeno (header): " + path;
        return false;
    }

    // Cabecalho glB: magic "glTF" (0x46546C67 LE), versao 2, tamanho total
    uint32_t magic = (uint32_t)bytes[0] | ((uint32_t)bytes[1] << 8) | ((uint32_t)bytes[2] << 16) | ((uint32_t)bytes[3] << 24);
    uint32_t version = (uint32_t)bytes[4] | ((uint32_t)bytes[5] << 8) | ((uint32_t)bytes[6] << 16) | ((uint32_t)bytes[7] << 24);
    uint32_t length = (uint32_t)bytes[8] | ((uint32_t)bytes[9] << 8) | ((uint32_t)bytes[10] << 16) | ((uint32_t)bytes[11] << 24);

    if (magic != 0x46546C67u) {
        out.error = "Magic GLB invalido: " + path;
        return false;
    }
    if (version != 2) {
        out.error = "Versao GLB nao suportada (esperado 2, obtido " + std::to_string(version) + "): " + path;
        return false;
    }
    if ((uint32_t)bytes.size() < length) {
        out.error = "Arquivo GLB truncado: " + path;
        return false;
    }

    // Percorrer chunks: JSON e BIN
    std::string json_text;
    std::vector<uint8_t> bin_data;
    size_t offset = 12;
    while (offset + 8 <= length) {
        uint32_t chunkLen = (uint32_t)bytes[offset] | ((uint32_t)bytes[offset + 1] << 8) |
                            ((uint32_t)bytes[offset + 2] << 16) | ((uint32_t)bytes[offset + 3] << 24);
        uint32_t chunkType = (uint32_t)bytes[offset + 4] | ((uint32_t)bytes[offset + 5] << 8) |
                             ((uint32_t)bytes[offset + 6] << 16) | ((uint32_t)bytes[offset + 7] << 24);
        offset += 8;
        if (offset + (size_t)chunkLen > length) break;

        if (chunkType == 0x4E4F534Au) {              // "JSON"
            json_text.assign(bytes.begin() + offset, bytes.begin() + offset + chunkLen);
        } else if (chunkType == 0x004E4942u) {        // "BIN"
            bin_data.assign(bytes.begin() + offset, bytes.begin() + offset + chunkLen);
        }
        offset += chunkLen;
    }

    if (json_text.empty()) {
        out.error = "Chunk JSON nao encontrado no GLB: " + path;
        return false;
    }

    JsonValue json = JsonParser::parse(json_text);
    if (json.is_null() || !json.is_object()) {
        out.error = "JSON invalido no GLB: " + path;
        return false;
    }

    std::string dir = file_dir(path);

    // Configurar buffers: dados BIN embutidos como buffer 0; buffers restantes
    // (se houver) carregados por URI (externo) ou data: URI.
    std::vector<GltfBuffer> buffers;
    if (json.has("buffers")) {
        const JsonValue& arr = json.at("buffers");
        buffers.resize(arr.size());
        if (!bin_data.empty() && arr.size() > 0) {
            buffers[0].data = std::move(bin_data);
        }
        for (size_t i = 0; i < arr.size(); ++i) {
            const JsonValue& b = arr.at_index(i);
            std::string uri = b.has("uri") ? b.at("uri").as_string() : "";
            if (i == 0 && !buffers[0].data.empty()) continue; // ja carregado do chunk BIN
            if (uri.rfind("data:", 0) == 0) {
                size_t comma = uri.find(',');
                if (comma != std::string::npos) {
                    std::string b64 = uri.substr(comma + 1);
                    base64_decode(b64, buffers[i].data);
                }
            } else if (!uri.empty()) {
                std::string full = dir + uri;
                if (!read_file_bytes(full, buffers[i].data)) {
                    ARBORIA_LOG_ERROR("[ArboriaMeshLoader] Nao foi possivel ler buffer externo GLB: " + full);
                    return false;
                }
            }
        }
    }

    std::vector<GltfBufferView> views;
    build_buffer_views(json, buffers, views);

    std::vector<GltfAccessor> accessors;
    build_accessors(json, accessors);

    if (!json.has("meshes")) {
        out.error = "GLB sem meshes: " + path;
        return false;
    }
    const JsonValue& meshes = json.at("meshes");
    for (size_t m = 0; m < meshes.size(); ++m) {
        const JsonValue& mesh = meshes.at_index(m);
        if (!mesh.has("primitives")) continue;
        const JsonValue& prims = mesh.at("primitives");
        for (size_t p = 0; p < prims.size(); ++p) {
            const JsonValue& prim = prims.at_index(p);
            if (!prim.has("attributes")) continue;
            const JsonValue& attrs = prim.at("attributes");

            int pos_acc = -1, nor_acc = -1, uv_acc = -1, idx_acc = -1;
            if (attrs.has("POSITION")) pos_acc = (int)attrs.at("POSITION").as_number();
            if (attrs.has("NORMAL")) nor_acc = (int)attrs.at("NORMAL").as_number();
            if (attrs.has("TEXCOORD_0")) uv_acc = (int)attrs.at("TEXCOORD_0").as_number();
            if (prim.has("indices")) idx_acc = (int)prim.at("indices").as_number();

            if (pos_acc < 0 || (size_t)pos_acc >= accessors.size()) continue;
            if (idx_acc < 0 || (size_t)idx_acc >= accessors.size()) continue;

            std::vector<float> positions, normals, uvs;
            std::vector<uint32_t> indices;

            if (!accessor_to_floats(json, buffers, views, accessors[(size_t)pos_acc], positions)) continue;
            if (nor_acc >= 0 && (size_t)nor_acc < accessors.size()) {
                accessor_to_floats(json, buffers, views, accessors[(size_t)nor_acc], normals);
            }
            if (uv_acc >= 0 && (size_t)uv_acc < accessors.size()) {
                accessor_to_floats(json, buffers, views, accessors[(size_t)uv_acc], uvs);
            }
            if (!accessor_to_indices(json, buffers, views, accessors[(size_t)idx_acc], indices)) continue;

            if (positions.empty() || indices.empty()) continue;

            out.vertices = std::move(positions);
            out.normals = std::move(normals);
            out.uvs = std::move(uvs);
            out.indices = std::move(indices);
            out.valid = true;
            return true;
        }
    }

    out.error = "Nenhum mesh com POSITION + indices encontrado no GLB: " + path;
    return false;
}

// ============================================================================
// DISPATCHER PUBLICO
// ============================================================================

LoadedMesh load_mesh_file(const std::string& filepath) {
    LoadedMesh result;
    if (filepath.empty()) {
        result.error = "Caminho do arquivo vazio.";
        return result;
    }

    std::string ext = file_extension(filepath);
    if (ext == "obj") {
        if (!load_obj(filepath, result)) {
            ARBORIA_LOG_ERROR("[ArboriaMeshLoader] " + result.error);
        }
        return result;
    }
    if (ext == "gltf") {
        if (!load_gltf(filepath, result)) {
            ARBORIA_LOG_ERROR("[ArboriaMeshLoader] " + result.error);
        }
        return result;
    }
    if (ext == "glb") {
        if (!load_glb(filepath, result)) {
            ARBORIA_LOG_ERROR("[ArboriaMeshLoader] " + result.error);
        }
        return result;
    }

    result.error = "Extensao nao suportada para carregamento de malha: ." + ext + " (arquivo: " + filepath + ")";
    ARBORIA_LOG_ERROR("[ArboriaMeshLoader] " + result.error);
    return result;
}

// ============================================================================
// Gate 10 — Importacao em Lote
// ============================================================================

std::vector<BatchImportResult> load_mesh_batch(const std::vector<std::string>& filepaths) {
    std::vector<BatchImportResult> results;
    results.reserve(filepaths.size());

    for (const auto& fp : filepaths) {
        BatchImportResult r;
        r.filepath = fp;
        r.mesh = load_mesh_file(fp);
        r.success = r.mesh.valid;
        if (!r.success) {
            ARBORIA_LOG_ERROR("[ArboriaMeshLoader] Batch import falhou: " + fp + " — " + r.mesh.error);
        }
        results.push_back(std::move(r));
    }

    return results;
}

// ============================================================================
// Gate 10 — Validacao de Integridade
// ============================================================================

MeshIntegrityReport validate_mesh_integrity(const LoadedMesh& mesh) {
    MeshIntegrityReport report;

    report.vertex_count = static_cast<uint32_t>(mesh.vertices.size() / 3);
    report.index_count = static_cast<uint32_t>(mesh.indices.size());
    report.triangle_count = report.index_count / 3;

    // Verificacao basica: vertices e indices nao vazios
    if (mesh.vertices.empty()) {
        report.valid = false;
        report.errors.push_back("Malha nao contem vertices.");
    }
    if (mesh.indices.empty()) {
        report.valid = false;
        report.errors.push_back("Malha nao contem indices.");
    }

    // Contagem de indices deve ser multiplo de 3 (triangulos)
    if (report.index_count % 3 != 0) {
        report.valid = false;
        report.errors.push_back("Contagem de indices (" + std::to_string(report.index_count) +
                                ") nao e multiplo de 3.");
    }

    // Indices dentro do intervalo de vertices
    uint32_t nverts = report.vertex_count;
    for (uint32_t i = 0; i < report.index_count; ++i) {
        if (mesh.indices[i] >= nverts) {
            report.has_out_of_range_indices = true;
            report.valid = false;
            report.errors.push_back("Index fora do intervalo na posicao " +
                                    std::to_string(i) + ": " + std::to_string(mesh.indices[i]) +
                                    " (maximo valido: " + std::to_string(nverts - 1) + ").");
            break;  // reportar apenas o primeiro
        }
    }

    // Triangulos degenerados (3 indices iguais)
    for (uint32_t t = 0; t + 2 < report.index_count; t += 3) {
        uint32_t i0 = mesh.indices[t];
        uint32_t i1 = mesh.indices[t + 1];
        uint32_t i2 = mesh.indices[t + 2];
        if (i0 == i1 && i1 == i2) {
            report.has_degenerate_triangles = true;
            report.warnings.push_back("Triangulo degenerado no indice " + std::to_string(t) +
                                      ": todos os indices iguais a " + std::to_string(i0) + ".");
        }
    }

    // Normais e UVs ausentes (avisos, nao erros)
    if (mesh.normals.empty()) {
        report.missing_normals = true;
        report.warnings.push_back("Malha sem normais — iluminacao pode ficar sem sombreamento adequado.");
    }
    if (mesh.uvs.empty()) {
        report.missing_uvs = true;
        report.warnings.push_back("Malha sem UVs — texturizacao nao sera possivel.");
    }

    return report;
}

} // namespace Arboria
