#pragma once

// IMPORTANT: Include the generated spec
#include "HybridWebSocketSpec.hpp"

#include <memory>
#include <string>
#include <vector>
#include <functional>
#include <thread>
#include <mutex>
#include <atomic>
#include <queue>

#include <libwebsockets.h>

namespace margelo::nitro::realtimenitro {

using namespace margelo::nitro;

/**
 * WebSocket connection states (matches TypeScript enum)
 */
enum class State {
  CONNECTING = 0,
  OPEN = 1,
  CLOSING = 2,
  CLOSED = 3
};

/**
 * High-performance WebSocket implementation using libwebsockets
 * 
 * This class implements the HybridWebSocketSpec interface generated
 * by Nitrogen from WebSocket.nitro.ts
 * 
 * Thread Safety:
 * - All public methods are thread-safe
 * - Internal state protected by mutexes
 * - Service thread for I/O operations
 */
class HybridWebSocket : public HybridWebSocketSpec {
public:
  /**
   * Constructor
   * Must be default-constructible for Nitro autolinking
   */
  explicit HybridWebSocket() : HybridObject(TAG) {
    // Initialize logging (set to silent in production)
    // lws_set_log_level(0, nullptr);
  }
  
  /**
   * Destructor
   * Ensures clean shutdown of WebSocket connection
   */
  virtual ~HybridWebSocket();
  
  // ============================================================
  // HybridWebSocketSpec Implementation
  // ============================================================
  
  /**
   * Connect to WebSocket server
   * 
   * @param url WebSocket URL (ws:// or wss://)
   * @param protocols Optional sub-protocols
   * @return Promise that resolves when connected
   */
  std::shared_ptr<Promise<void>> connect(
    const std::string& url, 
    const std::optional<std::vector<std::string>>& protocols
  ) override;
  
  /**
   * Send text message
   * @throws std::runtime_error if not connected
   */
  void send(const std::string& message) override;
  
  /**
   * Send binary data
   * @throws std::runtime_error if not connected
   */
  void sendBinary(const std::shared_ptr<ArrayBuffer>& data) override;
  
  /**
   * Close WebSocket connection
   */
  void close(
    const std::optional<double> code, 
    const std::optional<std::string>& reason
  ) override;
  
  /**
   * Set ping interval for keep-alive
   */
  void setPingInterval(double intervalMs) override;

  /**
   * Set CA certificate path for SSL verification
   */
  void setCAPath(const std::string& path) override;

  // Getters
  double getState() override;
  std::string getUrl() override;
  
  // Callback setters
  void setOnOpen(const std::optional<std::function<void()>>& value) override;
  void setOnMessage(const std::optional<std::function<void(const std::string&)>>& value) override;
  void setOnBinaryMessage(const std::optional<std::function<void(const std::shared_ptr<ArrayBuffer>&)>>& value) override;
  void setOnError(const std::optional<std::function<void(const std::string&)>>& value) override;
  void setOnClose(const std::optional<std::function<void(double, const std::string&)>>& value) override;
  
  // Callback getters (required by spec)
  std::optional<std::function<void()>> getOnOpen() override { return _onOpen; }
  std::optional<std::function<void(const std::string&)>> getOnMessage() override { return _onMessage; }
  std::optional<std::function<void(const std::shared_ptr<ArrayBuffer>&)>> getOnBinaryMessage() override { return _onBinaryMessage; }
  std::optional<std::function<void(const std::string&)>> getOnError() override { return _onError; }
  std::optional<std::function<void(double, const std::string&)>> getOnClose() override { return _onClose; }

  /**
   * Get external memory size for garbage collector
   */
  size_t getExternalMemorySize() noexcept override {
    return sizeof(HybridWebSocket);
  }

private:
  static constexpr auto TAG = "WebSocket";
  
  // ============================================================
  // LibWebSockets members
  // ============================================================
  
  struct lws_context* _context = nullptr;
  struct lws* _wsi = nullptr;
  
  // ============================================================
  // Connection state
  // ============================================================
  
  std::atomic<State> _state{State::CLOSED};
  std::string _url;
  std::string _host;
  std::string _path;
  int _port = 0;
  bool _useSsl = false;
  
  // ============================================================
  // Message queue (thread-safe)
  // ============================================================

  struct QueuedMessage {
    std::vector<uint8_t> data;
    bool isBinary;
  };

  std::queue<QueuedMessage> _sendQueue;
  std::mutex _sendMutex;
  
  // ============================================================
  // Service thread for I/O
  // ============================================================
  
  std::thread _serviceThread;
  std::atomic<bool> _running{false};
  
  // ============================================================
  // Callbacks (thread-safe)
  // ============================================================
  
  std::optional<std::function<void()>> _onOpen;
  std::optional<std::function<void(const std::string&)>> _onMessage;
  std::optional<std::function<void(const std::shared_ptr<ArrayBuffer>&)>> _onBinaryMessage;
  std::optional<std::function<void(const std::string&)>> _onError;
  std::optional<std::function<void(double, const std::string&)>> _onClose;
  std::mutex _callbackMutex;
  
  // ============================================================
  // Configuration
  // ============================================================

  int _pingIntervalMs = 30000; // 30 seconds default
  std::string _caPath;  // CA certificate path (empty = disable verification)

  // ============================================================
  // Buffer pool for reducing allocations
  // ============================================================

  std::vector<std::vector<uint8_t>> _bufferPool;
  std::mutex _bufferPoolMutex;
  static constexpr size_t MAX_POOLED_BUFFERS = 10;
  static constexpr size_t BUFFER_SIZE = 4096;

  // ============================================================
  // Performance metrics (atomic for lock-free reads)
  // ============================================================

  std::atomic<uint64_t> _messagesSent{0};
  std::atomic<uint64_t> _messagesReceived{0};
  std::atomic<uint64_t> _bytesSent{0};
  std::atomic<uint64_t> _bytesReceived{0};
  
  // ============================================================
  // Private methods
  // ============================================================
  
  /**
   * Parse WebSocket URL
   * @return true if valid, false otherwise
   */
  bool parseUrl(const std::string& url);
  
  /**
   * Service loop (runs in separate thread)
   */
  void serviceLoop();
  
  /**
   * Cleanup resources
   */
  void cleanup();
  
  /**
   * LibWebSockets callback handler (static)
   */
  static int websocketCallback(
    struct lws* wsi,
    enum lws_callback_reasons reason,
    void* user,
    void* in,
    size_t len
  );

  /**
   * Get buffer from pool or allocate new one
   */
  std::vector<uint8_t> getBuffer(size_t size);

  /**
   * Return buffer to pool for reuse
   */
  void returnBuffer(std::vector<uint8_t>&& buffer);
};

} // namespace margelo::nitro::realtimenitro