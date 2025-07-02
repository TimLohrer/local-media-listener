package dev.timlohrer.lml.bridge

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
        val tempFile = createTempFile(outputFileName, if (suffix.isNotEmpty()) ".$suffix" else "").toFile()
        tempFile.deleteOnExit()

        inputStream.use { it.copyTo(FileOutputStream(tempFile)) }
        return tempFile
    }   

    fun loadNativeLibraryWithOptionalHelper(libName: String, helperExeName: String? = null): File? {
        val libFileName = when {
            isWindows -> "${libName}_windows_${arch}.dll"
            isLinux -> "lib${libName}_linux_${arch}.so"
            isMac -> "lib${libName}_darwin_${arch}.dylib"
            else -> throw UnsupportedOperationException("Unsupported OS: $osName")
        }
        
        println("Loading native library: $libFileName")

        val libPath = "/lib/$libFileName"
        val extractedLib = extractResource(libPath, libFileName)

        println("Extracted native library: $libFileName")
        
        System.load(extractedLib.absolutePath)
        
        println("Native library loaded successfully: ${extractedLib.absolutePath}")

        // If there's a helper executable (e.g., helper.exe), extract it
        val helperFile = helperExeName?.let {
            val helperPath = "/lib/$it"
            extractResource(helperPath, it)
        }

        return helperFile
    }
    
    fun unloadNativeLibrary(libName: String) {
        try {
            val libFileName = when {
                isWindows -> "${libName}_windows_${arch}.dll"
                isLinux -> "lib${libName}_linux_${arch}.so"
                isMac -> "lib${libName}_darwin_${arch}.dylib"
                else -> throw UnsupportedOperationException("Unsupported OS: $osName")
            }
            val libPath = "/lib/$libFileName"
            val extractedLib = extractResource(libPath, libFileName)
            System.load(extractedLib.absolutePath)
            println("Unloaded native library: ${extractedLib.absolutePath}")
        } catch (e: Exception) {
            println("Failed to unload native library: ${e.message}")
        }
    }
}
