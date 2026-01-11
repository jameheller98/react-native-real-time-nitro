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
        .id = 0,
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
    // Optimized for mobile: smaller window size (12 instead of 15) saves 28KB per connection
    static const struct lws_extension extensions[] = {
      {
        "permessage-deflate",
        lws_extension_callback_pm_deflate,
        "permessage-deflate"
        "; client_no_context_takeover"
        "; client_max_window_bits=12"  // Smaller window for mobile (saves memory)
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
#ifdef LCCSCF_USE_TLS13
      ccinfo.ssl_connection |= LCCSCF_USE_TLS13;
#endif

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
  // Let libwebsockets automatically determine the optimal timeout
  // based on internal timers, pending writes, and connection state
  // (more efficient than manual adaptive polling)
  while (_running && _context) {
    // Service with auto timeout (0 = libwebsockets decides)
    int result = lws_service(_context, 0);

    if (result < 0) {
      break; // Service error
    }

    // Process send queue - BATCH PROCESS multiple messages
    if (_wsi && _state == State::OPEN) {
      // Try lock first to avoid blocking if queue is being modified
      std::unique_lock<std::mutex> lock(_sendMutex, std::try_to_lock);
      if (!lock.owns_lock()) {
        continue; // Skip this iteration if locked
      }

      // Adaptive batching: process many small messages or fewer large messages
      int batchCount = 0;
      size_t batchBytes = 0;
      const int MAX_BATCH_SIZE = 64;
      const size_t MAX_BATCH_BYTES = 256 * 1024; // 256KB per batch

      while (!_sendQueue.empty() &&
             batchCount < MAX_BATCH_SIZE &&
             batchBytes < MAX_BATCH_BYTES) {
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
          // Decrement queue bytes counter
          _queueBytes.fetch_sub(msg.data.size());

          // Track batch progress
          batchBytes += msg.data.size();
          batchCount++;

          _sendQueue.pop();

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

    // Backpressure: check queue limits
    if (_sendQueue.size() >= MAX_QUEUE_SIZE ||
        _queueBytes.load() >= MAX_QUEUE_BYTES) {
      throw std::runtime_error("Send queue full - connection too slow");
    }

    _sendQueue.push(std::move(msg));
    _queueBytes.fetch_add(msg.data.size());
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

    // Backpressure: check queue limits
    if (_sendQueue.size() >= MAX_QUEUE_SIZE ||
        _queueBytes.load() >= MAX_QUEUE_BYTES) {
      throw std::runtime_error("Send queue full - connection too slow");
    }

    _sendQueue.push(std::move(msg));
    _queueBytes.fetch_add(msg.data.size());
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

  {
    std::lock_guard<std::mutex> lock(_sendMutex);
    while (!_sendQueue.empty()) {
      _sendQueue.pop();
    }
    _queueBytes.store(0);
  }

  {
    std::lock_guard<std::mutex> lock(_fragmentMutex);
    _fragmentBuffer.clear();
  }
}

// ============================================================
// Getters / Setters
// ============================================================

void HybridWebSocket::setPingInterval(double intervalMs) {
  _pingIntervalMs = static_cast<int>(intervalMs);
  // Note: Actual ping sending is handled in the service loop
  // We do NOT use lws_set_timeout here as that would close the connection
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

double HybridWebSocket::getPingLatency() {
  return static_cast<double>(_pingLatencyMs.load(std::memory_order_relaxed));
}

ConnectionMetrics HybridWebSocket::getConnectionMetrics() {
  double queueSize;
  {
    std::lock_guard<std::mutex> lock(_sendMutex);
    queueSize = static_cast<double>(_sendQueue.size());
  }

  return ConnectionMetrics(
    static_cast<double>(_messagesSent.load(std::memory_order_relaxed)),
    static_cast<double>(_messagesReceived.load(std::memory_order_relaxed)),
    static_cast<double>(_bytesSent.load(std::memory_order_relaxed)),
    static_cast<double>(_bytesReceived.load(std::memory_order_relaxed)),
    static_cast<double>(_pingLatencyMs.load(std::memory_order_relaxed)),
    queueSize,
    static_cast<double>(_queueBytes.load(std::memory_order_relaxed))
  );
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

      if (ws->_pingIntervalMs > 0) {
        lws_set_timer_usecs(
          wsi,
          ws->_pingIntervalMs * 1000
        );
      }

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
      bool isFirstFragment = lws_is_first_fragment(wsi);
      bool isFinalFragment = lws_is_final_fragment(wsi);

      // Track performance metrics
      ws->_bytesReceived.fetch_add(len, std::memory_order_relaxed);

      // Handle fragmented messages (better memory usage for large messages >64KB)
      if (!isFirstFragment || !isFinalFragment) {
        std::lock_guard<std::mutex> fragLock(ws->_fragmentMutex);

        if (isFirstFragment) {
          // First fragment - reset buffer and pre-allocate intelligently
          ws->_fragmentBuffer.clear();

          // Smart pre-allocation: assume average fragmented message is 128KB
          // (most fragmented messages are large images/files)
          // This reduces reallocation overhead
          size_t estimatedSize = std::max(len * 4, static_cast<size_t>(128 * 1024));
          ws->_fragmentBuffer.reserve(estimatedSize);
          ws->_fragmentIsBinary = isBinary;

          #ifdef DEBUG
          printf("[WebSocket] First fragment received, pre-allocated %zu bytes\n", estimatedSize);
          #endif
        }

        // Accumulate fragment
        const uint8_t* data = static_cast<const uint8_t*>(in);
        ws->_fragmentBuffer.insert(ws->_fragmentBuffer.end(), data, data + len);

        if (isFinalFragment) {
          // Final fragment - deliver complete message
          ws->_messagesReceived.fetch_add(1, std::memory_order_relaxed);

          if (ws->_fragmentIsBinary) {
            auto buffer = ArrayBuffer::copy(ws->_fragmentBuffer.data(), ws->_fragmentBuffer.size());

            std::unique_lock<std::mutex> lock(ws->_callbackMutex, std::defer_lock);
            if (lock.try_lock() && ws->_onBinaryMessage.has_value()) {
              try {
                auto callback = ws->_onBinaryMessage.value();
                lock.unlock();
                callback(buffer);
              } catch (...) {}
            }
          } else {
            std::string message(ws->_fragmentBuffer.begin(), ws->_fragmentBuffer.end());

            std::unique_lock<std::mutex> lock(ws->_callbackMutex, std::defer_lock);
            if (lock.try_lock() && ws->_onMessage.has_value()) {
              try {
                auto callback = ws->_onMessage.value();
                lock.unlock();
                callback(message);
              } catch (...) {}
            }
          }

          // Clear buffer after delivery and free memory
          // Using swap trick to force deallocation
          std::vector<uint8_t>().swap(ws->_fragmentBuffer);
        }
      } else {
        // Complete message in single frame (most common case)
        ws->_messagesReceived.fetch_add(1, std::memory_order_relaxed);

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
      }
      break;
    }
      
    case LWS_CALLBACK_CLIENT_CONNECTION_ERROR: {
      // Connection error
      ws->_state = State::CLOSED;

      std::string error = in ?
        std::string(static_cast<char*>(in)) :
        "Connection error";

      // Enhanced error diagnostics - categorize common error types
      std::string detailedError = error;
      std::string errorCategory;

      if (error.find("SSL") != std::string::npos ||
          error.find("TLS") != std::string::npos ||
          error.find("certificate") != std::string::npos) {
        errorCategory = "SSL/TLS Error";
        detailedError += " (SSL/TLS handshake failed - check certificate validity and CA path)";
      } else if (error.find("timeout") != std::string::npos ||
                 error.find("Timeout") != std::string::npos) {
        errorCategory = "Timeout Error";
        detailedError += " (Connection timeout - check network connectivity and server availability)";
      } else if (error.find("DNS") != std::string::npos ||
                 error.find("resolve") != std::string::npos ||
                 error.find("getaddrinfo") != std::string::npos) {
        errorCategory = "DNS Error";
        detailedError += " (DNS resolution failed - check hostname and network)";
      } else if (error.find("refused") != std::string::npos ||
                 error.find("Refused") != std::string::npos) {
        errorCategory = "Connection Refused";
        detailedError += " (Server refused connection - check server is running and port is correct)";
      } else if (error.find("unreachable") != std::string::npos) {
        errorCategory = "Network Unreachable";
        detailedError += " (Network unreachable - check network connectivity)";
      } else {
        errorCategory = "Connection Error";
      }

      // Always log connection errors to help debugging
      printf("[WebSocket] ========================================\n");
      printf("[WebSocket] CONNECTION ERROR\n");
      printf("[WebSocket] Category: %s\n", errorCategory.c_str());
      printf("[WebSocket] Details: %s\n", detailedError.c_str());
      printf("[WebSocket] URL: %s\n", ws->_url.c_str());
      printf("[WebSocket] ========================================\n");

      std::lock_guard<std::mutex> lock(ws->_callbackMutex);
      if (ws->_onError.has_value()) {
        try {
          ws->_onError.value()(detailedError);
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
      // Send ping only if timer triggered it (atomic exchange clears flag)
      if (ws->_pingPending.exchange(false, std::memory_order_relaxed)) {
        // Record ping send time for latency tracking
        ws->_lastPingTime = std::chrono::steady_clock::now();

        // Send ping frame with empty payload
        unsigned char ping_payload[LWS_PRE];
        lws_write(wsi, &ping_payload[LWS_PRE], 0, LWS_WRITE_PING);

        #ifdef DEBUG
        printf("[WebSocket] Ping sent (interval: %dms)\n", ws->_pingIntervalMs);
        #endif
      }
      // Ready to write more data
      break;
    }

    case LWS_CALLBACK_WS_PEER_INITIATED_CLOSE: {
      // Server initiated close
      #ifdef DEBUG
      printf("[WebSocket] Server initiated close\n");
      #endif
      break;
    }

    case LWS_CALLBACK_CLIENT_RECEIVE_PONG: {
      // Received pong response - calculate latency for connection health monitoring
      auto now = std::chrono::steady_clock::now();
      auto latency = std::chrono::duration_cast<std::chrono::milliseconds>(
        now - ws->_lastPingTime
      ).count();

      // Store latency metric
      ws->_pingLatencyMs.store(latency, std::memory_order_relaxed);

      #ifdef DEBUG
      printf("[WebSocket] Received pong (latency: %lldms)\n", latency);
      #endif
      break;
    }

    case LWS_CALLBACK_WSI_DESTROY: {
      // Connection being destroyed
      if (userData) {
        delete userData;
      }
      break;
    }

    case LWS_CALLBACK_TIMER: {
      if (ws->_state == State::OPEN && ws->_pingIntervalMs > 0) {
        // Mark that a ping is pending
        ws->_pingPending.store(true, std::memory_order_relaxed);

        // Request callback when socket is writable
        lws_callback_on_writable(wsi);

        // Reschedule timer for next ping
        lws_set_timer_usecs(
          wsi,
          ws->_pingIntervalMs * 1000
        );
      }
      break;
    }
      
    default:
      break;
  }
  
  return 0;
}

} // namespace margelo::nitro::realtimenitro