package dev.timlohrer.data

data class MediaInfo(
    val title: String,
    val artist: String,
    val album: String,
    val imageUrl: String? = null
)
