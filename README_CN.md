# KernelSU-Next-AVD

轻量、现代且全自动的 Android 虚拟设备（AVD）**KernelSU Next** Root 工具。基于 GKI 可加载内核模块（LKM）机制，为 Android Studio 官方模拟器提供原生内核级 Root 支持。

本项目是 [KernelSU-AVD](https://github.com/HChenX/KernelSU-AVD)（作者 HChenX）的分支，将 Root 方案切换为 KernelSU Next，并延续了 `rootAVD` 的设计思路，目标适配 Android 12 (API 31) 到 Android 16/17 (API 37+) 的现代官方 AVD 镜像。

---

## 测试状态

| 模拟器版本 | 结果 |
|---|---|
| Android 16 | 可用。目前唯一完整验证通过的版本。 |
| Android 15 | 失败。报错来自 KernelSU Next 自身，仍待进一步排查。 |
| 其他版本 | 未经测试。 |

**请自行承担风险。** 目前仅在 Android 16 模拟器上验证通过。脚本在修改前会自动备份 `ramdisk.img`，使用 `restore` 即可恢复原厂镜像，因此失败的尝试是可恢复的。

---

## 项目特性

- **内核级 Root（Kernel-Level Root）**：直接利用 KernelSU Next 的 LKM（Loadable Kernel Module）机制与 GKI（通用内核镜像）无缝协作，运行在内核空间。
- **全面适配 16KB Page Size**：原生兼容 Android 15、Android 16 及更高版本的 16KB 内存页面大小（Page Size）系统镜像，彻底解决旧版 Root 工具在 16KB 模拟器上闪退、内存对齐报错（`mprotect failed`）等兼容性顽疾。
- **无多余历史包袱**：核心修补基于 `ksud boot-patch --ramdisk` 独立完成，无需复杂的 ash 脚本、不需要伪造 boot 镜像，也不依赖遗留的 busybox hacks。
- **纯净的权限隔离机制**：默认情况下所有应用（包括 shell）均不具备 Root 权限，安全可控，全部由 KernelSU Next 管理器界面按需授权。
- **全平台支持**：提供专属的 Windows 批处理脚本（`ksuAVD.bat`）以及 Linux / macOS Shell 脚本（`ksuAVD.sh`）。
- **非破坏性与一键还原**：修补前自动创建 `.backup` 备份文件，支持随时一键 `restore` 恢复出厂状态。

---

## 前置环境要求

1. **Android Studio 虚拟设备（AVD）**：
   - 目标模拟器需搭载 GKI 内核（如 `android12-5.10`、`android13-5.15`、`android14-6.1`、`android15-6.6`、`android16-6.12` 或更新版本）。
   - 系统架构：`x86_64` 或 `arm64-v8a`。
2. **Android SDK Platform-Tools（`adb`）**：
   - 请确保 `adb` 位于系统的环境变量 `PATH` 中，或者安装在标准 SDK 目录（Windows 下默认 `%LOCALAPPDATA%\Android\Sdk`，Linux/macOS 下默认 `~/Android/Sdk`）。
3. **已启动的模拟器**：
   - 在运行脚本前，必须先在 Android Studio 中启动目标 AVD，并在终端使用 `adb devices` 确认设备已成功连接识别。

---

## 目录结构

```text
KernelSU-Next-AVD/
├── ksuAVD.bat        # Windows 启动脚本
├── ksuAVD.sh         # Linux / macOS / 模拟器内部执行脚本
├── Apps/             # 应用放置目录（若缺少 KernelSU.apk 脚本将自动从官方下载）
│   └── .gitkeep
├── LICENSE           # GPL-3.0 开源许可证
├── README.md         # 英文说明文档
└── README_CN.md      # 中文说明文档
```

---

## 使用指南

### 1. 查看帮助与自动检测的系统镜像

在模拟器开机状态下，直接不带参数运行脚本。脚本会自动获取当前在线模拟器的架构、系统版本、内核版本，并自动检索本机已下载的系统镜像，生成可直接复制运行的命令：

**Windows**:
```cmd
ksuAVD.bat
```

**Linux / macOS**:
```bash
chmod +x ksuAVD.sh
./ksuAVD.sh
```

终端输出示例：
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

### 2. 修补 AVD 镜像并注入 KernelSU Next

复制上一步列表中生成的命令，或者直接传入目标 `ramdisk.img` 的路径（支持相对于 SDK 的相对路径或绝对路径）：

**Windows 示例**:
```cmd
ksuAVD.bat "system-images\android-37.2\google_apis_playstore_ps16k\x86_64\ramdisk.img"
```

或者直接指定特定 AVD 实例目录中的 ramdisk.img：
```cmd
ksuAVD.bat "D:\Android\AVD\Pixel_10_Pro.avd\ramdisk.img"
```

**Linux / macOS 示例**:
```bash
./ksuAVD.sh "system-images/android-34/google_apis/x86_64/ramdisk.img"
```

可追加的可选参数：

- `restore`：还原备份的 ramdisk（见第 5 节）。
- `DEBUG`：保留模拟器上 `/data/local/tmp/ksuAVD` 内的临时工作文件。
- `spoofed`：使用伪装包名（spoofed）版本的管理器 APK。
- `ci=<run>`：使用上游 CI 构建的管理器 APK，无需等待正式发布。
- `apk=<path>`：使用你自己提供的管理器 APK，路径与文件名均不限。

后两项的详细说明见[选择管理器 APK](#选择管理器-apk)。

#### 修补过程背后的逻辑：
1. 脚本将原始 `ramdisk.img` 与 `KernelSU.apk` 推送至模拟器的 `/data/local/tmp/ksuAVD/` 临时目录。
2. 提取对应架构的 `ksud` 原生二进制文件。
3. 自动探测当前 AVD 内核的 KMI 标识（例如 `android16-6.12`）。
4. 调用 `ksud boot-patch --ramdisk --kmi <KMI> --allow-shell`，自动完成解包、内核模块注入至 `/lib/modules`、劫持 `init` 并挂载 `ksuinit`，重新打包为 `ramdiskpatched4AVD.img`。
5. 脚本将宿主机原文件自动备份为 `ramdisk.img.backup`。
6. 将修补后的镜像拉回宿主机并替换原始 `ramdisk.img`。
7. 通过 ADB 自动安装 KernelSU Next 管理器应用。
8. 清理模拟器上的临时文件。

---

### 选择管理器 APK

默认情况下，脚本会在 `Apps/` 目录或脚本同级目录中查找 `KernelSU.apk`，两者都没有时
再从 GitHub 下载最新的 KernelSU Next 正式版。以下两个参数可以覆盖该行为。

**使用上游 CI 构建版本（尚未正式发布）。** 在
[Actions 页面](https://github.com/KernelSU-Next/KernelSU-Next/actions)
找到目标运行记录，传入其 run id 或完整 URL：

```bash
./ksuAVD.sh "path/to/ramdisk.img" ci=38912876962
./ksuAVD.sh "path/to/ramdisk.img" ci=https://github.com/KernelSU-Next/KernelSU-Next/actions/runs/38912876962
```

追加 `spoofed` 即可取用同一次运行中的伪装包名版本：

```bash
./ksuAVD.sh "path/to/ramdisk.img" ci=38912876962 spoofed
```

只有 **Build Manager CI** 工作流会产出管理器 APK，对应产物名为 `manager` 与
`manager-spoofed`。该仓库中大量成功的运行只构建 `ksud`、`ksuinit` 或 LKM 模块，
并不包含任何 APK；此外 GitHub 会在运行结束 90 天后删除产物。若目标产物不存在，
脚本会直接给出提示并附上该运行的链接，而不会让修补过程失败。

下载时优先使用已登录的 `gh` CLI，如不可用则回退到
[nightly.link](https://nightly.link)，它无需 token 即可镜像公开仓库的产物。
APK 会缓存为 `Apps/KernelSU-ci-<run-id>.apk`（伪装包名版本为
`Apps/KernelSU-ci-<run-id>-spoofed.apk`），再次传入同一 run id 不会重复下载。

**使用自备 APK。** 路径与文件名均不限，也可以是你自行编译的管理器：

```bash
./ksuAVD.sh "path/to/ramdisk.img" apk=/home/me/builds/my-kernelsu-next.apk
```

优先级为：`apk=` 高于 `ci=`，`ci=` 高于目录中的现成文件，最后才是最新正式版。
`apk=` 与 `ci=` 不能同时使用。无论来自哪个来源，只要 APK 中不含
`lib/<abi>/libksud.so`，脚本都会在向模拟器推送任何文件之前直接报错退出，
因为 `ksud` 正是从该文件中提取的。

---

### 3. 重启生效（冷启动 Cold Boot）

修补完成后，需要进行一次冷启动使新 ramdisk 生效：
1. **彻底关闭** 当前正在运行的模拟器实例。
2. 在 Android Studio 的 **Device Manager（设备管理器）** 中，找到该模拟器，点击右侧操作菜单，选择 **"Cold Boot Now"（立即冷启动）**。
   *(或者在命令行中使用参数 `emulator -avd <模拟器名称> -no-snapshot-load` 启动)*
3. 进入模拟器主界面，点击打开 **KernelSU Next** 图标。
4. 界面中央将正确显示 **“工作状态：正常 (LKM 模式)”**。

---

### 4. 开启 Shell 与应用的 Root 授权

KernelSU Next 遵循严格的最小权限原则，未明确授权的应用以及 adb shell 默认不具备 root 权限。

为 `adb shell` 开启 root 权限的步骤：
1. 在模拟器中打开 **KernelSU Next** 应用。
2. 点击底部导航栏的 **“超级用户”**（Superuser）。
3. 点击右上角菜单，勾选 **“显示系统应用”**（Show system apps）。
4. 在列表中找到 **Shell**（包名 `com.android.shell`），将开关切换为 **开启授权**。
5. 在宿主机终端执行 `adb shell su`，即可直接获得真实的 `uid=0(root)` 身份！

---

### 5. 还原原始镜像（恢复原厂）

如果你希望将模拟器恢复至未修改的原版状态：

**Windows**:
```cmd
ksuAVD.bat restore "path\to\ramdisk.img"
```

**Linux / macOS**:
```bash
./ksuAVD.sh restore "path/to/ramdisk.img"
```

---

### 6. 批量安装其他应用

如果需要向已 root 的 AVD 安装其他调试工具或应用，只需将 `.apk` 文件放进 `Apps/` 目录，然后运行：

**Windows**:
```cmd
ksuAVD.bat InstallApps
```

**Linux / macOS**:
```bash
./ksuAVD.sh InstallApps
```

---

## 技术原理对比

### 为什么在现代 AVD 上推荐使用 KernelSU Next？
在 Android 14 及以上版本的现代官方模拟器上，传统的修补方案常遇到瓶颈：
1. **16KB 内存分页（Page Size）**：从 Android 15 起，Google 大力推进 16KB Page Size，并在许多官方模拟器镜像中默认启用。旧时代编译的 Root 相关二进制文件（往往仅兼容 4KB 页面对齐）在 16KB 系统上加载时会直接遭遇内存映射异常（`mprotect failed: Invalid argument`）而崩溃。KernelSU Next 及其底层组件 `ksud` 全面原生兼容 16KB 与 4KB 页面。
2. **GKI 原生内核集成**：Android 12+ AVD 运行的是与真实真机统一的 Google GKI 内核。KernelSU Next 直接以驱动内核模块（`.ko`）的形式嵌入，无需修改内核源码镜像（kernel-ranchu），运行高效、隐蔽、稳定。

---

## 致敬与致谢（Credits）

本项目基于开源社区多位开发者的优秀工作成果构建，特此致以由衷的感谢：

- **[KernelSU-AVD](https://github.com/HChenX/KernelSU-AVD)**（作者 **HChenX**）：本项目的上游工程，AVD 检测、推送修补流程以及两个入口脚本均源自该项目。
- **[KernelSU Next](https://github.com/KernelSU-Next/KernelSU-Next)**（作者 **rifsxd** 及全体贡献者）：本项目所使用的 Root 方案，提供 LKM 模块与 `ksud` 修补核心。
- **[KernelSU](https://github.com/tiann/KernelSU)**（作者 **tiann**、**weishu** 及全体贡献者）：革命性的 Linux 内核级 Android Root 方案，KernelSU Next 即基于其构建。
- **[rootAVD](https://gitlab.com/newbit/rootAVD)**（作者 **newbit**）：AVD ramdisk 自动化修补流程的开创性项目，为本项目在 AVD 环境下的镜像检索、推送与写回机制提供了核心设计启发。
- **[Magisk](https://github.com/topjohnwu/Magisk)**（作者 **topjohnwu**）：现代 Systemless Root 理念的奠基者与灵感来源。

---

## 开源协议

本项目基于 [GNU General Public License v3.0 (GPL-3.0)](LICENSE) 协议开源。
