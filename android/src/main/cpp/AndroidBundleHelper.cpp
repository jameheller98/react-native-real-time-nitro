#include <jni.h>
#include <android/log.h>
#include <string>
#include <fstream>

#define LOG_TAG "AndroidBundleHelper"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

static std::string cacertPath;
JavaVM* javaVM = nullptr;

extern "C" {
  const char* getRealTimeNitroCACertPath() {
    if (!cacertPath.empty()) {
      return cacertPath.c_str();
    }

    if (!javaVM) {
      LOGE("JavaVM not initialized");
      return nullptr;
    }

    JNIEnv* env = nullptr;
    bool needDetach = false;

    int getEnvStat = javaVM->GetEnv((void**)&env, JNI_VERSION_1_6);
    if (getEnvStat == JNI_EDETACHED) {
      if (javaVM->AttachCurrentThread(&env, nullptr) != 0) {
        LOGE("Failed to attach thread");
        return nullptr;
      }
      needDetach = true;
    } else if (getEnvStat == JNI_EVERSION) {
      LOGE("GetEnv: version not supported");
      return nullptr;
    }

    try {
      // Get the application context
      jclass activityThreadClass = env->FindClass("android/app/ActivityThread");
      jmethodID currentActivityThread = env->GetStaticMethodID(activityThreadClass,
                                                                "currentActivityThread",
                                                                "()Landroid/app/ActivityThread;");
      jobject activityThread = env->CallStaticObjectMethod(activityThreadClass, currentActivityThread);

      jmethodID getApplication = env->GetMethodID(activityThreadClass,
                                                   "getApplication",
                                                   "()Landroid/app/Application;");
      jobject context = env->CallObjectMethod(activityThread, getApplication);

      // Get cache directory
      jclass contextClass = env->GetObjectClass(context);
      jmethodID getCacheDir = env->GetMethodID(contextClass, "getCacheDir", "()Ljava/io/File;");
      jobject cacheDir = env->CallObjectMethod(context, getCacheDir);

      jclass fileClass = env->GetObjectClass(cacheDir);
      jmethodID getAbsolutePath = env->GetMethodID(fileClass, "getAbsolutePath", "()Ljava/lang/String;");
      jstring cacheDirPath = (jstring)env->CallObjectMethod(cacheDir, getAbsolutePath);

      const char* cacheDirStr = env->GetStringUTFChars(cacheDirPath, nullptr);
      std::string cacertFilePath = std::string(cacheDirStr) + "/cacert.pem";
      env->ReleaseStringUTFChars(cacheDirPath, cacheDirStr);

      // Check if file already exists
      std::ifstream checkFile(cacertFilePath);
      if (checkFile.good()) {
        LOGI("CA cert already exists at: %s", cacertFilePath.c_str());
        checkFile.close();
        cacertPath = cacertFilePath;
        if (needDetach) javaVM->DetachCurrentThread();
        return cacertPath.c_str();
      }
      checkFile.close();

      // Get AssetManager
      jmethodID getAssets = env->GetMethodID(contextClass, "getAssets", "()Landroid/content/res/AssetManager;");
      jobject assetManager = env->CallObjectMethod(context, getAssets);

      jclass assetManagerClass = env->GetObjectClass(assetManager);
      jmethodID open = env->GetMethodID(assetManagerClass, "open", "(Ljava/lang/String;)Ljava/io/InputStream;");

      jstring assetPath = env->NewStringUTF("cacert.pem");
      jobject inputStream = env->CallObjectMethod(assetManager, open, assetPath);

      if (!inputStream) {
        LOGE("Failed to open cacert.pem from assets");
        if (needDetach) javaVM->DetachCurrentThread();
        return nullptr;
      }

      // Read and copy the asset
      jclass inputStreamClass = env->GetObjectClass(inputStream);
      jmethodID read = env->GetMethodID(inputStreamClass, "read", "([B)I");
      jmethodID close = env->GetMethodID(inputStreamClass, "close", "()V");

      std::ofstream outFile(cacertFilePath, std::ios::binary);
      if (!outFile.is_open()) {
        LOGE("Failed to create cacert.pem in cache");
        env->CallVoidMethod(inputStream, close);
        if (needDetach) javaVM->DetachCurrentThread();
        return nullptr;
      }

      jbyteArray buffer = env->NewByteArray(4096);
      jint bytesRead;
      while ((bytesRead = env->CallIntMethod(inputStream, read, buffer)) != -1) {
        jbyte* bytes = env->GetByteArrayElements(buffer, nullptr);
        outFile.write(reinterpret_cast<char*>(bytes), bytesRead);
        env->ReleaseByteArrayElements(buffer, bytes, JNI_ABORT);
      }

      outFile.close();
      env->CallVoidMethod(inputStream, close);
      env->DeleteLocalRef(buffer);

      LOGI("Copied CA cert to: %s", cacertFilePath.c_str());
      cacertPath = cacertFilePath;

    } catch (...) {
      LOGE("Exception while getting CA cert path");
      if (needDetach) javaVM->DetachCurrentThread();
      return nullptr;
    }

    if (needDetach) {
      javaVM->DetachCurrentThread();
    }

    return cacertPath.empty() ? nullptr : cacertPath.c_str();
  }
}
