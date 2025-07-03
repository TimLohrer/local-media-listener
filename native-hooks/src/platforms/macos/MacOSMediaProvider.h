#pragma once

#include "IMediaProvider.h"
#include <vector>
#include <string>

struct Application {
    std::string appName;
    std::string displayName;
};

class MacOSMediaProvider : public IMediaProvider {
public:
    MacOSMediaProvider();
    ~MacOSMediaProvider() override = default;
    
    std::optional<MediaInfo> getCurrentMediaInfo() override;
    bool playPause(const std::string& appName = "") override;
    bool next(const std::string& appName = "") override;
    bool previous(const std::string& appName = "") override;
    
private:
    std::vector<Application> supportedApplications_;
    
    std::optional<MediaInfo> fetchFromApp(const Application& app);
    std::string executeAppleScript(const std::string& script);
    std::string getAppNameFromDisplayName(const std::string& displayName);
}; 