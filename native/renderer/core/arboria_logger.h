#ifndef ARBORIA_LOGGER_H
#define ARBORIA_LOGGER_H

#include "arboria_types.h"
#include <string>
#include <mutex>
#include <fstream>
#include <chrono>
#include <iomanip>
#include <sstream>

namespace Arboria {

// Níveis de log do ARBORIA ENGINE
enum class LogLevel : uint8_t {
    DEBUG = 0,
    INFO = 1,
    WARN = 2,
    ERROR = 3
};

// Logger com níveis, saída para console e/ou arquivo, e macros
// desabilitáveis em compilação release via ARBORIA_DISABLE_LOGGING.
class ARBORIA_CLASS ArboriaLogger {
public:
    static ArboriaLogger& instance();

    void set_level(LogLevel level);
    void set_output_file(const std::string& filepath);
    void set_console_output(bool enabled);

    void log(LogLevel level, const std::string& message,
             const char* file = nullptr, int line = 0);

    // Atalhos por nível (respeitam m_level)
    void debug(const std::string& message, const char* file = nullptr, int line = 0);
    void info(const std::string& message, const char* file = nullptr, int line = 0);
    void warn(const std::string& message, const char* file = nullptr, int line = 0);
    void error(const std::string& message, const char* file = nullptr, int line = 0);

private:
    ArboriaLogger();
    ~ArboriaLogger();

    LogLevel m_level = LogLevel::INFO;
    bool m_console_output = true;
    std::ofstream m_file_stream;
    std::mutex m_mutex;

    std::string timestamp();
    const char* level_string(LogLevel level);
    std::string format(LogLevel level, const std::string& message,
                       const char* file, int line);
};

} // namespace Arboria

// Macros de conveniência — em release (ARBORIA_DISABLE_LOGGING definido),
// chamadas de DEBUG são removidas em tempo de compilação.
#ifdef ARBORIA_DISABLE_LOGGING
#define ARBORIA_LOG_DEBUG(msg)
#define ARBORIA_LOG_INFO(msg)
#define ARBORIA_LOG_WARN(msg)
#define ARBORIA_LOG_ERROR(msg)
#else
#define ARBORIA_LOG_DEBUG(msg) ::Arboria::ArboriaLogger::instance().debug(msg, __FILE__, __LINE__)
#define ARBORIA_LOG_INFO(msg)  ::Arboria::ArboriaLogger::instance().info(msg, __FILE__, __LINE__)
#define ARBORIA_LOG_WARN(msg)  ::Arboria::ArboriaLogger::instance().warn(msg, __FILE__, __LINE__)
#define ARBORIA_LOG_ERROR(msg) ::Arboria::ArboriaLogger::instance().error(msg, __FILE__, __LINE__)
#endif

#endif // ARBORIA_LOGGER_H
