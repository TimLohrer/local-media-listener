#include "LinuxMediaProvider.h"
#include "Logger.h"
#include <string>
#include <vector>
#include <cstring>

LinuxMediaProvider::LinuxMediaProvider() : dbusConnection_(nullptr) {
    initializeDBus();
}

LinuxMediaProvider::~LinuxMediaProvider() {
    cleanupDBus();
}

bool LinuxMediaProvider::initializeDBus() {
    DBusError error;
    dbus_error_init(&error);
    
    dbusConnection_ = dbus_bus_get(DBUS_BUS_SESSION, &error);
    if (dbus_error_is_set(&error)) {
        Logger::error("Failed to connect to session bus: " + std::string(error.message));
        dbus_error_free(&error);
        return false;
    }
    
    if (!dbusConnection_) {
        Logger::error("Failed to get D-Bus connection");
        return false;
    }
    
    return true;
}

void LinuxMediaProvider::cleanupDBus() {
    if (dbusConnection_) {
        dbus_connection_unref(dbusConnection_);
        dbusConnection_ = nullptr;
    }
}

std::optional<MediaInfo> LinuxMediaProvider::getCurrentMediaInfo() {
    return fetchFromMPRIS();
}

std::optional<MediaInfo> LinuxMediaProvider::fetchFromMPRIS() {
    if (!dbusConnection_) {
        return std::nullopt;
    }
    
    // List all available services
    DBusMessage* message = dbus_message_new_method_call(
        "org.freedesktop.DBus",
        "/org/freedesktop/DBus",
        "org.freedesktop.DBus",
        "ListNames"
    );
    
    if (!message) {
        return std::nullopt;
    }
    
    DBusMessage* reply = dbus_connection_send_with_reply_and_block(
        dbusConnection_, message, DBUS_TIMEOUT_USE_DEFAULT, nullptr
    );
    
    dbus_message_unref(message);
    
    if (!reply) {
        return std::nullopt;
    }
    
    // Parse the reply to find MPRIS services
    DBusMessageIter iter;
    if (!dbus_message_iter_init(reply, &iter)) {
        dbus_message_unref(reply);
        return std::nullopt;
    }
    
    DBusMessageIter arrayIter;
    if (dbus_message_iter_get_arg_type(&iter) != DBUS_TYPE_ARRAY) {
        dbus_message_unref(reply);
        return std::nullopt;
    }
    
    dbus_message_iter_recurse(&iter, &arrayIter);
    
    std::vector<std::string> mprisServices;
    
    while (dbus_message_iter_get_arg_type(&arrayIter) == DBUS_TYPE_STRING) {
        const char* serviceName;
        dbus_message_iter_get_basic(&arrayIter, &serviceName);
        
        if (std::string(serviceName).find("org.mpris.MediaPlayer2.") == 0) {
            mprisServices.push_back(serviceName);
        }
        
        dbus_message_iter_next(&arrayIter);
    }
    
    dbus_message_unref(reply);
    
    // Try to get media info from each MPRIS service
    for (const auto& service : mprisServices) {
        // Check playback status
        DBusMessage* statusMessage = dbus_message_new_method_call(
            service.c_str(),
            "/org/mpris/MediaPlayer2",
            "org.freedesktop.DBus.Properties",
            "Get"
        );
        
        if (!statusMessage) continue;
        
        const char* interface = "org.mpris.MediaPlayer2.Player";
        const char* property = "PlaybackStatus";
        
        dbus_message_append_args(statusMessage,
            DBUS_TYPE_STRING, &interface,
            DBUS_TYPE_STRING, &property,
            DBUS_TYPE_INVALID);
        
        DBusMessage* statusReply = dbus_connection_send_with_reply_and_block(
            dbusConnection_, statusMessage, DBUS_TIMEOUT_USE_DEFAULT, nullptr
        );
        
        dbus_message_unref(statusMessage);
        
        if (!statusReply) continue;
        
        // Parse playback status
        DBusMessageIter statusIter, variantIter;
        if (dbus_message_iter_init(statusReply, &statusIter) &&
            dbus_message_iter_get_arg_type(&statusIter) == DBUS_TYPE_VARIANT) {
            
            dbus_message_iter_recurse(&statusIter, &variantIter);
            
            if (dbus_message_iter_get_arg_type(&variantIter) == DBUS_TYPE_STRING) {
                const char* status;
                dbus_message_iter_get_basic(&variantIter, &status);
                
                if (strcmp(status, "Playing") != 0) {
                    dbus_message_unref(statusReply);
                    continue; // Not playing, try next service
                }
            }
        }
        
        dbus_message_unref(statusReply);
        
        // Get metadata
        DBusMessage* metadataMessage = dbus_message_new_method_call(
            service.c_str(),
            "/org/mpris/MediaPlayer2",
            "org.freedesktop.DBus.Properties",
            "Get"
        );
        
        if (!metadataMessage) continue;
        
        property = "Metadata";
        
        dbus_message_append_args(metadataMessage,
            DBUS_TYPE_STRING, &interface,
            DBUS_TYPE_STRING, &property,
            DBUS_TYPE_INVALID);
        
        DBusMessage* metadataReply = dbus_connection_send_with_reply_and_block(
            dbusConnection_, metadataMessage, DBUS_TIMEOUT_USE_DEFAULT, nullptr
        );
        
        dbus_message_unref(metadataMessage);
        
        if (!metadataReply) continue;
        
        // Parse metadata into MediaInfo
        MediaInfo info;
        {
            DBusMessageIter iter;
            if (dbus_message_iter_init(metadataReply, &iter) &&
                dbus_message_iter_get_arg_type(&iter) == DBUS_TYPE_VARIANT) {
                DBusMessageIter variantIter;
                dbus_message_iter_recurse(&iter, &variantIter);
                if (dbus_message_iter_get_arg_type(&variantIter) == DBUS_TYPE_ARRAY) {
                    DBusMessageIter arrayIter;
                    dbus_message_iter_recurse(&variantIter, &arrayIter);
                    while (dbus_message_iter_get_arg_type(&arrayIter) == DBUS_TYPE_DICT_ENTRY) {
                        DBusMessageIter entryIter;
                        dbus_message_iter_recurse(&arrayIter, &entryIter);
                        const char* key;
                        dbus_message_iter_get_basic(&entryIter, &key);
                        dbus_message_iter_next(&entryIter);
                        DBusMessageIter valueIter;
                        dbus_message_iter_recurse(&entryIter, &valueIter);
                        int argType = dbus_message_iter_get_arg_type(&valueIter);
                        if (strcmp(key, "xesam:title") == 0 && argType == DBUS_TYPE_STRING) {
                            const char* val;
                            dbus_message_iter_get_basic(&valueIter, &val);
                            info.title = val;
                        } else if (strcmp(key, "xesam:artist") == 0 && argType == DBUS_TYPE_ARRAY) {
                            DBusMessageIter artistIter;
                            dbus_message_iter_recurse(&valueIter, &artistIter);
                            if (dbus_message_iter_get_arg_type(&artistIter) == DBUS_TYPE_STRING) {
                                const char* val;
                                dbus_message_iter_get_basic(&artistIter, &val);
                                info.artist = val;
                            }
                        } else if (strcmp(key, "xesam:album") == 0 && argType == DBUS_TYPE_STRING) {
                            const char* val;
                            dbus_message_iter_get_basic(&valueIter, &val);
                            info.album = val;
                        } else if (strcmp(key, "mpris:length") == 0 && (argType == DBUS_TYPE_UINT64 || argType == DBUS_TYPE_INT64)) {
                            int64_t len;
                            dbus_message_iter_get_basic(&valueIter, &len);
                            info.duration = std::to_string(len / 1000000);
                        } else if (strcmp(key, "mpris:artUrl") == 0 && argType == DBUS_TYPE_STRING) {
                            const char* val;
                            dbus_message_iter_get_basic(&valueIter, &val);
                            info.imageUrl = val;
                        }
                        dbus_message_iter_next(&arrayIter);
                    }
                }
            }
        }
        // Fetch current position
        {
            DBusMessage* positionMessage = dbus_message_new_method_call(
                service.c_str(),
                "/org/mpris/MediaPlayer2",
                "org.freedesktop.DBus.Properties",
                "Get"
            );
            const char* interfaceName = "org.mpris.MediaPlayer2.Player";
            const char* propertyName = "Position";
            dbus_message_append_args(positionMessage,
                DBUS_TYPE_STRING, &interfaceName,
                DBUS_TYPE_STRING, &propertyName,
                DBUS_TYPE_INVALID);
            DBusMessage* positionReply = dbus_connection_send_with_reply_and_block(
                dbusConnection_, positionMessage, DBUS_TIMEOUT_USE_DEFAULT, nullptr
            );
            dbus_message_unref(positionMessage);
            if (positionReply) {
                DBusMessageIter posIter;
                if (dbus_message_iter_init(positionReply, &posIter) &&
                    dbus_message_iter_get_arg_type(&posIter) == DBUS_TYPE_VARIANT) {
                    DBusMessageIter varIter;
                    dbus_message_iter_recurse(&posIter, &varIter);
                    if (dbus_message_iter_get_arg_type(&varIter) == DBUS_TYPE_INT64) {
                        int64_t pos;
                        dbus_message_iter_get_basic(&varIter, &pos);
                        info.position = std::to_string(pos / 1000000.0);
                    }
                }
                dbus_message_unref(positionReply);
            }
        }
        // Extract app name from service name
        std::string appName = service;
        size_t pos = appName.find("org.mpris.MediaPlayer2.");
        if (pos != std::string::npos) {
            info.appName = appName.substr(pos + 23); // Length of "org.mpris.MediaPlayer2."
        }
        
        dbus_message_unref(metadataReply);
        
        return info;
    }
    
    return std::nullopt;
}

