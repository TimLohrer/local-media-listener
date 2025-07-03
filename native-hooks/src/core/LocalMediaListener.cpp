#include "LocalMediaListener.h"
#include <iostream>
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
    
    std::cout << "Initializing LocalMediaListener..." << std::endl;
    
    // Create media provider
    mediaProvider_ = IMediaProvider::create();
    if (!mediaProvider_) {
        std::cerr << "Failed to create media provider for this platform" << std::endl;
        return false;
    }
    
    // Create HTTP server
    httpServer_ = std::make_unique<HttpServer>(static_cast<std::shared_ptr<IMediaProvider>>(mediaProvider_));
    if (!httpServer_->start("127.0.0.1", 14565)) {
        std::cerr << "Failed to start HTTP server" << std::endl;
        return false;
    }
    
    // Start polling
    startPolling();
    
    running_.store(true);
    std::cout << "LocalMediaListener initialized successfully" << std::endl;
    return true;
}

void LocalMediaListener::shutdown() {
    if (!running_.load()) {
        return;
    }
    
    std::cout << "Shutting down LocalMediaListener..." << std::endl;
    
    // Stop polling
    stopPolling();
    
    // Stop HTTP server
    if (httpServer_) {
        httpServer_->stop();
        httpServer_.reset();
    }
    
    // Clean up media provider
    mediaProvider_.reset();
    
    running_.store(false);
    std::cout << "LocalMediaListener shut down successfully" << std::endl;
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
}

void LocalMediaListener::stopPolling() {
    shouldStop_.store(true);
    if (pollingThread_.joinable()) {
        pollingThread_.join();
    }
}

void LocalMediaListener::pollLoop() {
    const auto pollInterval = std::chrono::milliseconds(500);
    
    while (!shouldStop_.load()) {
        if (mediaProvider_ && httpServer_) {
            auto currentInfo = mediaProvider_->getCurrentMediaInfo();
            if (currentInfo.has_value()) {
                if (lastMediaInfo_ != currentInfo.value()) {
                    lastMediaInfo_ = currentInfo.value();
                    httpServer_->setCurrentMediaInfo(lastMediaInfo_);
                }
            } else {
                // No media playing - send empty info if we had something before
                MediaInfo emptyInfo{};
                if (lastMediaInfo_ != emptyInfo) {
                    lastMediaInfo_ = emptyInfo;
                    httpServer_->setCurrentMediaInfo(lastMediaInfo_);
                }
            }
        }
        
        std::this_thread::sleep_for(pollInterval);
    }
} 