#include <gtest/gtest.h>
#include "HttpServer.h"
#include "IMediaProvider.h"
#include <memory>
#include <thread>
#include <chrono>

// Mock MediaProvider for testing
class MockMediaProvider : public IMediaProvider {
public:
    mutable MediaInfo mockInfo;
    mutable bool shouldReturnInfo = false;
    mutable bool controlSuccess = true;
    
    std::optional<MediaInfo> getCurrentMediaInfo() override {
        if (shouldReturnInfo) {
            return mockInfo;
        }
        return std::nullopt;
    }
    
    bool playPause(const std::string& appName = "") override {
        return controlSuccess;
    }
    
    bool next(const std::string& appName = "") override {
        return controlSuccess;
    }
    
    bool previous(const std::string& appName = "") override {
        return controlSuccess;
    }
};

class HttpServerTest : public ::testing::Test {
protected:
    void SetUp() override {
        mockProvider = std::make_shared<MockMediaProvider>();
        server = std::make_unique<HttpServer>(mockProvider);
    }
    
    void TearDown() override {
        if (server) {
            server->stop();
        }
    }
    
    std::shared_ptr<MockMediaProvider> mockProvider;
    std::unique_ptr<HttpServer> server;
};

TEST_F(HttpServerTest, Construction) {
    EXPECT_NE(server, nullptr);
}

TEST_F(HttpServerTest, StartAndStop) {
    // Should be able to start server
    EXPECT_TRUE(server->start("127.0.0.1", 14566)); // Use different port to avoid conflicts
    
    // Give server time to start
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
    
    // Should be able to stop server
    server->stop();
}

TEST_F(HttpServerTest, SetAndGetCurrentMediaInfo) {
    MediaInfo testInfo("Test Title", "Test Artist", "Test Album", 
                       "test.jpg", "180", "45", "TestApp");
    
    // Set media info
    server->setCurrentMediaInfo(testInfo);
    
    // Get media info should return the same
    MediaInfo retrieved = server->getCurrentMediaInfo();
    EXPECT_EQ(retrieved, testInfo);
}

TEST_F(HttpServerTest, SetEmptyMediaInfo) {
    MediaInfo emptyInfo;
    
    // Set empty media info
    server->setCurrentMediaInfo(emptyInfo);
    
    // Get media info should return empty
    MediaInfo retrieved = server->getCurrentMediaInfo();
    EXPECT_TRUE(retrieved.isEmpty());
}

TEST_F(HttpServerTest, MediaInfoChangeDetection) {
    MediaInfo info1("Title1", "Artist1", "Album1", "img1.jpg", "120", "30", "App1");
    MediaInfo info2("Title2", "Artist2", "Album2", "img2.jpg", "180", "60", "App2");
    
    // Set first info
    server->setCurrentMediaInfo(info1);
    MediaInfo retrieved1 = server->getCurrentMediaInfo();
    EXPECT_EQ(retrieved1, info1);
    
    // Set different info
    server->setCurrentMediaInfo(info2);
    MediaInfo retrieved2 = server->getCurrentMediaInfo();
    EXPECT_EQ(retrieved2, info2);
    EXPECT_NE(retrieved2, info1);
}

TEST_F(HttpServerTest, SetSameMediaInfoTwice) {
    MediaInfo testInfo("Same Title", "Same Artist", "Same Album", 
                       "same.jpg", "200", "100", "SameApp");
    
    // Set media info twice
    server->setCurrentMediaInfo(testInfo);
    server->setCurrentMediaInfo(testInfo);
    
    // Should still return the same info
    MediaInfo retrieved = server->getCurrentMediaInfo();
    EXPECT_EQ(retrieved, testInfo);
} 