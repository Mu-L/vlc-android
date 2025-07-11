LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
LOCAL_MODULE := medialibrary
LOCAL_SRC_FILES := ../prefix/${APP_PLATFORM}-${APP_ABI}/lib/libmedialibrary.a
include $(PREBUILT_STATIC_LIBRARY)

include $(CLEAR_VARS)
LOCAL_MODULE := sqlite
LOCAL_SRC_FILES := ../prefix/${APP_PLATFORM}-${APP_ABI}/lib/libsqlite3.a
include $(PREBUILT_STATIC_LIBRARY)

include $(CLEAR_VARS)
LOCAL_SRC_FILES := medialibrary.cpp AndroidMediaLibrary.cpp AndroidDeviceLister.cpp utils.cpp
LOCAL_MODULE    := mla
LOCAL_LDLIBS    := $(MEDIALIBRARY_LDLIBS) -llog
LOCAL_C_INCLUDES := $(MEDIALIBRARY_INCLUDE_DIR)
LOCAL_STATIC_LIBRARIES := medialibrary sqlite
include $(BUILD_SHARED_LIBRARY)