bool LinuxMediaProvider::playPause(const std::string& appName) {
    return sendMPRISCommand("PlayPause");
}

bool LinuxMediaProvider::next(const std::string& appName) {
    return sendMPRISCommand("Next");
}

bool LinuxMediaProvider::previous(const std::string& appName) {
    return sendMPRISCommand("Previous");
}

bool LinuxMediaProvider::sendMPRISCommand(const std::string& command) {
    if (!dbusConnection_) {
        return false;
    }
    
    std::string activePlayer = findActivePlayer();
    if (activePlayer.empty()) {
        return false;
    }
    
    DBusMessage* message = dbus_message_new_method_call(
        activePlayer.c_str(),
        "/org/mpris/MediaPlayer2",
        "org.mpris.MediaPlayer2.Player",
        command.c_str()
    );
    
    if (!message) {
        return false;
    }
    
    DBusMessage* reply = dbus_connection_send_with_reply_and_block(
        dbusConnection_, message, DBUS_TIMEOUT_USE_DEFAULT, nullptr
    );
    
    dbus_message_unref(message);
    
    if (reply) {
        dbus_message_unref(reply);
        return true;
    }
    
    return false;
}

std::string LinuxMediaProvider::findActivePlayer() {
    // This should find the currently playing MPRIS service
    // For simplicity, we'll return the first MPRIS service we find
    // A more complete implementation would check playback status
    
    if (!dbusConnection_) {
        return "";
    }
    
    DBusMessage* message = dbus_message_new_method_call(
        "org.freedesktop.DBus",
        "/org/freedesktop/DBus",
        "org.freedesktop.DBus",
        "ListNames"
    );
    
    if (!message) {
        return "";
    }
    
    DBusMessage* reply = dbus_connection_send_with_reply_and_block(
        dbusConnection_, message, DBUS_TIMEOUT_USE_DEFAULT, nullptr
    );
    
    dbus_message_unref(message);
    
    if (!reply) {
        return "";
    }
    
    // Parse the reply to find MPRIS services
    DBusMessageIter iter;
    if (!dbus_message_iter_init(reply, &iter)) {
        dbus_message_unref(reply);
        return "";
    }
    
    DBusMessageIter arrayIter;
    if (dbus_message_iter_get_arg_type(&iter) != DBUS_TYPE_ARRAY) {
        dbus_message_unref(reply);
        return "";
    }
    
    dbus_message_iter_recurse(&iter, &arrayIter);
    
    std::string result;
    
    while (dbus_message_iter_get_arg_type(&arrayIter) == DBUS_TYPE_STRING) {
        const char* serviceName;
        dbus_message_iter_get_basic(&arrayIter, &serviceName);
        
        if (std::string(serviceName).find("org.mpris.MediaPlayer2.") == 0) {
            result = serviceName;
            break; // Return the first one found
        }
        
        dbus_message_iter_next(&arrayIter);
    }
    
    dbus_message_unref(reply);
    return result;
} 