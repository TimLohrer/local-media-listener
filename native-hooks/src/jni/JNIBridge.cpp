#include "JNIBridge.h"
#include "LocalMediaListener.h"
#include "Logger.h"

JNIEXPORT void JNICALL Java_dev_timlohrer_lml_bridge_NativeBridge_initNativeHook(JNIEnv *env, jobject obj) {
    Logger::debug("Loading jni bridge");
    LocalMediaListener::getInstance().initialize();
    Logger::debug("Init finished");
}

JNIEXPORT void JNICALL Java_dev_timlohrer_lml_bridge_NativeBridge_shutdownNativeHook(JNIEnv *env, jobject obj) {
    Logger::debug("Unloading jni bridge");
    LocalMediaListener::getInstance().shutdown();
    Logger::debug("Shutdown finished");
} 