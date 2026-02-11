package dev.timlohrer.lml

import dev.timlohrer.lml.data.MediaInfo
import dev.timlohrer.lml.networking.NativeHookClient
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.slf4j.LoggerFactory
import java.util.concurrent.atomic.AtomicBoolean

object LocalMediaListener {
    private val logger = LoggerFactory.getLogger(LocalMediaListener::class.java)
    var isRunning = false
    internal var lastStartupShutdownTime: Long = 0
    private val shouldExit = AtomicBoolean(false)
    
    @JvmStatic
    fun main(args: Array<String>) {
        // Add shutdown hook for graceful cleanup
        Runtime.getRuntime().addShutdownHook(Thread {
            logger.info("Received shutdown signal, cleaning up...")
            shouldExit.set(true)
            closeHook()
        })
        
        initialize { 
            onMediaChange { 
                logger.info(
                    "Media change: title='{}', artist='{}', album='{}', duration={}, position={}, isPlaying={}, source='{}', error='{}'",
                    it.title,
                    it.artist,
                    it.album,
                    it.duration,
                    it.position,
                    it.isPlaying,
                    it.source,
                    it.error
                )
            }
        }
        
        // Main loop that can be interrupted
        try {
            while (!shouldExit.get()) {
                Thread.sleep(1000)
            }
        } catch (e: InterruptedException) {
            logger.info("Main thread interrupted, shutting down...")
            Thread.currentThread().interrupt()
        } finally {
            closeHook()
        }
        
        logger.info("LocalMediaListener main loop exited.")
    }
    
    @Suppress("UNUSED")
    fun initialize(afterInitialized: (() -> Unit)? = null) {
        if (isRunning) {
            logger.info("LocalMediaListener is already running.")
            return
        }
        
        logger.info("Initializing LocalMediaListener...")

        lastStartupShutdownTime = System.currentTimeMillis()
        CoroutineScope(Dispatchers.IO).launch {
            try {
                if (!NativeHookClient.initialize()) {
                    logger.error("Failed to initialize LocalMediaListener backend.")
                    return@launch
                }

                isRunning = true
                logger.info("LocalMediaListener initialized successfully.")
                afterInitialized?.invoke()
            } catch (e: Exception) {
                logger.error("Failed to initialize LocalMediaListener", e)
            }
        }
    }
    
    @Suppress("UNUSED")
    fun getCurrentMediaInfo(): MediaInfo {
        return NativeHookClient.getCurrentMediaInfo()
    }
    
    @Suppress("UNUSED")
    fun onMediaChange(callback: (MediaInfo) -> Unit) {
        NativeHookClient.subscribeToMediaChanges(callback)
    }
    
    @Suppress("UNUSED")
    fun back(appName: String) {
        NativeHookClient.back(appName)
    }
    
    @Suppress("UNUSED")
    fun playPause(appName: String) {
        NativeHookClient.playPause(appName)
    }
    
    @Suppress("UNUSED")
    fun next(appName: String) {
        NativeHookClient.next(appName)
    }
    
    @Suppress("UNUSED")
    fun isAvailable(): Boolean {
        return isRunning || NativeHookClient.isNativeApiReady()
    }
    
    @Suppress("UNUSED")
    fun closeHook() {
        synchronized(this) {
            if (!isRunning) {
                logger.info("LocalMediaListener is not running. No need to exit.")
                return
            }

            logger.info("Shutting down LocalMediaListener...")
            lastStartupShutdownTime = System.currentTimeMillis()
            
            try {
                isRunning = false
                NativeHookClient.shutdown()
            } catch (e: Exception) {
                logger.error("Error during backend shutdown", e)
            }
            
            logger.info("LocalMediaListener shutdown complete.")
        }
    }
}
