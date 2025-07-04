#include <gtest/gtest.h>
#include "MediaInfo.h"
#include <nlohmann/json.hpp>

using json = nlohmann::json;

TEST(MediaInfoTest, DefaultConstructorIsEmpty) {
    MediaInfo info;
    EXPECT_TRUE(info.isEmpty());
}

TEST(MediaInfoTest, ParameterizedConstructor) {
    MediaInfo info("title", "artist", "album", "imageUrl", "duration", "position", "appName");
    EXPECT_EQ(info.title, "title");
    EXPECT_EQ(info.artist, "artist");
    EXPECT_EQ(info.album, "album");
    EXPECT_EQ(info.imageUrl, "imageUrl");
    EXPECT_EQ(info.duration, "duration");
    EXPECT_EQ(info.position, "position");
    EXPECT_EQ(info.appName, "appName");
    EXPECT_FALSE(info.isEmpty());
}

TEST(MediaInfoTest, EqualityOperators) {
    MediaInfo a("t", "ar", "al", "img", "dur", "pos", "app");
    MediaInfo b("t", "ar", "al", "img", "dur", "pos", "app");
    MediaInfo c("different", "artist", "album", "imageUrl", "duration", "position", "appName");
    EXPECT_EQ(a, b);
    EXPECT_NE(a, c);
    EXPECT_FALSE(a != b);
}

TEST(MediaInfoTest, ToJson) {
    MediaInfo info("title", "artist", "album", "image", "123", "45", "Spotify");
    json j = info.toJson();
    EXPECT_EQ(j["title"], "title");
    EXPECT_EQ(j["artist"], "artist");
    EXPECT_EQ(j["album"], "album");
    EXPECT_EQ(j["imageUrl"], "image");
    EXPECT_EQ(j["duration"], "123");
    EXPECT_EQ(j["position"], "45");
    EXPECT_EQ(j["source"], "Spotify");
} 