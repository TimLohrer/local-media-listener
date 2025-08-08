#include "HttpServer.h"
#include "Logger.h"
#include <httplib.h>
#include <algorithm>
#include <nlohmann/json.hpp> // For MediaInfo::toJson()

// WebSocketSession implementation
WebSocketSession::WebSocketSession(tcp::socket&& socket)
    : ws_(std::move(socket)) {
}

void WebSocketSession::run() {
    // Set suggested timeout settings for the websocket
    ws_.set_option(websocket::stream_base::timeout::suggested(beast::role_type::server));

    // Set a decorator to change the Server of the handshake
    ws_.set_option(websocket::stream_base::decorator(
        [](websocket::response_type& res) {
            res.set(http::field::server, "Local Media Listener WebSocket Server");
        }));

    // Accept the websocket handshake
    ws_.async_accept(
        beast::bind_front_handler(&WebSocketSession::onAccept, shared_from_this()));
}

void WebSocketSession::send(const std::string& message) {
    std::lock_guard<std::mutex> lock(sendMutex_);
    
    // Make a copy of the message and send it
    auto msg = std::make_shared<std::string>(message);
    ws_.async_write(
        net::buffer(*msg),
        [msg, self = shared_from_this()](beast::error_code ec, std::size_t bytes_transferred) {
            self->onWrite(ec, bytes_transferred);
        });
}

void WebSocketSession::close() {
    beast::error_code ec;
    ws_.close(websocket::close_code::normal, ec);
    if (ec) {
        Logger::error("WebSocket close error: " + std::string(ec.message()));
    }
}

void WebSocketSession::onAccept(beast::error_code ec) {
    if (ec) {
        Logger::error("WebSocket accept error: " + std::string(ec.message()));
        return;
    }

    // Read a message
    doRead();
}

void WebSocketSession::doRead() {
    // Read a message into our buffer
    ws_.async_read(
        buffer_,
        beast::bind_front_handler(&WebSocketSession::onRead, shared_from_this()));
}

void WebSocketSession::onRead(beast::error_code ec, std::size_t bytes_transferred) {
    boost::ignore_unused(bytes_transferred);

    // This indicates that the session was closed normally
    if (ec == websocket::error::closed) {
        Logger::info("WebSocket connection closed normally");
        if (onClose_) {
            onClose_(shared_from_this());
        }
        return;
    }

    // Handle common connection errors that don't require logging as errors
    if (ec == net::error::eof || 
        ec == net::error::connection_reset || 
        ec == net::error::connection_aborted ||
        ec == beast::error::timeout) {
        Logger::debug("WebSocket connection terminated: " + std::string(ec.message()));
        if (onClose_) {
            onClose_(shared_from_this());
        }
        return;
    }

    if (ec) {
        Logger::error("WebSocket read error: " + std::string(ec.message()));
        if (onClose_) {
            onClose_(shared_from_this());
        }
        return;
    }

    // Echo the message (we don't expect messages from clients in this application)
    Logger::info("Received WebSocket message");
    
    // Clear the buffer
    buffer_.consume(buffer_.size());

    // Do another read
    doRead();
}

void WebSocketSession::onWrite(beast::error_code ec, std::size_t bytes_transferred) {
    boost::ignore_unused(bytes_transferred);

    if (ec) {
        // Ignore canceled writes during handshake instead of closing session
        if (ec == net::error::operation_aborted) {
            Logger::debug("WebSocket write operation aborted (normal during handshake)");
            return;
        }
        
        // Handle common connection errors that don't require error logging
        if (ec == net::error::eof || 
            ec == net::error::connection_reset || 
            ec == net::error::connection_aborted ||
            ec == beast::error::timeout) {
            Logger::debug("WebSocket write connection terminated: " + std::string(ec.message()));
            return;
        }
        
        Logger::error("WebSocket write error: " + std::string(ec.message()));
        // Do not invoke onClose_ here to keep session alive
        return;
    }
}

// HttpServer implementation
HttpServer::HttpServer(std::shared_ptr<IMediaProvider> mediaProvider)
    : mediaProvider_(mediaProvider), running_(false), 
      httpServer_(std::make_unique<httplib::Server>()),
      wsAcceptor_(wsIoc_) {
}

