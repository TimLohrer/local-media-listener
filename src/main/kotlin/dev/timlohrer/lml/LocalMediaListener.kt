package dev.timlohrer.lml

import dev.timlohrer.lml.bridge.NativeBridge
import dev.timlohrer.lml.bridge.NativeLoader
import dev.timlohrer.lml.data.MediaInfo
import dev.timlohrer.lml.networking.NativeHookClient
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

object LocalMediaListener {
    internal const val BASE_URL = "http://localhost:14565"
    internal const val BASE_WS_URL = "ws://localhost:14565"
    var isRunning = false
    internal var native: NativeBridge? = null
    internal var lastStartupShutdownTime: Long = 0
    
    @JvmStatic
    fun main(args: Array<String>) {
        initialize { 
            onMediaChange { 
                println(it.toString())
            }
        }
        while (true) {
            Thread.sleep(1000)
        }
    }
    
    @Suppress("UNUSED")
    fun initialize(afterInitialized: (() -> Unit)? = null) {
        if (isRunning) {
            println("LocalMediaListener is already running.")
            return
        }
        
        println("Initializing LocalMediaListener...")

        lastStartupShutdownTime = System.currentTimeMillis()
        CoroutineScope(Dispatchers.IO).launch {
            CoroutineScope(Dispatchers.IO).launch {
                try {
                    native = NativeBridge()
                } catch (e: Exception) {
                    println("Failed to initialize NativeBridge: ${e.message}")
                    return@launch
                }
            }
                
            // wait for the websocket to be available
            delay(1000)
            isRunning = true
            
            println("LocalMediaListener initialized successfully.")
    
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
        if (!isRunning || native == null) {
            println("LocalMediaListener is not running. No need to exit.")
            return
        }

        println("Shutting down LocalMediaListener...")
        lastStartupShutdownTime = System.currentTimeMillis()
        
        native!!.shutdownNativeHook()
        System.gc()
        isRunning = false
    }
}