@echo off
setlocal EnableDelayedExpansion

REM ==============================================================================
REM KernelSU-Next-AVD: Root Android Virtual Devices (AVD) using KernelSU Next
REM Repository: https://github.com/ymuuuu/KernelSU-Next-AVD
REM Fork of KernelSU-AVD by HChenX. Inspired by rootAVD (newbit).
REM ==============================================================================

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "APPS_DIR=%SCRIPT_DIR%\Apps"
set "ADB_REMOTE_TMP=/data/local/tmp/ksuAVD"
set "UPSTREAM_REPO=KernelSU-Next/KernelSU-Next"

REM Locate Android SDK & ADB
call :FindSDK
call :FindADB

REM Parse arguments
set "ARG1=%~1"
set "DEBUG_MODE=0"
set "DO_RESTORE=0"
set "SHOW_HELP=0"
set "KSU_FLAVOR=normal"
set "KSU_CI_RUN="
set "KSU_APK_OVERRIDE="
set "TARGET_RAMDISK="

if /i "%ARG1%"=="InstallApps" (
    call :RunInstallApps
    exit /b %ERRORLEVEL%
)

REM Keywords are position independent; the first non-keyword argument is the
REM ramdisk path.
:ParseLoop
if "%~1"=="" goto :ParseDone
set "ARGV=%~1"
if /i "!ARGV!"=="restore" (
    set "DO_RESTORE=1"
) else if /i "!ARGV!"=="DEBUG" (
    set "DEBUG_MODE=1"
) else if /i "!ARGV!"=="spoofed" (
    set "KSU_FLAVOR=spoofed"
) else if /i "!ARGV!"=="-h" (
    set "SHOW_HELP=1"
) else if /i "!ARGV!"=="--help" (
    set "SHOW_HELP=1"
) else if /i "!ARGV!"=="/?" (
    set "SHOW_HELP=1"
) else if /i "!ARGV!"=="help" (
    set "SHOW_HELP=1"
) else if /i "!ARGV:~0,3!"=="ci=" (
    set "KSU_CI_RUN=!ARGV:~3!"
) else if /i "!ARGV:~0,4!"=="apk=" (
    set "KSU_APK_OVERRIDE=!ARGV:~4!"
) else (
    if not defined TARGET_RAMDISK set "TARGET_RAMDISK=!ARGV!"
)
shift
goto :ParseLoop
:ParseDone

if defined KSU_CI_RUN if defined KSU_APK_OVERRIDE (
    echo [x] Error: ci= and apk= cannot be combined. Pick one APK source.
    exit /b 1
)

REM If no target specified or help requested
if not defined TARGET_RAMDISK goto :HelpExit
if "%SHOW_HELP%"=="1" goto :HelpExit
goto :StartOperation

:HelpExit
call :ShowBanner
call :ShowDeviceStatus
call :ShowHelpAndFoundImages
exit /b 0

:StartOperation
call :ShowBanner

REM Check if target ramdisk exists
if not exist "%TARGET_RAMDISK%" (
    if defined SDK_DIR if exist "%SDK_DIR%\%TARGET_RAMDISK%" (
        set "TARGET_RAMDISK=%SDK_DIR%\%TARGET_RAMDISK%"
    ) else (
        echo [x] Error: Target ramdisk file not found:
        echo     "%TARGET_RAMDISK%"
        echo.
        call :ShowHelpAndFoundImages
        exit /b 1
    )
)

REM Handle restore operation
if "%DO_RESTORE%"=="1" (
    call :RestoreBackup "%TARGET_RAMDISK%"
    exit /b %ERRORLEVEL%
)

REM Verify ADB connection
call :CheckDeviceConnection
if %ERRORLEVEL% neq 0 exit /b 1

REM Ensure KernelSU Next APK exists
call :EnsureKernelSUApk
if %ERRORLEVEL% neq 0 exit /b 1

echo [*] Target ramdisk:
echo     "%TARGET_RAMDISK%"
echo.

REM Create remote working directory
echo [*] Initializing workspace on AVD: %ADB_REMOTE_TMP%
"%ADB_BIN%" shell "rm -rf %ADB_REMOTE_TMP% && mkdir -p %ADB_REMOTE_TMP%" >nul 2>&1

