package dev.timlohrer.lml.networking

import dev.timlohrer.lml.LocalMediaListener
import dev.timlohrer.lml.data.MediaInfo
import dev.timlohrer.lml.data.TransportMediaInfo
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import java.io.Closeable
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse

internal object NativeHookClient {
    val httpClient = HttpClient.newHttpClient()
    
    fun isNativeApiReady(): Boolean {
        if (LocalMediaListener.isRunning) {
            return true
        }
        
        val request = Request.Builder().url("${LocalMediaListener.BASE_URL}/ready").build()
        
        // NEIN INTELLIJ DAS IST NICHT UNREACHABLE CODE DU BASTARD
        return try {
            val response: Response = OkHttpClient().newCall(request).execute()
            response.isSuccessful
        } catch (e: Exception) {
            false
        }
    }
    
    fun getCurrentMediaInfo(): MediaInfo {
        if (!LocalMediaListener.isRunning) {
            println("LocalMediaListener is not running. Please initialize it before fetching any data!")
            return MediaInfo.stopped()
        }
        
        val request = HttpRequest.newBuilder()
            .uri(URI.create("${LocalMediaListener.BASE_URL}/now-playing"))
            .GET()
            .build()
        
        return try {
            val response = httpClient.send(request, HttpResponse.BodyHandlers.ofString())
            if (response.statusCode() != 200) {
                println("Failed to fetch current media info: ${response.statusCode()}")
                return MediaInfo.stopped()
            }
            val mediaInfo = Json.decodeFromString<TransportMediaInfo>(response.body()).toMediaInfo()
            mediaInfo.isPlaying = true
            mediaInfo
        } catch (e: Exception) {
            println("Error parsing media info: ${e.message}")
            MediaInfo.error("Error parsing media info: ${e.message}")
        }
    }
    
    fun subscribeToMediaChanges(onUpdate: (MediaInfo) -> Unit): Closeable {
        if (!LocalMediaListener.isRunning) {
            val errorMessage = "LocalMediaListener is not running. Please initialize it before subscribing!"
            println(errorMessage)
            onUpdate(MediaInfo.error(errorMessage))
            return Closeable { println("No-op closeable: LocalMediaListener not running.") }
        }

        val request = Request.Builder()
            .url("${LocalMediaListener.BASE_WS_URL}/now-playing/subscribe")
            .build()

        lateinit var currentWebSocket: WebSocket

        val webSocketListener = object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                println("WebSocket connection opened: ${response.message}")
                currentWebSocket = webSocket
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                try {
                    if (text.contains("stopped", ignoreCase = true)) {
                        onUpdate(MediaInfo.stopped())
                    } else {
                        val mediaInfo = Json.decodeFromString<TransportMediaInfo>(text).toMediaInfo()
                        mediaInfo.isPlaying = true
                        onUpdate(mediaInfo)
                    }
                } catch (e: Exception) {
                    println("Error parsing WebSocket message: $e, message: $text")
                    onUpdate(MediaInfo.error("Failed to parse media info: ${e.message}"))
                }
            }

            override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
                println("Received binary message (unhandled): ${bytes.hex()}")
            }

            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                println("WebSocket connection closing: code=$code, reason=$reason")
                webSocket.close(1000, null)
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                println("WebSocket connection closed: code=$code, reason=$reason")
                onUpdate(MediaInfo.stopped())
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                val responseMessage = response?.message ?: "No response"
                println("WebSocket connection failure: ${t.message}, response: $responseMessage")
                onUpdate(MediaInfo.error("WebSocket connection failed: ${t.message}"))
            }
        }

        val ws = OkHttpClient().newWebSocket(request, webSocketListener)
        currentWebSocket = ws
        
        return Closeable {
            println("Unsubscribing and closing WebSocket connection.")
            currentWebSocket.cancel()
        }
    }
        
    fun exitNativeHook() {
        if (!LocalMediaListener.isRunning) {
            println("LocalMediaListener is not running. No need to exit.")
            return
        }
        
        val request = HttpRequest.newBuilder()
            .uri(URI.create("${LocalMediaListener.BASE_URL}/exit"))
            .GET()
            .build()
        
        try {
            val response = httpClient.send(request, HttpResponse.BodyHandlers.ofString())
            if (response.statusCode() != 200) {
                println("Failed to exit NativeHook: ${response.statusCode()}")
                return
            }
        } catch (e: Exception) {
            println("Error exiting NativeHook: ${e.message}")
            return
        }
        
        LocalMediaListener.isRunning = false
        println("Exited NativeHook")
    }
}