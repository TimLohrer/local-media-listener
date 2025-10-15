#pragma once

#include <jni.h>

#ifdef __cplusplus
extern "C" {
#endif

// JNI functions that will be called from Kotlin
JNIEXPORT void JNICALL Java_dev_timlohrer_lml_bridge_NativeBridge_initNativeHook(JNIEnv *env, jobject obj, jint port);
JNIEXPORT void JNICALL Java_dev_timlohrer_lml_bridge_NativeBridge_shutdownNativeHook(JNIEnv *env, jobject obj);

#ifdef __cplusplus
}
#endif 