HttpServer::~HttpServer() {
    stop();
}

bool HttpServer::start(const std::string& host, int port) {
    Logger::info("starting server");
    if (running_.load()) {
        Logger::debug("already running");
        return true; // Already running
    }
    Logger::debug("not running");
    running_.store(true);

    // Start httplib server in a separate thread
    Logger::debug("starting httplib server");
    serverThread_ = std::thread(&HttpServer::runServer, this, host, port);
    Logger::debug("httplib server started");

    // Start Beast WebSocket server in a separate thread
    Logger::debug("starting beast server");
    wsThread_ = std::thread(&HttpServer::runWebSocketServer, this, host, port + 1);
    Logger::debug("beast server started");

    // Give the servers a moment to start
    Logger::debug("waiting for servers to start");
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
    Logger::debug("thread woke up");
    Logger::info("server started");
    return true;
}

void HttpServer::stop() {
    if (!running_.load()) {
        Logger::debug("not running");
        return;
    }
    Logger::debug("stopping server");
    running_.store(false);
    
    // Stop httplib server
    if (httpServer_) {
        Logger::debug("stopping httplib server");
        httpServer_->stop();
        Logger::debug("httplib server stopped");
    }

    // Stop Beast WebSocket server
    Logger::debug("stopping beast server");
    wsIoc_.stop();
    Logger::debug("beast server stopped");
    
    // Close the WebSocket acceptor to stop accepting new connections
    beast::error_code ec;
    Logger::debug("closing beast acceptor");
    wsAcceptor_.close(ec);
    Logger::debug("beast acceptor closed");
    if (ec) {
        Logger::error("Error closing WebSocket acceptor: " + std::string(ec.message()));
    }

    // Close all active WebSocket sessions first
    {
        std::lock_guard<std::mutex> lock(wsConnectionsMutex_);
        for (auto& session : wsConnections_) {
            Logger::debug("closing websocket session");
            session->close();
            Logger::debug("websocket session closed");
        }
        Logger::debug("clearing websocket connections");
        wsConnections_.clear();
        Logger::debug("websocket connections cleared");
    }

    // Wait for threads to complete
    if (serverThread_.joinable()) {
        Logger::debug("joining httplib server thread");
        serverThread_.join();
        Logger::debug("httplib server thread joined");
    }
    
    if (wsThread_.joinable()) {
        Logger::debug("joining beast server thread");
        wsThread_.join();
        Logger::debug("beast server thread joined");
    }
    Logger::info("server stopped");
}

void HttpServer::setCurrentMediaInfo(const MediaInfo& info) {
    std::lock_guard<std::mutex> lock(currentInfoMutex_);
    if (currentInfo_ != info) {
        currentInfo_ = info;
        notifyWebSocketClients(info);
    }
}

MediaInfo HttpServer::getCurrentMediaInfo() const {
    std::lock_guard<std::mutex> lock(currentInfoMutex_);
    return currentInfo_;
}

void HttpServer::notifyWebSocketClients(const MediaInfo& info) {
    std::lock_guard<std::mutex> lock(wsConnectionsMutex_);
    std::string message;
    if (info.isEmpty()) {
        message = "{\"type\":\"stopped\"}";
    } else {
        message = info.toJson().dump();
    }
    
    for (auto& session : wsConnections_) {
        session->send(message);
    }
}

