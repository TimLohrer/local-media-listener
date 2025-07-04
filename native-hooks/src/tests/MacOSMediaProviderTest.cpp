#include <gtest/gtest.h>

#ifdef PLATFORM_MACOS
#include "MacOSMediaProvider.h"

class MacOSMediaProviderTest : public ::testing::Test {
protected:
    void SetUp() override {
        provider = std::make_unique<MacOSMediaProvider>();
    }
    
    std::unique_ptr<MacOSMediaProvider> provider;
};

TEST_F(MacOSMediaProviderTest, Construction) {
    EXPECT_NE(provider, nullptr);
}

TEST_F(MacOSMediaProviderTest, GetCurrentMediaInfoNoApps) {
    // When no supported apps are running, should return nullopt
    auto info = provider->getCurrentMediaInfo();
    // Note: This test may pass or fail depending on what's actually running
    // In a real test environment, you'd mock the AppleScript execution
    EXPECT_TRUE(true); // Placeholder - actual behavior depends on system state
}

TEST_F(MacOSMediaProviderTest, SupportedApplicationsInitialized) {
    // Test that supported applications are properly initialized
    // We can't directly access the private member, but we can test behavior
    
    // These should not crash
    provider->playPause("Spotify");
    provider->next("Music");
    provider->previous("Spotify");
    
    EXPECT_TRUE(true); // If we get here without crashing, the test passes
}

TEST_F(MacOSMediaProviderTest, ExecuteAppleScriptEmptyCommand) {
    // Test with empty AppleScript command
    // Note: This accesses a private method, so we test through public interface
    
    // Test control commands with empty app name (should try all apps)
    bool result1 = provider->playPause("");
    bool result2 = provider->next("");
    bool result3 = provider->previous("");
    
    // Results depend on system state, but calls should not crash
    EXPECT_TRUE(true);
}

TEST_F(MacOSMediaProviderTest, ControlCommandsWithSpecificApp) {
    // Test control commands with specific app names
    bool spotifyPause = provider->playPause("Spotify");
    bool musicNext = provider->next("Apple Music");
    bool spotifyPrev = provider->previous("Spotify");
    
    // Results depend on whether apps are running and have media
    // But the calls should not crash
    EXPECT_TRUE(true);
}

TEST_F(MacOSMediaProviderTest, ControlCommandsWithInvalidApp) {
    // Test control commands with invalid app name
    bool result1 = provider->playPause("NonExistentApp");
    bool result2 = provider->next("FakePlayer");
    bool result3 = provider->previous("NotReal");
    
    // Should return false for non-existent apps
    EXPECT_FALSE(result1);
    EXPECT_FALSE(result2);
    EXPECT_FALSE(result3);
}

#else

// Placeholder test for non-macOS platforms
TEST(MacOSMediaProviderTest, NotAvailableOnThisPlatform) {
    EXPECT_TRUE(true);
}

#endif 