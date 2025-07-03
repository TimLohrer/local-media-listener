#pragma once

#include <string>
#include <nlohmann/json.hpp>

struct MediaInfo {
    std::string title;
    std::string artist;
    std::string album;
    std::string imageUrl;
    std::string duration;
    std::string position;
    std::string appName;
    
    MediaInfo() = default;
    
    MediaInfo(const std::string& title, const std::string& artist, const std::string& album,
              const std::string& imageUrl, const std::string& duration, const std::string& position,
              const std::string& appName)
        : title(title), artist(artist), album(album), imageUrl(imageUrl), 
          duration(duration), position(position), appName(appName) {}
    
    bool operator==(const MediaInfo& other) const {
        return title == other.title && artist == other.artist && album == other.album &&
               imageUrl == other.imageUrl && duration == other.duration && 
               position == other.position && appName == other.appName;
    }
    
    bool operator!=(const MediaInfo& other) const {
        return !(*this == other);
    }
    
    nlohmann::json toJson() const {
        return nlohmann::json{
            {"title", title},
            {"artist", artist},
            {"album", album},
            {"imageUrl", imageUrl},
            {"duration", duration},
            {"position", position},
            {"source", appName}
        };
    }
    
    bool isEmpty() const {
        return title.empty() && artist.empty() && album.empty();
    }
}; 