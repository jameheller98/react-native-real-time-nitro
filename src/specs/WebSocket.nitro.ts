import { type HybridObject } from 'react-native-nitro-modules'

/**
 * WebSocket connection states
 */
export enum WebSocketState {
  CONNECTING = 0,
  OPEN = 1,
  CLOSING = 2,
  CLOSED = 3,
}

/**
 * High-performance WebSocket client
 *
 * @example
 * ```typescript
 * const ws = createWebSocket()
 *
 * ws.onOpen = () => console.log('Connected')
 * ws.onMessage = (msg) => console.log('Received:', msg)
 *
 * await ws.connect('wss://echo.websocket.org')
 * ws.send('Hello!')
 * ```
 */
export interface WebSocket extends HybridObject<{
  ios: 'c++'
  android: 'c++'
}> {
  /**
   * Connect to a WebSocket server
   *
   * @param url - WebSocket URL (ws:// or wss://)
   * @param protocols - Optional sub-protocols
   * @returns Promise that resolves when connected
   * @throws Error if URL is invalid or connection fails
   */
  connect(url: string, protocols?: string[]): Promise<void>

  /**
   * Send a text message
   *
   * @param message - Text message to send
   * @throws Error if not connected
   */
  send(message: string): void

  /**
   * Send binary data
   *
   * @param data - ArrayBuffer containing binary data
   * @throws Error if not connected
   */
  sendBinary(data: ArrayBuffer): void

  /**
   * Close the WebSocket connection
   *
   * @param code - Close code (default: 1000 - Normal Closure)
   * @param reason - Close reason string
   */
  close(code?: number, reason?: string): void

  /**
   * Get current connection state
   */
  readonly state: number // WebSocketState

  /**
   * Get the connected URL
   */
  readonly url: string

  /**
   * Callback when connection opens
   */
  onOpen?: () => void

  /**
   * Callback when text message is received
   *
   * @param message - Received text message
   */
  onMessage?: (message: string) => void

  /**
   * Callback when binary data is received
   *
   * @param data - Received binary data as ArrayBuffer
   */
  onBinaryMessage?: (data: ArrayBuffer) => void

  /**
   * Callback when an error occurs
   *
   * @param error - Error message
   */
  onError?: (error: string) => void

  /**
   * Callback when connection closes
   *
   * @param code - Close code
   * @param reason - Close reason
   */
  onClose?: (code: number, reason: string) => void

  /**
   * Set ping interval for keep-alive
   *
   * @param intervalMs - Ping interval in milliseconds (0 to disable)
   */
  setPingInterval(intervalMs: number): void

  /**
   * Set CA certificate file path for SSL/TLS verification
   *
   * @param path - Absolute path to CA certificate file (PEM format)
   *              Pass empty string to disable certificate verification
   */
  setCAPath(path: string): void

  /**
   * Get current ping/pong latency in milliseconds
   *
   * @returns Latency in milliseconds (0 if no ping/pong completed yet)
   */
  getPingLatency(): number

  /**
   * Get comprehensive connection metrics
   *
   * @returns Object containing performance metrics
   */
  getConnectionMetrics(): ConnectionMetrics
}

/**
 * Connection performance metrics
 */
export interface ConnectionMetrics {
  /**
   * Total messages sent
   */
  messagesSent: number

  /**
   * Total messages received
   */
  messagesReceived: number

  /**
   * Total bytes sent
   */
  bytesSent: number

  /**
   * Total bytes received
   */
  bytesReceived: number

  /**
   * Current ping latency in milliseconds (0 if unavailable)
   */
  pingLatencyMs: number

  /**
   * Current send queue size
   */
  queueSize: number

  /**
   * Current send queue bytes
   */
  queueBytes: number
}
