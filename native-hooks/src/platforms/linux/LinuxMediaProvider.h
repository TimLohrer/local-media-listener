#pragma once

#include "IMediaProvider.h"
#include <dbus/dbus.h>

class LinuxMediaProvider : public IMediaProvider {
public:
    LinuxMediaProvider();
    ~LinuxMediaProvider() override;
    
    std::optional<MediaInfo> getCurrentMediaInfo() override;
    bool playPause(const std::string& appName = "") override;
    bool next(const std::string& appName = "") override;
    bool previous(const std::string& appName = "") override;
    
private:
    DBusConnection* dbusConnection_;
    
    bool initializeDBus();
    void cleanupDBus();
    std::optional<MediaInfo> fetchFromMPRIS();
    bool sendMPRISCommand(const std::string& command);
    std::string findActivePlayer();
}; 