# KernelSU-Next-AVD

Root an Android Virtual Device (AVD) with **KernelSU Next**, using the GKI loadable kernel module (LKM) method.

Two scripts do the whole job. They patch the emulator's `ramdisk.img`, install the KernelSU Next manager, and keep a backup so you can undo it. It targets official Android Studio emulators from Android 12 (API 31) up to Android 16/17 (API 37+).

This is a fork of [KernelSU-AVD](https://github.com/HChenX/KernelSU-AVD) by HChenX, switched over to KernelSU Next.

Releases and updates are announced on Telegram: [t.me/ymuulabs](https://t.me/ymuulabs).

---

## Tested status

| Emulator | Result |
|---|---|
| Android 16 | Working. This is the only version confirmed end to end. |
| Android 15 | Fails. The errors come from KernelSU Next itself and still need investigation. |
| Everything else | Untested. |

**Try it at your own risk.** Only the Android 16 emulator has been verified. Your `ramdisk.img` is backed up before it is touched, and `restore` puts the stock one back, so a failed attempt is recoverable.

---

## What you get

- **Kernel-level root**: KernelSU Next is loaded as a real kernel module (`.ko`) into the GKI kernel the emulator already runs.
- **16KB page size support**: works on the Android 15/16 images that use 16KB memory pages, where older root tools crash with `mprotect failed`.
- **No legacy hacks**: patching is done by `ksud boot-patch --ramdisk`. No fake boot images, no bootloader tricks, no ash script pipelines.
- **Root is opt-in**: no app gets root until you grant it in the manager, ADB shell included.
- **Windows, Linux and macOS**: `ksuAVD.bat` for Windows, `ksuAVD.sh` for the rest.
- **Reversible**: the original ramdisk is saved as `ramdisk.img.backup`, and `restore` puts it back.

---

## Before you start

1. **An AVD on a GKI kernel** - `android12-5.10`, `android13-5.15`, `android14-6.1`, `android15-6.6`, `android16-6.12` or newer. Architecture `x86_64` or `arm64-v8a`.
2. **`adb`** - either in your `PATH` or in the standard SDK folder (`%LOCALAPPDATA%\Android\Sdk` on Windows, `~/Android/Sdk` on Linux and macOS).
3. **The emulator running** - start the AVD first and check it with `adb devices`. The patching happens inside the emulator.

---

## Files

```text
KernelSU-Next-AVD/
├── ksuAVD.bat        # Windows entry script
├── ksuAVD.sh         # Linux / macOS entry script (also runs inside the AVD)
├── Apps/             # Put APKs here (the manager APK is downloaded if missing)
│   └── .gitkeep
├── LICENSE           # GPL-3.0
├── README.md         # This file
└── README_CN.md      # Chinese version
```

---

## Usage

### 1. Run it with no arguments

With the AVD running, start the script with no arguments. It reports the emulator it sees and lists a ready-to-paste command for every system image found on your machine.

**Windows**:
```cmd
ksuAVD.bat
```

**Linux / macOS**:
```bash
chmod +x ksuAVD.sh
./ksuAVD.sh
```

Output looks like this:
```text
==============================================================================
                KernelSU-Next-AVD: Root AVD with KernelSU Next
              GitHub: https://github.com/ymuuuu/KernelSU-Next-AVD
==============================================================================

--- ADB Connected Device Status ---
  Model:           sdk_gphone16k_x86_64
  Android Version: 17 (API 37)
  Architecture:    x86_64
  Kernel:          6.12.81-android16-6-g4f69fc7b210c-ab16167562

Usage:
  ksuAVD.bat <path_to_ramdisk.img> [OPTIONS]
  ksuAVD.bat restore <path_to_ramdisk.img>
  ksuAVD.bat InstallApps

--- Available System Images / AVDs Detected on This Machine ---
  [1] ksuAVD.bat "system-images\android-35\google_apis\x86_64\ramdisk.img"
  [2] ksuAVD.bat "system-images\android-37.2\google_apis_playstore_ps16k\x86_64\ramdisk.img"
```

---

### 2. Patch the AVD

Paste one of the listed commands, or pass the path to your `ramdisk.img` yourself. Paths may be relative to the SDK or absolute.

**Windows**:
```cmd
ksuAVD.bat "system-images\android-37.2\google_apis_playstore_ps16k\x86_64\ramdisk.img"
```

A specific AVD instance folder works too:
```cmd
ksuAVD.bat "D:\Android\AVD\Pixel_10_Pro.avd\ramdisk.img"
```

**Linux / macOS**:
```bash
./ksuAVD.sh "system-images/android-34/google_apis/x86_64/ramdisk.img"
```

Options you can append:

- `restore` - put the backed-up ramdisk back (see step 5).
- `DEBUG` - leave the working files on the AVD in `/data/local/tmp/ksuAVD`.
- `spoofed` - use the spoofed package-ID variant of the manager APK.
- `ci=<run>` - use the manager APK from an upstream CI run, before it is released.
- `apk=<path>` - use a manager APK you supply, at any path and any filename.

See [Choosing the manager APK](#choosing-the-manager-apk) for the two new ones.

#### What the script does

1. Pushes your `ramdisk.img`, the manager APK and `ksuAVD.sh` to `/data/local/tmp/ksuAVD/` on the emulator.
2. Unpacks `ksud` from the APK for the emulator's architecture.
3. Reads the running kernel's KMI, for example `android16-6.12`.
4. Runs `ksud boot-patch --ramdisk --allow-shell`, which injects the matching KernelSU Next module and chainloads `ksuinit`.
5. Copies your original `ramdisk.img` to `ramdisk.img.backup`.
6. Pulls the patched image back and puts it in place of `ramdisk.img`.
7. Installs the manager app on the AVD.
8. Deletes the temporary files from the emulator.

---

### Choosing the manager APK

By default the script looks for `KernelSU.apk` in `Apps/` or next to itself, and
downloads the latest KernelSU Next release if it finds neither. Two options
override that.

**Use a build from upstream CI, before it is released.** Open the run on the
[Actions page](https://github.com/KernelSU-Next/KernelSU-Next/actions) and pass
either its id or its full URL:

```bash
./ksuAVD.sh "path/to/ramdisk.img" ci=38912876962
./ksuAVD.sh "path/to/ramdisk.img" ci=https://github.com/KernelSU-Next/KernelSU-Next/actions/runs/38912876962
```

Add `spoofed` to take the spoofed variant from the same run:

```bash
./ksuAVD.sh "path/to/ramdisk.img" ci=38912876962 spoofed
```

Only **Build Manager CI** runs publish a manager APK, as the artifacts `manager`
and `manager-spoofed`. Plenty of green runs on that repository build only `ksud`,
`ksuinit` or the LKM modules and carry no APK at all, and GitHub deletes
artifacts 90 days after the run. If the artifact is not there you get a message
saying so and a link to the run, rather than a failed patch.

The download uses the `gh` CLI when it is installed and logged in, and otherwise
falls back to [nightly.link](https://nightly.link), which mirrors artifacts of
public repositories without a token. The APK is cached as
`Apps/KernelSU-ci-<run-id>.apk`, or `Apps/KernelSU-ci-<run-id>-spoofed.apk` for
the spoofed variant, so passing the same run again does not re-download it.

**Use an APK you supply.** Any path, any filename, including a manager you built
yourself:

```bash
./ksuAVD.sh "path/to/ramdisk.img" apk=/home/me/builds/my-kernelsu-next.apk
```

`apk=` wins over `ci=`, which wins over a drop-in file, which wins over the
latest release. The two cannot be combined. Whichever source is used, the APK is
rejected before anything is pushed to the emulator if it contains no
`lib/<abi>/libksud.so`, because `ksud` is extracted from it.

---

### 3. Cold boot to apply it

The new ramdisk is only read on a cold boot:

1. **Close** the emulator completely.
2. In Android Studio **Device Manager**, open the emulator's drop-down menu and pick **"Cold Boot Now"**. From the command line, add `-no-snapshot-load`.
3. Open the **KernelSU Next** app on the emulator.
4. It should say **Working (LKM Mode)**.

---

### 4. Grant root to the shell and to apps

Nothing has root until you say so, including `adb shell`.

To give `adb shell` root:

1. Open **KernelSU Next** on the emulator.
2. Go to the **Superuser** tab.
3. Open the top-right menu and turn on **"Show system apps"**.
4. Find **Shell** (`com.android.shell`) and set it to **Grant**.
5. Run `adb shell su` from your terminal. You are now `uid=0(root)`.

---

### 5. Go back to stock

**Windows**:
```cmd
ksuAVD.bat restore "path\to\ramdisk.img"
```

**Linux / macOS**:
```bash
./ksuAVD.sh restore "path/to/ramdisk.img"
```

---

### 6. Install extra apps

Drop any APKs into `Apps/` and run:

**Windows**:
```cmd
ksuAVD.bat InstallApps
```

**Linux / macOS**:
```bash
./ksuAVD.sh InstallApps
```

---

## Why KernelSU Next on a modern AVD

Older root methods break on recent emulator images for two reasons:

1. **16KB page size**. From Android 15 on, emulator images can use 16KB memory pages, and often do by default. Binaries built only for 4KB pages die immediately with alignment errors (`mprotect failed`). `ksud` and the KernelSU Next modules handle both page sizes.
2. **GKI**. Android 12+ emulators run Google's Generic Kernel Image, the same one real devices use. KernelSU Next loads into it as a kernel module in `/lib/modules`, so there is no patched kernel binary and no zygote hijacking.

---

## Credits

This project stands on other people's work:

- **[KernelSU-AVD](https://github.com/HChenX/KernelSU-AVD)** by **HChenX**: the project this one is forked from. The AVD detection, the push-and-patch flow and both entry scripts come from there.
- **[KernelSU Next](https://github.com/KernelSU-Next/KernelSU-Next)** by **rifsxd** and contributors: the root solution used here, including the LKM modules and the `ksud` boot patcher.
- **[KernelSU](https://github.com/tiann/KernelSU)** by **tiann**, **weishu** and contributors: the kernel-based root solution KernelSU Next builds on.
- **[rootAVD](https://gitlab.com/newbit/rootAVD)** by **newbit**: first automated the ramdisk extract, patch and replace cycle for Android Studio AVDs.
- **[Magisk](https://github.com/topjohnwu/Magisk)** by **topjohnwu**: the foundation of systemless Android modding.

---

## License

[GNU General Public License v3.0](LICENSE).

## Disclaimer
I am no developer or a low level programmer, I am a guy who loves breaking, testing, building security releated tools that helps with my workflow, excpect bugs and errors, thank you.