package dev.timlohrer.lml.data

import kotlinx.serialization.Serializable

@Serializable
data class TransportMediaInfo(
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
    fun toMediaInfo(): MediaInfo {
        return MediaInfo(
            title = title,
            artist = artist,
            album = album,
            imageUrl = imageUrl,
            duration = duration?.replace(",", ".")?.toIntOrNull(),
            position = position?.replace(",", ".")?.toDoubleOrNull(),
            isPlaying = isPlaying,
            source = source,
            error = error
        )
    }
}
