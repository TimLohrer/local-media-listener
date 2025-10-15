#pragma once

#include "MediaInfo.h"
#include "IMediaProvider.h"
#include "HttpServer.h"
#include <memory>
#include <atomic>
#include <thread>

class LocalMediaListener {
public:
    static LocalMediaListener& getInstance();
    
    bool initialize(int port = 14565);
    void shutdown();
    
    MediaInfo getCurrentMediaInfo() const;
    bool playPause(const std::string& appName = "");
    bool next(const std::string& appName = "");
    bool previous(const std::string& appName = "");
    
    bool isRunning() const;
    
private:
    LocalMediaListener() = default;
    ~LocalMediaListener();
    
    std::shared_ptr<IMediaProvider> mediaProvider_;
    std::unique_ptr<HttpServer> httpServer_;
    
    std::atomic<bool> running_;
    std::atomic<bool> shouldStop_;
    std::thread pollingThread_;
    
    MediaInfo lastMediaInfo_;
    
    void pollLoop();
    void startPolling();
    void stopPolling();
}; 