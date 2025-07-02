#include <jni.h>
#include "libnative_hook_linux_arm64.h"

JNIEXPORT void JNICALL
Java_dev_timlohrer_lml_bridge_NativeBridge_initNativeHook(JNIEnv *env, jobject obj) {
    Init();
}

JNIEXPORT void JNICALL
Java_dev_timlohrer_lml_bridge_NativeBridge_shutdownNativeHook(JNIEnv *env, jobject obj) {
    Shutdown();
}