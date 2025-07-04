#include <gtest/gtest.h>
#include "LocalMediaListener.h"
#include <thread>
#include <chrono>

class LocalMediaListenerTest : public ::testing::Test {
protected:
    void SetUp() override {
        // Ensure clean state before each test
        LocalMediaListener::getInstance().shutdown();
    }
    
    void TearDown() override {
        // Clean up after each test
        LocalMediaListener::getInstance().shutdown();
    }
};

TEST_F(LocalMediaListenerTest, SingletonInstance) {
    auto& instance1 = LocalMediaListener::getInstance();
    auto& instance2 = LocalMediaListener::getInstance();
    
    // Should return the same instance
    EXPECT_EQ(&instance1, &instance2);
}

TEST_F(LocalMediaListenerTest, InitialStateNotRunning) {
    auto& listener = LocalMediaListener::getInstance();
    EXPECT_FALSE(listener.isRunning());
}

TEST_F(LocalMediaListenerTest, InitializeAndShutdown) {
    auto& listener = LocalMediaListener::getInstance();
    
    // Initialize should succeed
    EXPECT_TRUE(listener.initialize());
    EXPECT_TRUE(listener.isRunning());
    
    // Should be able to shutdown
    listener.shutdown();
    EXPECT_FALSE(listener.isRunning());
}

TEST_F(LocalMediaListenerTest, DoubleInitialize) {
    auto& listener = LocalMediaListener::getInstance();
    
    // First initialize should succeed
    EXPECT_TRUE(listener.initialize());
    EXPECT_TRUE(listener.isRunning());
    
    // Second initialize should also succeed (already running)
    EXPECT_TRUE(listener.initialize());
    EXPECT_TRUE(listener.isRunning());
}

TEST_F(LocalMediaListenerTest, GetCurrentMediaInfoWhenNotRunning) {
    auto& listener = LocalMediaListener::getInstance();
    
    // Should return empty MediaInfo when not running
    MediaInfo info = listener.getCurrentMediaInfo();
    EXPECT_TRUE(info.isEmpty());
}

TEST_F(LocalMediaListenerTest, ControlMethodsWhenNotRunning) {
    auto& listener = LocalMediaListener::getInstance();
    
    // Control methods should return false when not running
    EXPECT_FALSE(listener.playPause());
    EXPECT_FALSE(listener.next());
    EXPECT_FALSE(listener.previous());
}

TEST_F(LocalMediaListenerTest, ControlMethodsWithAppName) {
    auto& listener = LocalMediaListener::getInstance();
    
    // Should handle app name parameter
    EXPECT_FALSE(listener.playPause("Spotify"));
    EXPECT_FALSE(listener.next("Music"));
    EXPECT_FALSE(listener.previous("iTunes"));
} 