#! /bin/sh
set -e


#############
# FUNCTIONS #
#############

diagnostic()
{
    echo "$@" 1>&2;
}

fail()
{
    diagnostic "$1"
    exit 1
}

# Read the Android Wiki http://wiki.videolan.org/AndroidCompile
# Setup all that stuff correctly.
# Get the latest Android SDK Platform or modify numbers in configure.sh and libvlc/default.properties.

RELEASE=0
RESET=0
while [ $# -gt 0 ]; do
    case $1 in
        help|--help|-h)
            echo "Use -a to set the ARCH:"
            echo "  ARM:     (armeabi-v7a|arm)"
            echo "  ARM64:   (arm64-v8a|arm64)"
            echo "  X86:     x86, x86_64"
            echo "Use --release to build in release mode"
            echo "Use --signrelease to build in release mode and sign apk, see vlc-android/build.gradle"
            echo "Use --reset to reset code from git"
            echo "Use -s to set your keystore file and -p for the password"
            echo "Use -c to get a ChromeOS build"
            echo "Use -l to build only LibVLC"
            echo "Use -ml to build only the medialibrary"
            echo "Use -b to bypass libvlc source checks (vlc custom sources)"
            echo "Use -t to use prebuilt contribs for LibVLC"
            echo "Use -m2 to set the maven local repository path to use"
            exit 0
            ;;
        a|-a)
            ANDROID_ABI=$2
            shift
            ;;
        -r|release|--release)
            RELEASE=1
            ;;
        signrelease|--signrelease)
            SIGNED_RELEASE=1
            RELEASE=1
            ;;
        -s|--signature)
            KEYSTORE_FILE=$2
            shift
            ;;
        -p|--password)
            PASSWORD_KEYSTORE=$2
            shift
            ;;
        -m2|--local-maven)
            M2_REPO=$2
            shift
            ;;
        -l)
            BUILD_LIBVLC=1
            NO_ML=1
            ;;
        -t)
            PREBUILT_CONTRIBS=1
            ;;
        -ml)
            BUILD_MEDIALIB=1
            ;;
        run)
            RUN=1
            ;;
        test)
            TEST=1
            ;;
        stub)
            STUB=1
            ;;
        --reset)
            RESET=1
            ;;
        --no-ml)
            NO_ML=1
            ;;
        --init)
            GRADLE_SETUP=1
            ;;
        -b)
            BYPASS_VLC_SRC_CHECKS=1
            ;;
        -vlc4)
            FORCE_VLC_4=1
            ;;
        *)
            diagnostic "$0: Invalid option '$1'."
            diagnostic "$0: Try --help for more information."
            exit 1
            ;;
    esac
    shift
done

if [ -z "$ANDROID_NDK" ] || [ -z "$ANDROID_SDK" ]; then
   diagnostic "You must define ANDROID_NDK, ANDROID_SDK before starting."
   diagnostic "They must point to your NDK and SDK directories."
   exit 1
fi

if [ -z "$ANDROID_ABI" ]; then
   diagnostic "*** No ANDROID_ABI defined architecture: using arm64-v8a"
   ANDROID_ABI="arm64-v8a"
elif [ "$ANDROID_ABI" = "arm64" ]; then
    ANDROID_ABI="arm64-v8a"
elif [ "$ANDROID_ABI" = "arm" ]; then
    ANDROID_ABI="armeabi-v7a"
fi

if [ "$ANDROID_ABI" = "armeabi-v7a" ]; then
    GRADLE_ABI="ARMv7"
    ARCH="arm"
    TRIPLET="arm-linux-androideabi"
elif [ "$ANDROID_ABI" = "arm64-v8a" ]; then
    GRADLE_ABI="ARMv8"
    ARCH="arm64"
    TRIPLET="aarch64-linux-android"
elif [ "$ANDROID_ABI" = "x86" ]; then
    GRADLE_ABI="x86"
    ARCH="x86"
    TRIPLET="i686-linux-android"
elif [ "$ANDROID_ABI" = "x86_64" ]; then
    GRADLE_ABI="x86_64"
    ARCH="x86_64"
    TRIPLET="x86_64-linux-android"
else
    diagnostic "Invalid arch specified: '$ANDROID_ABI'."
    diagnostic "Try --help for more information"
    exit 1
fi

if [ -n "$M2_REPO" ]; then
  if test -d "$M2_REPO"; then
    echo "Custom local maven repository found"
  else
    diagnostic "Invalid local maven repository path: $M2_REPO"
    exit 1
  fi
