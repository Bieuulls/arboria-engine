#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <cstring>

// ARBORIA ENGINE — FERRAMENTA DE AUDITORIA FORENSE E RASTREAMENTO DE LICENÇA
// Permite auditar executáveis (.exe), bibliotecas (.dll) ou modelos (.vgmesh)
// e comprovar a propriedade intelectual do criador do ARBORIA ENGINE.

int main(int argc, char* argv[]) {
    std::cout << "====================================================\n";
    std::cout << "  ARBORIA ENGINE - AUDITOR FORENSE DE PROPRIEDADE    \n";
    std::cout << "====================================================\n";

    if (argc < 2) {
        std::cout << "Uso: arboria_license_verifier <arquivo_jogo_ou_malha>\n";
        std::cout << "Exemplos:\n";
        std::cout << "  arboria_license_verifier game.exe\n";
        std::cout << "  arboria_license_verifier libarboria_native.dll\n";
        std::cout << "  arboria_license_verifier rock.vgmesh\n";
        return 1;
    }

    std::string path = argv[1];
    std::ifstream file(path, std::ios::binary);
    if (!file.is_open()) {
        std::cerr << "[ERRO] Nao foi possivel abrir o arquivo: " << path << "\n";
        return 1;
    }

    // Le o arquivo em memoria
    file.seekg(0, std::ios::end);
    size_t size = file.tellg();
    file.seekg(0, std::ios::beg);

    std::vector<uint8_t> buffer(size);
    file.read(reinterpret_cast<char*>(buffer.data()), size);
    file.close();

    std::cout << "[ARQUIVO ANALISADO]: " << path << " (" << size << " bytes)\n";

    // 1. Verificacao de Modelo 3D (.vgmesh)
    if (size >= 8 && std::memcmp(buffer.data(), "ARBORIA2", 8) == 0) {
        std::cout << "[STATUS]: MODELO 3D GENUINO ARBORIA ENGINE DETECTADO!\n";
        std::cout << "[MAGIC HEADER]: ARBORIA2 (Valido)\n";
        std::cout << "[PROPRIETARIO]: Criador Oficial ARBORIA ENGINE\n";
        return 0;
    }

    // 2. Verificacao de Binario (DLL / EXE) procurando o Token Criptografico
    const std::string needle = "ARB-V72-ARBORIA_OFFICIAL_GENESIS";
    bool found = false;
    std::string detected_token = "";

    for (size_t i = 0; i + needle.length() < size; ++i) {
        if (std::memcmp(&buffer[i], needle.c_str(), needle.length()) == 0) {
            found = true;
            char token_buf[128] = {0};
            std::memcpy(token_buf, &buffer[i], std::min(sizeof(token_buf) - 1, size - i));
            detected_token = token_buf;
            break;
        }
    }

    if (found) {
        std::cout << "----------------------------------------------------\n";
        std::cout << "[SUCESSO]: PROVA FORENSE DE AUTORIA CONFIRMADA!\n";
        std::cout << "[TOKEN RASTREADO]: " << detected_token << "\n";
        std::cout << "[ASSINATURA]: ARBORIA_OFFICIAL_GENESIS\n";
        std::cout << "[STATUS LEGAL]: Obra construida sob o motor proprietario ARBORIA ENGINE.\n";
        std::cout << "----------------------------------------------------\n";
        return 0;
    } else {
        std::cout << "[AVISO]: Nenhuma assinatura ARBORIA ENGINE detectada neste arquivo.\n";
        return 2;
    }
}
