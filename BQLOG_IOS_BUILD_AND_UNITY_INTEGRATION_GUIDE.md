# BqLog iOS 构建与 Unity 集成指南

## 目录

1. [项目概述](#1-项目概述)
2. [构建脚本修改](#2-构建脚本修改)
3. [XCFramework 生成](#3-xcframework-生成)
4. [Universal Framework 生成](#4-universal-framework-生成)
5. [Unity 集成步骤](#5-unity-集成步骤)
6. [常见问题与解决方案](#6-常见问题与解决方案)
7. [附录](#7-附录)

---

## 1. 项目概述

BqLog 是一个高性能日志库，支持多平台构建。本指南详细说明如何在 iOS 平台构建通用框架，并集成到 Unity 项目中。

**项目结构：**
```
BqLog/
├── src/                    # 源码目录
├── include/                # 头文件目录
├── build/lib/ios/          # iOS 构建脚本
│   ├── build_all_and_pack.sh    # 主构建脚本
│   ├── proj_generate.sh         # Xcode 项目生成脚本
│   └── ios.toolchain.cmake      # iOS CMake 工具链
└── artifacts/              # 构建产物目录
```

---

## 2. 构建脚本修改

### 2.1 build_all_and_pack.sh

**修改内容：**
- 添加 `SIMULATOR64` 平台到构建目标（用于生成 x86_64 模拟器架构）
- 添加 Universal Framework 生成阶段
- 添加架构验证步骤

**关键代码：**

```bash
TARGET_PLATFORMS=(OS64 SIMULATOR64 SIMULATOR64COMBINED TVOS VISIONOS WATCHOS)
```

**Universal Framework 生成逻辑：**
1. 拷贝设备框架（OS64）作为基础
2. 使用 `lipo -create` 合并设备（arm64）和模拟器（x86_64）二进制文件
3. 使用 `lipo -info` 和 `file` 命令验证架构

### 2.2 proj_generate.sh

**修改内容：**
- 添加平台参数支持，允许指定构建平台
- 默认平台为 `OS64`

**使用方式：**
```bash
./proj_generate.sh              # 默认构建设备版本
./proj_generate.sh SIMULATOR64   # 构建模拟器版本
```

---

## 3. XCFramework 生成

### 3.1 XCFramework 格式说明

XCFramework 是 Apple 官方推荐的多平台框架格式，支持：
- iOS 设备（arm64）
- iOS 模拟器（x86_64, arm64）
- tvOS、visionOS、watchOS 等

### 3.2 生成命令

构建脚本使用 `xcodebuild -create-xcframework` 命令生成：

```bash
xcodebuild -create-xcframework \
    -framework <设备框架路径> \
    -framework <模拟器框架路径> \
    -framework <其他平台框架路径> \
    -output <输出路径>
```

### 3.3 输出结构

```
BqLog.xcframework/
├── ios-arm64/
│   └── BqLog.framework/
├── ios-x86_64-simulator/
│   └── BqLog.framework/
├── ios-arm64_x86_64-simulator/
│   └── BqLog.framework/
├── tvos-arm64/
│   └── BqLog.framework/
└── Info.plist
```

---

## 4. Universal Framework 生成

### 4.1 架构说明

| 平台 | 架构 | 用途 |
|------|------|------|
| iOS 设备 | arm64 | 物理设备运行 |
| iOS 模拟器（Intel） | x86_64 | Intel Mac 上的模拟器 |
| iOS 模拟器（Apple Silicon） | arm64 | Apple Silicon Mac 上的模拟器 |

### 4.2 生成流程

1. **构建设备版本**：`PLATFORM=OS64`，产物为 arm64
2. **构建模拟器版本**：`PLATFORM=SIMULATOR64`，产物为 x86_64
3. **合并二进制**：使用 `lipo -create` 合并两个架构

### 4.3 验证命令

```bash
# 查看架构信息
lipo -info BqLog-universal.framework/BqLog

# 输出示例：
# Architectures in the fat file: BqLog are: x86_64 arm64
```

---

## 5. Unity 集成步骤

### 5.1 文件拷贝

| 文件 | 源路径 | Unity 目标路径 |
|------|--------|---------------|
| BqLog.xcframework | `install/dynamic_lib/lib/Release/BqLog.xcframework` | `Assets/Plugins/iOS/BqLog.xcframework` |
| 头文件 | `install/dynamic_lib/include/` | `Assets/Plugins/iOS/BqLog/Headers/` |

### 5.2 Unity Player Settings 配置

1. **打开 Player Settings**：`Edit → Project Settings → Player`
2. **切换到 iOS 平台**
3. **Other Settings**：
   - **Scripting Backend**：IL2CPP（iOS 默认）
   - **Architecture**：ARM64
   - **Minimum iOS Version**：12.0+

### 5.3 Linker Flags 配置

**方法一：通过 Player Settings UI**

在 `Other Settings → Configuration → Additional linker flags` 中添加：
```
-framework Security -framework UIKit
```

**方法二：通过 PostProcessBuild 脚本**

创建 `Assets/Editor/iOS/FixUnityFrameworkEmbed.cs`：

```csharp
#if UNITY_EDITOR && UNITY_IOS
using UnityEditor;
using UnityEditor.Callbacks;
using UnityEditor.iOS.Xcode;
using System.IO;

public static class FixUnityFrameworkEmbed
{
    [PostProcessBuild(999)]
    public static void OnPostProcessBuild(BuildTarget target, string path)
    {
        if (target != BuildTarget.iOS) return;
        
        // 设置 Linker Flags
        string projPath = PBXProject.GetPBXProjectPath(path);
        PBXProject project = new PBXProject();
        project.ReadFromFile(projPath);
        
        string mainGuid = project.GetUnityMainTargetGuid();
        string frameworkGuid = project.GetUnityFrameworkTargetGuid();
        
        // 添加系统框架依赖
        project.AddBuildProperty(mainGuid, "OTHER_LDFLAGS", "-framework Security");
        project.AddBuildProperty(mainGuid, "OTHER_LDFLAGS", "-framework UIKit");
        project.AddBuildProperty(frameworkGuid, "OTHER_LDFLAGS", "-framework Security");
        project.AddBuildProperty(frameworkGuid, "OTHER_LDFLAGS", "-framework UIKit");
        
        // 添加头文件搜索路径
        string bqLogHeadersPath = "$(SRCROOT)/Libraries/Plugins/iOS/BqLog/Headers";
        project.AddBuildProperty(mainGuid, "HEADER_SEARCH_PATHS", bqLogHeadersPath);
        project.AddBuildProperty(frameworkGuid, "HEADER_SEARCH_PATHS", bqLogHeadersPath);
        
        project.WriteToFile(projPath);
    }
}
#endif
```

### 5.4 C# 包装层示例

创建 `Assets/Plugins/BqLog/BqLog.cs`：

```csharp
using UnityEngine;
using System.Runtime.InteropServices;

public static class BqLog
{
    [DllImport("__Internal")]
    private static extern void bq_log_init();
    
    [DllImport("__Internal")]
    private static extern void bq_log_write(int level, string tag, string message);
    
    public static void Init()
    {
        #if UNITY_IOS && !UNITY_EDITOR
        bq_log_init();
        #endif
    }
    
    public static void Write(int level, string tag, string message)
    {
        #if UNITY_IOS && !UNITY_EDITOR
        bq_log_write(level, tag, message);
        #endif
    }
}
```

---

## 6. 常见问题与解决方案

### 6.1 install_name_tool 找不到

**错误信息：**
```
CMake Error at /opt/homebrew/share/cmake/Modules/CMakeFindBinUtils.cmake:273:
  Could not find install_name_tool, please check your installation.
```

**原因：**
- `xcode-select` 指向了纯 Command Line Tools，缺少 iOS SDK 和完整的 Xcode 工具链

**解决方案：**
```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

**验证：**
```bash
xcode-select --print-path
# 输出: /Applications/Xcode.app/Contents/Developer

xcodebuild -version
# 显示 Xcode 版本信息
```

### 6.2 string_impl.h 文件找不到

**错误信息：**
```
fatal error: 'bq_common/types/string_impl.h' file not found
```

**原因：**
- Unity 没有将 `BqLog/Headers/` 添加到 `HEADER_SEARCH_PATHS`
- 头文件使用相对路径引用，编译器无法解析

**解决方案：**
在 PostProcessBuild 脚本中添加头文件搜索路径：

```csharp
string bqLogHeadersPath = "$(SRCROOT)/Libraries/Plugins/iOS/BqLog/Headers";
project.AddBuildProperty(mainGuid, "HEADER_SEARCH_PATHS", bqLogHeadersPath);
project.AddBuildProperty(frameworkGuid, "HEADER_SEARCH_PATHS", bqLogHeadersPath);
```

### 6.3 Linker Flags 未生效

**错误信息：**
```
Undefined symbols for architecture arm64:
  "_SecItemCopyMatching", referenced from:
      ...
```

**原因：**
- 缺少 Security 或 UIKit 系统框架链接

**解决方案：**
添加 Linker Flags：
```csharp
project.AddBuildProperty(mainGuid, "OTHER_LDFLAGS", "-framework Security");
project.AddBuildProperty(mainGuid, "OTHER_LDFLAGS", "-framework UIKit");
```

### 6.4 XCFramework 未生成

**原因：**
- 构建脚本未完成执行
- 缺少某个平台的构建产物

**解决方案：**
重新运行构建脚本：
```bash
cd build/lib/ios
rm -rf XCodeProj artifacts install pack
./build_all_and_pack.sh
```

---

## 7. 附录

### 7.1 构建脚本参数说明

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `PLATFORM` | 目标平台 | OS64 |
| `DEPLOYMENT_TARGET` | iOS 最低版本 | 9.0 |
| `BUILD_LIB_TYPE` | 库类型 | dynamic_lib |
| `APPLE_LIB_FORMAT` | 输出格式 | framework |

### 7.2 支持的平台

| 平台 | 架构 | 说明 |
|------|------|------|
| OS64 | arm64 | iOS 设备 |
| SIMULATOR64 | x86_64 | iOS 模拟器（Intel） |
| SIMULATOR64COMBINED | x86_64, arm64 | iOS 模拟器（通用） |
| TVOS | arm64 | tvOS 设备 |
| SIMULATORARM64_TVOS | arm64 | tvOS 模拟器 |
| VISIONOS | arm64 | visionOS 设备 |
| SIMULATOR_VISIONOS | arm64 | visionOS 模拟器 |
| WATCHOS | armv7k, arm64_32 | watchOS 设备 |
| SIMULATOR_WATCHOSCOMBINED | x86_64, arm64 | watchOS 模拟器 |

### 7.3 构建配置

| 配置 | 说明 |
|------|------|
| Debug | 完整调试信息，无优化 |
| Release | 优化编译，无调试信息 |
| MinSizeRel | 最小体积优化 |
| RelWithDebInfo | 优化编译，带调试信息 |

### 7.4 工具版本要求

| 工具 | 最低版本 |
|------|----------|
| Xcode | 12.0+ |
| CMake | 3.14+ |
| Unity | 2020.3+ |

---

**文档版本**: 1.0  
**创建日期**: 2026-07-21  
**适用项目**: BqLog iOS 构建与 Unity 集成