package dev.timlohrer.lml

import dev.timlohrer.lml.bridge.NativeBridge
import dev.timlohrer.lml.bridge.NativeLoader
import dev.timlohrer.lml.data.MediaInfo
import dev.timlohrer.lml.networking.NativeHookClient
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.concurrent.atomic.AtomicBoolean

object LocalMediaListener {
    internal const val BASE_URL = "http://localhost:14565"
    internal const val BASE_WS_URL = "ws://localhost:14566"
    var isRunning = false
    internal var native: NativeBridge? = null
    internal var lastStartupShutdownTime: Long = 0
    private val shouldExit = AtomicBoolean(false)
    
    @JvmStatic
    fun main(args: Array<String>) {
        // Add shutdown hook for graceful cleanup
        Runtime.getRuntime().addShutdownHook(Thread {
            Logger.info("Received shutdown signal, cleaning up...")
            shouldExit.set(true)
            closeHook()
        })
        
        initialize { 
            onMediaChange { 
                Logger.info("Media change: ${it.toString()}")
            }
        }
        
        // Main loop that can be interrupted
        try {
            while (!shouldExit.get()) {
                Thread.sleep(1000)
            }
        } catch (e: InterruptedException) {
            Logger.info("Main thread interrupted, shutting down...")
            Thread.currentThread().interrupt()
        } finally {
            closeHook()
        }
        
        Logger.info("LocalMediaListener main loop exited.")
    }
    
    @Suppress("UNUSED")
    fun initialize(afterInitialized: (() -> Unit)? = null) {
        if (isRunning) {
            Logger.info("LocalMediaListener is already running.")
            return
        }
        
        Logger.info("Initializing LocalMediaListener...")

        lastStartupShutdownTime = System.currentTimeMillis()
        CoroutineScope(Dispatchers.IO).launch {
            CoroutineScope(Dispatchers.IO).launch {
                try {
                    // Check if native library is available before attempting to load
                    if (!NativeLoader.isNativeLibraryAvailable("native_hook")) {
                        Logger.error("Native library not available for current platform/architecture")
                        Logger.error("Platform: ${System.getProperty("os.name")}, Architecture: ${System.getProperty("os.arch")}")
                        return@launch
                    }
                    
                    Logger.debug("Native library is available, attempting to initialize NativeBridge...")
                    native = NativeBridge()
                } catch (e: Exception) {
                    Logger.error("Failed to initialize NativeBridge: ${e.message}")
                    Logger.error("Exception type: ${e.javaClass.simpleName}")
                    if (e is UnsatisfiedLinkError) {
                        Logger.error("This indicates the native library couldn't be loaded")
                        Logger.error("Check if the library was built for the correct platform/architecture")
                    }
                    return@launch
                }
            }
                
            // wait for the websocket to be available
            delay(3000)
            isRunning = true
            
            Logger.info("LocalMediaListener initialized successfully.")
    
            afterInitialized?.invoke()
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
        val now = System.currentTimeMillis()
        return (now - lastStartupShutdownTime > 3 * 1000) && (isRunning || !(NativeLoader.isWindows && NativeLoader.arch == "arm64"))
    }
    
    @Suppress("UNUSED")
    fun closeHook() {
        synchronized(this) {
            if (!isRunning || native == null) {
                Logger.info("LocalMediaListener is not running. No need to exit.")
                return
            }

            Logger.info("Shutting down LocalMediaListener...")
            lastStartupShutdownTime = System.currentTimeMillis()
            
            try {
                native!!.shutdownNativeHook()
            } catch (e: Exception) {
                Logger.error("Error during native shutdown: ${e.message}")
            } finally {
                native = null
                isRunning = false
                System.gc()
            }
            
            Logger.info("LocalMediaListener shutdown complete.")
        }
    }
}