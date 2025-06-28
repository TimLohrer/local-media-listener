package dev.timlohrer

import dev.timlohrer.bridge.NativeBridge
import dev.timlohrer.data.MediaInfo
import dev.timlohrer.networking.NativeHookClient

object LocalMediaListener {
    internal const val BASE_URL = "http://localhost:14565"
    internal const val BASE_WS_URL = "ws://localhost:14565"
    internal var isRunning = false
    
    @JvmStatic
    fun main(args: Array<String>) {}
    
    @Suppress("UNUSED")
    fun initialize() {
        if (isRunning) {
            println("LocalMediaListener is already running.")
            return
        }
        
        println("Initializing LocalMediaListener...")
        Thread {
            try {
                NativeBridge()
            } catch (e: Exception) {
                println("Failed to initialize NativeBridge: ${e.message}")
                return@Thread
            }
        }.start()

        while (!NativeHookClient.isNativeApiReady()) {
            Thread.sleep(200)
            isRunning = true
        }
        
        println("LocalMediaListener initialized successfully.")
        
        onMediaChange { info ->
            if (info.isStopped()) {
                println("No media is currently playing.")
            } else if (info.isError()) {
                println("Error: ${info.error}")
            } else {
                println("Now playing: ${info.title} by ${info.artist} from album ${info.album}")
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
    fun exit() {
        if (!isRunning) {
            println("LocalMediaListener is not running. No need to exit.")
            return
        }
        
        NativeHookClient.exitNativeHook()
    }
}