<h1 align="center">⚡ react-native-real-time-nitro</h1>

<p align="center">
  <strong>High-performance WebSocket client for React Native</strong>
</p>

<p align="center">
  <a href="https://www.npmjs.com/package/react-native-real-time-nitro">
    <img src="https://img.shields.io/npm/v/react-native-real-time-nitro.svg?style=flat-square&color=00D9FF" alt="npm version" />
  </a>
  <a href="https://www.npmjs.com/package/react-native-real-time-nitro">
    <img src="https://img.shields.io/npm/dm/react-native-real-time-nitro.svg?style=flat-square&color=00D9FF" alt="npm downloads" />
  </a>
  <a href="https://github.com/jameheller98/react-native-real-time-nitro/blob/main/LICENSE">
    <img src="https://img.shields.io/npm/l/react-native-real-time-nitro.svg?style=flat-square&color=00D9FF" alt="license" />
  </a>
  <a href="https://github.com/jameheller98/react-native-real-time-nitro">
    <img src="https://img.shields.io/badge/platform-iOS%20%7C%20Android-00D9FF.svg?style=flat-square" alt="platforms" />
  </a>
</p>

<p align="center">
  A blazing-fast WebSocket library built with native C++ for maximum performance
</p>

---

## ✨ Features

<table>
<tr>
<td>

🚀 **Native Performance**
- Zero JavaScript overhead
- C++ implementation

</td>
<td>

🔒 **Secure by Default**
- SSL/TLS support
- Bundled CA certificates

</td>
</tr>
<tr>
<td>

📦 **Binary Support**
- Native ArrayBuffer
- Full binary protocol support

</td>
<td>

🗜️ **Auto Compression**
- 60-80% bandwidth reduction
- Per-message-deflate

</td>
</tr>
<tr>
<td>

🧵 **Thread-Safe**
- Background I/O thread
- Non-blocking operations

</td>
<td>

🌍 **Cross-Platform**
- iOS & Android
- Identical API

</td>
</tr>
</table>

---

## 📦 Installation

### Prerequisites

This library requires `react-native-nitro-modules` as a peer dependency:

```bash
npm install react-native-nitro-modules react-native-real-time-nitro
```

or

```bash
yarn add react-native-nitro-modules react-native-real-time-nitro
```

### Platform Setup

<table>
<tr>
<td width="50%">

**🍎 iOS**

```bash
cd ios && pod install
```

</td>
<td width="50%">

**🤖 Android**

No additional setup required ✅

</td>
</tr>
</table>

---

## 🚀 Quick Start

```typescript
import { createWebSocket } from 'react-native-real-time-nitro'

const ws = createWebSocket()

// 📡 Setup callbacks
ws.onOpen = () => console.log('✅ Connected')
ws.onMessage = (msg) => console.log('📨 Received:', msg)
ws.onError = (error) => console.error('❌ Error:', error)
ws.onClose = (code, reason) => console.log('🔌 Closed:', code, reason)

// 🔗 Connect
await ws.connect('wss://echo.websocket.org')

// 📤 Send message
ws.send('Hello!')

// 👋 Close when done
ws.close(1000, 'Done')
```

---

## 📚 API Reference

### 🏭 Factory

#### `createWebSocket(): WebSocket`

Creates a new WebSocket instance.

```typescript
import { createWebSocket } from 'react-native-real-time-nitro'

const ws = createWebSocket()
```

---

### 🔧 Methods

<details>
<summary><strong>📡 connect(url: string, protocols?: string[]): Promise&lt;void&gt;</strong></summary>

<br/>

Connect to a WebSocket server.

**Parameters:**
- `url` - WebSocket URL (`ws://` or `wss://`)
- `protocols` - Optional array of subprotocol names

**Example:**
```typescript
await ws.connect('wss://example.com', ['chat', 'v1.protocol'])
```

</details>

<details>
<summary><strong>📤 send(message: string): void</strong></summary>

