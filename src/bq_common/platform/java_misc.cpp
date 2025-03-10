﻿/*
 * Copyright (C) 2024 THL A29 Limited, a Tencent company.
 * BQLOG is licensed under the Apache License, Version 2.0.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 */
#include "bq_common/bq_common.h"

#if BQ_JAVA
#include <jni.h>
#include <sys/types.h>
#if BQ_ANDROID
#include <android/log.h>
#endif

namespace bq {
    namespace platform {
        static JavaVM* java_vm = NULL;
        static BQ_TLS int32_t jni_attacher_counter = 0;

        static bq::array<void (*)()>& get_jni_onload_callbacks()
        {
            static bq::array<void (*)()> jni_onload_callbacks_inst;
            return jni_onload_callbacks_inst;
        }

        jni_env::jni_env()
        {
            assert(java_vm != NULL && "invoke functions on java_vm before it is initialized");
            jint get_env_result = java_vm->GetEnv((void**)&env, JNI_VERSION_1_6);
            if (!(JNI_OK == get_env_result || JNI_EDETACHED == get_env_result)) {
                bq::util::log_device_console(log_level::fatal, "JVM GetEnv error, error code:%d", get_env_result);
                assert(false && "JVM GetEnv error");
            }
            if (jni_attacher_counter == 0) {
                attached_in_init = (JNI_OK == get_env_result);
            }
            if (JNI_EDETACHED == get_env_result) {
                if (0 != jni_attacher_counter) {
                    bq::util::log_device_console(log_level::fatal, "jni_env attach error, jni_attacher_counter:%d", jni_attacher_counter);
                    assert(false && "jni_env attach error");
                }
                using attach_param_type = function_argument_type_t<decltype(&JavaVM::AttachCurrentThread), 0>;
                jint attach_result = java_vm->AttachCurrentThread(reinterpret_cast<attach_param_type>(&env), nullptr);
                if (JNI_OK != attach_result) {
                    bq::util::log_device_console(log_level::fatal, "jni_env attach error, AttachCurrentThread error code:%d", attach_result);
                    assert(false && "AttachCurrentThread error");
                }
            }
            ++jni_attacher_counter;
        }

        jni_env::~jni_env()
        {
            --jni_attacher_counter;
            assert(jni_attacher_counter >= 0 && "--jni_attacher_counter is less than 0!");
            if (0 == jni_attacher_counter) {
                if (!attached_in_init) {
                    jint detach_result = java_vm->DetachCurrentThread();
                    if (JNI_OK != detach_result) {
                        bq::util::log_device_console(log_level::fatal, "jni_env attach error, DetachCurrentThread error code:%d", detach_result);
                        assert(false && "AttachCurrentThread error");
                    }
                }
            }
        }

        jni_onload_register::jni_onload_register(void (*onload_callback)())
        {
            assert(!java_vm && "jni_onload_register should be called before JNI_Onload");
            get_jni_onload_callbacks().push_back(onload_callback);
        }

        JavaVM* get_jvm()
        {
            return java_vm;
        }

#ifdef __cplusplus
        extern "C" {
#endif
        JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void* reserved)
        {
            (void)reserved;
            java_vm = vm;
#if BQ_ANDROID
            __android_log_write(ANDROID_LOG_INFO, "Bq", "JNI_Onload is called");
            android_jni_onload();
#elif BQ_IOS
            bq::platform::ios_print("Bq JNI_Onload is called");
#else
            printf("Bq JNI_Onload is called");
#endif
            for (auto callback : get_jni_onload_callbacks()) {
                callback();
            }
            return JNI_VERSION_1_6;
        }
#ifdef __cplusplus
        }
#endif
    }
}
#endif
