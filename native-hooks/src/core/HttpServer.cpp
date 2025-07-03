#include "HttpServer.h"
#include <httplib.h>
#include <iostream>
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
        std::cerr << "WebSocket close error: " << ec.message() << std::endl;
    }
}

void WebSocketSession::onAccept(beast::error_code ec) {
    if (ec) {
        std::cerr << "WebSocket accept error: " << ec.message() << std::endl;
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

    // This indicates that the session was closed
    if (ec == websocket::error::closed) {
        if (onClose_) {
            onClose_(shared_from_this());
        }
        return;
    }

    if (ec) {
        std::cerr << "WebSocket read error: " << ec.message() << std::endl;
        if (onClose_) {
            onClose_(shared_from_this());
        }
        return;
    }

    // Echo the message (we don't expect messages from clients in this application)
    std::cout << "Received WebSocket message: " << beast::make_printable(buffer_.data()) << std::endl;
    
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
            return;
        }
        std::cerr << "WebSocket write error: " << ec.message() << std::endl;
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
    if (running_.load()) {
        return true; // Already running
    }
    
    running_.store(true);

    // Start httplib server in a separate thread
    serverThread_ = std::thread(&HttpServer::runServer, this, host, port);

    // Start Beast WebSocket server in a separate thread
    wsThread_ = std::thread(&HttpServer::runWebSocketServer, this, host, port + 1);
    
    // Give the servers a moment to start
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
    
    return true;
}

void HttpServer::stop() {
    if (!running_.load()) {
        return;
    }
    
    running_.store(false);
    
    // Stop httplib server
    if (httpServer_) {
        httpServer_->stop();
    }

    // Stop Beast WebSocket server
    wsIoc_.stop();
    
    // Close the WebSocket acceptor to stop accepting new connections
    beast::error_code ec;
    wsAcceptor_.close(ec);
    if (ec) {
        std::cerr << "Error closing WebSocket acceptor: " << ec.message() << std::endl;
    }

    // Close all active WebSocket sessions first
    {
        std::lock_guard<std::mutex> lock(wsConnectionsMutex_);
        for (auto& session : wsConnections_) {
            session->close();
        }
        wsConnections_.clear();
    }

    // Wait for threads to complete
    if (serverThread_.joinable()) {
        serverThread_.join();
    }
    
    if (wsThread_.joinable()) {
        wsThread_.join();
    }
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
    // CORS headers for httplib server
    httpServer_->set_default_headers({
        {"Access-Control-Allow-Origin", "*"},
        {"Access-Control-Allow-Methods", "GET, POST, OPTIONS"},
        {"Access-Control-Allow-Headers", "Content-Type, Authorization"}
    });
    
    // Ready endpoint
    httpServer_->Get("/ready", [](const httplib::Request&, httplib::Response& res) {
        res.status = 200;
    });
    
    // Current media info endpoint
    httpServer_->Get("/now-playing", [this](const httplib::Request&, httplib::Response& res) {
        std::lock_guard<std::mutex> lock(currentInfoMutex_);
        if (currentInfo_.isEmpty()) {
            res.status = 204; // No Content
        } else {
            res.set_content(currentInfo_.toJson().dump(), "application/json");
        }
    });
    
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
    
    httpServer_->Post("/control/next", [this](const httplib::Request& req, httplib::Response& res) {
        std::string appName = req.body;
        if (mediaProvider_->next(appName)) {
            res.status = 200;
        } else {
            res.status = 500;
            res.set_content("Failed to skip to next track", "text/plain");
        }
    });
    
    httpServer_->Post("/control/back", [this](const httplib::Request& req, httplib::Response& res) {
        std::string appName = req.body;
        if (mediaProvider_->previous(appName)) {
            res.status = 200;
        } else {
            res.status = 500;
            res.set_content("Failed to skip to previous track", "text/plain");
        }
    });
    
    std::cout << "OS Media daemon listening on http://" << host << ":" << port << std::endl;
    
    httpServer_->listen(host.c_str(), port);
}

void HttpServer::runWebSocketServer(const std::string& host, int port) {
    try {
        auto const address = net::ip::make_address(host);
        auto const portNum = static_cast<unsigned short>(port);

        // Open the acceptor
        wsAcceptor_.open(tcp::v4());
        wsAcceptor_.set_option(net::socket_base::reuse_address(true));
        wsAcceptor_.bind({address, portNum});
        wsAcceptor_.listen(net::socket_base::max_listen_connections);

        std::cout << "WebSocket server listening on ws://" << host << ":" << port << std::endl;

        // Start accepting connections
        doAccept();

        // Run the I/O service
        wsIoc_.run();
    } catch (std::exception const& e) {
        std::cerr << "WebSocket server error: " << e.what() << std::endl;
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
        std::cerr << "WebSocket accept error: " << ec.message() << std::endl;
    } else {
        // Create the session and run it
        auto session = std::make_shared<WebSocketSession>(std::move(socket));
        
        // Set up the close callback
        session->onClose_ = [this](std::shared_ptr<WebSocketSession> session) {
            removeWebSocketSession(session);
        };
        
        // Add to our connection set
        {
            std::lock_guard<std::mutex> lock(wsConnectionsMutex_);
            wsConnections_.insert(session);
        }
        
        // Send current media info to new client
        {
            std::lock_guard<std::mutex> infoLock(currentInfoMutex_);
            if (!currentInfo_.isEmpty()) {
                session->send(currentInfo_.toJson().dump());
            }
        }
        
        session->run();
        
        std::cout << "WebSocket connection established." << std::endl;
    }

    // Accept another connection
    if (running_.load()) {
        doAccept();
    }
}

void HttpServer::removeWebSocketSession(std::shared_ptr<WebSocketSession> session) {
    std::lock_guard<std::mutex> lock(wsConnectionsMutex_);
    wsConnections_.erase(session);
    std::cout << "WebSocket connection closed." << std::endl;
} 