fi
####################
# Configure gradle #
####################

if [ -z "$KEYSTORE_FILE" ]; then
    KEYSTORE_FILE="$HOME/.android/debug.keystore"
    STOREALIAS="androiddebugkey"
else
    if [ -z "$PASSWORD_KEYSTORE" ]; then
        diagnostic "No password"
        exit 1
    fi
    rm -f gradle.properties
    STOREALIAS="vlc"
fi

if [ ! -f gradle.properties ]; then
    echo android.enableJetifier=true > gradle.properties
    echo android.useAndroidX=true >> gradle.properties
    echo kapt.incremental.apt=true >> gradle.properties
    echo kapt.use.worker.api=true >> gradle.properties
    echo kapt.include.compile.classpath=false >> gradle.properties
    echo keyStoreFile=$KEYSTORE_FILE >> gradle.properties
    echo storealias=$STOREALIAS >> gradle.properties
    if [ -z "$PASSWORD_KEYSTORE" ]; then
        echo storepwd=android >> gradle.properties
    fi
fi

init_local_props() {
    (
    # initialize the local.properties file,
    # or fix it if it was modified (by Android Studio, for example).
    echo_props() {
        echo "sdk.dir=$ANDROID_SDK"
        echo "android.ndkPath=$ANDROID_NDK"
    }
    # first check if the file just needs to be created for the first time
    if [ ! -f "$1" ]; then
        echo_props > "$1"
        return 0
    fi
    # escape special chars to get regex that matches string
    make_regex() {
        echo "$1" | sed -e 's/\([[\^$.*]\)/\\\1/g' -
    }
    android_sdk_regex=`make_regex "${ANDROID_SDK}"`
    android_ndk_regex=`make_regex "${ANDROID_NDK}"`
    # check for lines setting the SDK directory
    sdk_line_start="^sdk\.dir="
    total_sdk_count=`grep -c "${sdk_line_start}" "$1"`
    good_sdk_count=`grep -c "${sdk_line_start}${android_sdk_regex}\$" "$1"`
    # check for lines setting the NDK directory
    ndk_line_start="^ndk\.dir="
    total_ndk_count=`grep -c "${ndk_line_start}" "$1"`
    good_ndk_count=`grep -c "${ndk_line_start}${android_ndk_regex}\$" "$1"`
    # if one of each is found and both match the environment vars, no action needed
    if [ "$total_sdk_count" -eq "1" ] && [ "$good_sdk_count" -eq "1" ] \
    && [ "$total_ndk_count" -eq "1" ] && [ "$good_ndk_count" -eq "1" ]
    then
        return 0
    fi
    # if neither property is set they can simply be appended to the file
    if [ "$total_sdk_count" -eq "0" ] && [ "$total_ndk_count" -eq "0" ]; then
        echo_props >> "$1"
        return 0
    fi
    # if a property is set incorrectly or too many times,
    # remove all instances of both properties and append correct ones.
    replace_props() {
        temp_props="$1.tmp"
        while IFS= read -r LINE || [ -n "$LINE" ]; do
            line_sdk_dir="${LINE#sdk.dir=}"
            line_ndk_dir="${LINE#android.ndkPath=}"
            if [ "x$line_sdk_dir" = "x$LINE" ] && [ "x$line_ndk_dir" = "x$LINE" ]; then
                echo "$LINE"
            fi
        done <"$1" >"$temp_props"
        echo_props >> "$temp_props"
        mv -f -- "$temp_props" "$1"
    }
    echo "local.properties: Contains incompatible sdk.dir and/or android.ndkPath properties. Replacing..."
    replace_props "$1"
    echo "local.properties: Finished replacing sdk.dir and/or android.ndkPath with current environment variables."
    )
}
init_local_props local.properties || { echo "Error initializing local.properties"; exit $?; }

if [ ! -d "$ANDROID_SDK/licenses" ]; then
    mkdir "$ANDROID_SDK/licenses"
    echo "24333f8a63b6825ea9c5514f83c2829b004d1fee" > "$ANDROID_SDK/licenses/android-sdk-license"
    echo "d56f5187479451eabf01fb78af6dfcb131a6481e" >> "$ANDROID_SDK/licenses/android-sdk-license"
    echo "24333f8a63b6825ea9c5514f83c2829b004d1fee" >> "$ANDROID_SDK/licenses/android-sdk-license"
fi

if [ "$FORCE_VLC_4" = 1 ]; then
    gradle_prop="-PforceVlc4=true"
fi

##########
# GRADLE #
##########

