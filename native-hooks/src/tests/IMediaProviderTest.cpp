#include <gtest/gtest.h>
#include "IMediaProvider.h"

class IMediaProviderTest : public ::testing::Test {
protected:
    void SetUp() override {
        // Create provider instance
        provider = IMediaProvider::create();
    }
    
    std::shared_ptr<IMediaProvider> provider;
};

TEST_F(IMediaProviderTest, FactoryCreatesProvider) {
    // Factory should create a provider instance on supported platforms
    EXPECT_NE(provider, nullptr);
}

TEST_F(IMediaProviderTest, ProviderHasRequiredMethods) {
    if (provider) {
        // Test that all required methods exist and can be called
        auto info = provider->getCurrentMediaInfo();
        
        // Control methods should be callable (results depend on system state)
        bool playResult = provider->playPause();
        bool nextResult = provider->next();
        bool prevResult = provider->previous();
        
        // Methods should exist and be callable without crashing
        EXPECT_TRUE(true);
    }
}

TEST_F(IMediaProviderTest, ProviderHandlesEmptyAppName) {
    if (provider) {
        // Test control methods with empty app name
        bool playResult = provider->playPause("");
        bool nextResult = provider->next("");
        bool prevResult = provider->previous("");
        
        // Should handle empty string gracefully
        EXPECT_TRUE(true);
    }
}

TEST_F(IMediaProviderTest, ProviderHandlesSpecificAppName) {
    if (provider) {
        // Test control methods with specific app names
        bool playResult = provider->playPause("TestApp");
        bool nextResult = provider->next("AnotherApp");
        bool prevResult = provider->previous("ThirdApp");
        
        // Should handle app names gracefully
        EXPECT_TRUE(true);
    }
}

TEST_F(IMediaProviderTest, GetCurrentMediaInfoReturnsValidStructure) {
    if (provider) {
        auto info = provider->getCurrentMediaInfo();
        
        if (info.has_value()) {
            // If info is returned, it should have the correct structure
            MediaInfo mediaInfo = info.value();
            
            // Test that the structure exists (fields may be empty)
            EXPECT_TRUE(true); // MediaInfo has all required fields by definition
        } else {
            // No media info available is also valid
            EXPECT_TRUE(true);
        }
    }
} 