#include "JNIBridge.h"
#include "LocalMediaListener.h"

JNIEXPORT void JNICALL Java_dev_timlohrer_lml_bridge_NativeBridge_initNativeHook(JNIEnv *env, jobject obj) {
    LocalMediaListener::getInstance().initialize();
}

JNIEXPORT void JNICALL Java_dev_timlohrer_lml_bridge_NativeBridge_shutdownNativeHook(JNIEnv *env, jobject obj) {
    LocalMediaListener::getInstance().shutdown();
} 