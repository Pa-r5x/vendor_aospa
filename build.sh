#!/usr/bin/env bash
# AOSPA build helper script

export TERM=xterm

# red = errors, cyan = warnings, green = confirmations, blue = informational
# plain for generic text, bold for titles, reset flag at each end of line
# plain blue should not be used for readability reasons - use plain cyan instead
CLR_RST=$(tput sgr0)                        ## reset flag
CLR_RED=$CLR_RST$(tput setaf 1)             #  red, plain
CLR_GRN=$CLR_RST$(tput setaf 2)             #  green, plain
CLR_BLU=$CLR_RST$(tput setaf 4)             #  blue, plain
CLR_CYA=$CLR_RST$(tput setaf 6)             #  cyan, plain
CLR_BLD=$(tput bold)                        ## bold flag
CLR_BLD_RED=$CLR_RST$CLR_BLD$(tput setaf 1) #  red, bold
CLR_BLD_GRN=$CLR_RST$CLR_BLD$(tput setaf 2) #  green, bold
CLR_BLD_BLU=$CLR_RST$CLR_BLD$(tput setaf 4) #  blue, bold
CLR_BLD_CYA=$CLR_RST$CLR_BLD$(tput setaf 6) #  cyan, bold
CLR_BLD_YLW=$CLR_RST$CLR_BLD$(tput setaf 3) #  yellow, bold

# Set defaults
AOSPA_VARIANT="alpha"
JOBS="12"
DEVICE="oneplus7t"
SHA256="prebuilts/build-tools/path/linux-x86/sha256sum"

function checkExit () {
    EXIT_CODE=$?
    if [ $EXIT_CODE -ne 0 ]; then
        echo "${CLR_BLD_RED}Build failed!${CLR_RST}"
        echo -e ""
        exit $EXIT_CODE
    fi
}

# Use CCACHE
if [ "$Use_CCACHE" = "Yes" ]; then
echo -e""
echo -e "${CLR_BLD_CYA}CCACHE is Enabled for this Build${CLR_RST}"
export CCACHE_EXEC=$(which ccache)
export USE_CCACHE=1
export CCACHE_DIR=/home/ccache/fazil
ccache -M 98G
fi

if [ "$Use_CCACHE" = "Clean" ]; then
export CCACHE_EXEC=$(which ccache)
export CCACHE_DIR=/home/ccache/fazil
ccache -C
export USE_CCACHE=1
ccache -M 98G
wait
echo -e "${CLR_BLD_GRN}CCACHE Cleared${CLR_RST}"
fi

# Set thin lto ccache DIR
export THINLTO_CACHE_DIR=/home/ccache/fazil/tlto

# Its Clean Time
if [ "$Build" = "Clean" ]; then
rm -rf out
export FLAG_CLEAN_BUILD=y
fi

# Install Clean
if [ "$Build" = "Install Clean" ]; then
export FLAG_INSTALLCLEAN_BUILD=y
fi

# BUILD_TYPE
if [ "$Build_type" ]; then
export BUILD_TYPE="$Build_type"
fi

# Repo Sync
if [ "$Sync" = "true" ]; then
export FLAG_SYNC=y
fi

# Fastboot image
if [ "$Fastboot_zip" = "true" ]; then
export FLAG_IMG_ZIP=y
fi

# Delta OTA
if [ "$Delta_OTA" = "true" ]; then
   export DELTA_TARGET_FILES="aospa-$DEVICE-target_files-$PREV_FILE_TAG.zip"
    if [ ! -f "$(pwd)/$DELTA_TARGET_FILES" ]; then
        echo -e "${CLR_BLD_RED}error: target delta file not found!${CLR_RST}"
        exit 1
    fi
fi

# Sign Build
export KEY_MAPPINGS="vendor/aospa/signing/keys"

# Make sure we are running on 64-bit before carrying on with anything
ARCH=$(uname -m | sed 's/x86_//;s/i[3-6]86/32/')
if [ "$ARCH" != "64" ]; then
        echo -e "${CLR_BLD_RED}error: unsupported arch (expected: 64, found: $ARCH)${CLR_RST}"
        exit 1
fi

# Perform a build from scratch by resyncing everything!
if [ "$Remove_AOSPA" = "true" ]; then
    rm -rf aospa
    mkdir aospa
    cd aospa
    repo init -u https://github.com/pa-faiz/manifest -b vauxite --depth=1
    echo -e "${CLR_BLD_YLW}Syncing with latest source${CLR_RST}"
    repo sync --current-branch --no-tags -j12
    cd ../
fi

# Set up paths
DIR_ROOT=$(pwd)

# Make sure everything looks sane so far
if [ ! -d "$DIR_ROOT/vendor/aospa" ]; then
        echo -e "${CLR_BLD_RED}error: insane root directory ($DIR_ROOT)${CLR_RST}"
        exit 1
fi

