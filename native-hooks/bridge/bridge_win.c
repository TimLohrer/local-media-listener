#include <jni.h>
#include "native_hook.h"

JNIEXPORT void JNICALL
Java_dev_timlohrer_bridge_NativeBridge_initNativeHook(JNIEnv *env, jobject obj) {
    Init();
}