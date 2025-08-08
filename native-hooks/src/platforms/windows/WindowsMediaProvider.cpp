#include "WindowsMediaProvider.h"
#if defined(_WIN32)
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.Control.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/Windows.Security.Cryptography.h>
#endif
#include <iostream>
#include <locale>
#include <codecvt>
#include <optional>
#include <chrono>
#include "Logger.h"

// Helper to convert winrt::hstring to UTF-8 std::string with validation
#if defined(_WIN32)
static std::string toUtf8(const winrt::hstring& hs) {
    try {
        std::wstring ws(hs.c_str());
        std::wstring_convert<std::codecvt_utf8<wchar_t>> conv;
        std::string result = conv.to_bytes(ws);
        
        // Validate UTF-8 and remove invalid characters
        std::string clean_result;
        clean_result.reserve(result.length());
        
        for (size_t i = 0; i < result.length(); ) {
            unsigned char c = static_cast<unsigned char>(result[i]);
            
            // ASCII characters (0-127) are always valid
            if (c < 128) {
                clean_result += result[i];
                i++;
                continue;
            }
            
            // Multi-byte UTF-8 character validation
            int bytes_to_read = 0;
            if ((c & 0xE0) == 0xC0) bytes_to_read = 1;       // 110xxxxx
            else if ((c & 0xF0) == 0xE0) bytes_to_read = 2;  // 1110xxxx
            else if ((c & 0xF8) == 0xF0) bytes_to_read = 3;  // 11110xxx
            else {
                // Invalid start byte, skip
                i++;
                continue;
            }
            
            // Check if we have enough bytes and they're valid continuation bytes
            bool valid = true;
            if (i + bytes_to_read >= result.length()) {
                valid = false;
            } else {
                for (int j = 1; j <= bytes_to_read; j++) {
                    unsigned char cont = static_cast<unsigned char>(result[i + j]);
                    if ((cont & 0xC0) != 0x80) {  // Should be 10xxxxxx
                        valid = false;
                        break;
                    }
                }
            }
            
            if (valid) {
                // Copy the complete UTF-8 character
                for (int j = 0; j <= bytes_to_read; j++) {
                    clean_result += result[i + j];
                }
                i += bytes_to_read + 1;
            } else {
                // Skip invalid character
                i++;
            }
        }
        
        return clean_result;
    } catch (...) {
        return "";  // Return empty string on any conversion error
    }
}
#endif

WindowsMediaProvider::WindowsMediaProvider() {
#if defined(_WIN32)
    try {
        // Try to initialize apartment - this may fail if already initialized, which is OK
        try {
            winrt::init_apartment();
        } catch (...) {
            // Already initialized or failed to initialize - continue anyway
        }
        
        sessionManager_ = winrt::Windows::Media::Control::GlobalSystemMediaTransportControlsSessionManager::RequestAsync().get();
        // Initialize timeline props for interpolation
        auto session = sessionManager_.GetCurrentSession();
        if (session) {
            try {
                lastTimelineProps_ = session.GetTimelineProperties();
                lastTimelineFetchTime_ = std::chrono::steady_clock::now();
                auto playbackInfo = session.GetPlaybackInfo();
                if (playbackInfo) {
                    lastPlaybackStatus_ = playbackInfo.PlaybackStatus();
                }
            } catch (...) {
                // Continue initialization even if timeline setup fails
            }
        }
        initialized_ = true;
    } catch (...) {
        initialized_ = false;
    }
#else
    initialized_ = false;
#endif
}

WindowsMediaProvider::~WindowsMediaProvider() {
#if defined(_WIN32)
    try {
        // Reset any WinRT objects to ensure proper cleanup
        sessionManager_ = nullptr;
        lastTimelineProps_ = std::nullopt;
        initialized_ = false;
        
        // Uninitialize the apartment
        winrt::uninit_apartment();
    } catch (...) {
        // Suppress any exceptions during cleanup
    }
#endif
}

