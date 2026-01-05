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

    ws.setCAPath('');

    ws.connect('wss://echo.websocket.org')

    ws.onOpen = () => {
      console.log('WebSocket connected')
    }

    ws.onError = (e) => {
      console.log('WebSocket error', e)
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
