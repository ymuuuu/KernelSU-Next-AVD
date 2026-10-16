#!/usr/bin/env bash
# ==============================================================================
# KernelSU-Next-AVD: Root Android Virtual Devices (AVD) using KernelSU Next
# Repository: https://github.com/ymuuuu/KernelSU-Next-AVD
# Fork of KernelSU-AVD by HChenX. Inspired by rootAVD (newbit).
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS_DIR="$SCRIPT_DIR/Apps"
ADB_REMOTE_TMP="/data/local/tmp/ksuAVD"
UPSTREAM_REPO="KernelSU-Next/KernelSU-Next"

# Detect if running on Android device or on host machine
is_device() {
    if [ "$1" = "--device" ] || [ -f "/system/bin/sh" ] && [ "$(id -u)" -eq 2000 -o "$(id -u)" -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

show_banner() {
    echo "=============================================================================="
    echo "                KernelSU-Next-AVD: Root AVD with KernelSU Next                "
    echo "              GitHub: https://github.com/ymuuuu/KernelSU-Next-AVD             "
    echo "=============================================================================="
    echo ""
}

# ==============================================================================
# Device-Side Logic (executed inside the Android Virtual Device)
# ==============================================================================
run_on_device() {
    cd "$ADB_REMOTE_TMP" || { echo "[x] Cannot enter $ADB_REMOTE_TMP"; exit 1; }

    echo "[-] Running inside AVD environment..."

    # 1. Determine device architecture & ABI
    ABI=$(getprop ro.product.cpu.abi 2>/dev/null || true)
    if [ -z "$ABI" ]; then
        ARCH=$(uname -m)
        case "$ARCH" in
            x86_64) ABI="x86_64" ;;
            aarch64) ABI="arm64-v8a" ;;
            x86|i686) ABI="x86" ;;
            armv7l|armv8l) ABI="armeabi-v7a" ;;
            riscv64) ABI="riscv64" ;;
            *) ABI="x86_64" ;;
        esac
    fi
    echo "[-] Detected AVD ABI: $ABI"

    # 2. Extract ksud from KernelSU.apk if needed
    if [ ! -f "ksud" ]; then
        if [ -f "KernelSU.apk" ]; then
            echo "[*] Extracting ksud for $ABI from KernelSU.apk..."
            unzip -qo "KernelSU.apk" "lib/$ABI/libksud.so" -d . 2>/dev/null || true
            if [ -f "lib/$ABI/libksud.so" ]; then
                cp -f "lib/$ABI/libksud.so" "ksud"
            else
                unzip -qo "KernelSU.apk" "lib/*" -d . 2>/dev/null || true
                if [ -f "lib/x86_64/libksud.so" ] && [ "$ABI" = "x86_64" ]; then
                    cp -f "lib/x86_64/libksud.so" "ksud"
                elif [ -f "lib/arm64-v8a/libksud.so" ] && [ "$ABI" = "arm64-v8a" ]; then
                    cp -f "lib/arm64-v8a/libksud.so" "ksud"
                fi
            fi
        fi
    fi

    if [ ! -f "ksud" ] || [ ! -s "ksud" ]; then
        echo "[x] Error: ksud binary could not be found or extracted!"
        exit 1
    fi
    chmod 755 "ksud"

    # Verify ksud execution
    KSUD_VER=$(./ksud --version 2>/dev/null || echo "unknown")
    echo "[-] ksud binary ready ($KSUD_VER)"

    # 3. Detect target KMI (Kernel Module Interface)
    KMI=$(./ksud boot-info current-kmi 2>/dev/null || true)
    if [ -z "$KMI" ]; then
        echo "[*] Detecting KMI from kernel release..."
        UNAMER=$(uname -r)
        ANDVER=$(echo "$UNAMER" | grep -o 'android[0-9]\+' || true)
        KVER=$(echo "$UNAMER" | cut -d'.' -f1,2 || true)
        if [ -n "$ANDVER" ] && [ -n "$KVER" ]; then
            KMI="${ANDVER}-${KVER}"
        fi
    fi

    if [ -z "$KMI" ]; then
        echo "[x] Error: Unable to determine KMI for running kernel: $(uname -r)"
        exit 1
    fi
    echo "[-] Target GKI KMI: $KMI"

    # 4. Locate input ramdisk
    RDF="ramdisk.img"
    if [ ! -f "$RDF" ]; then
        if [ -f "ramdisk.img.lz4" ]; then
            RDF="ramdisk.img.lz4"
        elif [ -f "ramdisk.img.gz" ]; then
            RDF="ramdisk.img.gz"
        else
            echo "[x] Error: No ramdisk.img found in $ADB_REMOTE_TMP"
            exit 1
        fi
    fi

    # 5. Patch ramdisk with KernelSU Next
    echo "[*] Invoking ksud boot-patch --ramdisk on $RDF..."
    ./ksud boot-patch \
        -b "$RDF" \
        --ramdisk \
        --kmi "$KMI" \
        --allow-shell \
        -o . \
        --out-name "ramdiskpatched4AVD.img"

    if [ $? -ne 0 ] || [ ! -f "ramdiskpatched4AVD.img" ] || [ ! -s "ramdiskpatched4AVD.img" ]; then
        echo "[x] Error: ksud boot-patch failed!"
        exit 1
    fi

    echo "[V] KernelSU Next ramdisk patch successful: $ADB_REMOTE_TMP/ramdiskpatched4AVD.img"
    exit 0
}

