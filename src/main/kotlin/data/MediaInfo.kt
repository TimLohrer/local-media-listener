package dev.timlohrer.data

import kotlinx.serialization.Serializable

@Serializable
data class MediaInfo(
    val title: String,
    val artist: String,
    val album: String,
    val imageUrl: String? = null,
    val duration: String? = null,
    val position: String? = null,
    var isPlaying: Boolean = false,
    val source: String,
    val error: String? = null,
) {
    companion object {
        fun stopped(): MediaInfo {
            return MediaInfo(
                title = "",
                artist = "",
                album = "",
                imageUrl = null,
                isPlaying = false,
                source = ""
            )
        }

        fun error(error: String): MediaInfo {
            return MediaInfo(
                title = "Error",
                artist = "Error",
                album = "Error",
                imageUrl = null,
                isPlaying = false,
                source = "Error",
                error = error
            )
        }
    }
    
    fun isStopped(): Boolean {
        return !isPlaying && title.isEmpty()
    }
    
    fun isError(): Boolean {
        return error != null
    }
}