# Setup AOSPA variant if specified
if [ $AOSPA_VARIANT ]; then
    AOSPA_VARIANT=`echo $AOSPA_VARIANT |  tr "[:upper:]" "[:lower:]"`
    if [ "${AOSPA_VARIANT}" = "stable" ]; then
        export AOSPA_BUILDTYPE=STABLE
    elif [ "${AOSPA_VARIANT}" = "beta" ]; then
        export AOSPA_BUILDTYPE=BETA
    elif [ "${AOSPA_VARIANT}" = "alpha" ]; then
        export AOSPA_BUILDTYPE=ALPHA
    else
        echo -e "${CLR_BLD_RED} Unknown AOSPA variant - use alpha, beta or stable${CLR_RST}"
        exit 1
    fi
fi

# Setup AOSPA version if specified
if [ $AOSPA_USER_VERSION ]; then
    # Check if it is a number
    if [[ $AOSPA_USER_VERSION =~ ^[0-9]{1,3}(\.[0-9]{1,2})?(\.[0-9]{1,2})?$ ]]; then
        export AOSPA_BUILDVERSION=$AOSPA_USER_VERSION
    else
        echo -e "${CLR_BLD_RED}Invalid AOSPA version - use any non-negative number${CLR_RST}"
        exit 1
    fi
fi

# Initializationizing!
echo -e "${CLR_BLD_BLU}Setting up the environment${CLR_RST}"
echo -e ""
. build/envsetup.sh
echo -e ""

# Use the thread count specified by user
CMD=""
if [ $JOBS ]; then
  CMD+="-j$JOBS"
fi

# Pick the default thread count (allow overrides from the environment)
if [ -z "$JOBS" ]; then
        if [ "$(uname -s)" = 'Darwin' ]; then
                JOBS=$(sysctl -n machdep.cpu.core_count)
        else
                JOBS=$(cat /proc/cpuinfo | grep '^processor' | wc -l)
        fi
fi

# Grab the build version
AOSPA_DISPLAY_VERSION="$(cat $DIR_ROOT/vendor/aospa/target/product/version.mk | grep 'AOSPA_MAJOR_VERSION := *' | sed 's/.*= //')"
if [ $AOSPA_BUILDVERSION ]; then
    AOSPA_DISPLAY_VERSION+="$AOSPA_BUILDVERSION"
fi

# Check the starting time (of the real build process)
TIME_START=$(date +%s.%N)

# Friendly logging to tell the user everything is working fine is always nice
echo -e "${CLR_BLD_GRN}Building AOSPA $AOSPA_DISPLAY_VERSION for $DEVICE${CLR_RST}"
echo -e "${CLR_GRN}Start time: $(date)${CLR_RST}"
echo -e ""

# Lunch-time!
echo -e "${CLR_BLD_BLU}Lunching $DEVICE${CLR_RST} ${CLR_CYA}(Including dependencies sync)${CLR_RST}"
echo -e ""
lunch "aospa_$DEVICE-$TARGET_RELEASE-$BUILD_TYPE"
AOSPA_VERSION="$(get_build_var AOSPA_VERSION)"
checkExit
echo -e ""

# Perform installclean, if requested so
if [ "$FLAG_INSTALLCLEAN_BUILD" = 'y' ]; then
	    echo -e "${CLR_BLD_YLW}Cleaning compiled image files left from old builds${CLR_RST}"
	    echo -e ""
	    m installclean "$CMD"
fi

# Prep for a clean build, if requested so
if [ "$FLAG_CLEAN_BUILD" = 'y' ]; then
        echo -e "${CLR_BLD_YLW}Cleaning output files left from old builds${CLR_RST}"
        echo -e ""
        m clobber "$CMD"
fi

# Sync up with source, if asked to
if [ "$FLAG_SYNC" = 'y' ]; then
        echo -e "${CLR_BLD_YLW}Syncing with latest source${CLR_RST}"
        echo -e ""
        repo sync -j"$JOBS" -c --current-branch --no-tags
fi

# Force Sync up with source, if asked to
if [ "$Force_Sync" = "true" ]; then
        echo -e "${CLR_BLD_YLW}Force Syncing with latest source${CLR_RST}"
        echo -e ""
        repo sync --force-sync -c --current-branch --no-tags -j12
fi

# Download KernelSU Patch
if [ "$KernelSU" = "true" ]; then
    cd kernel/msm-4.14
    rm -rf KernelSU && git stash -u > /dev/null
    git clone https://github.com/tiann/KernelSU -b v0.9.5 KernelSU
fi

# Build away!
echo -e "${CLR_BLD_BLU}Starting compilation${CLR_RST}"
echo -e ""

# If we aren't in Jenkins, use the engineering tag
if [ -z "${BUILD_NUMBER}" ]; then
    export FILE_NAME_TAG=eng.$USER
else
    export FILE_NAME_TAG=$BUILD_NUMBER
fi

# Build a Specific Module
if [ "${MODULES}" = "NO" ]; then
    checkExit

    elif [ "${MODULES}" ]; then
        echo -e "${CLR_BLD_CYA}Building ${MODULES}${CLR_RST}"
        echo -e ""
        m ${MODULES[@]} "$CMD"
        exit 0
    fi

