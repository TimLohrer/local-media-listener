package dev.timlohrer.lml.bridge

import dev.timlohrer.lml.Logger

internal class NativeBridge {
    
    init {
        try {
            Logger.debug("Attempting to load native library...")
            NativeLoader.loadNativeLibraryWithOptionalHelper("native_hook")
            Logger.debug("Native library loaded successfully, initializing native hook...")
            initNativeHook()
            Logger.info("NativeBridge initialized successfully")
        } catch (e: UnsatisfiedLinkError) {
            Logger.error("Failed to load native library: ${e.message}")
            Logger.error("This usually indicates the native library couldn't be found or loaded")
            throw e
        } catch (e: Exception) {
            Logger.error("Failed to initialize NativeBridge: ${e.message}")
            Logger.error("Exception type: ${e.javaClass.simpleName}")
            throw e
        }
    }
    
    external fun initNativeHook()
    external fun shutdownNativeHook()
}