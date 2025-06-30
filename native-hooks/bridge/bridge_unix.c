#include <jni.h>
#include "libnative_hook.h"

JNIEXPORT void JNICALL
Java_dev_timlohrer_lml_bridge_NativeBridge_initNativeHook(JNIEnv *env, jobject obj) {
    Init();
}