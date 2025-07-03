#pragma once

#include "MediaInfo.h"
#include <memory>
#include <optional>

class IMediaProvider {
public:
    virtual ~IMediaProvider() = default;
    
    // Fetch current media information
    virtual std::optional<MediaInfo> getCurrentMediaInfo() = 0;
    
    // Media control functions
    virtual bool playPause(const std::string& appName = "") = 0;
    virtual bool next(const std::string& appName = "") = 0;
    virtual bool previous(const std::string& appName = "") = 0;
    
    // Factory method
    static std::shared_ptr<IMediaProvider> create();
}; 