REM Push required files
echo [*] Pushing KernelSU Next APK to AVD...
"%ADB_BIN%" push "%KSU_APK_PATH%" "%ADB_REMOTE_TMP%/KernelSU.apk"
if %ERRORLEVEL% neq 0 (
    echo [x] Failed to push KernelSU Next APK to device.
    exit /b 1
)

echo [*] Pushing ksuAVD.sh script to AVD...
"%ADB_BIN%" push "%SCRIPT_DIR%\ksuAVD.sh" "%ADB_REMOTE_TMP%/ksuAVD.sh" >nul 2>&1
"%ADB_BIN%" shell "chmod 755 %ADB_REMOTE_TMP%/ksuAVD.sh"

echo [*] Pushing ramdisk.img to AVD (this may take a few seconds)...
"%ADB_BIN%" push "%TARGET_RAMDISK%" "%ADB_REMOTE_TMP%/ramdisk.img"
if %ERRORLEVEL% neq 0 (
    echo [x] Failed to push ramdisk.img to device.
    exit /b 1
)

REM Execute patching script on device
echo.
echo ==============================================================================
echo [*] Running KernelSU Next patch process inside AVD...
echo ==============================================================================
"%ADB_BIN%" shell "sh %ADB_REMOTE_TMP%/ksuAVD.sh --device"
set "PATCH_EXIT=%ERRORLEVEL%"
echo ==============================================================================
echo.

if %PATCH_EXIT% neq 0 (
    echo [x] Patching failed inside AVD with exit code %PATCH_EXIT%!
    if "%DEBUG_MODE%"=="0" (
        "%ADB_BIN%" shell "rm -rf %ADB_REMOTE_TMP%" >nul 2>&1
    )
    exit /b %PATCH_EXIT%
)

REM Backup original ramdisk if not already backed up
set "BACKUP_FILE=%TARGET_RAMDISK%.backup"
if not exist "%BACKUP_FILE%" (
    echo [*] Creating backup of original ramdisk:
    echo     "%BACKUP_FILE%"
    copy /y "%TARGET_RAMDISK%" "%BACKUP_FILE%" >nul
) else (
    echo [*] Existing backup preserved:
    echo     "%BACKUP_FILE%"
)

REM Pull patched ramdisk back
echo [*] Pulling patched ramdisk from AVD...
"%ADB_BIN%" pull "%ADB_REMOTE_TMP%/ramdiskpatched4AVD.img" "%TARGET_RAMDISK%"
if %ERRORLEVEL% neq 0 (
    echo [x] Failed to pull patched ramdisk!
    exit /b 1
)

REM Install KernelSU Manager APK
echo [*] Installing KernelSU Next Manager app on AVD...
"%ADB_BIN%" install -r "%KSU_APK_PATH%"

REM Flush the streamed install to disk. Stopping the emulator right after an
REM install leaves base.apk broken, and PackageManager drops the app at the
REM next boot.
echo [*] Syncing filesystems before shutdown...
"%ADB_BIN%" shell sync
timeout /t 10 /nobreak >nul

REM Cleanup remote workspace
if "%DEBUG_MODE%"=="0" (
    echo [*] Cleaning up temporary files on AVD...
    "%ADB_BIN%" shell "rm -rf %ADB_REMOTE_TMP%" >nul 2>&1
) else (
    echo [!] DEBUG mode: Temporary files kept at %ADB_REMOTE_TMP%
)

echo.
echo ==============================================================================
echo [V] SUCCESS! KernelSU Next has been successfully integrated into your AVD ramdisk!
echo ==============================================================================
echo.
echo Next Steps:
echo   1. Fully STOP the running emulator.
echo   2. Start it again using "Cold Boot Now" in Android Studio Device Manager
echo      (or launch via CLI with: emulator -avd ^<avd_name^> -no-snapshot-load).
echo   3. Open the KernelSU Next app inside the emulator. You should see "Working"!
echo   4. Go to the "Superuser" tab to grant root permissions to Apps or Shell.
echo.
exit /b 0

REM ==============================================================================
REM Subroutines
REM ==============================================================================

:ShowBanner
echo ==============================================================================
echo                 KernelSU-Next-AVD: Root AVD with KernelSU Next
echo               GitHub: https://github.com/ymuuuu/KernelSU-Next-AVD
echo ==============================================================================
echo.
exit /b 0