<br/>

Send a text message (only when connected).

**Example:**
```typescript
ws.send('Hello server!')
```

> ⚠️ **Note:** Only call when `ws.state === 1` (OPEN)

</details>

<details>
<summary><strong>📦 sendBinary(data: ArrayBuffer): void</strong></summary>

<br/>

Send binary data.

**Example:**
```typescript
const buffer = new ArrayBuffer(4)
const view = new Uint8Array(buffer)
view[0] = 0x48 // 'H'
ws.sendBinary(buffer)
```

> ⚠️ **Note:** Only call when `ws.state === 1` (OPEN)

</details>

<details>
<summary><strong>🔌 close(code?: number, reason?: string): void</strong></summary>

<br/>

Close the connection gracefully.

**Parameters:**
- `code` - Close code (default: 1000)
- `reason` - Close reason string

**Example:**
```typescript
ws.close(1000, 'Normal closure')
```

</details>

<details>
<summary><strong>💓 setPingInterval(seconds: number): void</strong></summary>

<br/>

Set keep-alive ping interval.

**Example:**
```typescript
ws.setPingInterval(30) // ping every 30 seconds
```

</details>

<details>
<summary><strong>🔐 setCAPath(path: string): void</strong></summary>

<br/>

Set custom CA certificate path for SSL/TLS verification.

**Examples:**
```typescript
// Use custom certificate
ws.setCAPath('/path/to/cert.pem')

// Disable verification (dev only)
ws.setCAPath('')
```

> 🚨 **Warning:** Empty path disables SSL verification. Use only in development!

</details>

---

### 📊 Properties

| Property | Type | Description |
|----------|------|-------------|
| **state** | `WebSocketState` (readonly) | Current connection state |
| **url** | `string` (readonly) | Connected WebSocket URL |

#### Connection States

```typescript
enum WebSocketState {
  CONNECTING = 0,  // 🔄 Connection in progress
  OPEN = 1,        // ✅ Connected and ready
  CLOSING = 2,     // ⏳ Closing in progress
  CLOSED = 3       // 🔌 Connection closed
}
```

**Example:**
```typescript
if (ws.state === 1) {
  ws.send('Message')
}
```

---

### 🎯 Event Callbacks

| Callback | Parameters | Description |
|----------|------------|-------------|
| **onOpen** | `() => void` | ✅ Connection established |
| **onMessage** | `(message: string) => void` | 📨 Text message received |
| **onBinaryMessage** | `(data: ArrayBuffer) => void` | 📦 Binary data received |
| **onError** | `(error: string) => void` | ❌ Error occurred |
| **onClose** | `(code: number, reason: string) => void` | 🔌 Connection closed |

**Example:**
```typescript
ws.onOpen = () => console.log('✅ Connected!')
ws.onMessage = (msg) => console.log('📨', msg)
ws.onBinaryMessage = (data) => console.log('📦', new Uint8Array(data))
ws.onError = (error) => console.error('❌', error)
ws.onClose = (code, reason) => console.log('🔌', code, reason)
```

---

## 💡 Examples

### 💬 Basic Chat

```typescript
import { createWebSocket } from 'react-native-real-time-nitro'
import { useEffect } from 'react'

export default function Chat() {
  useEffect(() => {
    const ws = createWebSocket()

    ws.onOpen = () => {
      console.log('✅ Connected to chat')
      ws.send('Hello everyone!')
    }

    ws.onMessage = (msg) => {
      console.log('💬 New message:', msg)
    }

    ws.connect('wss://chat-server.com')

    return () => ws.close()
  }, [])

  return <YourChatUI />
}
```

### 📦 Binary Data

