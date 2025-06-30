package dev.timlohrer.lml.bridge

internal class NativeBridge {
    init {
        NativeLoader.loadNativeLibraryWithOptionalHelper("native_hook")
        val windowsHelperFile = NativeLoader.loadNativeLibraryWithOptionalHelper("bridge")
        
        windowsHelperFile?.let {
            println("Helper executable extracted to: ${it.absolutePath}")
        }

        initNativeHook()
    }
    
    external fun initNativeHook()
}