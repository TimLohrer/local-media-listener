package dev.timlohrer.lml.bridge

internal class NativeBridge {
    
    init {
        NativeLoader.loadNativeLibraryWithOptionalHelper("native_hook")
        initNativeHook()
    }
    
    external fun initNativeHook()
    external fun shutdownNativeHook()
}