:FindSDK
set "SDK_DIR="
if defined ANDROID_HOME if exist "%ANDROID_HOME%" set "SDK_DIR=%ANDROID_HOME%"
if not defined SDK_DIR if defined ANDROID_SDK_ROOT if exist "%ANDROID_SDK_ROOT%" set "SDK_DIR=%ANDROID_SDK_ROOT%"
if not defined SDK_DIR if exist "%LOCALAPPDATA%\Android\Sdk" set "SDK_DIR=%LOCALAPPDATA%\Android\Sdk"
if defined SDK_DIR (
    for %%a in ("!SDK_DIR!") do set "SDK_DIR=%%~fa"
)
exit /b 0

:FindADB
set "ADB_BIN=adb"
where adb >nul 2>&1
if %ERRORLEVEL% equ 0 exit /b 0

if defined SDK_DIR (
    if exist "%SDK_DIR%\platform-tools\adb.exe" (
        set "ADB_BIN=%SDK_DIR%\platform-tools\adb.exe"
        exit /b 0
    )
)
echo [!] Warning: adb command not found in PATH or Android SDK platform-tools.
exit /b 1

:CheckDeviceConnection
"%ADB_BIN%" get-state >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [x] Error: No running Android emulator / device detected by ADB!
    echo     Please make sure your AVD is launched and fully booted before running this script.
    echo.
    "%ADB_BIN%" devices
    exit /b 1
)
exit /b 0

:ShowDeviceStatus
echo --- ADB Connected Device Status ---
%ADB_BIN% get-state >nul 2>&1
set "ADB_STATE_EXIT=%ERRORLEVEL%"
if not "%ADB_STATE_EXIT%"=="0" (
    echo   Device: None connected - Start your AVD first
    echo.
    exit /b 0
)

set "DEV_MODEL=Unknown"
set "DEV_ANDROID=Unknown"
set "DEV_SDK=Unknown"
set "DEV_ABI=Unknown"
set "DEV_KERNEL=Unknown"

for /f "tokens=*" %%i in ('%ADB_BIN% shell getprop ro.product.model') do set "DEV_MODEL=%%i"
for /f "tokens=*" %%i in ('%ADB_BIN% shell getprop ro.build.version.release') do set "DEV_ANDROID=%%i"
for /f "tokens=*" %%i in ('%ADB_BIN% shell getprop ro.build.version.sdk') do set "DEV_SDK=%%i"
for /f "tokens=*" %%i in ('%ADB_BIN% shell getprop ro.product.cpu.abi') do set "DEV_ABI=%%i"
for /f "tokens=*" %%i in ('%ADB_BIN% shell uname -r') do set "DEV_KERNEL=%%i"

echo   Model:           !DEV_MODEL!
echo   Android Version: !DEV_ANDROID! (API !DEV_SDK!)
echo   Architecture:    !DEV_ABI!
echo   Kernel:          !DEV_KERNEL!
echo.
exit /b 0

REM Reject an APK that cannot supply ksud, before anything is pushed. Without
REM lib/<abi>/libksud.so the device-side stage fails much later and much less
REM obviously, inside the emulator. A zip we cannot inspect is let through.
:VerifyManagerApk
set "APK_CHECK=%~1"
powershell -NoProfile -Command ^
    "try { " ^
    "  Add-Type -AssemblyName System.IO.Compression.FileSystem; " ^
    "  $zip = [IO.Compression.ZipFile]::OpenRead($env:APK_CHECK); " ^
    "  $hit = $zip.Entries | Where-Object { $_.FullName -like 'lib/*/libksud.so' } | Select-Object -First 1; " ^
    "  $zip.Dispose(); " ^
    "  if ($hit) { exit 0 } else { exit 1 } " ^
    "} catch { exit 0 }"
if %ERRORLEVEL% neq 0 (
    echo [x] Error: this does not look like a KernelSU Next manager APK:
    echo     "%APK_CHECK%"
    echo     It contains no lib/^<abi^>/libksud.so, so ksud cannot be extracted.
    exit /b 1
)
exit /b 0

