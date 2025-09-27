#include "Logger.h"
#include <iostream>
#include <sstream>
#include <chrono>
#include <iomanip>
#include <cstring>

// Static member initialization
Logger::Level Logger::currentLevel = Logger::Level::WARN;
bool Logger::useColors = true;

std::string Logger::getTimestamp() {
    auto now = std::chrono::system_clock::now();
    auto time_t = std::chrono::system_clock::to_time_t(now);
    auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
        now.time_since_epoch()) % 1000;
    
    std::ostringstream oss;
    oss << std::put_time(std::localtime(&time_t), "%Y-%m-%d %H:%M:%S");
    oss << '.' << std::setfill('0') << std::setw(3) << ms.count();
    return oss.str();
}

std::string Logger::getLevelString(Level level) {
    switch (level) {
        case Level::DEBUG: return "[DEBUG]";
        case Level::INFO:  return "[INFO ]";
        case Level::WARN:  return "[WARN ]";
        case Level::ERROR: return "[ERROR]";
        case Level::FATAL: return "[FATAL]";
        default:           return "[UNKWN]";
    }
}

std::string Logger::getColorCode(Level level) {
    if (!useColors) return "";
    
    switch (level) {
        case Level::DEBUG: return "\033[36m"; // Cyan
        case Level::INFO:  return "\033[32m"; // Green
        case Level::WARN:  return "\033[33m"; // Yellow
        case Level::ERROR: return "\033[31m"; // Red
        case Level::FATAL: return "\033[35m"; // Magenta
        default: return "\033[0m";
    }
}

std::string Logger::resetColor() {
    return useColors ? "\033[0m" : "";
}

std::string Logger::getGrayColor() {
    return useColors ? "\033[90m" : "";
}

std::string Logger::getBlueColor() {
    return useColors ? "\033[34m" : "";
}

void Logger::log(Level level, const std::string& message) {
    if (level < currentLevel) return;
    
    std::string timestamp = getTimestamp();
    std::string levelStr = getLevelString(level);
    std::string colorCode = getColorCode(level);
    std::string grayCode = getGrayColor();
    std::string blueCode = getBlueColor();
    std::string resetCode = resetColor();
    
    std::cout << blueCode << "[NATIVE] " << resetCode
              << grayCode << "[" << timestamp << "] " << resetCode
              << colorCode << levelStr << " " << resetCode
              << message << std::endl;
}

// Basic log level methods
void Logger::debug(const std::string& message) {
    log(Level::DEBUG, message);
}

void Logger::info(const std::string& message) {
    log(Level::INFO, message);
}

void Logger::warn(const std::string& message) {
    log(Level::WARN, message);
}

void Logger::error(const std::string& message) {
    log(Level::ERROR, message);
}

void Logger::fatal(const std::string& message) {
    log(Level::FATAL, message);
}

// Configuration methods
void Logger::setLevel(Level level) {
    currentLevel = level;
}

void Logger::setUseColors(bool use) {
    useColors = use;
}

Logger::Level Logger::getLevel() {
    return currentLevel;
}

bool Logger::getUseColors() {
    return useColors;
}

void formatHelper(std::ostringstream& oss, const std::string& format) {
    oss << format;
}

template<typename T, typename... Args>
void formatHelper(std::ostringstream& oss, const std::string& format, T value, Args... args) {
    size_t pos = format.find("{}");
    if (pos == std::string::npos) {
        oss << format;
        return;
    }
    
    oss << format.substr(0, pos);
    oss << value;
    formatHelper(oss, format.substr(pos + 2), args...);
}

template void formatHelper(std::ostringstream&, const std::string&, int);
template void formatHelper(std::ostringstream&, const std::string&, double);
template void formatHelper(std::ostringstream&, const std::string&, const std::string&);
template void formatHelper(std::ostringstream&, const std::string&, const char*);
template void formatHelper(std::ostringstream&, const std::string&, bool);