if [ ! -e "./gradlew" ] || [ ! -x "./gradlew" ]; then
    diagnostic "gradlew not found"
    # the SHA256 is found in https://gradle.org/release-checksums/
    GRADLE_VERSION=8.13
    GRADLE_SHA256=20f1b1176237254a6fc204d8434196fa11a4cfb387567519c61556e8710aed78
    GRADLE_URL=https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip
    GRADLE_DOWNLOADED_ZIP=gradle-${GRADLE_VERSION}-bin.zip

    export PATH="$(pwd -P)/gradle-${GRADLE_VERSION}/bin:$PATH"
    GRADLE_PATH_VERSION=$(cd buildsystem/gradle_version; gradle -q 2>/dev/null | grep gradle_version= | cut -b 16-)
    if [ "$GRADLE_PATH_VERSION" != "$GRADLE_VERSION" ]; then
        diagnostic "gradle could not be found in PATH, downloading"
        wget ${GRADLE_URL} -O ${GRADLE_DOWNLOADED_ZIP}  2>/dev/null || curl -LO ${GRADLE_URL} || fail "gradle: download failed"
        echo $GRADLE_SHA256 ${GRADLE_DOWNLOADED_ZIP} | sha256sum -c || fail "gradle: hash mismatch"

        unzip -o ${GRADLE_DOWNLOADED_ZIP} || fail "gradle: unzip failed"
        rm -rf ${GRADLE_DOWNLOADED_ZIP}
    fi

    gradle wrapper ${gradle_prop} || fail "gradle: wrapper failed"

    chmod a+x gradlew
fi
./gradlew -version || fail "gradle: wrapper failed"

####################
# Fetch VLC source #
####################


if [ "$FORCE_VLC_4" = 1 ]; then
    LIBVLCJNI_TESTED_HASH=e90807431330d949b855b37695b9004af6b00bd9
else
    LIBVLCJNI_TESTED_HASH=28b690d499711e7362eb61d03855e06e2854f396
fi
LIBVLCJNI_REPOSITORY=https://code.videolan.org/videolan/libvlcjni.git

: ${VLC_LIBJNI_PATH:="$(pwd -P)/libvlcjni"}

if [ ! -d "$VLC_LIBJNI_PATH" ] || [ ! -d "$VLC_LIBJNI_PATH/.git" ]; then
    diagnostic "libvlcjni sources: not found, cloning"
    if [ "$FORCE_VLC_4" = 1 ]; then
        branch="master"
    else
        branch="libvlcjni-3.x"
    fi
    if [ ! -d "$VLC_LIBJNI_PATH" ]; then
        git clone --single-branch --branch ${branch} "${LIBVLCJNI_REPOSITORY}"
        cd libvlcjni
    else # folder exist with only the artifacts
        cd libvlcjni
        git init
        git remote add origin "${LIBVLCJNI_REPOSITORY}"
        git pull origin ${branch}
    fi
    git reset --hard ${LIBVLCJNI_TESTED_HASH} || fail "libvlcjni sources: LIBVLCJNI_TESTED_HASH ${LIBVLCJNI_TESTED_HASH} not found"
    init_local_props local.properties || { echo "Error initializing local.properties"; exit $?; }
    cd ..
fi

# If you want to use an existing vlc dir add its path to an VLC_SRC_DIR env var
if [ -z "$VLC_SRC_DIR" ]; then
    get_vlc_args=
    if [ "$BYPASS_VLC_SRC_CHECKS" = 1 ]; then
        get_vlc_args="${get_vlc_args} -b"
    fi
    if [ $RESET -eq 1 ]; then
        get_vlc_args="${get_vlc_args} --reset"
    fi

    (cd ${VLC_LIBJNI_PATH} && ./buildsystem/get-vlc.sh ${get_vlc_args})
fi

# Always clone VLC when using --init since we'll need to package some files
# during the final assembly (lua/hrtfs/..)
if [ "$GRADLE_SETUP" = 1 ]; then
    exit 0
fi

############
# Make VLC #
############
diagnostic "Configuring"

# Build LibVLC if asked for it, or needed by medialibrary
OUT_DBG_DIR="$(pwd -P)/.dbg/${ANDROID_ABI}"
mkdir -p $OUT_DBG_DIR