REM Accepts a bare run id, or any Actions URL that contains /runs/<id>.
:ParseRunId
set "RID=%~1"
set "RID_WORK=!RID:runs/=|!"
if not "!RID_WORK!"=="!RID!" (
    for /f "tokens=2 delims=|" %%a in ("!RID_WORK!") do set "RID=%%a"
)
for /f "tokens=1 delims=/?#" %%a in ("!RID!") do set "RID=%%a"
echo !RID!| findstr /r "^[0-9][0-9]*$" >nul
if %ERRORLEVEL% neq 0 (
    echo [x] Error: could not read a run id from:
    echo     "%~1"
    echo     Pass the numeric run id, or the full Actions URL of the run.
    exit /b 1
)
set "RUN_ID=!RID!"
exit /b 0

:FetchCiApk
call :ParseRunId "%KSU_CI_RUN%"
if %ERRORLEVEL% neq 0 exit /b 1

if /i "%KSU_FLAVOR%"=="spoofed" (
    set "CI_ARTIFACT=manager-spoofed"
    set "CI_CACHE=%APPS_DIR%\KernelSU-ci-!RUN_ID!-spoofed.apk"
) else (
    set "CI_ARTIFACT=manager"
    set "CI_CACHE=%APPS_DIR%\KernelSU-ci-!RUN_ID!.apk"
)

if exist "!CI_CACHE!" (
    call :VerifyManagerApk "!CI_CACHE!"
    if !ERRORLEVEL! neq 0 exit /b 1
    set "KSU_APK_PATH=!CI_CACHE!"
    echo [-] Using cached CI build: "!CI_CACHE!"
    exit /b 0
)

echo [*] Fetching artifact "!CI_ARTIFACT!" from %UPSTREAM_REPO% run !RUN_ID!...
if not exist "%APPS_DIR%" mkdir "%APPS_DIR%"
set "CI_TMP=%APPS_DIR%\.ci-!RUN_ID!"
if exist "!CI_TMP!" rd /s /q "!CI_TMP!"
mkdir "!CI_TMP!"

set "CI_OK=0"
where gh >nul 2>&1
if !ERRORLEVEL! equ 0 (
    gh auth status >nul 2>&1
    if !ERRORLEVEL! equ 0 (
        echo [-] Downloading with the gh CLI...
        gh run download !RUN_ID! -R %UPSTREAM_REPO% -n "!CI_ARTIFACT!" -D "!CI_TMP!" >nul 2>&1
        if !ERRORLEVEL! equ 0 (
            set "CI_OK=1"
        ) else (
            echo [-] gh could not fetch "!CI_ARTIFACT!", trying the mirror.
        )
    )
)

REM GitHub's own artifact endpoint requires a token. nightly.link mirrors
REM artifacts of public repositories without one.
if "!CI_OK!"=="0" (
    set "CI_URL=https://nightly.link/%UPSTREAM_REPO%/actions/runs/!RUN_ID!/!CI_ARTIFACT!.zip"
    set "CI_ZIP=!CI_TMP!\artifact.zip"
    echo [-] Downloading from !CI_URL!
    powershell -NoProfile -Command ^
        "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; " ^
        "try { " ^
        "  Invoke-WebRequest -Uri $env:CI_URL -OutFile $env:CI_ZIP; " ^
        "  Expand-Archive -LiteralPath $env:CI_ZIP -DestinationPath $env:CI_TMP -Force; " ^
        "  exit 0 " ^
        "} catch { exit 1 }"
    if !ERRORLEVEL! equ 0 set "CI_OK=1"
)

set "CI_APK="
if "!CI_OK!"=="1" (
    for /f "delims=" %%f in ('dir "!CI_TMP!\*.apk" /s /b /a-d 2^>nul') do (
        if not defined CI_APK set "CI_APK=%%f"
    )
)

if not defined CI_APK (
    if exist "!CI_TMP!" rd /s /q "!CI_TMP!"
    echo [x] Error: run !RUN_ID! has no "!CI_ARTIFACT!" artifact.
    echo     Only "Build Manager CI" runs publish manager APKs, and artifacts
    echo     expire 90 days after the run. Check what this run actually built:
    echo     https://github.com/%UPSTREAM_REPO%/actions/runs/!RUN_ID!
    exit /b 1
)