void HttpServer::runServer(const std::string& host, int port) {
    Logger::debug("runServer");
    // CORS headers for httplib server
    httpServer_->set_default_headers({
        {"Access-Control-Allow-Origin", "*"},
        {"Access-Control-Allow-Methods", "GET, POST, OPTIONS"},
        {"Access-Control-Allow-Headers", "Content-Type, Authorization"}
    });
    Logger::debug("httplib server set default headers");
    // Ready endpoint
    httpServer_->Get("/ready", [](const httplib::Request&, httplib::Response& res) {
        res.status = 200;
    });
    Logger::debug("httplib server ready endpoint");
    // Current media info endpoint
    httpServer_->Get("/now-playing", [this](const httplib::Request&, httplib::Response& res) {
        std::lock_guard<std::mutex> lock(currentInfoMutex_);
        if (currentInfo_.isEmpty()) {
            res.status = 204; // No Content
        } else {
            res.set_content(currentInfo_.toJson().dump(), "application/json");
        }
    });
    Logger::debug("httplib server now-playing endpoint");
    // Media control endpoints
    httpServer_->Post("/control/play-pause", [this](const httplib::Request& req, httplib::Response& res) {
        std::string appName = req.body;
        if (mediaProvider_->playPause(appName)) {
            res.status = 200;
        } else {
            res.status = 500;
            res.set_content("Failed to toggle play/pause", "text/plain");
        }
    });
    Logger::debug("httplib server play-pause endpoint");
    httpServer_->Post("/control/next", [this](const httplib::Request& req, httplib::Response& res) {
        std::string appName = req.body;
        if (mediaProvider_->next(appName)) {
            res.status = 200;
        } else {
            res.status = 500;
            res.set_content("Failed to skip to next track", "text/plain");
        }
    });
    Logger::debug("httplib server next endpoint");
    httpServer_->Post("/control/back", [this](const httplib::Request& req, httplib::Response& res) {
        std::string appName = req.body;
        if (mediaProvider_->previous(appName)) {
            res.status = 200;
        } else {
            res.status = 500;
            res.set_content("Failed to skip to previous track", "text/plain");
        }
    });
    Logger::debug("httplib server back endpoint");
    Logger::info("OS Media daemon listening on http://" + host + ":" + std::to_string(port));
    Logger::debug("httplib server listening");
    httpServer_->listen(host.c_str(), port);
    Logger::debug("httplib server listening");
}

void HttpServer::runWebSocketServer(const std::string& host, int port) {
    Logger::debug("runWebSocketServer");
    try {
        auto const address = net::ip::make_address(host);
        auto const portNum = static_cast<unsigned short>(port);

        // Open the acceptor
        wsAcceptor_.open(tcp::v4());
        wsAcceptor_.set_option(net::socket_base::reuse_address(true));
        wsAcceptor_.bind({address, portNum});
        Logger::debug("beast server bound");
        wsAcceptor_.listen(net::socket_base::max_listen_connections);
        Logger::debug("beast server opened");
        Logger::info("WebSocket server listening on ws://" + host + ":" + std::to_string(port));
        Logger::debug("beast server listening");
        // Start accepting connections
        doAccept();
        Logger::debug("beast server accepting connections");
        // Run the I/O service
        wsIoc_.run();
        Logger::debug("beast server running");
    } catch (std::exception const& e) {
        Logger::error("WebSocket server error: " + std::string(e.what()));
    }
}

void HttpServer::doAccept() {
    // The new connection gets its own strand
    wsAcceptor_.async_accept(
        net::make_strand(wsIoc_),
        beast::bind_front_handler(&HttpServer::onAccept, this));
}

void HttpServer::onAccept(beast::error_code ec, tcp::socket socket) {
    if (ec) {
        Logger::error("WebSocket accept error: " + std::string(ec.message()));
    } else {
        // Create the session and run it
        auto session = std::make_shared<WebSocketSession>(std::move(socket));
        Logger::debug("beast server session created");
        // Set up the close callback
        session->onClose_ = [this](std::shared_ptr<WebSocketSession> session) {
            removeWebSocketSession(session);
        };
        Logger::debug("beast server session close callback set");
        // Add to our connection set
        {
            std::lock_guard<std::mutex> lock(wsConnectionsMutex_);
            wsConnections_.insert(session);
        }
        Logger::debug("beast server session added to connections");
        // Send current media info to new client
        {
            std::lock_guard<std::mutex> infoLock(currentInfoMutex_);
            if (!currentInfo_.isEmpty()) {
                session->send(currentInfo_.toJson().dump());
                Logger::debug("beast server session sent current media info");
            }
        }
        Logger::debug("beast server session added to connections");
        session->run();
        Logger::debug("beast server session run");
        Logger::info("WebSocket connection established.");
    }

    // Accept another connection
    if (running_.load()) {
        doAccept();
        Logger::debug("beast server accepting another connection");
    }
}

void HttpServer::removeWebSocketSession(std::shared_ptr<WebSocketSession> session) {
    std::lock_guard<std::mutex> lock(wsConnectionsMutex_);
    wsConnections_.erase(session);
    Logger::info("WebSocket connection closed.");
} 