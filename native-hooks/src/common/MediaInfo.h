#pragma once

#include <string>
#include <nlohmann/json.hpp>

// Helper function to remove problematic characters, keeping only safe ASCII
inline std::string cleanUtf8(const std::string& input) {
    std::string clean_result;
    clean_result.reserve(input.length());
    
    for (char c : input) {
        unsigned char uc = static_cast<unsigned char>(c);
        // Keep only printable ASCII characters (space to tilde)
        if (uc >= 32 && uc <= 126) {
            clean_result += c;
        }
        // Skip everything else (control chars, extended ASCII, UTF-8, etc.)
    }
    
    return clean_result;
}

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
            {"title", cleanUtf8(title)},
            {"artist", cleanUtf8(artist)},
            {"album", cleanUtf8(album)},
            {"imageUrl", cleanUtf8(imageUrl)},
            {"duration", cleanUtf8(duration)},
            {"position", cleanUtf8(position)},
            {"source", cleanUtf8(appName)}
        };
    }
    
    bool isEmpty() const {
        return title.empty() && artist.empty() && album.empty();
    }
}; 