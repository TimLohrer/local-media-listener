package dev.timlohrer.lml.networking

import dev.timlohrer.lml.LocalMediaListener
import dev.timlohrer.lml.data.MediaInfo
import org.endlesssource.mediainterface.SystemMediaFactory
import org.endlesssource.mediainterface.api.MediaSession
import org.endlesssource.mediainterface.api.MediaSessionListener
import org.endlesssource.mediainterface.api.NowPlaying
import org.endlesssource.mediainterface.api.PlaybackState
import org.endlesssource.mediainterface.api.SystemMediaInterface
import org.endlesssource.mediainterface.api.SystemMediaOptions
import org.slf4j.LoggerFactory
import java.io.Closeable
import java.util.concurrent.atomic.AtomicReference

internal object NativeHookClient {
    private val logger = LoggerFactory.getLogger(NativeHookClient::class.java)
    @Volatile
    private var mediaInterface: SystemMediaInterface? = null

    @Synchronized
    fun initialize(): Boolean {
        if (mediaInterface != null) {
            return true
        }

        val support = SystemMediaFactory.getCurrentPlatformSupport()
        if (!support.available()) {
            logger.error("Media interface support unavailable: {}", support.reason())
            return false
        }

        return try {
            val options = SystemMediaOptions.defaults()
                .withEventDrivenEnabled(true)
                .withSessionPollInterval(java.time.Duration.ofMillis(250))
                .withSessionUpdateInterval(java.time.Duration.ofMillis(250))
            mediaInterface = SystemMediaFactory.createSystemInterface(options)
            true
        } catch (e: Exception) {
            logger.error("Failed to initialize mediainterface", e)
            false
        }
    }

    @Synchronized
    fun shutdown() {
        mediaInterface?.close()
        mediaInterface = null
    }

    fun isNativeApiReady(): Boolean {
        return mediaInterface != null
    }
    
    fun getCurrentMediaInfo(): MediaInfo {
        if (!LocalMediaListener.isRunning) {
            logger.warn("LocalMediaListener is not running. Please initialize it before fetching any data!")
            return MediaInfo.stopped()
        }

        val currentMediaInterface = mediaInterface ?: return MediaInfo.stopped()

        return try {
            val session = currentMediaInterface.getActiveSession()
                .orElseGet {
                    currentMediaInterface.getAllSessions().firstOrNull()
                }
                ?: return MediaInfo.stopped()
            sessionToMediaInfo(session)
        } catch (e: Exception) {
            logger.error("Error reading media info from mediainterface", e)
            MediaInfo.error("Error reading media info: ${e.message}")
        }
    }
    
    fun subscribeToMediaChanges(onUpdate: (MediaInfo) -> Unit): Closeable {
        if (!LocalMediaListener.isRunning) {
            val errorMessage = "LocalMediaListener is not running. Please initialize it before subscribing!"
            logger.warn(errorMessage)
            onUpdate(MediaInfo.error(errorMessage))
            return Closeable { logger.debug("No-op closeable: LocalMediaListener not running.") }
        }

        val currentMediaInterface = mediaInterface
        if (currentMediaInterface == null) {
            val errorMessage = "Media backend is not initialized."
            logger.warn(errorMessage)
            onUpdate(MediaInfo.error(errorMessage))
            return Closeable { logger.debug("No-op closeable: backend not initialized.") }
        }

        val lastMediaInfo = AtomicReference<MediaInfo?>(null)

        fun emitCurrentIfChanged() {
            try {
                val mediaInfo = getCurrentMediaInfo()
                val previous = lastMediaInfo.getAndSet(mediaInfo)
                if (previous != mediaInfo) {
                    onUpdate(mediaInfo)
                }
            } catch (e: Exception) {
                onUpdate(MediaInfo.error("Media event handling failed: ${e.message}"))
            }
        }

        val listener = object : MediaSessionListener {
            override fun onNowPlayingChanged(session: MediaSession, nowPlaying: java.util.Optional<NowPlaying>) {
                emitCurrentIfChanged()
            }

            override fun onPlaybackStateChanged(session: MediaSession, state: PlaybackState) {
                emitCurrentIfChanged()
            }

            override fun onSessionActiveChanged(session: MediaSession, active: Boolean) {
                emitCurrentIfChanged()
            }

            override fun onSessionAdded(session: MediaSession) {
                session.addListener(this)
                emitCurrentIfChanged()
            }

            override fun onSessionRemoved(sessionId: String) {
                emitCurrentIfChanged()
            }
        }

        currentMediaInterface.addSessionListener(listener)
        currentMediaInterface.getAllSessions().forEach { it.addListener(listener) }
        emitCurrentIfChanged()

        return Closeable {
            logger.info("Unsubscribing media change listener.")
            runCatching {
                currentMediaInterface.removeSessionListener(listener)
                currentMediaInterface.getAllSessions().forEach { it.removeListener(listener) }
            }.onFailure {
                logger.debug("Failed while removing media listeners", it)
            }
        }
    }
    