# ==============================================================================
# Host-Side Logic (macOS / Linux / WSL)
# ==============================================================================
find_sdk() {
    SDK_DIR=""
    if [ -n "$ANDROID_HOME" ] && [ -d "$ANDROID_HOME" ]; then
        SDK_DIR="$ANDROID_HOME"
    elif [ -n "$ANDROID_SDK_ROOT" ] && [ -d "$ANDROID_SDK_ROOT" ]; then
        SDK_DIR="$ANDROID_SDK_ROOT"
    elif [ -d "$HOME/Library/Android/sdk" ]; then
        SDK_DIR="$HOME/Library/Android/sdk"
    elif [ -d "$HOME/Android/Sdk" ]; then
        SDK_DIR="$HOME/Android/Sdk"
    fi
}

find_adb() {
    if command -v adb >/dev/null 2>&1; then
        ADB_BIN="adb"
        return 0
    fi
    if [ -n "$SDK_DIR" ] && [ -x "$SDK_DIR/platform-tools/adb" ]; then
        ADB_BIN="$SDK_DIR/platform-tools/adb"
        return 0
    fi
    echo "[!] Warning: adb not found in PATH or Android SDK platform-tools."
    ADB_BIN="adb"
}

check_device() {
    if ! "$ADB_BIN" get-state >/dev/null 2>&1; then
        echo "[x] Error: No running Android emulator / device detected by ADB!"
        echo "    Please start your AVD and ensure adb connects before running this script."
        echo ""
        "$ADB_BIN" devices
        exit 1
    fi
}

