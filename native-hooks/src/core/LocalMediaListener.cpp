#include "LocalMediaListener.h"
#include "Logger.h"
#include <chrono>
#include <thread>

LocalMediaListener& LocalMediaListener::getInstance() {
    static LocalMediaListener instance;
    return instance;
}

LocalMediaListener::~LocalMediaListener() {
    shutdown();
}

bool LocalMediaListener::initialize() {
    if (running_.load()) {
        return true; // Already initialized
    }
    
    Logger::info("Initializing LocalMediaListener...");
    
    // Create media provider
    mediaProvider_ = IMediaProvider::create();
    if (!mediaProvider_) {
        Logger::error("Failed to create media provider for this platform");
        return false;
    }
    
    Logger::debug("Creating HTTP server");
    // Create HTTP server
    httpServer_ = std::make_unique<HttpServer>(static_cast<std::shared_ptr<IMediaProvider>>(mediaProvider_));
    Logger::debug("pointer created");
    if (!httpServer_->start("127.0.0.1", 14565)) {
        Logger::error("Failed to start HTTP server");
        return false;
    }
    Logger::debug("server up");
    
    // Start polling
    startPolling();
    Logger::debug("polling started");
    
    running_.store(true);
    Logger::info("LocalMediaListener initialized successfully");
    return true;
}

void LocalMediaListener::shutdown() {
    if (!running_.load()) {
        Logger::debug("not running");
        return;
    }
    
    Logger::info("Shutting down LocalMediaListener...");
    
    // Stop polling
    Logger::debug("stopping polling");
    stopPolling();
    Logger::debug("polling stopped");
    
    // Stop HTTP server
    if (httpServer_) {
        Logger::debug("stopping server");
        httpServer_->stop();
        httpServer_.reset();
        Logger::debug("server stopped");
    }
    
    // Clean up media provider
    Logger::debug("cleaning up media provider");
    mediaProvider_.reset();
    Logger::debug("media provider cleaned up");
    
    running_.store(false);
    Logger::info("LocalMediaListener shut down successfully");
}

MediaInfo LocalMediaListener::getCurrentMediaInfo() const {
    if (!running_.load() || !httpServer_) {
        return MediaInfo{};
    }
    
    return httpServer_->getCurrentMediaInfo();
}

bool LocalMediaListener::playPause(const std::string& appName) {
    if (!running_.load() || !mediaProvider_) {
        return false;
    }
    
    return mediaProvider_->playPause(appName);
}

bool LocalMediaListener::next(const std::string& appName) {
    if (!running_.load() || !mediaProvider_) {
        return false;
    }
    
    return mediaProvider_->next(appName);
}

bool LocalMediaListener::previous(const std::string& appName) {
    if (!running_.load() || !mediaProvider_) {
        return false;
    }
    
    return mediaProvider_->previous(appName);
}

bool LocalMediaListener::isRunning() const {
    return running_.load();
}

void LocalMediaListener::startPolling() {
    shouldStop_.store(false);
    pollingThread_ = std::thread(&LocalMediaListener::pollLoop, this);
    Logger::debug("polling thread started");
}

void LocalMediaListener::stopPolling() {
    shouldStop_.store(true);
    if (pollingThread_.joinable()) {
        Logger::debug("joining polling thread");
        pollingThread_.join();
        Logger::debug("polling thread joined");
    }
    Logger::debug("polling thread stopped");
}

void LocalMediaListener::pollLoop() {
    const auto pollInterval = std::chrono::milliseconds(500);
    
    while (!shouldStop_.load()) {
        try {
            if (mediaProvider_ && httpServer_) {
                Logger::debug("Polling for media info");
                auto currentInfo = mediaProvider_->getCurrentMediaInfo();
                if (currentInfo.has_value()) {
                    if (lastMediaInfo_ != currentInfo.value()) {
                        Logger::debug("Media info changed, updating");
                        lastMediaInfo_ = currentInfo.value();
                        httpServer_->setCurrentMediaInfo(lastMediaInfo_);
                        Logger::debug("Media info updated successfully");
                    }
                } else {
                    // No media playing - send empty info if we had something before
                    MediaInfo emptyInfo{};
                    if (lastMediaInfo_ != emptyInfo) {
                        Logger::debug("No media playing, clearing info");
                        lastMediaInfo_ = emptyInfo;
                        httpServer_->setCurrentMediaInfo(lastMediaInfo_);
                        Logger::debug("Media info cleared successfully");
                    }
                }
            }
        } catch (const std::exception& e) {
            Logger::error("Exception in polling loop: " + std::string(e.what()));
        } catch (...) {
            Logger::error("Unknown exception in polling loop");
        }
        
        std::this_thread::sleep_for(pollInterval);
    }
} 