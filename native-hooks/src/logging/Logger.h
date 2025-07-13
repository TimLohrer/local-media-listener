#ifndef LOGGER_H
#define LOGGER_H

#include <string>
#include <sstream>

// Avoid name collisions with the Windows API ERROR macro
#ifdef ERROR
#undef ERROR
#endif

class Logger {
public:
    enum class Level {
        DEBUG,
        INFO,
        WARN,
        ERROR,
        FATAL
    };

private:
    static Level currentLevel;
    static bool useColors;
    
    static std::string getTimestamp();
    static std::string getLevelString(Level level);
    static std::string getColorCode(Level level);
    static std::string resetColor();
    static std::string getGrayColor();
    static std::string getBlueColor();
    static void log(Level level, const std::string& message);

public:
    // log levels
    static void debug(const std::string& message);
    static void info(const std::string& message);
    static void warn(const std::string& message);
    static void error(const std::string& message);
    static void fatal(const std::string& message);
    
    // Format support
    template<typename... Args>
    static void debug(const std::string& format, Args... args);
    
    template<typename... Args>
    static void info(const std::string& format, Args... args);
    
    template<typename... Args>
    static void warn(const std::string& format, Args... args);
    
    template<typename... Args>
    static void error(const std::string& format, Args... args);
    
    template<typename... Args>
    static void fatal(const std::string& format, Args... args);
    
    // Configuration
    static void setLevel(Level level);
    static void setUseColors(bool use);
    static Level getLevel();
    static bool getUseColors();
    
    // Helper for string formatting
    template<typename... Args>
    static std::string format(const std::string& format, Args... args);
};

// Template stubs
template<typename... Args>
void Logger::debug(const std::string& format, Args... args) {
    debug(Logger::format(format, args...));
}

template<typename... Args>
void Logger::info(const std::string& format, Args... args) {
    info(Logger::format(format, args...));
}

template<typename... Args>
void Logger::warn(const std::string& format, Args... args) {
    warn(Logger::format(format, args...));
}

template<typename... Args>
void Logger::error(const std::string& format, Args... args) {
    error(Logger::format(format, args...));
}

template<typename... Args>
void Logger::fatal(const std::string& format, Args... args) {
    fatal(Logger::format(format, args...));
}

template<typename... Args>
std::string Logger::format(const std::string& format, Args... args) {
    std::ostringstream oss;
    formatHelper(oss, format, args...);
    return oss.str();
}

// Helper for formatting
void formatHelper(std::ostringstream& oss, const std::string& format);

template<typename T, typename... Args>
void formatHelper(std::ostringstream& oss, const std::string& format, T value, Args... args);

#endif