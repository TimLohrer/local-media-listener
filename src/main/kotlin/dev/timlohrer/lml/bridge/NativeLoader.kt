package dev.timlohrer.lml.bridge

import dev.timlohrer.lml.Logger
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import kotlin.io.path.createTempFile

object NativeLoader {
    private val osName = System.getProperty("os.name").lowercase()
    val isWindows = osName.contains("win")
    val isMac = osName.contains("mac")
    val isLinux = osName.contains("nix") || osName.contains("nux") || osName.contains("aix")
    private val osArch = System.getProperty("os.arch")
    val arch = when {
        "x86" in osArch -> "amd64"
        "amd64" in osArch -> "amd64"
        "aarch64" in osArch -> "arm64"
        "arm" in osArch -> "arm64"
        else -> throw UnsupportedOperationException("Unsupported architecture: $osArch")
    }

    private fun extractResource(resourcePath: String, outputFileName: String): File {
        val inputStream: InputStream = NativeLoader::class.java.getResourceAsStream(resourcePath)
            ?: throw IllegalArgumentException("Resource not found: $resourcePath")

        val suffix = outputFileName.substringAfterLast('.', "")
        val tempFile = createTempFile(outputFileName, if (suffix.isNotEmpty()) ".${suffix}" else "").toFile()
        tempFile.deleteOnExit()

        // Ensure both streams are closed so the file handle is released on Windows
        inputStream.use { input ->
            FileOutputStream(tempFile).use { output ->
                input.copyTo(output)
            }
        }

        return tempFile
    }   

    fun loadNativeLibraryWithOptionalHelper(libName: String, helperExeName: String? = null): File? {
        val libFileName = when {
            isWindows -> "lib${libName}_windows_${arch}.dll"
            isLinux -> "lib${libName}_linux_${arch}.so"
            isMac -> "lib${libName}_darwin_${arch}.dylib"
            else -> throw UnsupportedOperationException("Unsupported OS: $osName")
        }
        
        Logger.debug("Loading native library: $libFileName")
        Logger.debug("Platform: $osName, Architecture: $arch")

        val libPath = "/lib/$libFileName"
        
        try {
            val extractedLib = extractResource(libPath, libFileName)
            Logger.debug("Extracted native library: $libFileName to ${extractedLib.absolutePath}")
            Logger.debug("File exists: ${extractedLib.exists()}, File size: ${extractedLib.length()} bytes")
            
            System.load(extractedLib.absolutePath)
            Logger.debug("Native library loaded successfully: ${extractedLib.absolutePath}")
            
        } catch (e: UnsatisfiedLinkError) {
            Logger.error("Failed to load native library: ${e.message}")
            Logger.error("Library path: $libPath")
            Logger.error("This could be due to missing dependencies or incompatible architecture")
            throw e
        } catch (e: IllegalArgumentException) {
            Logger.error("Resource not found: $libPath")
            Logger.error("Available resources in /lib/ directory may be missing")
            throw e
        } catch (e: Exception) {
            Logger.error("Unexpected error loading native library: ${e.message}")
            Logger.error("Exception type: ${e.javaClass.simpleName}")
            throw e
        }

        // If there's a helper executable (e.g., helper.exe), extract it
        val helperFile = helperExeName?.let {
            val helperPath = "/lib/$it"
            try {
                extractResource(helperPath, it)
            } catch (e: Exception) {
                Logger.warn("Failed to extract helper executable: ${e.message}")
                null
            }
        }

        return helperFile
    }
    
    fun isNativeLibraryAvailable(libName: String): Boolean {
        val libFileName = when {
            isWindows -> "lib${libName}_windows_${arch}.dll"
            isLinux -> "lib${libName}_linux_${arch}.so"
            isMac -> "lib${libName}_darwin_${arch}.dylib"
            else -> return false
        }
        
        val libPath = "/lib/$libFileName"
        return try {
            NativeLoader::class.java.getResourceAsStream(libPath) != null
        } catch (e: Exception) {
            Logger.debug("Error checking native library availability: ${e.message}")
            false
        }
    }
    
    fun unloadNativeLibrary(libName: String) {
        try {
            val libFileName = when {
                isWindows -> "lib${libName}_windows_${arch}.dll"
                isLinux -> "lib${libName}_linux_${arch}.so"
                isMac -> "lib${libName}_darwin_${arch}.dylib"
                else -> throw UnsupportedOperationException("Unsupported OS: $osName")
            }
            val libPath = "/lib/$libFileName"
            val extractedLib = extractResource(libPath, libFileName)
            System.load(extractedLib.absolutePath)
            Logger.debug("Unloaded native library: ${extractedLib.absolutePath}")
        } catch (e: Exception) {
            Logger.error("Failed to unload native library: ${e.message}")
        }
    }
}