# Build signed rom package if specified
if [ "${KEY_MAPPINGS}" ]; then
    m otatools target-files-package "$CMD"

    checkExit

    echo -e "${CLR_BLD_BLU}Signing target files apks${CLR_RST}"
    sign_target_files_apks -o -d $KEY_MAPPINGS \
        "$OUT"/obj/PACKAGING/target_files_intermediates/aospa_$DEVICE-target_files.zip \
        aospa-$DEVICE-signed-target_files-$FILE_NAME_TAG.zip

    checkExit

    echo -e "${CLR_BLD_BLU}Generating signed install package${CLR_RST}"
    ota_from_target_files -k $KEY_MAPPINGS/releasekey \
        --block ${INCREMENTAL} \
        aospa-$DEVICE-signed-target_files-$FILE_NAME_TAG.zip \
        aospa-$AOSPA_VERSION.zip

    checkExit

    if [ "$DELTA_TARGET_FILES" ]; then
        ota_from_target_files -k $KEY_MAPPINGS/releasekey \
            --block --incremental_from $DELTA_TARGET_FILES \
            aospa-$DEVICE-signed-target_files-$FILE_NAME_TAG.zip \
            aospa-$AOSPA_VERSION-delta.zip
        checkExit
    fi

    if [ "$FLAG_IMG_ZIP" = 'y' ]; then
        echo -e "${CLR_BLD_BLU}Generating signed fastboot package${CLR_RST}"
        img_from_target_files \
            aospa-$DEVICE-signed-target_files-$FILE_NAME_TAG.zip \
            aospa-$AOSPA_VERSION-image.zip
        checkExit
    fi

# Build rom package
elif [ "$FLAG_IMG_ZIP" = 'y' ]; then
    m otatools target-files-package "$CMD"

    checkExit

    echo -e "${CLR_BLD_BLU}Generating fastboot package${CLR_RST}"
    img_from_target_files \
        "$OUT"/obj/PACKAGING/target_files_intermediates/aospa_$DEVICE-target_files.zip \
        aospa-$AOSPA_VERSION-image.zip

    checkExit

elif [ "$DELTA_TARGET_FILES" ]; then
    m otatools target-files-package "$CMD"
    checkExit

    echo -e "${CLR_BLD_BLU}Generating Delta OTA package${CLR_RST}"
    ota_from_target_files \
        --block --incremental_from $DELTA_TARGET_FILES \
        "$OUT"/obj/PACKAGING/target_files_intermediates/aospa_$DEVICE-target_files.zip \
        aospa-$AOSPA_VERSION-delta.zip
    checkExit

    sha256sum aospa-$AOSPA_VERSION-delta.zip | cut -d ' ' -f1 > aospa-$AOSPA_VERSION-delta.zip.sha256sum
    echo -e "${CLR_BLD_GRN}Delta OTA Package Complete${CLR_RST}": "${CLR_CYA}aospa-$AOSPA_VERSION-delta.zip${CLR_RST}"
    echo -e "size: `ls -lah aospa-$AOSPA_VERSION-delta.zip | cut -d ' ' -f 5`"
    echo -e "sha256: `cat aospa-$AOSPA_VERSION-delta.zip.sha256sum | cut -d ' ' -f 1`"
else
    m otapackage "$CMD"

    checkExit

    sha256sum aospa-$AOSPA_VERSION.zip | cut -d ' ' -f1 > aospa-$AOSPA_VERSION.zip.sha256sum
    echo -e "${CLR_BLD_GRN}Package Complete${CLR_RST}": "${CLR_CYA}aospa-$AOSPA_VERSION.zip${CLR_RST}"
    echo -e "size: `ls -lah aospa-$AOSPA_VERSION.zip | cut -d ' ' -f 5`"
    echo -e "sha256: `cat aospa-$AOSPA_VERSION.zip.sha256sum | cut -d ' ' -f 1`"
fi

mv "$OUT"/obj/PACKAGING/target_files_intermediates/aospa_$DEVICE-target_files.zip \
aospa-$DEVICE-target_files-$FILE_NAME_TAG.zip
echo -e ""
echo "    :::      ::::::::   ::::::::  :::::::::      :::     ";
echo "  :+: :+:   :+:    :+: :+:    :+: :+:    :+:   :+: :+:   ";
echo " +:+   +:+  +:+    +:+ +:+        +:+    +:+  +:+   +:+  ";
echo "+#++:++#++: +#+    +:+ +#++:++#++ +#++:++#+  +#++:++#++: ";
echo "+#+     +#+ +#+    +#+        +#+ +#+        +#+     +#+ ";
echo "#+#     #+# #+#    #+# #+#    #+# #+#        #+#     #+# ";
echo "###     ###  ########   ########  ###        ###     ### ";
echo "            Paranoid Android Project                     ";
echo -e ""

# Check the finishing time
TIME_END=$(date +%s.%N)

# Log those times at the end as a fun fact of the day
echo -e "${CLR_BLD_GRN}Total time elapsed:${CLR_RST} ${CLR_GRN}$(echo "($TIME_END - $TIME_START) / 60" | bc) minutes ($(echo "$TIME_END - $TIME_START" | bc) seconds)${CLR_RST}"
echo -e ""

exit 0
