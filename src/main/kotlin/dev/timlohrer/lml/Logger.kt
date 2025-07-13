package dev.timlohrer.lml

import java.time.LocalDateTime
import java.time.format.DateTimeFormatter

object Logger {
    enum class Level {
        DEBUG, INFO, WARN, ERROR, FATAL
    }
    
    private var currentLevel = Level.DEBUG
    private var useColors = true
    
    private fun getTimestamp(): String {
        val now = LocalDateTime.now()
        val formatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss.SSS")
        return now.format(formatter)
    }
    
    private fun getLevelString(level: Level): String {
        return when (level) {
            Level.DEBUG -> "[DEBUG]"
            Level.INFO  -> "[INFO ]"
            Level.WARN  -> "[WARN ]"
            Level.ERROR -> "[ERROR]"
            Level.FATAL -> "[FATAL]"
        }
    }
    
    private fun getColorCode(level: Level): String {
        if (!useColors) return ""
        
        return when (level) {
            Level.DEBUG -> "\u001B[36m" // Cyan
            Level.INFO -> "\u001B[32m"  // Green
            Level.WARN -> "\u001B[33m"  // Yellow
            Level.ERROR -> "\u001B[31m" // Red
            Level.FATAL -> "\u001B[35m" // Magenta
        }
    }
    
    private fun resetColor(): String {
        return if (useColors) "\u001B[0m" else ""
    }
    
    private fun getGrayColor(): String {
        return if (useColors) "\u001B[90m" else ""
    }
    
    private fun getRedColor(): String {
        return if (useColors) "\u001B[31m" else ""
    }
    
    private fun log(level: Level, message: String) {
        if (level.ordinal < currentLevel.ordinal) return
        
        val timestamp = getTimestamp()
        val levelStr = getLevelString(level)
        val colorCode = getColorCode(level)
        val grayCode = getGrayColor()
        val redCode = getRedColor()
        val resetCode = resetColor()
        
        println("$redCode[ JAVA ]$resetCode $grayCode[$timestamp] $resetCode$colorCode$levelStr $resetCode$message")
    }
    
    // Log level methods
    fun debug(message: String) {
        log(Level.DEBUG, message)
    }
    
    fun info(message: String) {
        log(Level.INFO, message)
    }
    
    fun warn(message: String) {
        log(Level.WARN, message)
    }
    
    fun error(message: String) {
        log(Level.ERROR, message)
    }
    
    fun fatal(message: String) {
        log(Level.FATAL, message)
    }
    
    // Configuration methods
    fun setLevel(level: Level) {
        currentLevel = level
    }
    
    fun setUseColors(use: Boolean) {
        useColors = use
    }
    
    fun getLevel(): Level {
        return currentLevel
    }
    
    fun getUseColors(): Boolean {
        return useColors
    }
} 