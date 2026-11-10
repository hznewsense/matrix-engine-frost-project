# Quick Start

本文档描述从环境配置到生成 Android APK 的最短可执行流程，基于仓库内的两个脚本：

- [`setup.bat`](setup.bat)：检测并准备 JDK / Android SDK / NDK / Gradle wrapper
- [`build.bat`](build.bat)：调用 Gradle 组装 APK 并归位到 `Apks/`

## 0. 最简流程

在仓库根目录执行：

```bat
setup.bat
```

成功后执行：

```bat
build.bat
```

产物：

```text
Apks\MEFrost_<版本>_<git>_<variant>.apk
```

例如：

```text
Apks\MEFrost_1.0.0_7431a8c_release.apk
```

用 `adb` 直接安装运行：

```bat
adb install -r Apks\MEFrost_1.0.0_7431a8c_release.apk
adb shell am start -W -n com.ns.mefrost/com.ns.mefrost.MainActivity
```

## 1. 环境要求

| 项 | 版本 | 是否随仓库提供 |
| --- | --- | --- |
| JDK | 17+ | 否，`setup.bat` 自动检测或安装 |
| Android SDK | compileSdk 36 | 否，`setup.bat` 自动检测或安装 |
| Android Build Tools | 36.1.0 | 否，`setup.bat` 自动安装 |
| Android NDK | 29.0.14206865 | 否，`setup.bat` 自动安装 |
| Gradle | 8.4 | 是，`MEFrostJava/host/gradle/wrapper/` |
| Android Gradle Plugin | 8.3.0 | 否，Gradle 自动下载 |
| Git LFS | 任意 | 是（用于 PCK / AAR 拉取） |

本工程**不编译 C++、不导出 PCK**，因此不需要 Python、SCons 或 Matrix 编辑器。

### 1.1 必须先拉 LFS 对象

`frost.pck`（约 177 MB）超过 GitHub 单文件 100 MB 限制；引擎 fat AAR 也会随版本整体替换。
两者都通过 Git LFS 存储，克隆后如果只是占位符，`setup.bat` 会直接报错：

```bat
git lfs install
git lfs pull
```

| 文件 | 大小 | 存储方式 |
| --- | --- | --- |
| `MEFrostJava/app/src/main/assets/frost.pck` | 约 177 MB | Git LFS |
| `MEFrostJava/app/libs/MatrixSdk_Integrated_1.3.1.aar` | 约 22 MB | Git LFS |
| `MEFrostJava/app/src/main/jniLibs/arm64-v8a/*.so` | 约 7 MB | 普通 Git 对象 |

## 2. 配置环境

```bat
setup.bat
```

正常完成后输出：

```text
[INFO] Checking bundled Android project files...
[ OK ] Bundled AAR, frost.pck and native libraries are ready
[INFO] Checking the bundled Gradle 8.4 wrapper...
[ OK ] Gradle wrapper 8.4 ready
[INFO] Resolving JDK 17+...
[ OK ] JAVA_HOME: C:\Program Files\Microsoft\jdk-17.0.20.101-hotspot\
[INFO] Resolving Android SDK...
[ OK ] Android SDK: D:\Android\Sdk
[INFO] Checking Android SDK platform and build tools...
[ OK ] Android SDK platform and build tools are ready
[INFO] Resolving Android NDK 29.0.14206865...
[ OK ] Android NDK: D:\Android\Sdk\ndk\29.0.14206865
[ OK ] Environment setup complete.

Resolved environment:
  ANDROID_HOME     = D:\Android\Sdk
  ANDROID_SDK_ROOT = D:\Android\Sdk
  ANDROID_NDK_ROOT = D:\Android\Sdk\ndk\29.0.14206865
  JAVA_HOME        = C:\Program Files\Microsoft\jdk-17.0.20.101-hotspot\

[ OK ] You can now run: build.bat
```

可选参数：

| 参数 | 作用 |
| --- | --- |
| `--skip-jdk` | 跳过 JDK 检测（已有 `JAVA_HOME` 时可用） |
| `--skip-winget` | 禁止自动安装依赖，只做检测 |
| `--persist-env` | 用 `setx` 把解析结果写入系统环境变量 |
| `--no-pause` | 结束后不暂停，适合 CI |
| `--help` | 显示帮助 |

说明：

- 解析结果会写入仓库根目录的 `.setup-user-env.cmd`（已在 `.gitignore` 中排除），`build.bat` 会自动读取。
- 不带 `--persist-env` 时，环境变量只在当前进程内生效，不会污染系统配置。
- 找不到 SDK 时会提示手动输入路径；只有确认后才会调用 `winget` / `sdkmanager` 安装。

## 3. 构建 APK

```bat
build.bat
```

开始阶段会打印本次实际使用的工具链：

```text
[INFO] Build dependencies:
  ANDROID_SDK_ROOT  = D:\Android\Sdk
  ANDROID_NDK_ROOT  = D:\Android\Sdk\ndk\29.0.14206865
  JAVA_HOME         = C:\Program Files\Microsoft\jdk-17.0.20.101-hotspot\
  GRADLE_WRAPPER    = ...\MEFrostJava\host\gradle\wrapper\gradle-wrapper.jar
```