REM Verify before caching, so a bad artifact never becomes a cache entry that
REM later runs would pick up.
call :VerifyManagerApk "!CI_APK!"
if %ERRORLEVEL% neq 0 (
    if exist "!CI_TMP!" rd /s /q "!CI_TMP!"
    exit /b 1
)
move /y "!CI_APK!" "!CI_CACHE!" >nul
if exist "!CI_TMP!" rd /s /q "!CI_TMP!"
set "KSU_APK_PATH=!CI_CACHE!"
echo [V] CI build saved to "!CI_CACHE!"
exit /b 0

:EnsureKernelSUApk
set "KSU_APK_PATH="
if /i "%KSU_FLAVOR%"=="spoofed" (
    set "KSU_APK_NAME=KernelSU-spoofed.apk"
) else (
    set "KSU_APK_NAME=KernelSU.apk"
)

REM Source priority: apk= override, ci= artifact, drop-in file, latest release.
if defined KSU_APK_OVERRIDE (
    if not exist "%KSU_APK_OVERRIDE%" (
        echo [x] Error: supplied APK not found:
        echo     "%KSU_APK_OVERRIDE%"
        exit /b 1
    )
    call :VerifyManagerApk "%KSU_APK_OVERRIDE%"
    if !ERRORLEVEL! neq 0 exit /b 1
    set "KSU_APK_PATH=%KSU_APK_OVERRIDE%"
    echo [-] Using supplied manager APK: "%KSU_APK_OVERRIDE%"
    exit /b 0
)

if defined KSU_CI_RUN (
    call :FetchCiApk
    exit /b !ERRORLEVEL!
)

if exist "%APPS_DIR%\%KSU_APK_NAME%" (
    set "KSU_APK_PATH=%APPS_DIR%\%KSU_APK_NAME%"
    exit /b 0
)
if exist "%SCRIPT_DIR%\%KSU_APK_NAME%" (
    set "KSU_APK_PATH=%SCRIPT_DIR%\%KSU_APK_NAME%"
    exit /b 0
)

echo [!] %KSU_APK_NAME% was not found in Apps\ or script root directory.
echo [*] Attempting to download the latest KernelSU Next release APK (%KSU_FLAVOR%) from GitHub...
if not exist "%APPS_DIR%" mkdir "%APPS_DIR%"

powershell -NoProfile -Command ^
    "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; " ^
    "$repo = 'KernelSU-Next/KernelSU-Next'; " ^
    "try { " ^
    "  $spoofed = $env:KSU_FLAVOR -eq 'spoofed'; " ^
    "  $release = Invoke-RestMethod -Uri \"https://api.github.com/repos/$repo/releases/latest\"; " ^
    "  $asset = $release.assets | Where-Object { $_.name -like '*.apk' -and $_.name -notlike '*debug*' -and ($spoofed -eq ($_.name -like '*spoofed*')) } | Select-Object -First 1; " ^
    "  if (-not $asset) { $asset = $release.assets | Where-Object { $_.name -like '*.apk' } | Select-Object -First 1; } " ^
    "  Write-Host \"Downloading $($asset.name)...\"; " ^
    "  Invoke-WebRequest -Uri $asset.browser_download_url -OutFile '%APPS_DIR%\%KSU_APK_NAME%'; " ^
    "  exit 0; " ^
    "} catch { " ^
    "  Write-Host \"Download failed: $_\" -ForegroundColor Red; " ^
    "  exit 1; " ^
    "}"

if exist "%APPS_DIR%\%KSU_APK_NAME%" (
    call :VerifyManagerApk "%APPS_DIR%\%KSU_APK_NAME%"
    if !ERRORLEVEL! neq 0 exit /b 1
    set "KSU_APK_PATH=%APPS_DIR%\%KSU_APK_NAME%"
    echo [V] Downloaded successfully to "%APPS_DIR%\%KSU_APK_NAME%".
    exit /b 0
)

echo [x] Error: Could not download %KSU_APK_NAME% automatically.
echo     Please manually download the KernelSU Next APK (%KSU_FLAVOR%) from https://github.com/KernelSU-Next/KernelSU-Next/releases
echo     and place it at: "%APPS_DIR%\%KSU_APK_NAME%"
exit /b 1

