#include "arboria_logger.h"
#include <iostream>

namespace Arboria {

ArboriaLogger::ArboriaLogger() = default;
ArboriaLogger::~ArboriaLogger() = default;

ArboriaLogger& ArboriaLogger::instance() {
    static ArboriaLogger logger;
    return logger;
}

void ArboriaLogger::set_level(LogLevel level) {
    m_level = level;
}

void ArboriaLogger::set_output_file(const std::string& filepath) {
    if (m_file_stream.is_open()) {
        m_file_stream.close();
    }
    if (!filepath.empty()) {
        m_file_stream.open(filepath, std::ios::out | std::ios::app);
    }
}

void ArboriaLogger::set_console_output(bool enabled) {
    m_console_output = enabled;
}

std::string ArboriaLogger::timestamp() {
    auto now = std::chrono::system_clock::now();
    auto time = std::chrono::system_clock::to_time_t(now);
    std::ostringstream ss;
    ss << std::put_time(std::localtime(&time), "%Y-%m-%d %H:%M:%S");
    return ss.str();
}

const char* ArboriaLogger::level_string(LogLevel level) {
    switch (level) {
        case LogLevel::DEBUG: return "DEBUG";
        case LogLevel::INFO:  return "INFO ";
        case LogLevel::WARN:  return "WARN ";
        case LogLevel::ERROR: return "ERROR";
        default:            return "UNKN ";
    }
}

std::string ArboriaLogger::format(LogLevel level, const std::string& message,
                                  const char* file, int line) {
    std::ostringstream ss;
    ss << "[" << timestamp() << "] [" << level_string(level) << "] ";
    if (file) {
        ss << file;
        if (line > 0) ss << ":" << line;
        ss << " - ";
    }
    ss << message;
    return ss.str();
}

void ArboriaLogger::log(LogLevel level, const std::string& message,
                        const char* file, int line) {
    std::lock_guard<std::mutex> lock(m_mutex);
    std::string formatted = format(level, message, file, line);

    if (m_console_output) {
        std::ostream& out = (level == LogLevel::ERROR) ? std::cerr : std::cout;
        out << formatted << std::endl;
    }

    if (m_file_stream.is_open()) {
        m_file_stream << formatted << std::endl;
        m_file_stream.flush();
    }
}

void ArboriaLogger::debug(const std::string& message, const char* file, int line) {
    if (m_level <= LogLevel::DEBUG) {
        log(LogLevel::DEBUG, message, file, line);
    }
}

void ArboriaLogger::info(const std::string& message, const char* file, int line) {
    if (m_level <= LogLevel::INFO) {
        log(LogLevel::INFO, message, file, line);
    }
}

void ArboriaLogger::warn(const std::string& message, const char* file, int line) {
    if (m_level <= LogLevel::WARN) {
        log(LogLevel::WARN, message, file, line);
    }
}

void ArboriaLogger::error(const std::string& message, const char* file, int line) {
    if (m_level <= LogLevel::ERROR) {
        log(LogLevel::ERROR, message, file, line);
    }
}

} // namespace Arboria