随后完成：

1. 通过 wrapper 执行 `:app:assembleRelease`；
2. 校验 APK 体积（原生库是否被 strip、PCK 是否打入）；
3. 复制到 `Apks/`。

最终输出：

```text
[ OK ] APK built: ...\Apks\MEFrost_1.0.0_7431a8c_release.apk (113292560 bytes)
```

命名规则：

| 字段 | 来源 |
| --- | --- |
| `MEFrost` | 产品名 |
| `1.0.0` | `build.bat` 中的 `VERSION_NAME` |
| `7431a8c` | git 短提交（无 git 时为 `unknown`） |
| `release` | 构建变体 |

默认使用 Android 调试证书签名。

### 3.1 构建参数

| 参数 | 作用 |
| --- | --- |
| （无参数） | 构建 release APK |
| `--apk` | 同上，显式指定 |
| `--clean` | 删除 Gradle 缓存与 `Apks/*.apk` 后退出 |
| `--all` | 先清理再完整构建 |
| `--clean-host` | 只删除 Gradle 构建输出与缓存 |
| `--plan` | 只打印解析出的构建计划，不执行 |
| `--no-pause` | 结束后不暂停，适合 CI |
| `--help` | 显示帮助 |

排障常用：

```bat
build.bat --plan
build.bat --clean-host
build.bat --all
```

## 4. 自定义应用身份

`MEFrostJava/app/build.gradle` 的所有构建参数都有默认值，可用 `-P` 覆盖。直接调 Gradle 时：

```bat
cd MEFrostJava\host
java -classpath gradle/wrapper/gradle-wrapper.jar org.gradle.wrapper.GradleWrapperMain ^
  -Pexport_package_name=com.example.frost ^
  -Pexport_version_name=1.2.0 ^
  -Pexport_version_code=120 ^
  :app:assembleRelease
```

| 属性 | 默认值 | 说明 |
| --- | --- | --- |
| `export_package_name` | `com.ns.mefrost` | 需与 `namespace` 一致，否则 AAR 内服务找不到 |
| `export_version_name` | `1.0.0` | 版本名 |
| `export_version_code` | `1` | Android 版本号（int） |
| `export_compile_sdk` | `36` | 编译 SDK |
| `export_min_sdk` | `30` | 最低支持版本 |
| `export_target_sdk` | `36` | 目标 SDK |
| `export_ndk_version` | `29.0.14206865` | 必须固定，否则 AGP 静默跳过 strip |
| `export_enabled_abis` | `arm64-v8a` | 只支持 arm64，其它值会抛异常 |

修改 `export_package_name` 时，同时改 `MEFrostJava/app/build.gradle` 里的 `namespace`，并检查
`AndroidManifest.xml` 中 `<queries>` 声明的包名。

## 5. 用 Android Studio 打开

仓库是标准 Gradle 工程，可直接打开 `MEFrostJava/host/settings.gradle` 所在的目录：

1. Android Studio → Open → 选择 `MEFrostJava/host/` 目录；
2. 等待 Gradle 同步（会自动下载 AGP 8.3.0 与依赖）；
3. 选择 `app` 配置后直接 Run。

注意 `settings.gradle` 通过相对路径把 `../app` 注册为 `:app` 模块，因此**必须打开
`MEFrostJava/host/`**，不能直接打开仓库根目录。

## 6. 常见问题

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| `frost.pck not found` | LFS 对象未拉取 | `git lfs pull` |
| `MatrixSdk AAR not found` | LFS 对象未拉取 | `git lfs pull` |
| `Android NDK 29.0.14206865 not found` | NDK 未安装 | 运行 `setup.bat`，或 `sdkmanager "ndk;29.0.14206865"` |
| `JAVA_HOME is not set to a JDK` | 未配置 JDK | 运行 `setup.bat`，或手动设置 `JAVA_HOME` |
| APK 体积数百 MB | 原生库未被 strip | 确认 `ANDROID_NDK_ROOT` 存在后 `build.bat --clean-host` |
| APK 只有几 MB | PCK / 原生库未打入 | 检查 `MEFrostJava/app/src/main/assets/` 与 `MEFrostJava/app/src/main/jniLibs/arm64-v8a/` |
| Gradle 卡在下载 Gradle 8.4 | 网络受限 | wrapper 指向腾讯云镜像，可改 `gradle-wrapper.properties` |
| 应用启动后黑屏 | PCK 校验失败或原生库未加载 | `adb logcat \| findstr MEFrost` |
| `lintVital` 报 Kotlin 元数据版本不兼容 | 已知告警，不影响产物 | 可忽略，或升级 Gradle/AGP |

## 7. 相关文档

- [README.md](README.md)：项目定位、架构与接入说明
- [License.txt](License.txt)：Matrix Engine Demo Public License v1.0
