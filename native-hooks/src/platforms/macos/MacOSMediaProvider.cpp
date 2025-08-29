#include "MacOSMediaProvider.h"
#include <cstdlib>
#include <memory>
#include <sstream>
#include <iostream>

MacOSMediaProvider::MacOSMediaProvider() {
    // Initialize supported applications
    supportedApplications_ = {
        {"Spotify", "Spotify"},
        {"Music", "Apple Music"}
        // Add more applications as needed
    };
}

std::optional<MediaInfo> MacOSMediaProvider::getCurrentMediaInfo() {
    for (const auto& app : supportedApplications_) {
        auto info = fetchFromApp(app);
        if (info.has_value()) {
            return info;
        }
    }
    return std::nullopt;
}

std::optional<MediaInfo> MacOSMediaProvider::fetchFromApp(const Application& app) {
    std::string script = R"(
        osascript -e '
        if application ")" + app.appName + R"(" is running then
            tell application ")" + app.appName + R"("
                try
                    set currentState to player state
                    -- Check if there is media loaded (playing, paused, or stopped but with current track)
                    if (currentState is playing) or (currentState is paused) then
                    try
                        set t to name of current track
                    on error
                        set t to "null"
                    end try

                    try
                        set ar to artist of current track
                    on error
                        set ar to "null"
                    end try

                    try
                        set al to album of current track
                    on error
                        set al to "null"
                    end try

                    try
                        set artUrl to artwork url of current track
                    on error
                        set artUrl to "null"
                    end try

                    try
                        set dur_sec to duration of current track
                        set dur to dur_sec * 1000
                        set dur to dur as string
                    on error
                        set dur to "null"
                    end try

                    try
                        set pos to player position
                        set pos to pos as string
                    on error
                        set pos to "null"
                    end try

                    return t & "|" & ar & "|" & al & "|" & artUrl & "|" & dur & "|" & pos
                end if
                on error
                    -- If we can'\''t get player state, try to get current track anyway
                    try
                        set t to name of current track
                        if t is not equal to "" then
                            try
                                set ar to artist of current track
                            on error
                                set ar to "null"
                            end try

                            try
                                set al to album of current track
                            on error
                                set al to "null"
                            end try

                            try
                                set artUrl to artwork url of current track
                            on error
                                set artUrl to "null"
                            end try

                            try
                                set dur to duration of current track
                                set dur to dur as string
                            on error
                                set dur to "null"
                            end try

                            try
                                set pos to player position
                                set pos to pos as string
                            on error
                                set pos to "null"
                            end try

                            return t & "|" & ar & "|" & al & "|" & artUrl & "|" & dur & "|" & pos
                        end if
                    on error
                        -- No track available
                    end try
                end try
            end tell
        end if
        '
    )";
    
    std::string output = executeAppleScript(script);
    if (output.empty()) {
        return std::nullopt;
    }
    
    // Parse the pipe-separated output
    std::vector<std::string> parts;
    std::stringstream ss(output);
    std::string item;
    
    while (std::getline(ss, item, '|')) {
        parts.push_back(item);
    }
    
    if (parts.size() < 6) {
        return std::nullopt;
    }
    
    return MediaInfo{
        parts[0], // title
        parts[1], // artist
        parts[2], // album
        parts[3], // imageUrl
        parts[4], // duration
        parts[5], // position
        app.displayName // appName
    };
}

bool MacOSMediaProvider::playPause(const std::string& appName) {
    std::string targetApp = getAppNameFromDisplayName(appName);
    if (targetApp.empty()) {
        // Try all supported apps if no specific app provided
        for (const auto& app : supportedApplications_) {
            std::string script = R"(
                osascript -e '
                if application ")" + app.appName + R"(" is running then
                    tell application ")" + app.appName + R"(" to playpause
                end if
                '
            )";
            
            if (!executeAppleScript(script).empty()) {
                return true;
            }
        }
        return false;
    }
    
    std::string script = R"(
        osascript -e '
        if application ")" + targetApp + R"(" is running then
            tell application ")" + targetApp + R"(" to playpause
        end if
        '
    )";
    
    return !executeAppleScript(script).empty();
}

bool MacOSMediaProvider::next(const std::string& appName) {
    std::string targetApp = getAppNameFromDisplayName(appName);
    if (targetApp.empty()) {
        // Try all supported apps
        for (const auto& app : supportedApplications_) {
            std::string script = R"(
                osascript -e '
                if application ")" + app.appName + R"(" is running then
                    tell application ")" + app.appName + R"(" to next track
                end if
                '
            )";
            
            if (!executeAppleScript(script).empty()) {
                return true;
            }
        }
        return false;
    }
    
    std::string script = R"(
        osascript -e '
        if application ")" + targetApp + R"(" is running then
            tell application ")" + targetApp + R"(" to next track
        end if
        '
    )";
    
    return !executeAppleScript(script).empty();
}

bool MacOSMediaProvider::previous(const std::string& appName) {
    std::string targetApp = getAppNameFromDisplayName(appName);
    if (targetApp.empty()) {
        // Try all supported apps
        for (const auto& app : supportedApplications_) {
            std::string script = R"(
                osascript -e '
                if application ")" + app.appName + R"(" is running then
                    tell application ")" + app.appName + R"(" to previous track
                end if
                '
            )";
            
            if (!executeAppleScript(script).empty()) {
                return true;
            }
        }
        return false;
    }
    
    std::string script = R"(
        osascript -e '
        if application ")" + targetApp + R"(" is running then
            tell application ")" + targetApp + R"(" to previous track
        end if
        '
    )";
    
    return !executeAppleScript(script).empty();
}

std::string MacOSMediaProvider::executeAppleScript(const std::string& script) {
    FILE* pipe = popen(script.c_str(), "r");
    if (!pipe) {
        return "";
    }
    
    char buffer[256];
    std::string result;
    
    while (fgets(buffer, sizeof(buffer), pipe) != nullptr) {
        result += buffer;
    }
    
    pclose(pipe);
    
    // Remove trailing newlines
    while (!result.empty() && (result.back() == '\n' || result.back() == '\r')) {
        result.pop_back();
    }
    
    return result;
}

std::string MacOSMediaProvider::getAppNameFromDisplayName(const std::string& displayName) {
    for (const auto& app : supportedApplications_) {
        if (app.displayName == displayName) {
            return app.appName;
        }
    }
    return "";
} 