show_device_status() {
    echo "--- ADB Connected Device Status ---"
    if ! "$ADB_BIN" get-state >/dev/null 2>&1; then
        echo "  Device: None connected (Start your AVD first)"
        echo ""
        return 0
    fi

    DEV_MODEL=$("$ADB_BIN" shell getprop ro.product.model 2>/dev/null | tr -d '\r')
    DEV_ANDROID=$("$ADB_BIN" shell getprop ro.build.version.release 2>/dev/null | tr -d '\r')
    DEV_SDK=$("$ADB_BIN" shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r')
    DEV_ABI=$("$ADB_BIN" shell getprop ro.product.cpu.abi 2>/dev/null | tr -d '\r')
    DEV_KERNEL=$("$ADB_BIN" shell uname -r 2>/dev/null | tr -d '\r')

    echo "  Model:           $DEV_MODEL"
    echo "  Android Version: $DEV_ANDROID (API $DEV_SDK)"
    echo "  Architecture:    $DEV_ABI"
    echo "  Kernel:          $DEV_KERNEL"
    echo ""
}

# Reject an APK that cannot supply ksud, before anything is pushed. Without
# lib/<abi>/libksud.so the device-side stage fails much later and much less
# obviously, inside the emulator.
verify_manager_apk() {
    APK_TO_CHECK="$1"
    if ! command -v unzip >/dev/null 2>&1; then
        return 0
    fi
    if unzip -l "$APK_TO_CHECK" 2>/dev/null | grep -q "lib/.*/libksud\.so"; then
        return 0
    fi
    echo "[x] Error: this does not look like a KernelSU Next manager APK:"
    echo "    $APK_TO_CHECK"
    echo "    It contains no lib/<abi>/libksud.so, so ksud cannot be extracted."
    return 1
}

# Accepts a bare run id, or any Actions URL that contains /runs/<id>.
parse_run_id() {
    RUN_ID_RAW="$1"
    case "$RUN_ID_RAW" in
        *runs/*)
            RUN_ID="${RUN_ID_RAW#*runs/}"
            RUN_ID="${RUN_ID%%/*}"
            RUN_ID="${RUN_ID%%\?*}"
            ;;
        *)
            RUN_ID="$RUN_ID_RAW"
            ;;
    esac
    case "$RUN_ID" in
        ''|*[!0-9]*)
            echo "[x] Error: could not read a run id from:"
            echo "    $RUN_ID_RAW"
            echo "    Pass the numeric run id, or the full Actions URL of the run."
            exit 1
            ;;
    esac
}

fetch_ci_apk() {
    parse_run_id "$KSU_CI_RUN"

    if [ "$KSU_FLAVOR" = "spoofed" ]; then
        CI_ARTIFACT="manager-spoofed"
        CI_CACHE="$APPS_DIR/KernelSU-ci-$RUN_ID-spoofed.apk"
    else
        CI_ARTIFACT="manager"
        CI_CACHE="$APPS_DIR/KernelSU-ci-$RUN_ID.apk"
    fi

    if [ -f "$CI_CACHE" ]; then
        verify_manager_apk "$CI_CACHE" || exit 1
        KSU_APK_PATH="$CI_CACHE"
        echo "[-] Using cached CI build: $KSU_APK_PATH"
        return 0
    fi

    echo "[*] Fetching artifact \"$CI_ARTIFACT\" from $UPSTREAM_REPO run $RUN_ID..."
    mkdir -p "$APPS_DIR"
    CI_TMP="$APPS_DIR/.ci-$RUN_ID"
    rm -rf "$CI_TMP"
    mkdir -p "$CI_TMP"

    CI_OK=0
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        echo "[-] Downloading with the gh CLI..."
        if gh run download "$RUN_ID" -R "$UPSTREAM_REPO" -n "$CI_ARTIFACT" -D "$CI_TMP" >/dev/null 2>&1; then
            CI_OK=1
        else
            echo "[!] gh could not fetch \"$CI_ARTIFACT\" from that run."
        fi
    fi

    if [ "$CI_OK" -eq 0 ]; then
        # GitHub's own artifact endpoint requires a token. nightly.link mirrors
        # artifacts of public repositories without one.
        CI_URL="https://nightly.link/$UPSTREAM_REPO/actions/runs/$RUN_ID/$CI_ARTIFACT.zip"
        echo "[-] Downloading from $CI_URL"
        if curl -fsL -o "$CI_TMP/artifact.zip" "$CI_URL"; then
            unzip -qo "$CI_TMP/artifact.zip" -d "$CI_TMP" 2>/dev/null || true
            CI_OK=1
        fi
    fi

    CI_APK=""
    if [ "$CI_OK" -eq 1 ]; then
        CI_APK=$(find "$CI_TMP" -name '*.apk' -type f 2>/dev/null | head -n 1)
    fi

    if [ -z "$CI_APK" ]; then
        rm -rf "$CI_TMP"
        echo "[x] Error: run $RUN_ID has no \"$CI_ARTIFACT\" artifact."
        echo "    Only \"Build Manager CI\" runs publish manager APKs, and artifacts"
        echo "    expire 90 days after the run. Check what this run actually built:"
        echo "    https://github.com/$UPSTREAM_REPO/actions/runs/$RUN_ID"
        exit 1
    fi

    # Verify before caching, so a bad artifact never becomes a cache entry that
    # later runs would pick up.
    if ! verify_manager_apk "$CI_APK"; then
        rm -rf "$CI_TMP"
        exit 1
    fi
    mv -f "$CI_APK" "$CI_CACHE"
    rm -rf "$CI_TMP"
    KSU_APK_PATH="$CI_CACHE"
    echo "[V] CI build saved to $KSU_APK_PATH"
}

ensure_ksu_apk() {
    if [ "$KSU_FLAVOR" = "spoofed" ]; then
        KSU_APK_NAME="KernelSU-spoofed.apk"
    else
        KSU_APK_NAME="KernelSU.apk"
    fi

    # Source priority: apk= override, ci= artifact, drop-in file, latest release.
    if [ -n "$KSU_APK_OVERRIDE" ]; then
        if [ ! -f "$KSU_APK_OVERRIDE" ]; then
            echo "[x] Error: supplied APK not found:"
            echo "    $KSU_APK_OVERRIDE"
            exit 1
        fi
        verify_manager_apk "$KSU_APK_OVERRIDE" || exit 1
        KSU_APK_PATH="$KSU_APK_OVERRIDE"
        echo "[-] Using supplied manager APK: $KSU_APK_PATH"
        return 0
    fi

    if [ -n "$KSU_CI_RUN" ]; then
        fetch_ci_apk
        return 0
    fi

    if [ -f "$APPS_DIR/$KSU_APK_NAME" ]; then
        KSU_APK_PATH="$APPS_DIR/$KSU_APK_NAME"
        return 0
    fi
    if [ -f "$SCRIPT_DIR/$KSU_APK_NAME" ]; then
        KSU_APK_PATH="$SCRIPT_DIR/$KSU_APK_NAME"
        return 0
    fi

    echo "[!] $KSU_APK_NAME was not found in Apps/ or script root directory."
    echo "[*] Attempting to download the latest KernelSU Next release APK ($KSU_FLAVOR) from GitHub..."
    mkdir -p "$APPS_DIR"

    if [ "$KSU_FLAVOR" = "spoofed" ]; then
        LATEST_URL=$(curl -sL https://api.github.com/repos/KernelSU-Next/KernelSU-Next/releases/latest | grep "browser_download_url.*apk" | grep -v "debug" | grep "spoofed" | head -n 1 | cut -d '"' -f 4 || true)
    else
        LATEST_URL=$(curl -sL https://api.github.com/repos/KernelSU-Next/KernelSU-Next/releases/latest | grep "browser_download_url.*apk" | grep -v "debug" | grep -v "spoofed" | head -n 1 | cut -d '"' -f 4 || true)
    fi
    if [ -n "$LATEST_URL" ]; then
        echo "[-] Downloading from: $LATEST_URL"
        curl -L -o "$APPS_DIR/$KSU_APK_NAME" "$LATEST_URL"
        if [ -f "$APPS_DIR/$KSU_APK_NAME" ]; then
            verify_manager_apk "$APPS_DIR/$KSU_APK_NAME" || exit 1
            KSU_APK_PATH="$APPS_DIR/$KSU_APK_NAME"
            echo "[V] Downloaded successfully to $KSU_APK_PATH"
            return 0
        fi
    fi

    echo "[x] Error: Could not download $KSU_APK_NAME automatically."
    echo "    Please manually download the KernelSU Next APK ($KSU_FLAVOR) from https://github.com/KernelSU-Next/KernelSU-Next/releases"
    echo "    and place it at: $APPS_DIR/$KSU_APK_NAME"
    exit 1
}

restore_backup() {
    RESTORE_TARGET="$1"
    BACKUP_SRC="${RESTORE_TARGET}.backup"
    if [ ! -f "$BACKUP_SRC" ]; then
        echo "[x] Error: Backup file not found: $BACKUP_SRC"
        exit 1
    fi
    echo "[*] Restoring backup:"
    echo "    From: $BACKUP_SRC"
    echo "    To:   $RESTORE_TARGET"
    cp -f "$BACKUP_SRC" "$RESTORE_TARGET"
    echo "[V] Restore completed successfully!"
    exit 0
}

run_install_apps() {
    show_banner
    check_device
    echo "[*] Installing all APK files from: $APPS_DIR"
    FOUND=0
    for apk in "$APPS_DIR"/*.apk; do
        if [ -f "$apk" ]; then
            FOUND=1
            echo "[*] Installing $(basename "$apk")..."
            "$ADB_BIN" install -r "$apk"
        fi
    done
    if [ "$FOUND" -eq 0 ]; then
        echo "[!] No .apk files found in $APPS_DIR"
    else
        echo "[V] Finished installing apps."
    fi
    exit 0
}

show_help_and_images() {
    echo "Usage:"
    echo "  ./ksuAVD.sh <path_to_ramdisk.img> [OPTIONS]"
    echo "  ./ksuAVD.sh restore <path_to_ramdisk.img>"
    echo "  ./ksuAVD.sh InstallApps"
    echo ""
    echo "Options:"
    echo "  restore      Restore original ramdisk from ramdisk.img.backup"
    echo "  DEBUG        Keep temporary working files on AVD ($ADB_REMOTE_TMP)"
    echo "  spoofed      Use the spoofed package-ID manager APK variant"
    echo "  ci=<run>     Use the manager APK built by an upstream Actions run,"
    echo "               before it is released. Takes a run id or an Actions URL."
    echo "  apk=<path>   Use this manager APK file, at any path or filename."
    echo ""
    echo "Manager APK source priority: apk=, then ci=, then a drop-in file in"
    echo "Apps/ or next to the script, then the latest upstream release."
    echo ""
    echo "--- Available System Images / AVDs Detected on This Machine ---"
    FOUND_COUNT=0

    if [ -n "$SDK_DIR" ] && [ -d "$SDK_DIR/system-images" ]; then
        find "$SDK_DIR/system-images" -name "ramdisk*.img" 2>/dev/null | while IFS= read -r f; do
            if [ -n "$f" ]; then
                FOUND_COUNT=$((FOUND_COUNT + 1))
                REL_PATH="${f#$SDK_DIR/}"
                echo "  Example $FOUND_COUNT (Relative to SDK):"
                echo "    ./ksuAVD.sh \"$REL_PATH\""
                echo ""
            fi
        done
    fi

    AVD_DIR="$HOME/.android/avd"
    if [ -n "$ANDROID_AVD_HOME" ] && [ -d "$ANDROID_AVD_HOME" ]; then
        AVD_DIR="$ANDROID_AVD_HOME"
    elif [ -n "$ANDROID_SDK_HOME" ] && [ -d "$ANDROID_SDK_HOME/.android/avd" ]; then
        AVD_DIR="$ANDROID_SDK_HOME/.android/avd"
    fi

    if [ -d "$AVD_DIR" ]; then
        find "$AVD_DIR" -name "ramdisk*.img" 2>/dev/null | while IFS= read -r f; do
            if [ -n "$f" ]; then
                FOUND_COUNT=$((FOUND_COUNT + 1))
                echo "  Example $FOUND_COUNT (AVD Instance):"
                echo "    ./ksuAVD.sh \"$f\""
                echo ""
            fi
        done
    fi

    if [ "$FOUND_COUNT" -eq 0 ]; then
        echo "  No ramdisk.img was automatically found under standard SDK/AVD paths."
        echo "  You can pass the absolute path directly, for example:"
        echo "    ./ksuAVD.sh ~/Android/Sdk/system-images/android-34/google_apis/x86_64/ramdisk.img"
        echo ""
    fi
}

# ==============================================================================
# Main Entry Point
# ==============================================================================

# If invoked with --device or running inside Android environment
if is_device "$1"; then
    run_on_device
fi

find_sdk
find_adb

ARG1="$1"
DEBUG_MODE=0
DO_RESTORE=0
SHOW_HELP=0
KSU_FLAVOR="normal"
KSU_CI_RUN=""
KSU_APK_OVERRIDE=""
TARGET_RAMDISK=""

if [ "$ARG1" = "InstallApps" ]; then
    run_install_apps
fi

# Keywords are position independent; the first non-keyword argument is the
# ramdisk path.
for arg in "$@"; do
    case "$arg" in
        restore)             DO_RESTORE=1 ;;
        DEBUG)               DEBUG_MODE=1 ;;
        spoofed)             KSU_FLAVOR="spoofed" ;;
        ci=*)                KSU_CI_RUN="${arg#ci=}" ;;
        apk=*)               KSU_APK_OVERRIDE="${arg#apk=}" ;;
        -h|--help|help)      SHOW_HELP=1 ;;
        *)
            if [ -z "$TARGET_RAMDISK" ]; then
                TARGET_RAMDISK="$arg"
            fi
            ;;
    esac
done

if [ -n "$KSU_CI_RUN" ] && [ -n "$KSU_APK_OVERRIDE" ]; then
    echo "[x] Error: ci= and apk= cannot be combined. Pick one APK source."
    exit 1
fi

if [ -z "$TARGET_RAMDISK" ] || [ "$SHOW_HELP" -eq 1 ]; then
    show_banner
    show_device_status
    show_help_and_images
    exit 0
fi

show_banner

# Resolve relative path
if [ ! -f "$TARGET_RAMDISK" ]; then
    if [ -n "$SDK_DIR" ] && [ -f "$SDK_DIR/$TARGET_RAMDISK" ]; then
        TARGET_RAMDISK="$SDK_DIR/$TARGET_RAMDISK"
    else
        echo "[x] Error: Target ramdisk file not found:"
        echo "    $TARGET_RAMDISK"
        echo ""
        show_help_and_images
        exit 1
    fi
fi

if [ "$DO_RESTORE" -eq 1 ]; then
    restore_backup "$TARGET_RAMDISK"
fi

check_device
ensure_ksu_apk

echo "[*] Target ramdisk:"
echo "    $TARGET_RAMDISK"
echo ""

echo "[*] Initializing workspace on AVD: $ADB_REMOTE_TMP"
"$ADB_BIN" shell "rm -rf $ADB_REMOTE_TMP && mkdir -p $ADB_REMOTE_TMP"

echo "[*] Pushing KernelSU Next APK to AVD..."
"$ADB_BIN" push "$KSU_APK_PATH" "$ADB_REMOTE_TMP/KernelSU.apk"

echo "[*] Pushing ksuAVD.sh script to AVD..."
"$ADB_BIN" push "$SCRIPT_DIR/ksuAVD.sh" "$ADB_REMOTE_TMP/ksuAVD.sh"
"$ADB_BIN" shell "chmod 755 $ADB_REMOTE_TMP/ksuAVD.sh"

echo "[*] Pushing ramdisk.img to AVD..."
"$ADB_BIN" push "$TARGET_RAMDISK" "$ADB_REMOTE_TMP/ramdisk.img"

echo ""
echo "=============================================================================="
echo "[*] Running KernelSU Next patch process inside AVD..."
echo "=============================================================================="
"$ADB_BIN" shell "sh $ADB_REMOTE_TMP/ksuAVD.sh --device"
PATCH_EXIT=$?
echo "=============================================================================="
echo ""

if [ $PATCH_EXIT -ne 0 ]; then
    echo "[x] Patching failed inside AVD with exit code $PATCH_EXIT!"
    if [ "$DEBUG_MODE" -eq 0 ]; then
        "$ADB_BIN" shell "rm -rf $ADB_REMOTE_TMP" >/dev/null 2>&1 || true
    fi
    exit $PATCH_EXIT
fi

BACKUP_FILE="${TARGET_RAMDISK}.backup"
if [ ! -f "$BACKUP_FILE" ]; then
    echo "[*] Creating backup of original ramdisk:"
    echo "    $BACKUP_FILE"
    cp -f "$TARGET_RAMDISK" "$BACKUP_FILE"
else
    echo "[*] Existing backup preserved:"
    echo "    $BACKUP_FILE"
fi

echo "[*] Pulling patched ramdisk from AVD..."
"$ADB_BIN" pull "$ADB_REMOTE_TMP/ramdiskpatched4AVD.img" "$TARGET_RAMDISK"

echo "[*] Installing KernelSU Next Manager app on AVD..."
"$ADB_BIN" install -r "$KSU_APK_PATH"

# Flush the streamed install to disk. Stopping the emulator right after an
# install leaves base.apk broken, and PackageManager drops the app at the
# next boot.
echo "[*] Syncing filesystems before shutdown..."
"$ADB_BIN" shell sync
sleep 10

if [ "$DEBUG_MODE" -eq 0 ]; then
    echo "[*] Cleaning up temporary files on AVD..."
    "$ADB_BIN" shell "rm -rf $ADB_REMOTE_TMP" >/dev/null 2>&1 || true
else
    echo "[!] DEBUG mode: Temporary files kept at $ADB_REMOTE_TMP"
fi

echo ""
echo "=============================================================================="
echo "[V] SUCCESS! KernelSU Next has been successfully integrated into your AVD ramdisk!"
echo "=============================================================================="
echo ""
echo "Next Steps:"
echo "  1. Fully STOP the running emulator."
echo "  2. Start it again using \"Cold Boot Now\" in Android Studio Device Manager"
echo "     (or launch via CLI with: emulator -avd <avd_name> -no-snapshot-load)."
echo "  3. Open the KernelSU Next app inside the emulator. You should see \"Working\"!"
echo "  4. Go to the \"Superuser\" tab to grant root permissions to Apps or Shell."
echo ""
