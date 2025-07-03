#pragma once

#include "MediaInfo.h"
#include "IMediaProvider.h"
#include <memory>
#include <atomic>
#include <thread>
#include <mutex>
#include <vector>
#include <functional>
#include <set>

// Boost.Beast includes for WebSocket support
#include <boost/beast/core.hpp>
#include <boost/beast/websocket.hpp>
#include <boost/asio/ip/tcp.hpp>
#include <boost/asio/strand.hpp>

// Forward declaration for httplib server type
namespace httplib {
    class Server;
}

// Forward declarations for Beast types
namespace beast = boost::beast;
namespace http = beast::http;
namespace websocket = beast::websocket;
namespace net = boost::asio;
using tcp = net::ip::tcp;

// WebSocket session class for managing individual connections
class WebSocketSession : public std::enable_shared_from_this<WebSocketSession> {
public:
    explicit WebSocketSession(tcp::socket&& socket);
    void run();
    void send(const std::string& message);
    void close();
    
private:
    websocket::stream<beast::tcp_stream> ws_;
    beast::flat_buffer buffer_;
    std::function<void(std::shared_ptr<WebSocketSession>)> onClose_;
    std::mutex sendMutex_;
    
    void onAccept(beast::error_code ec);
    void doRead();
    void onRead(beast::error_code ec, std::size_t bytes_transferred);
    void onWrite(beast::error_code ec, std::size_t bytes_transferred);
    
    friend class HttpServer;
};

class HttpServer {
public:
    HttpServer(std::shared_ptr<IMediaProvider> mediaProvider);
    ~HttpServer();
    
    bool start(const std::string& host = "127.0.0.1", int port = 14565);
    void stop();
    
    void setCurrentMediaInfo(const MediaInfo& info);
    MediaInfo getCurrentMediaInfo() const;
    
    void notifyWebSocketClients(const MediaInfo& info);
    
private:
    std::shared_ptr<IMediaProvider> mediaProvider_;
    std::atomic<bool> running_;
    std::thread serverThread_; // Thread for httplib server
    std::thread wsThread_; // Thread for Beast WebSocket server
    
    mutable std::mutex currentInfoMutex_;
    MediaInfo currentInfo_;
    
    // Beast WebSocket server related members
    net::io_context wsIoc_;
    tcp::acceptor wsAcceptor_;
    std::set<std::shared_ptr<WebSocketSession>> wsConnections_;
    mutable std::mutex wsConnectionsMutex_;

    // httplib server as a unique_ptr for proper lifecycle management
    std::unique_ptr<httplib::Server> httpServer_;

    void runServer(const std::string& host, int port);
    void runWebSocketServer(const std::string& host, int port);
    void doAccept();
    void onAccept(beast::error_code ec, tcp::socket socket);
    void removeWebSocketSession(std::shared_ptr<WebSocketSession> session);
}; 