if [ "$BUILD_MEDIALIB" != 1 ] || [ ! -d "${VLC_LIBJNI_PATH}/libvlc/jni/libs/" ]; then
    if [ "$PREBUILT_CONTRIBS" = 1 ];then
        VLC_CONTRIB_SHA="$(cd ${VLC_LIBJNI_PATH}/vlc && extras/ci/get-contrib-sha.sh android-${ARCH})"
        if [ "$FORCE_VLC_4" = 1 ]; then
            export VLC_PREBUILT_CONTRIBS_URL="https://artifacts.videolan.org/vlc/android-${ARCH}/vlc-contrib-${TRIPLET}-${VLC_CONTRIB_SHA}.tar.bz2"
        else
            export VLC_PREBUILT_CONTRIBS_URL="https://artifacts.videolan.org/vlc-3.0/android-${ARCH}/vlc-contrib-${TRIPLET}-${VLC_CONTRIB_SHA}.tar.bz2"
        fi
        if ${VLC_LIBJNI_PATH}/vlc/extras/ci/check-url.sh "$VLC_PREBUILT_CONTRIBS_URL"; then CONTRIB_FLAGS="--with-prebuilt-contribs"; fi
    fi
    ${VLC_LIBJNI_PATH}/buildsystem/compile-libvlc.sh -a ${ARCH} ${CONTRIB_FLAGS}

    cp -a ${VLC_LIBJNI_PATH}/libvlc/jni/obj/local/${ANDROID_ABI}/*.so "${OUT_DBG_DIR}"
fi

if [ "$NO_ML" != 1 ]; then
    medialig_args="-a $ANDROID_ABI"
    if [ "$RELEASE" = 1 ]; then
        medialig_args="$medialig_args --release"
    fi
    if [ "$RESET" = 1 ]; then
        medialig_args="$medialig_args --reset"
    fi
    buildsystem/compile-medialibrary.sh ${medialig_args}
    cp -a medialibrary/jni/obj/local/${ANDROID_ABI}/*.so "${OUT_DBG_DIR}"
fi

##################
# Compile the UI #
##################
BUILDTYPE="Dev"
if [ "$TEST" = 1 ]; then
    BUILDTYPE="Debug"
elif [ "$SIGNED_RELEASE" = 1 ]; then
    BUILDTYPE="signedRelease"
elif [ "$RELEASE" = 1 ]; then
    BUILDTYPE="Release"
fi
if [ "$TEST" = 1 ] || [ "$RUN" = 1 ]; then
    ACTION="install"
else
    ACTION="assemble"
fi
GRADLE_TASK="${ACTION}${BUILDTYPE}"

if [ -n "$M2_REPO" ]; then
    gradle_prop="$gradle_prop -Dmaven.repo.local=$M2_REPO"
fi

if [ "$BUILD_LIBVLC" = 1 ];then
    GRADLE_ABI=$GRADLE_ABI ./gradlew ${gradle_prop} --project-dir ${VLC_LIBJNI_PATH}/libvlc $GRADLE_TASK
    RUN=0
elif [ "$BUILD_MEDIALIB" = 1 ]; then
    gradle_prop="$gradle_prop -PvlcLibVariant=$GRADLE_ABI"
    ./gradlew ${gradle_prop} --project-dir medialibrary $GRADLE_TASK
    RUN=0
else
    ./gradlew ${gradle_prop} $GRADLE_TASK
    if [ "$BUILDTYPE" = "Release" ] && [ "$ACTION" = "assemble" ]; then
        ./gradlew ${gradle_prop} "bundle${BUILDTYPE}"
    fi
    if [ "$TEST" = 1 ]; then
        ./gradlew ${gradle_prop} "application:vlc-android:install${BUILDTYPE}AndroidTest"

        echo -e "\n===================================\nRun following for UI tests:"
        echo "adb shell am instrument -w -m -e clearPackageData true   -e package org.videolan.vlc -e debug false org.videolan.vlc.debug.test/org.videolan.vlc.MultidexTestRunner 1> result_UI_test.txt"
    fi
fi

if [ ! -d "./application/remote-access-client/remoteaccess/dist" ] ; then
    echo "\033[1;32mWARNING: This was built without the remote access at ./remoteaccess/dist ..."
fi

#######
# RUN #
#######
if [ "$RUN" = 1 ]; then
    export PATH="${ANDROID_SDK}/platform-tools/:$PATH"
    if [ "$STUB" = 1 ]; then
        EXTRA="--ez 'extra_test_stubs' true"
    fi
    adb wait-for-device
    if [ "$RELEASE" = 1 ]; then
        adb shell am start -n org.videolan.vlc/org.videolan.vlc.StartActivity $EXTRA
    else
        adb shell am start -n org.videolan.vlc.debug/org.videolan.vlc.StartActivity $EXTRA
    fi
fi