    fun back(appName: String) {
        if (!LocalMediaListener.isRunning) {
            logger.warn("LocalMediaListener is not running. No need to back.")
            return
        }

        val session = resolveSession(appName) ?: run {
            logger.warn("No media session found for app '{}'", appName)
            return
        }

        val success = runCatching { session.controls.previous() }
            .getOrElse {
                logger.error("Error going back", it)
                false
            }
        if (!success) {
            logger.error("Back command was rejected for app '{}'", appName)
        }
    }
    
    fun next(appName: String) {
        if (!LocalMediaListener.isRunning) {
            logger.warn("LocalMediaListener is not running. No need to next.")
            return
        }

        val session = resolveSession(appName) ?: run {
            logger.warn("No media session found for app '{}'", appName)
            return
        }

        val success = runCatching { session.controls.next() }
            .getOrElse {
                logger.error("Error going next", it)
                false
            }
        if (!success) {
            logger.error("Next command was rejected for app '{}'", appName)
        }
    }
    
    fun playPause(appName: String) {
        if (!LocalMediaListener.isRunning) {
            logger.warn("LocalMediaListener is not running. No need to play/pause.")
            return
        }

        val session = resolveSession(appName) ?: run {
            logger.warn("No media session found for app '{}'", appName)
            return
        }

        val success = runCatching { session.controls.togglePlayPause() }
            .getOrElse {
                logger.error("Error toggling play/pause", it)
                false
            }
        if (!success) {
            logger.error("Play/pause command was rejected for app '{}'", appName)
        }
    }

    private fun resolveSession(appName: String): MediaSession? {
        val currentMediaInterface = mediaInterface ?: return null

        if (appName.isBlank()) {
            return currentMediaInterface.getActiveSession().orElse(null)
        }

        return currentMediaInterface.getSessionByApp(appName).orElseGet {
            currentMediaInterface.getAllSessions()
                .firstOrNull { it.applicationName.equals(appName, ignoreCase = true) }
        }
    }

    private fun sessionToMediaInfo(session: MediaSession): MediaInfo {
        val nowPlaying = session.nowPlaying.orElse(null)
        val playbackState = runCatching { session.controls.playbackState }.getOrDefault(PlaybackState.UNKNOWN)
        return MediaInfo(
            title = nowPlaying?.title?.orElse("") ?: "",
            artist = nowPlaying?.artist?.orElse("") ?: "",
            album = nowPlaying?.album?.orElse("") ?: "",
            imageUrl = nowPlaying?.artwork?.orElse(null),
            duration = nowPlaying?.duration?.map { it.seconds.toInt().coerceAtLeast(0) }?.orElse(null),
            position = nowPlaying?.position?.map { it.seconds.toDouble() + (it.nano / 1_000_000_000.0) }?.orElse(null),
            isPlaying = playbackState == PlaybackState.PLAYING,
            source = session.applicationName
        )
    }
}
