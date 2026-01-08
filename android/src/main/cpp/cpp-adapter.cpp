#include <jni.h>
#include "NitroRealTimeNitroOnLoad.hpp"

// JavaVM storage for AndroidBundleHelper
extern JavaVM* javaVM;

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void*) {
  // Store JavaVM for AndroidBundleHelper
  javaVM = vm;

  // Initialize Nitro
  return margelo::nitro::realtimenitro::initialize(vm);
}