:RestoreBackup
set "RESTORE_TARGET=%~1"
set "BACKUP_SRC=%RESTORE_TARGET%.backup"
if not exist "%BACKUP_SRC%" (
    echo [x] Error: Backup file not found:
    echo     "%BACKUP_SRC%"
    exit /b 1
)
echo [*] Restoring backup:
echo     From: "%BACKUP_SRC%"
echo     To:   "%RESTORE_TARGET%"
copy /y "%BACKUP_SRC%" "%RESTORE_TARGET%" >nul
if %ERRORLEVEL% equ 0 (
    echo [V] Restore completed successfully!
) else (
    echo [x] Restore failed!
)
exit /b %ERRORLEVEL%

:RunInstallApps
call :ShowBanner
call :CheckDeviceConnection
if %ERRORLEVEL% neq 0 exit /b 1

echo [*] Installing all APK files from: %APPS_DIR%
set "FOUND_ANY=0"
for %%f in ("%APPS_DIR%\*.apk") do (
    set "FOUND_ANY=1"
    echo [*] Installing "%%~nxf"...
    "%ADB_BIN%" install -r "%%f"
)
if "%FOUND_ANY%"=="0" (
    echo [!] No .apk files found in %APPS_DIR%
) else (
    echo [V] Finished installing apps.
)
exit /b 0

:ShowHelpAndFoundImages
echo Usage:
echo   ksuAVD.bat ^<path_to_ramdisk.img^> [OPTIONS]
echo   ksuAVD.bat restore ^<path_to_ramdisk.img^>
echo   ksuAVD.bat InstallApps
echo.
echo Options:
echo   restore      Restore original ramdisk from ramdisk.img.backup
echo   DEBUG        Keep temporary working files on AVD (/data/local/tmp/ksuAVD)
echo   spoofed      Use the spoofed package-ID manager APK variant
echo   ci=^<run^>     Use the manager APK built by an upstream Actions run,
echo                before it is released. Takes a run id or an Actions URL.
echo   apk=^<path^>   Use this manager APK file, at any path or filename.
echo.
echo Manager APK source priority: apk=, then ci=, then a drop-in file in
echo Apps\ or next to the script, then the latest upstream release.
echo.
echo --- Available System Images / AVDs Detected on This Machine ---
set "FOUND_COUNT=0"

REM Search system-images
if defined SDK_DIR (
    if exist "%SDK_DIR%\system-images" (
        for /f "delims=" %%f in ('dir "%SDK_DIR%\system-images\ramdisk*.img" /s /b /a-d 2^>nul') do (
            set /a FOUND_COUNT+=1
            call :PrintDetectedPath "%%f"
        )
    )
)

REM Search AVD instances in .android/avd or ANDROID_AVD_HOME or ANDROID_SDK_HOME
set "AVD_SEARCH_DIR=%USERPROFILE%\.android\avd"
if defined ANDROID_AVD_HOME if exist "%ANDROID_AVD_HOME%" set "AVD_SEARCH_DIR=%ANDROID_AVD_HOME%"
if defined ANDROID_SDK_HOME (
    for %%a in ("%ANDROID_SDK_HOME%") do (
        if exist "%%~fa\.android\avd" set "AVD_SEARCH_DIR=%%~fa\.android\avd"
    )
)

if exist "%AVD_SEARCH_DIR%" (
    for /f "delims=" %%f in ('dir "%AVD_SEARCH_DIR%\ramdisk*.img" /s /b /a-d 2^>nul') do (
        set /a FOUND_COUNT+=1
        call :PrintDetectedPath "%%f"
    )
)

if "%FOUND_COUNT%"=="0" (
    echo   No ramdisk.img was automatically found under standard SDK/AVD paths.
    echo   You can pass the path directly, for example:
    echo     ksuAVD.bat "D:\RuanJian\AVD\Pixel_10_Pro.avd\ramdisk.img"
    echo.
)
exit /b 0

:PrintDetectedPath
set "ITEM_PATH=%~1"
set "REL_ITEM_PATH=!ITEM_PATH!"
if defined SDK_DIR (
    set "TMP_SDK=!SDK_DIR!\"
    for /f "delims=" %%k in ("!TMP_SDK!") do set "REL_ITEM_PATH=!REL_ITEM_PATH:%%k=!"
)
echo   [%FOUND_COUNT%] ksuAVD.bat "!REL_ITEM_PATH!"
echo.
exit /b 0