std::optional<MediaInfo> WindowsMediaProvider::getCurrentMediaInfo() {
#if defined(_WIN32)
    if (!initialized_) {
        Logger::debug("WindowsMediaProvider not initialized");
        return std::nullopt;
    }
    try {
        auto session = sessionManager_.GetCurrentSession();
        if (!session) {
            Logger::debug("No current session available");
            return std::nullopt;
        }
        auto props = session.TryGetMediaPropertiesAsync().get();

        MediaInfo info;
        info.title = toUtf8(props.Title());
        info.artist = toUtf8(props.Artist());
        info.album = toUtf8(props.AlbumTitle());
        // Populate app name and cached thumbnail URL
        info.appName = toUtf8(session.SourceAppUserModelId());
        info.imageUrl = lastImageUrl_;

        // Update timeline props if changed, otherwise interpolate and fetch thumbnail
        auto now = std::chrono::steady_clock::now();
        auto newTimeline = session.GetTimelineProperties();
        if (!lastTimelineProps_ ||
            newTimeline.Position().count() != lastTimelineProps_->Position().count() ||
            newTimeline.EndTime().count() != lastTimelineProps_->EndTime().count()) {
            lastTimelineProps_ = newTimeline;
            lastTimelineFetchTime_ = now;
            lastPlaybackStatus_ = session.GetPlaybackInfo().PlaybackStatus();
            // Fetch and cache thumbnail image
            auto thumbRef = props.Thumbnail();
            if (thumbRef) {
                try {
                    auto ras = thumbRef.OpenReadAsync().get();
                    auto buffer = winrt::Windows::Storage::Streams::Buffer(ras.Size());
                    auto loaded = ras.ReadAsync(buffer, ras.Size(), winrt::Windows::Storage::Streams::InputStreamOptions::None).get();
                    auto base64 = winrt::Windows::Security::Cryptography::CryptographicBuffer::EncodeToBase64String(loaded);
                    std::string mime = toUtf8(ras.ContentType());
                    lastImageUrl_ = "data:" + mime + ";base64," + toUtf8(base64);
                } catch (...) {
                    lastImageUrl_.clear();
                }
            } else {
                lastImageUrl_.clear();
            }
        }

        double basePos = static_cast<double>(lastTimelineProps_->Position().count()) / 10000000.0;
        if (lastPlaybackStatus_ == winrt::Windows::Media::Control::GlobalSystemMediaTransportControlsSessionPlaybackStatus::Playing) {
            double elapsed = std::chrono::duration<double>(now - lastTimelineFetchTime_).count();
            basePos += elapsed;
        }
        info.position = std::to_string(basePos);

        int durationSeconds = static_cast<int>(lastTimelineProps_->EndTime().count() / 10000000);
        info.duration = std::to_string(durationSeconds);

        return info;
    } catch (const std::exception& e) {
        Logger::error("Exception in getCurrentMediaInfo: " + std::string(e.what()));
        return std::nullopt;
    } catch (...) {
        Logger::error("Unknown exception in getCurrentMediaInfo - this may be a WinRT access violation");
        return std::nullopt;
    }
#else
    return std::nullopt;
#endif
}

bool WindowsMediaProvider::playPause(const std::string& appName) {
#if defined(_WIN32)
    if (!initialized_) return false;
    try {
        auto session = sessionManager_.GetCurrentSession();
        if (!session) return false;
        
        // Check if play/pause controls are available
        auto playbackInfo = session.GetPlaybackInfo();
        if (!playbackInfo) return false;
        
        auto controls = playbackInfo.Controls();
        auto status = playbackInfo.PlaybackStatus();
        
        using winrt::Windows::Media::Control::GlobalSystemMediaTransportControlsSessionPlaybackStatus;
        if (status == GlobalSystemMediaTransportControlsSessionPlaybackStatus::Playing) {
            if (controls.IsPauseEnabled()) {
                session.TryPauseAsync().get();
            } else {
                return false;
            }
        } else {
            if (controls.IsPlayEnabled()) {
                session.TryPlayAsync().get();
            } else {
                return false;
            }
        }
        Logger::debug("PlayPause operation completed successfully");
        return true;
    } catch (const std::exception& e) {
        Logger::error("Exception in playPause: " + std::string(e.what()));
        return false;
    } catch (...) {
        Logger::error("Unknown exception in playPause - this may be a WinRT access violation");
        return false;
    }
#else
    return false;
#endif
}

bool WindowsMediaProvider::next(const std::string& appName) {
#if defined(_WIN32)
    if (!initialized_) return false;
    try {
        auto session = sessionManager_.GetCurrentSession();
        if (!session) return false;
        
        // Check if skip next is supported before attempting
        auto playbackInfo = session.GetPlaybackInfo();
        if (!playbackInfo || 
            !playbackInfo.Controls().IsNextEnabled()) {
            return false;
        }
        
        // Use timeout to prevent hanging
        auto skipResult = session.TrySkipNextAsync();
        if (!skipResult) return false;
        
        // Wait with timeout
        auto future = skipResult.get();
        Logger::debug("Next operation completed successfully");
        return true;
    } catch (const std::exception& e) {
        Logger::error("Exception in next: " + std::string(e.what()));
        return false;
    } catch (...) {
        Logger::error("Unknown exception in next - this may be a WinRT access violation");
        return false;
    }
#else
    return false;
#endif
}

bool WindowsMediaProvider::previous(const std::string& appName) {
#if defined(_WIN32)
    if (!initialized_) return false;
    try {
        auto session = sessionManager_.GetCurrentSession();
        if (!session) return false;
        
        // Check if skip previous is supported before attempting
        auto playbackInfo = session.GetPlaybackInfo();
        if (!playbackInfo || 
            !playbackInfo.Controls().IsPreviousEnabled()) {
            return false;
        }
        
        // Use timeout to prevent hanging
        auto skipResult = session.TrySkipPreviousAsync();
        if (!skipResult) return false;
        
        // Wait with timeout
        auto future = skipResult.get();
        Logger::debug("Previous operation completed successfully");
        return true;
    } catch (const std::exception& e) {
        Logger::error("Exception in previous: " + std::string(e.what()));
        return false;
    } catch (...) {
        Logger::error("Unknown exception in previous - this may be a WinRT access violation");
        return false;
    }
#else
    return false;
#endif
} 