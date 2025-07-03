#include "WindowsMediaProvider.h"
#if defined(_WIN32)
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.Control.h>
#endif
#include <iostream>
#include <locale>
#include <codecvt>
#include <optional>
#include <chrono>

// Helper to convert winrt::hstring to UTF-8 std::string
static std::string toUtf8(const winrt::hstring& hs) {
    std::wstring ws(hs.c_str());
    std::wstring_convert<std::codecvt_utf8<wchar_t>> conv;
    return conv.to_bytes(ws);
}

WindowsMediaProvider::WindowsMediaProvider() {
#if defined(_WIN32)
    winrt::init_apartment();
    sessionManager_ = winrt::Windows::Media::Control::GlobalSystemMediaTransportControlsSessionManager::RequestAsync().get();
    // Initialize timeline props for interpolation
    auto session = sessionManager_.GetCurrentSession();
    if (session) {
        lastTimelineProps_ = session.GetTimelineProperties();
        lastTimelineFetchTime_ = std::chrono::steady_clock::now();
        lastPlaybackStatus_ = session.GetPlaybackInfo().PlaybackStatus();
    }
    initialized_ = true;
#else
    initialized_ = false;
#endif
}

WindowsMediaProvider::~WindowsMediaProvider() {
    // Cleanup
}

std::optional<MediaInfo> WindowsMediaProvider::getCurrentMediaInfo() {
#if defined(_WIN32)
    if (!initialized_) return std::nullopt;
    try {
        auto session = sessionManager_.GetCurrentSession();
        if (!session) return std::nullopt;
        auto props = session.TryGetMediaPropertiesAsync().get();

        MediaInfo info;
        info.title = toUtf8(props.Title());
        info.artist = toUtf8(props.Artist());
        info.album = toUtf8(props.AlbumTitle());
        info.imageUrl = "";
        info.appName = toUtf8(session.SourceAppUserModelId());

        // Update timeline props if changed, otherwise interpolate
        auto now = std::chrono::steady_clock::now();
        auto newTimeline = session.GetTimelineProperties();
        if (!lastTimelineProps_ ||
            newTimeline.Position().count() != lastTimelineProps_->Position().count() ||
            newTimeline.EndTime().count() != lastTimelineProps_->EndTime().count()) {
            lastTimelineProps_ = newTimeline;
            lastTimelineFetchTime_ = now;
            lastPlaybackStatus_ = session.GetPlaybackInfo().PlaybackStatus();
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
    } catch (...) {
        return std::nullopt;
    }
#else
    return std::nullopt;
#endif
}

bool WindowsMediaProvider::playPause(const std::string& appName) {
#if defined(_WIN32)
    if (!initialized_) return false;
    auto session = sessionManager_.GetCurrentSession();
    if (!session) return false;
    // Toggle play/pause 
    auto status = session.GetPlaybackInfo().PlaybackStatus();
    using winrt::Windows::Media::Control::GlobalSystemMediaTransportControlsSessionPlaybackStatus;
    if (status == GlobalSystemMediaTransportControlsSessionPlaybackStatus::Playing) {
        session.TryPauseAsync().get();
    } else {
        session.TryPlayAsync().get();
    }
    return true;
#else
    return false;
#endif
}

bool WindowsMediaProvider::next(const std::string& appName) {
#if defined(_WIN32)
    if (!initialized_) return false;
    auto session = sessionManager_.GetCurrentSession();
    if (!session) return false;
    session.TrySkipNextAsync().get();
    return true;
#else
    return false;
#endif
}

bool WindowsMediaProvider::previous(const std::string& appName) {
#if defined(_WIN32)
    if (!initialized_) return false;
    auto session = sessionManager_.GetCurrentSession();
    if (!session) return false;
    session.TrySkipPreviousAsync().get();
    return true;
#else
    return false;
#endif
} 