import {
  DarkTheme,
  DefaultTheme,
  ThemeProvider,
} from '@react-navigation/native'
import { Stack } from 'expo-router'
import { StatusBar } from 'expo-status-bar'
import { createWebSocket } from 'react-native-real-time-nitro'
import 'react-native-reanimated'

import { useColorScheme } from '@/hooks/use-color-scheme'
import { useEffect } from 'react'

export const unstable_settings = {
  anchor: '(tabs)',
}

export default function RootLayout() {
  const colorScheme = useColorScheme()

  useEffect(() => {
    const ws = createWebSocket()

    // Don't call setCAPath - let it use default (no verification for development)
    // For production, bundle CA certificates and call:
    // ws.setCAPath('/path/to/cacert.pem')

    ws.onOpen = () => {
      console.log('✅ WebSocket connected')
    }

    ws.onMessage = (msg) => {
      console.log('📥 Received:', msg)
    }

    ws.onError = (error) => {
      console.error('❌ WebSocket error:', error)
    }

    ws.onClose = (code, reason) => {
      console.log('🔌 WebSocket closed:', code, reason)
    }

    // Connect to echo server
    ws.connect('wss://echo.websocket.org')
      .then(() => {
        console.log('🔄 Connection initiated...')
        // Send test message after connection
        setTimeout(() => {
          if (ws.state === 1) { // OPEN
            ws.send('Hello from React Native!')
          }
        }, 1000)
      })
      .catch((err) => {
        console.error('💥 Connection failed:', err.message)
      })

    return () => {
      ws.close()
    }
  }, [])

  return (
    <ThemeProvider value={colorScheme === 'dark' ? DarkTheme : DefaultTheme}>
      <Stack>
        <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
        <Stack.Screen
          name="modal"
          options={{ presentation: 'modal', title: 'Modal' }}
        />
      </Stack>
      <StatusBar style="auto" />
    </ThemeProvider>
  )
}
