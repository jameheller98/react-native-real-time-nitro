import { NitroModules } from 'react-native-nitro-modules'
import type { WebSocket } from './specs/WebSocket.nitro'

/**
 * Create a new WebSocket instance
 *
 * SSL/TLS works automatically without certificate verification
 * For production, use ws.setCAPath('/path/to/cacert.pem') to enable verification
 *
 * @returns WebSocket hybrid object
 *
 * @example
 * ```typescript
 * const ws = createWebSocket()
 *
 * ws.onOpen = () => console.log('Connected!')
 * ws.onMessage = (msg) => console.log('Received:', msg)
 *
 * await ws.connect('wss://echo.websocket.org')
 * ws.send('Hello, Server!')
 * ```
 */
export function createWebSocket(): WebSocket {
  return NitroModules.createHybridObject<WebSocket>('WebSocket')
}

// Re-export types
export type { WebSocket, ConnectionMetrics } from './specs/WebSocket.nitro'
export { WebSocketState } from './specs/WebSocket.nitro'