```typescript
const ws = createWebSocket()

ws.onBinaryMessage = (data) => {
  const view = new Uint8Array(data)
  console.log('📦 Received bytes:', view)
}

ws.onOpen = () => {
  // Send binary data
  const buffer = new ArrayBuffer(8)
  const view = new Uint8Array(buffer)
  view[0] = 0x48 // 'H'
  view[1] = 0x65 // 'e'
  view[2] = 0x6C // 'l'
  view[3] = 0x6C // 'l'
  view[4] = 0x6F // 'o'
  ws.sendBinary(buffer)
}

await ws.connect('wss://binary-server.com')
```

### 🔐 Secure Connection

```typescript
const ws = createWebSocket()

// ✅ Use bundled CA certificates (recommended)
await ws.connect('wss://secure-server.com')

// 🔧 Or use custom certificate
ws.setCAPath('/path/to/custom-cert.pem')
await ws.connect('wss://secure-server.com')

// 🚨 Dev only: Disable verification
ws.setCAPath('')
await ws.connect('wss://dev-server.com')
```

### 💓 Keep-Alive

```typescript
const ws = createWebSocket()

// Send ping every 30 seconds
ws.setPingInterval(30)

await ws.connect('wss://server.com')
```

---

## 🔍 Common Close Codes

| Code | Name | Description |
|------|------|-------------|
| `1000` | 🟢 Normal Closure | Normal closure; connection completed |
| `1001` | 🚪 Going Away | Endpoint going away (e.g., server shutdown) |
| `1002` | ❌ Protocol Error | Protocol error detected |
| `1003` | 🚫 Unsupported Data | Unsupported data type received |
| `1006` | ⚠️ Abnormal Closure | Abnormal closure (no close frame) |
| `1008` | 🛑 Policy Violation | Message violates policy |
| `1009` | 📏 Message Too Big | Message too large to process |
| `1011` | 💥 Internal Error | Internal server error |

---

## 🛠️ Troubleshooting

### ❌ Connection Fails

> **Problem:** Cannot connect to WebSocket server

**Solutions:**
- ✅ Verify URL starts with `ws://` or `wss://`
- ✅ Check server is running and accessible
- ✅ For SSL issues, try `ws.setCAPath('')` (dev only)
- ✅ Check network connectivity

### 📤 Messages Not Sending

> **Problem:** `send()` doesn't work

**Solutions:**
- ✅ Ensure `ws.state === 1` (OPEN state)
- ✅ Check `onError` callback for error messages
- ✅ Verify server is accepting messages
- ✅ Wait for `onOpen` callback before sending

### 🔐 SSL/TLS Errors

> **Problem:** Certificate verification fails

**Solutions:**
- ✅ Use `setCAPath()` with valid certificate bundle
- ✅ Ensure certificate includes intermediate certificates
- ✅ For development, disable with `setCAPath('')`
- ✅ Check certificate expiration date

---

## 📄 License

MIT © [Hoang Tuan](https://github.com/jameheller98)

---

## 🔗 Links

<p align="center">
  <a href="https://github.com/jameheller98/react-native-real-time-nitro">
    <img src="https://img.shields.io/badge/GitHub-Repository-181717?style=for-the-badge&logo=github" alt="GitHub" />
  </a>
  <a href="https://www.npmjs.com/package/react-native-real-time-nitro">
    <img src="https://img.shields.io/badge/npm-Package-CB3837?style=for-the-badge&logo=npm" alt="npm" />
  </a>
  <a href="https://github.com/jameheller98/react-native-real-time-nitro/issues">
    <img src="https://img.shields.io/badge/Issues-Report-E34C26?style=for-the-badge&logo=githubactions&logoColor=white" alt="Issues" />
  </a>
</p>

---

<p align="center">
  Made with ❤️ by <a href="mailto:nguyentuanwd.ou@gmail.com">Hoang Tuan</a>
</p>

<p align="center">
  <sub>Built with <a href="https://nitro.margelo.com/">Nitro Modules</a> • <a href="https://libwebsockets.org/">libwebsockets</a> • <a href="https://www.trustedfirmware.org/projects/mbed-tls/">mbedTLS</a></sub>
</p>
