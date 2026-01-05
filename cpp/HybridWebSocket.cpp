#include "HybridWebSocket.hpp"
#include <NitroModules/ArrayBuffer.hpp>

#include <sstream>
#include <chrono>
#include <cstring>
#include <algorithm> 

// LibWebSockets includes
#include <libwebsockets.h>

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

    // Log parsed URL components for debugging
    printf("[WebSocket] Connecting to:\n");
    printf("  URL: %s\n", url.c_str());
    printf("  Host: %s\n", _host.c_str());
    printf("  Port: %d\n", _port);
    printf("  Path: %s\n", _path.c_str());
    printf("  SSL: %s\n", _useSsl ? "yes" : "no");

    // Cleanup any existing connection
    cleanup();

    _state = State::CONNECTING;
    
    // Setup LibWebSockets protocols list
    static struct lws_protocols protocolsList[] = {
      {
        .name = "websocket-protocol",
        .callback = HybridWebSocket::websocketCallback,
        .per_session_data_size = sizeof(WebSocketUserData),
        .rx_buffer_size = 65536,
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

    // Note: On mobile platforms (iOS/Android), CA certs are in system trust store
    // LibWebSockets should automatically use them for SSL verification

    // Enable LibWebSockets logging for debugging
    lws_set_log_level(LLL_ERR | LLL_WARN | LLL_NOTICE | LLL_INFO | LLL_DEBUG, nullptr);

    printf("[WebSocket] Creating LibWebSockets context...\n");
    _context = lws_create_context(&info);
    if (!_context) {
      _state = State::CLOSED;
      throw std::runtime_error("Failed to create WebSocket context - check LibWebSockets installation");
    }
    printf("[WebSocket] Context created successfully\n");
    
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
      ccinfo.ssl_connection = LCCSCF_USE_SSL |
                              LCCSCF_ALLOW_SELFSIGNED |
                              LCCSCF_SKIP_SERVER_CERT_HOSTNAME_CHECK;
      printf("[WebSocket] SSL enabled with permissive certificate validation\n");
    }

    // User data for callbacks
    auto* userData = new WebSocketUserData{this};
    ccinfo.userdata = userData;
    ccinfo.pwsi = &_wsi;

    // Initiate connection
    printf("[WebSocket] Initiating connection to %s:%d%s...\n",
           _host.c_str(), _port, _path.c_str());
    _wsi = lws_client_connect_via_info(&ccinfo);
    if (!_wsi) {
      delete userData;
      cleanup();
      std::string errorMsg = "Failed to initiate WebSocket connection to " +
                            _host + ":" + std::to_string(_port) +
                            " - Check network connectivity, DNS resolution, and LibWebSockets logs above";
      throw std::runtime_error(errorMsg);
    }
    printf("[WebSocket] Connection initiated, waiting for handshake...\n");
    
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
  while (_running && _context) {
    // Service the connection
    int result = lws_service(_context, 50); // 50ms timeout
    
    if (result < 0) {
      break; // Service error
    }
    
    // Process send queue
    if (_wsi && _state == State::OPEN) {
      std::lock_guard<std::mutex> lock(_sendMutex);
      
      if (!_sendQueue.empty()) {
        auto& data = _sendQueue.front();
        
        // Prepare buffer with LWS_PRE padding
        std::vector<uint8_t> buffer(LWS_PRE + data.size());
        std::copy(data.begin(), data.end(), buffer.begin() + LWS_PRE);
        
        // Write to WebSocket
        int written = lws_write(
          _wsi, 
          buffer.data() + LWS_PRE,
          data.size(),
          LWS_WRITE_TEXT
        );
        
        if (written == static_cast<int>(data.size())) {
          _sendQueue.pop();
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
  
  std::lock_guard<std::mutex> lock(_sendMutex);
  std::vector<uint8_t> data(message.begin(), message.end());
  _sendQueue.push(std::move(data));
  
  // Wake up service thread
  if (_context) {
    lws_cancel_service(_context);
  }
}

void HybridWebSocket::sendBinary(const std::shared_ptr<ArrayBuffer>& data) {
  if (_state != State::OPEN) {
    throw std::runtime_error("WebSocket is not open");
  }
  
  std::lock_guard<std::mutex> lock(_sendMutex);
  
  const uint8_t* bytes = data->data();
  size_t size = data->size();
  
  std::vector<uint8_t> buffer(bytes, bytes + size);
  _sendQueue.push(std::move(buffer));
  
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

      printf("[WebSocket] Connection established successfully!\n");

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
      
      if (isBinary) {
        // Binary message - use static factory method
        auto buffer = ArrayBuffer::copy(static_cast<const uint8_t*>(in), len);
        
        std::lock_guard<std::mutex> lock(ws->_callbackMutex);
        if (ws->_onBinaryMessage.has_value()) {
          try {
            ws->_onBinaryMessage.value()(buffer);
          } catch (...) {}
        }
      } else {
        // Text message
        std::string message(static_cast<char*>(in), len);
        
        std::lock_guard<std::mutex> lock(ws->_callbackMutex);
        if (ws->_onMessage.has_value()) {
          try {
            ws->_onMessage.value()(message);
          } catch (...) {}
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

      printf("[WebSocket] CONNECTION ERROR: %s\n", error.c_str());

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

} // namespace margelo::nitro::realtimenitro