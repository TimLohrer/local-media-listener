#pragma once

#include "IMediaProvider.h"
#if defined(_WIN32)
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.Control.h>
#include <optional>
#include <chrono>
#endif

// Forward declarations for Windows Runtime types
namespace winrt::Windows::Media::Control {
    struct GlobalSystemMediaTransportControlsSessionManager;
    struct GlobalSystemMediaTransportControlsSession;
}

class WindowsMediaProvider : public IMediaProvider {
public:
    WindowsMediaProvider();
    ~WindowsMediaProvider() override;
    
    std::optional<MediaInfo> getCurrentMediaInfo() override;
    bool playPause(const std::string& appName = "") override;
    bool next(const std::string& appName = "") override;
    bool previous(const std::string& appName = "") override;
    
private:
#if defined(_WIN32)
    winrt::Windows::Media::Control::GlobalSystemMediaTransportControlsSessionManager sessionManager_{nullptr};
    bool initialized_{false};
    // Last fetched timeline properties and timestamp for interpolation
    std::optional<winrt::Windows::Media::Control::GlobalSystemMediaTransportControlsSessionTimelineProperties> lastTimelineProps_;
    std::chrono::steady_clock::time_point lastTimelineFetchTime_;
    winrt::Windows::Media::Control::GlobalSystemMediaTransportControlsSessionPlaybackStatus lastPlaybackStatus_{};
#endif
    
    bool initializeWindowsRT();
    std::optional<MediaInfo> fetchFromWindowsMedia();
}; 