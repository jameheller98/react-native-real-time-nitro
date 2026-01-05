#include <jni.h>
#include "NitroRealTimeNitroOnLoad.hpp"

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void*) {
  return margelo::nitro::realtimenitro::initialize(vm);
}
