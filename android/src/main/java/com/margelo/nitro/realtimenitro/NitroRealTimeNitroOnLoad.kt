package com.margelo.nitro.realtimenitro

object NitroRealTimeNitroOnLoad {
    init {
        System.loadLibrary("NitroRealTimeNitro")
    }

    @JvmStatic
    fun initializeNative() {
        // Native initialization happens automatically via JNI_OnLoad
    }
}
