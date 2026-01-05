#include "HybridWebSocket.hpp"
#include <NitroModules/ArrayBuffer.hpp>

#include <sstream>
#include <chrono>
#include <cstring>
#include <algorithm>

// LibWebSockets includes
#include <libwebsockets.h>

// Platform-specific helpers
#if defined(__APPLE__) || defined(__ANDROID__)
extern "C" const char* getRealTimeNitroCACertPath();
#endif

namespace margelo::nitro::realtimenitro {

// ============================================================
// User data stored per WebSocket connection
// ============================================================

struct WebSocketUserData {
  HybridWebSocket* instance;
};

// ============================================================
// Constructor / Destructor
// ============================================================

HybridWebSocket::~HybridWebSocket() {
  cleanup();
}

// ============================================================
// URL Parsing
// ============================================================

bool HybridWebSocket::parseUrl(const std::string& url) {
  size_t pos = 0;
  // 1. Check protocol
  if (url.find("wss://") == 0) {
    _useSsl = true;
    pos = 6;
  } else if (url.find("ws://") == 0) {
    _useSsl = false;
    pos = 5;
  } else {
    return false;
  }
  
  // 2. Find host end
  size_t hostEnd = url.find_first_of(":/?", pos);
  if (hostEnd == std::string::npos) {
    hostEnd = url.length();
  }
  
  _host = url.substr(pos, hostEnd - pos);
  if (_host.empty()) {
    return false;
  }
  
  // 3. Parse port (if present)
  _port = _useSsl ? 443 : 80;
  
  if (hostEnd < url.length() && url[hostEnd] == ':') {
    size_t portStart = hostEnd + 1;
    size_t portEnd = url.find('/', portStart);
    if (portEnd == std::string::npos) {
      portEnd = url.length();
    }
    
    std::string portStr = url.substr(portStart, portEnd - portStart);
    try {
      _port = std::stoi(portStr);
    } catch (...) {
      return false;
    }
    
    hostEnd = portEnd;
  }
  
  // 4. Parse path
  if (hostEnd < url.length() && url[hostEnd] == '/') {
    _path = url.substr(hostEnd);
  } else {
    _path = "/";
  }
  
  _url = url;
  return true;
}

// ============================================================
// Connect
// ============================================================

std::shared_ptr<Promise<void>> HybridWebSocket::connect(
    const std::string& url,
    const std::optional<std::vector<std::string>>& protocols) {
  
  return Promise<void>::async([this, url, protocols]() {
    // Validate and parse URL
    if (!parseUrl(url)) {
      throw std::invalid_argument("Invalid WebSocket URL: " + url);
    }

    // Cleanup any existing connection
    cleanup();

    _state = State::CONNECTING;

    // Setup LibWebSockets protocols list with compression support
    static struct lws_protocols protocolsList[] = {
      {
        .name = "websocket-protocol",
        .callback = HybridWebSocket::websocketCallback,
        .per_session_data_size = sizeof(WebSocketUserData),
        .rx_buffer_size = 65536,
        .tx_packet_size = 0, // 0 = use default
      },
      LWS_PROTOCOL_LIST_TERM
    };
    
    // Create LibWebSockets context
    struct lws_context_creation_info info;
    std::memset(&info, 0, sizeof(info));
    
    info.port = CONTEXT_PORT_NO_LISTEN;
    info.protocols = protocolsList;
    info.gid = -1;
    info.uid = -1;
    info.options = LWS_SERVER_OPTION_DO_SSL_GLOBAL_INIT;

    // For client connections, SSL/TLS configuration is done at connection time
    // using LCCSCF_* flags in lws_client_connect_info (see below)

    // Set CA cert path
    // On iOS/macOS, try to get bundled CA cert automatically
    // On other platforms, use provided path or nullptr
    const char* caCertPath = nullptr;

    if (!_caPath.empty()) {
      caCertPath = _caPath.c_str();
      printf("[WebSocket] Using provided CA cert: %s\n", _caPath.c_str());
    } else {
      #if defined(__APPLE__) || defined(__ANDROID__)
      caCertPath = getRealTimeNitroCACertPath();
      if (caCertPath) {
        // Store the bundled cert path so the rest of the code knows we have a CA cert
        _caPath = caCertPath;
        printf("[WebSocket] Using bundled CA cert: %s\n", caCertPath);
      }
      #endif
    }

    if (caCertPath) {
      info.client_ssl_ca_filepath = caCertPath;
    } else {
      info.client_ssl_ca_filepath = nullptr;
      printf("[WebSocket] WARNING: No CA cert available - mbedTLS may fail SSL handshake\n");
    }

    // Enable per-message-deflate compression extension
    // This can reduce bandwidth by 60-80% for text messages
    static const struct lws_extension extensions[] = {
      {
        "permessage-deflate",
        lws_extension_callback_pm_deflate,
        "permessage-deflate"
        "; client_no_context_takeover"
        "; client_max_window_bits"
      },
      { nullptr, nullptr, nullptr }
    };
    info.extensions = extensions;

    // Note: On mobile platforms (iOS/Android), CA certs are in system trust store
    // LibWebSockets should automatically use them for SSL verification

    // Enable LibWebSockets logging for debugging
    // Always enable error and warning logs to help diagnose connection issues
    // Note: On iOS/Android, these logs may go to system logs (use adb logcat or Xcode console)
    lws_set_log_level(LLL_ERR | LLL_WARN | LLL_NOTICE | LLL_USER, nullptr);

    printf("[WebSocket] ========================================\n");
    printf("[WebSocket] Initializing connection to: %s\n", url.c_str());
    printf("[WebSocket] Host: %s, Port: %d, Path: %s\n", _host.c_str(), _port, _path.c_str());
    printf("[WebSocket] SSL: %s\n", _useSsl ? "ENABLED" : "DISABLED");
    printf("[WebSocket] ========================================\n");

    printf("[WebSocket] Creating LibWebSockets context...\n");
    _context = lws_create_context(&info);
    if (!_context) {
      _state = State::CLOSED;
      printf("[WebSocket] ❌ FAILED to create context!\n");
      throw std::runtime_error("Failed to create WebSocket context - check LibWebSockets installation");
    }
    printf("[WebSocket] ✅ Context created successfully\n");
    
    // Setup connection info
    struct lws_client_connect_info ccinfo;
    std::memset(&ccinfo, 0, sizeof(ccinfo));

    ccinfo.context = _context;
    ccinfo.address = _host.c_str();
    ccinfo.port = _port;
    ccinfo.path = _path.c_str();
    ccinfo.host = _host.c_str();
    ccinfo.origin = _host.c_str();
    ccinfo.protocol = protocolsList[0].name;

    // SSL configuration
    if (_useSsl) {
      ccinfo.ssl_connection = LCCSCF_USE_SSL;

      if (_caPath.empty()) {
        // No CA certificate - disable verification (insecure, for development only)
        ccinfo.ssl_connection |= LCCSCF_ALLOW_SELFSIGNED;
        ccinfo.ssl_connection |= LCCSCF_SKIP_SERVER_CERT_HOSTNAME_CHECK;
        ccinfo.ssl_connection |= LCCSCF_ALLOW_EXPIRED;
        ccinfo.ssl_connection |= LCCSCF_ALLOW_INSECURE;
        printf("[WebSocket] SSL enabled WITHOUT certificate verification (insecure)\n");
      } else {
        printf("[WebSocket] SSL enabled WITH certificate verification using: %s\n", _caPath.c_str());
      }
    } else {
      printf("[WebSocket] SSL disabled - using plain WebSocket\n");
      ccinfo.ssl_connection = 0; // Explicitly no SSL
    }

    // User data for callbacks
    auto* userData = new WebSocketUserData{this};
    ccinfo.userdata = userData;
    ccinfo.pwsi = &_wsi;

    // Initiate connection
    printf("[WebSocket] 🔄 Initiating connection to %s:%d%s (SSL:%s)...\n",
           _host.c_str(), _port, _path.c_str(), _useSsl ? "YES" : "NO");
    printf("[WebSocket] Using SSL flags: 0x%x\n", ccinfo.ssl_connection);

    _wsi = lws_client_connect_via_info(&ccinfo);
    if (!_wsi) {
      delete userData;
      cleanup();
      printf("[WebSocket] ❌ lws_client_connect_via_info() returned NULL\n");
      printf("[WebSocket] This usually means:\n");
      printf("[WebSocket]   1. DNS resolution failed for %s\n", _host.c_str());
      printf("[WebSocket]   2. SSL/TLS configuration error\n");
      printf("[WebSocket]   3. Out of memory\n");
      printf("[WebSocket]   4. Invalid parameters\n");
      printf("[WebSocket] Check system/Xcode console for LibWebSockets errors\n");

      std::string errorMsg = "Failed to initiate WebSocket connection to " +
                            _host + ":" + std::to_string(_port) +
                            " - Check network connectivity, DNS resolution, and LibWebSockets logs above";
      throw std::runtime_error(errorMsg);
    }
    printf("[WebSocket] ✅ Connection handle created, waiting for handshake...\n");
    
    // Start service thread
    _running = true;
    _serviceThread = std::thread([this]() {
      serviceLoop();
    });
    
    // Note: This returns immediately after initiating connection
    // The actual "connected" state is signaled via onOpen callback
  });
}

// ============================================================
// Service Loop (runs in separate thread)
// ============================================================

void HybridWebSocket::serviceLoop() {
  // Adaptive polling: start aggressive, back off when idle
  int pollTimeout = 1; // Start with 1ms for low latency
  int idleCount = 0;
  const int MAX_IDLE_COUNT = 10;
  const int MAX_TIMEOUT = 50; // Max 50ms when idle

  while (_running && _context) {
    // Service the connection with adaptive timeout
    int result = lws_service(_context, pollTimeout);

    if (result < 0) {
      break; // Service error
    }

    // Adaptive polling: increase timeout when idle to save CPU
    if (result == 0) {
      idleCount++;
      if (idleCount > MAX_IDLE_COUNT && pollTimeout < MAX_TIMEOUT) {
        pollTimeout = std::min(pollTimeout * 2, MAX_TIMEOUT);
      }
    } else {
      idleCount = 0;
      pollTimeout = 1; // Reset to low latency when active
    }

    // Process send queue - BATCH PROCESS multiple messages
    if (_wsi && _state == State::OPEN) {
      // Try lock first to avoid blocking if queue is being modified
      std::unique_lock<std::mutex> lock(_sendMutex, std::try_to_lock);
      if (!lock.owns_lock()) {
        continue; // Skip this iteration if locked
      }

      // Process up to 64 messages per iteration (increased batch size)
      int batchCount = 0;
      const int MAX_BATCH_SIZE = 64;

      while (!_sendQueue.empty() && batchCount < MAX_BATCH_SIZE) {
        auto& msg = _sendQueue.front();

        // Prepare buffer with LWS_PRE padding
        std::vector<uint8_t> buffer(LWS_PRE + msg.data.size());
        std::copy(msg.data.begin(), msg.data.end(), buffer.begin() + LWS_PRE);

        // Determine write protocol based on message type
        lws_write_protocol writeProtocol = msg.isBinary ? LWS_WRITE_BINARY : LWS_WRITE_TEXT;

        // Unlock during write to avoid blocking senders
        lock.unlock();

        // Write to WebSocket
        int written = lws_write(
          _wsi,
          buffer.data() + LWS_PRE,
          msg.data.size(),
          writeProtocol
        );

        lock.lock();

        if (written == static_cast<int>(msg.data.size())) {
          _sendQueue.pop();
          batchCount++;
          // Track performance metrics
          _messagesSent.fetch_add(1, std::memory_order_relaxed);
          _bytesSent.fetch_add(msg.data.size(), std::memory_order_relaxed);
        } else {
          // Write failed, stop batch processing
          break;
        }
      }
    }
  }
}

// ============================================================
// Send
// ============================================================

void HybridWebSocket::send(const std::string& message) {
  if (_state != State::OPEN) {
    throw std::runtime_error("WebSocket is not open");
  }

  QueuedMessage msg;
  msg.data.reserve(message.size()); // Pre-allocate to avoid reallocation
  msg.data.assign(message.begin(), message.end());
  msg.isBinary = false;

  {
    std::lock_guard<std::mutex> lock(_sendMutex);
    _sendQueue.push(std::move(msg));
  }

  // Wake up service thread only if needed (when idle)
  // lws_cancel_service is relatively expensive, so avoid when not needed
  if (_context) {
    lws_cancel_service(_context);
  }
}

void HybridWebSocket::sendBinary(const std::shared_ptr<ArrayBuffer>& data) {
  if (_state != State::OPEN) {
    throw std::runtime_error("WebSocket is not open");
  }

  const uint8_t* bytes = data->data();
  size_t size = data->size();

  QueuedMessage msg;
  msg.data.reserve(size); // Pre-allocate to avoid reallocation
  msg.data.assign(bytes, bytes + size);
  msg.isBinary = true;

  {
    std::lock_guard<std::mutex> lock(_sendMutex);
    _sendQueue.push(std::move(msg));
  }

  // Wake up service thread
  if (_context) {
    lws_cancel_service(_context);
  }
}

// ============================================================
// Close
// ============================================================

void HybridWebSocket::close(
    const std::optional<double> code, 
    const std::optional<std::string>& reason) {
  
  if (_state == State::CLOSED || _state == State::CLOSING) {
    return;
  }
  
  _state = State::CLOSING;
  
  if (_wsi) {
    int closeCode = code.has_value() ? 
                   static_cast<int>(code.value()) : 
                   LWS_CLOSE_STATUS_NORMAL;
    std::string closeReason = reason.value_or("");
    
    lws_close_reason(
      _wsi, 
      static_cast<lws_close_status>(closeCode),
      reinterpret_cast<unsigned char*>(const_cast<char*>(closeReason.c_str())),
      closeReason.length()
    );
    lws_callback_on_writable(_wsi);
  }
  
  // Stop service loop
  _running = false;
}

// ============================================================
// Cleanup
// ============================================================

void HybridWebSocket::cleanup() {
  _running = false;
  
  if (_serviceThread.joinable()) {
    _serviceThread.join();
  }
  
  if (_context) {
    lws_context_destroy(_context);
    _context = nullptr;
  }
  
  _wsi = nullptr;
  _state = State::CLOSED;
  
  std::lock_guard<std::mutex> lock(_sendMutex);
  while (!_sendQueue.empty()) {
    _sendQueue.pop();
  }
}

// ============================================================
// Getters / Setters
// ============================================================

void HybridWebSocket::setPingInterval(double intervalMs) {
  _pingIntervalMs = static_cast<int>(intervalMs);

  if (_wsi && intervalMs > 0) {
    lws_set_timeout(
      _wsi,
      PENDING_TIMEOUT_USER_OK,
      static_cast<int>(intervalMs / 1000)
    );
  }
}

void HybridWebSocket::setCAPath(const std::string& path) {
  _caPath = path;
}

double HybridWebSocket::getState() {
  return static_cast<double>(_state.load());
}

std::string HybridWebSocket::getUrl() {
  return _url;
}

void HybridWebSocket::setOnOpen(
    const std::optional<std::function<void()>>& value) {
  std::lock_guard<std::mutex> lock(_callbackMutex);
  _onOpen = value;
}

void HybridWebSocket::setOnMessage(
    const std::optional<std::function<void(const std::string&)>>& value) {
  std::lock_guard<std::mutex> lock(_callbackMutex);
  _onMessage = value;
}

void HybridWebSocket::setOnBinaryMessage(
    const std::optional<std::function<void(const std::shared_ptr<ArrayBuffer>&)>>& value) {
  std::lock_guard<std::mutex> lock(_callbackMutex);
  _onBinaryMessage = value;
}

void HybridWebSocket::setOnError(
    const std::optional<std::function<void(const std::string&)>>& value) {
  std::lock_guard<std::mutex> lock(_callbackMutex);
  _onError = value;
}

void HybridWebSocket::setOnClose(
    const std::optional<std::function<void(double, const std::string&)>>& value) {
  std::lock_guard<std::mutex> lock(_callbackMutex);
  _onClose = value;
}

// ============================================================
// LibWebSockets Callback Handler
// ============================================================

int HybridWebSocket::websocketCallback(
    struct lws* wsi,
    enum lws_callback_reasons reason,
    void* user,
    void* in,
    size_t len) {
  
  auto* userData = static_cast<WebSocketUserData*>(user);
  if (!userData || !userData->instance) {
    return 0;
  }
  
  auto* ws = userData->instance;
  
  switch (reason) {
    case LWS_CALLBACK_CLIENT_ESTABLISHED: {
      // Connection established
      ws->_state = State::OPEN;

      #ifdef DEBUG
      printf("[WebSocket] Connection established successfully!\n");
      #endif

      std::lock_guard<std::mutex> lock(ws->_callbackMutex);
      if (ws->_onOpen.has_value()) {
        try {
          ws->_onOpen.value()();
        } catch (...) {
          // Catch exceptions from JS callback
        }
      }
      break;
    }
      
    case LWS_CALLBACK_CLIENT_RECEIVE: {
      bool isBinary = lws_frame_is_binary(wsi);

      // Track performance metrics
      ws->_messagesReceived.fetch_add(1, std::memory_order_relaxed);
      ws->_bytesReceived.fetch_add(len, std::memory_order_relaxed);

      if (isBinary) {
        // Binary message - use static factory method
        auto buffer = ArrayBuffer::copy(static_cast<const uint8_t*>(in), len);

        // Optimize: check if callback exists before locking
        std::unique_lock<std::mutex> lock(ws->_callbackMutex, std::defer_lock);
        if (lock.try_lock() && ws->_onBinaryMessage.has_value()) {
          try {
            // Copy callback to minimize critical section
            auto callback = ws->_onBinaryMessage.value();
            lock.unlock();
            // Execute outside of lock
            callback(buffer);
          } catch (...) {
            // Catch exceptions from JS callback
          }
        }
      } else {
        // Text message - reserve space for better performance
        std::string message;
        message.reserve(len);
        message.assign(static_cast<char*>(in), len);

        // Optimize: check if callback exists before locking
        std::unique_lock<std::mutex> lock(ws->_callbackMutex, std::defer_lock);
        if (lock.try_lock() && ws->_onMessage.has_value()) {
          try {
            // Copy callback to minimize critical section
            auto callback = ws->_onMessage.value();
            lock.unlock();
            // Execute outside of lock
            callback(message);
          } catch (...) {
            // Catch exceptions from JS callback
          }
        }
      }
      break;
    }
      
    case LWS_CALLBACK_CLIENT_CONNECTION_ERROR: {
      // Connection error
      ws->_state = State::CLOSED;

      std::string error = in ?
        std::string(static_cast<char*>(in)) :
        "Connection error";

      // Always log connection errors to help debugging
      printf("[WebSocket] CONNECTION ERROR: %s\n", error.c_str());
      printf("[WebSocket] URL was: %s\n", ws->_url.c_str());

      std::lock_guard<std::mutex> lock(ws->_callbackMutex);
      if (ws->_onError.has_value()) {
        try {
          ws->_onError.value()(error);
        } catch (...) {}
      }
      break;
    }
      
    case LWS_CALLBACK_CLIENT_CLOSED: {
      // Connection closed
      ws->_state = State::CLOSED;
      
      std::lock_guard<std::mutex> lock(ws->_callbackMutex);
      if (ws->_onClose.has_value()) {
        try {
          ws->_onClose.value()(1000.0, "Connection closed");
        } catch (...) {}
      }
      break;
    }
      
    case LWS_CALLBACK_CLIENT_WRITEABLE: {
      // Ready to write more data
      break;
    }
      
    case LWS_CALLBACK_WSI_DESTROY: {
      // Connection being destroyed
      if (userData) {
        delete userData;
      }
      break;
    }
      
    default:
      break;
  }
  
  return 0;
}

// ============================================================
// Buffer Pool Implementation
// ============================================================

std::vector<uint8_t> HybridWebSocket::getBuffer(size_t size) {
  std::lock_guard<std::mutex> lock(_bufferPoolMutex);

  // Try to reuse a buffer from the pool if available
  if (!_bufferPool.empty() && _bufferPool.back().capacity() >= size) {
    auto buffer = std::move(_bufferPool.back());
    _bufferPool.pop_back();
    buffer.resize(size);
    return buffer;
  }

  // Allocate new buffer if pool is empty or buffers are too small
  std::vector<uint8_t> buffer;
  buffer.reserve(std::max(size, BUFFER_SIZE));
  buffer.resize(size);
  return buffer;
}

void HybridWebSocket::returnBuffer(std::vector<uint8_t>&& buffer) {
  std::lock_guard<std::mutex> lock(_bufferPoolMutex);

  // Only return buffers to pool if we haven't exceeded the max
  if (_bufferPool.size() < MAX_POOLED_BUFFERS) {
    buffer.clear(); // Keep capacity, clear contents
    _bufferPool.push_back(std::move(buffer));
  }
  // Otherwise just let it be destroyed
}

} // namespace margelo::nitro::realtimenitro