<#
.SYNOPSIS
    Windows PowerShell script to build BqLog Android .so libraries via CMake + Ninja with Android NDK.
    Builds for ARM64 (arm64-v8a) and armeabi-v7a.

.DESCRIPTION
    Usage (all parameters optional; missing ones will be prompted):
        .\win_build_all.ps1 all  [java] [node] [python] [dynamic_lib|static_lib|both]
        .\win_build_all.ps1 build [java] [node] [python] [dynamic_lib|static_lib|both]
        .\win_build_all.ps1 pack
        .\win_build_all.ps1 inspect   (inspect exported symbols of existing .so files)

    Normalized values:
        java,node,python : ON | OFF
        lib type          : static_lib | dynamic_lib
        all lib type      : dynamic_lib | static_lib | both  (default: both)
#>

param(
    [string]$Action = "all",
    [string]$Arg1 = "",  # java
    [string]$Arg2 = "",  # node
    [string]$Arg3 = "",  # python
    [string]$Arg4 = ""   # build_lib_type
)

$ErrorActionPreference = "Stop"

$BUILD_JOBS = if ($env:BUILD_JOBS) { $env:BUILD_JOBS } else { "10" }

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$REPO_ROOT = Resolve-Path "$SCRIPT_DIR\..\..\.."
$SRC_DIR = "$REPO_ROOT\src"
$PACK_DIR = "$REPO_ROOT\pack"

# $BuildConfigs = @("Debug", "MinSizeRel", "RelWithDebInfo", "Release")
$BuildConfigs = @("Release")

# Android ABIs to build
$ANDROID_ABIS = @("arm64-v8a", "armeabi-v7a")
$ANDROID_PLATFORM = "android-21"

$JAVA_SUPPORT = ""
$NODE_API_SUPPORT = ""
$PYTHON_SUPPORT = ""
$BUILD_LIB_TYPE = ""
$BUILD_LIB_TYPE_ALL = ""

# ============================================================
# Helper Functions
# ============================================================

function Normalize-OnOff {
    param([string]$Val)
    switch -Regex ($Val.ToLower()) {
        "^(on|yes|y|1|true)$"  { return "ON" }
        "^(off|no|n|0|false)$" { return "OFF" }
        default                 { return "" }
    }
}

function Normalize-BuildLibType {
    param([string]$Val)
    switch ($Val.ToLower()) {
        "static_lib"  { return "static_lib" }
        "dynamic_lib" { return "dynamic_lib" }
        "both"        { return "both" }
        default       { return "" }
    }
}

function Ask-YesNo {
    param([string]$Prompt)
    while ($true) {
        $c = Read-Host "$Prompt (Y/N)"
        switch ($c.ToUpper()) {
            "Y" { return "ON" }
            "N" { return "OFF" }
        }
    }
}

function Ask-BuildLibType {
    Write-Host ""
    Write-Host "Select library type:"
    Write-Host "  [S] static_lib"
    Write-Host "  [D] dynamic_lib"
    while ($true) {
        $c = Read-Host "Enter choice (S/D)"
        switch ($c.ToUpper()) {
            "S" { $script:BUILD_LIB_TYPE = "static_lib"; return }
            "D" { $script:BUILD_LIB_TYPE = "dynamic_lib"; return }
            default { Write-Host "Invalid choice. Please enter S or D." }
        }
    }
}

function Ensure-CommonParams {
    if (-not $JAVA_SUPPORT) {
        $script:JAVA_SUPPORT = Ask-YesNo "Enable Java/JNI support?"
    }
    if (-not $NODE_API_SUPPORT) {
        $script:NODE_API_SUPPORT = Ask-YesNo "Enable Node-API (Node.js) support?"
    }
    if (-not $PYTHON_SUPPORT) {
        $script:PYTHON_SUPPORT = Ask-YesNo "Enable Python (CPython C Extension) support?"
    }
}

function Find-AndroidNDK {
    if ($env:ANDROID_NDK) {
        $ndk = $env:ANDROID_NDK
        if (Test-Path "$ndk\build\cmake\android.toolchain.cmake") {
            return $ndk
        }
    }
    if ($env:ANDROID_SDK_ROOT) {
        $sdk = $env:ANDROID_SDK_ROOT
        $ndkDir = "$sdk\ndk"
        if (Test-Path $ndkDir) {
            $versions = Get-ChildItem -Path $ndkDir -Directory | Sort-Object Name -Descending
            foreach ($v in $versions) {
                $candidate = $v.FullName
                if (Test-Path "$candidate\build\cmake\android.toolchain.cmake") {
                    return $candidate
                }
            }
        }
    }
    if ($env:ANDROID_HOME) {
        $sdk = $env:ANDROID_HOME
        $ndkDir = "$sdk\ndk"
        if (Test-Path $ndkDir) {
            $versions = Get-ChildItem -Path $ndkDir -Directory | Sort-Object Name -Descending
            foreach ($v in $versions) {
                $candidate = $v.FullName
                if (Test-Path "$candidate\build\cmake\android.toolchain.cmake") {
                    return $candidate
                }
            }
        }
    }
    return $null
}

function Find-Ninja {
    if ($env:CMAKE_MAKE_PROGRAM) {
        $ninja = $env:CMAKE_MAKE_PROGRAM
        if (Test-Path $ninja) {
            return $ninja
        }
    }
    if ($env:ANDROID_SDK_ROOT) {
        $sdk = $env:ANDROID_SDK_ROOT
        $cmakeDir = "$sdk\cmake"
        if (Test-Path $cmakeDir) {
            $versions = Get-ChildItem -Path $cmakeDir -Directory | Sort-Object Name -Descending
            foreach ($v in $versions) {
                $candidate = "$($v.FullName)\bin\ninja.exe"
                if (Test-Path $candidate) {
                    return $candidate
                }
            }
        }
    }
    if ($env:ANDROID_HOME) {
        $sdk = $env:ANDROID_HOME
        $cmakeDir = "$sdk\cmake"
        if (Test-Path $cmakeDir) {
            $versions = Get-ChildItem -Path $cmakeDir -Directory | Sort-Object Name -Descending
            foreach ($v in $versions) {
                $candidate = "$($v.FullName)\bin\ninja.exe"
                if (Test-Path $candidate) {
                    return $candidate
                }
            }
        }
    }
    $whichNinja = Get-Command ninja -ErrorAction SilentlyContinue
    if ($whichNinja) {
        return $whichNinja.Source
    }
    return $null
}

function Find-CMake {
    if ($env:CMAKE_PATH) {
        $cmake = "$env:CMAKE_PATH\bin\cmake.exe"
        if (Test-Path $cmake) {
            return $cmake
        }
    }
    if ($env:ANDROID_SDK_ROOT) {
        $sdk = $env:ANDROID_SDK_ROOT
        $cmakeDir = "$sdk\cmake"
        if (Test-Path $cmakeDir) {
            $versions = Get-ChildItem -Path $cmakeDir -Directory | Sort-Object Name -Descending
            foreach ($v in $versions) {
                $candidate = "$($v.FullName)\bin\cmake.exe"
                if (Test-Path $candidate) {
                    return $candidate
                }
            }
        }
    }
    if ($env:ANDROID_HOME) {
        $sdk = $env:ANDROID_HOME
        $cmakeDir = "$sdk\cmake"
        if (Test-Path $cmakeDir) {
            $versions = Get-ChildItem -Path $cmakeDir -Directory | Sort-Object Name -Descending
            foreach ($v in $versions) {
                $candidate = "$($v.FullName)\bin\cmake.exe"
                if (Test-Path $candidate) {
                    return $candidate
                }
            }
        }
    }
    $whichCmake = Get-Command cmake -ErrorAction SilentlyContinue
    if ($whichCmake) {
        return $whichCmake.Source
    }
    return $null
}

# ============================================================
# Build Function
# ============================================================

function Build-OnePair {
    param(
        [string]$BuildLibType,
        [string]$Abi
    )

    $projDir = "$SCRIPT_DIR\proj_${BuildLibType}_${Abi}"

    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $projDir
    New-Item -ItemType Directory -Force -Path $projDir | Out-Null

    Push-Location $projDir

    try {
        Write-Host ""
        Write-Host "===== Build Configuration ====="
        Write-Host "  TARGET_PLATFORM   : android"
        Write-Host "  ANDROID_ABI       : $Abi"
        Write-Host "  BUILD_LIB_TYPE    : $BuildLibType"
        Write-Host "  JAVA_SUPPORT      : $JAVA_SUPPORT"
        Write-Host "  NODE_API_SUPPORT  : $NODE_API_SUPPORT"
        Write-Host "  PYTHON_SUPPORT    : $PYTHON_SUPPORT"
        Write-Host "  ANDROID_NDK       : $ANDROID_NDK"
        Write-Host "  NINJA             : $NINJA_PATH"
        Write-Host "  CMAKE             : $CMAKE_PATH"
        Write-Host "================================="
        Write-Host ""

        foreach ($cfg in $BuildConfigs) {
            Write-Host "  BUILD FOR CONFIG ${BuildLibType} / ${Abi} : ${cfg}"

            $cfgDir = "build_${cfg}"
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $cfgDir
            New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null

            Push-Location $cfgDir

            try {
                $cmakeArgs = @(
                    $SRC_DIR,
                    "-G", "Ninja",
                    "-DTARGET_PLATFORM:STRING=android",
                    "-DBUILD_LIB_TYPE:STRING=$BuildLibType",
                    "-DJAVA_SUPPORT:BOOL=$JAVA_SUPPORT",
                    "-DJNI_SUPPORT:BOOL=$JNI_SUPPORT",
                    "-DNODE_API_SUPPORT:BOOL=$NODE_API_SUPPORT",
                    "-DPYTHON_SUPPORT:BOOL=$PYTHON_SUPPORT",
                    "-DCMAKE_BUILD_TYPE=$cfg",
                    "-DCMAKE_SYSTEM_NAME=Android",
                    "-DCMAKE_SYSTEM_VERSION=21",
                    "-DANDROID_PLATFORM=$ANDROID_PLATFORM",
                    "-DANDROID_ABI=$Abi",
                    "-DCMAKE_ANDROID_ARCH_ABI=$Abi",
                    "-DANDROID_NDK=$ANDROID_NDK",
                    "-DCMAKE_ANDROID_NDK=$ANDROID_NDK",
                    "-DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK\build\cmake\android.toolchain.cmake",
                    "-DCMAKE_MAKE_PROGRAM=$NINJA_PATH",
                    "-DANDROID_STL=none",
                    "-DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON",
                    "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON",
                    "-DCMAKE_INSTALL_PREFIX=$REPO_ROOT\install"
                )

                & $CMAKE_PATH @cmakeArgs
                if ($LASTEXITCODE -ne 0) {
                    throw "CMake configuration failed for $cfg / $Abi"
                }

                & $CMAKE_PATH --build . --parallel $BUILD_JOBS
                if ($LASTEXITCODE -ne 0) {
                    throw "CMake build failed for $cfg / $Abi"
                }

                & $CMAKE_PATH --install .
                if ($LASTEXITCODE -ne 0) {
                    throw "CMake install failed for $cfg / $Abi"
                }
            }
            finally {
                Pop-Location
            }
        }
    }
    finally {
        Pop-Location
    }
}

function Build-AllCombos {
    foreach ($abi in $ANDROID_ABIS) {
        if ($BUILD_LIB_TYPE_ALL -eq "dynamic_lib") {
            Build-OnePair "dynamic_lib" $abi
        }
        elseif ($BUILD_LIB_TYPE_ALL -eq "static_lib") {
            Build-OnePair "static_lib" $abi
        }
        else {
            Build-OnePair "dynamic_lib" $abi
            Build-OnePair "static_lib" $abi
        }
    }
}

function Do-Pack {
    Write-Host ""
    Write-Host "===== Packaging ====="
    Write-Host "  TARGET_PLATFORM   : android"
    Write-Host "  PACKAGE_NAME      : bqlog-lib"
    Write-Host "================================="
    Write-Host ""

    $workDir = "$SCRIPT_DIR\pack"
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $workDir
    New-Item -ItemType Directory -Force -Path $workDir | Out-Null

    Push-Location $workDir

    try {
        $cmakeArgs = @(
            $PACK_DIR,
            "-G", "Ninja",
            "-DTARGET_PLATFORM:STRING=android",
            "-DPACKAGE_NAME:STRING=bqlog-lib",
            "-DCMAKE_MAKE_PROGRAM=$NINJA_PATH"
        )

        & $CMAKE_PATH @cmakeArgs
        if ($LASTEXITCODE -ne 0) {
            throw "CMake pack configuration failed"
        }

        & $CMAKE_PATH --build . --target package --parallel $BUILD_JOBS
        if ($LASTEXITCODE -ne 0) {
            throw "CMake pack build failed"
        }
    }
    finally {
        Pop-Location
    }
}

# ============================================================
# Inspect .so Exported Symbols
# ============================================================

function Find-NDK-Binutils {
    # Modern NDK (r22+) ships only LLVM binutils: llvm-nm.exe / llvm-objdump.exe.
    # Older NDKs may provide nm.exe / objdump.exe (GCC-style prefixes). Support both.
    $llvmDir = "$ANDROID_NDK\toolchains\llvm\prebuilt"
    if (Test-Path $llvmDir) {
        $hostDir = Get-ChildItem -Path $llvmDir -Directory | Sort-Object Name -Descending | Select-Object -First 1
        if ($hostDir) {
            $bin = "$($hostDir.FullName)\bin"
            if ((Test-Path "$bin\llvm-nm.exe") -or (Test-Path "$bin\nm.exe")) {
                return $bin
            }
        }
    }
    return $null
}

function Inspect-SoSymbols {
    Write-Host ""
    Write-Host "===== Inspect .so Exported Symbols ====="
    Write-Host "========================================"
    Write-Host ""

    $binutils = Find-NDK-Binutils
    if (-not $binutils) {
        Write-Warning "Could not locate NDK binutils (llvm-nm/llvm-objdump). Skipping symbol inspection."
        return
    }

    # Use LLVM binutils if present (modern NDK), otherwise fall back to nm/objdump (older NDK).
    $nmTool = if (Test-Path "$binutils\llvm-nm.exe") { "llvm-nm.exe" } else { "nm.exe" }
    $objdumpTool = if (Test-Path "$binutils\llvm-objdump.exe") { "llvm-objdump.exe" } else { "objdump.exe" }

    # Locate built dynamic libraries under install (or artifacts)
    $searchRoots = @(
        "$REPO_ROOT\install",
        "$REPO_ROOT\artifacts"
    )

    $foundAny = $false
    foreach ($root in $searchRoots) {
        if (-not (Test-Path $root)) { continue }

        $soFiles = Get-ChildItem -Path $root -Recurse -Filter "*.so" -File
        foreach ($so in $soFiles) {
            $foundAny = $true
            Write-Host "--------------------------------------------------------"
            Write-Host "  File: $($so.FullName)"
            Write-Host "  ABI : $($so.Directory.Parent.Name)"
            Write-Host "--------------------------------------------------------"

            # 'nm -D --defined-only' lists dynamic (exported) symbols defined in the .so
            Write-Host "--- Exported (defined) dynamic symbols ($nmTool -D --defined-only) ---"
            & "$binutils\$nmTool" -D --defined-only $so.FullName
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "$nmTool failed on $($so.FullName)"
            }

            Write-Host ""
            Write-Host "--- Exported symbols via $objdumpTool -T (dynamic symbol table) ---"
            & "$binutils\$objdumpTool" -T $so.FullName
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "$objdumpTool failed on $($so.FullName)"
            }

            Write-Host ""
        }
    }

    if (-not $foundAny) {
        Write-Host "No .so files found under: $($searchRoots -join ', ')"
    }
}

# ============================================================
# Main
# ============================================================

# Parse arguments
if (-not $Action) {
    $Action = "all"
}

$JAVA_SUPPORT = Normalize-OnOff $Arg1
$NODE_API_SUPPORT = Normalize-OnOff $Arg2
$PYTHON_SUPPORT = Normalize-OnOff $Arg3
$BUILD_LIB_TYPE = Normalize-BuildLibType $Arg4

Write-Host "Parsed params:"
Write-Host "  ACTION:            $Action"
Write-Host "  JAVA_SUPPORT:      $(if ($JAVA_SUPPORT) { $JAVA_SUPPORT } else { '<unset>' })"
Write-Host "  NODE_API_SUPPORT:  $(if ($NODE_API_SUPPORT) { $NODE_API_SUPPORT } else { '<unset>' })"
Write-Host "  PYTHON_SUPPORT:    $(if ($PYTHON_SUPPORT) { $PYTHON_SUPPORT } else { '<unset>' })"
Write-Host "  BUILD_LIB_TYPE:    $(if ($BUILD_LIB_TYPE) { $BUILD_LIB_TYPE } else { '<unset>' })"

# Locate NDK
$ANDROID_NDK = Find-AndroidNDK
if (-not $ANDROID_NDK) {
    $ANDROID_NDK = Read-Host "Could not auto-detect Android NDK. Please enter the path to your NDK (e.g., E:\home\.android\sdk\ndk\26.1.10909125)"
    if (-not (Test-Path "$ANDROID_NDK\build\cmake\android.toolchain.cmake")) {
        throw "Invalid NDK path: $ANDROID_NDK (toolchain file not found)"
    }
}
Write-Host "Using Android NDK: $ANDROID_NDK"

# For 'inspect' only the NDK binutils are needed; skip Ninja/CMake detection.
if ($Action -ne "inspect") {
    # Locate Ninja
    $NINJA_PATH = Find-Ninja
    if (-not $NINJA_PATH) {
        $NINJA_PATH = Read-Host "Could not auto-detect Ninja. Please enter the full path to ninja.exe"
        if (-not (Test-Path $NINJA_PATH)) {
            throw "Invalid Ninja path: $NINJA_PATH"
        }
    }
    Write-Host "Using Ninja: $NINJA_PATH"

    # Locate CMake
    $CMAKE_PATH = Find-CMake
    if (-not $CMAKE_PATH) {
        $CMAKE_PATH = Read-Host "Could not auto-detect CMake. Please enter the full path to cmake.exe"
        if (-not (Test-Path $CMAKE_PATH)) {
            throw "Invalid CMake path: $CMAKE_PATH"
        }
    }
    Write-Host "Using CMake: $CMAKE_PATH"
}

# Clean previous artifacts (skip for 'inspect' so existing .so files are preserved)
if ($Action -ne "inspect") {
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue "$REPO_ROOT\artifacts"
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue "$REPO_ROOT\install"
}

# Dispatch action
switch ($Action) {
    "all" {
        if (-not $JAVA_SUPPORT) {
            $script:JAVA_SUPPORT = Ask-YesNo "Enable Java/JNI support?"
        }
        if (-not $NODE_API_SUPPORT) {
            $script:NODE_API_SUPPORT = Ask-YesNo "Enable Node-API (Node.js) support?"
        }
        if (-not $PYTHON_SUPPORT) {
            $script:PYTHON_SUPPORT = Ask-YesNo "Enable Python (CPython C Extension) support?"
        }

        $BUILD_LIB_TYPE_ALL = if ($BUILD_LIB_TYPE) { $BUILD_LIB_TYPE } else { "both" }
        Build-AllCombos
        Do-Pack
        Inspect-SoSymbols
        Write-Host "---------"
        Write-Host "Finished!"
        Write-Host "---------"
    }
    "build" {
        Ensure-CommonParams
        if (-not $BUILD_LIB_TYPE) {
            Ask-BuildLibType
        }

        foreach ($abi in $ANDROID_ABIS) {
            Build-OnePair $BUILD_LIB_TYPE $abi
        }
        Inspect-SoSymbols
        Write-Host "---------"
        Write-Host "Finished!"
        Write-Host "---------"
    }
    "pack" {
        Do-Pack
        Write-Host "---------"
        Write-Host "Finished!"
        Write-Host "---------"
    }
    "inspect" {
        Inspect-SoSymbols
        Write-Host "---------"
        Write-Host "Finished!"
        Write-Host "---------"
    }
    default {
        Write-Host "Unknown action: $Action"
        Write-Host "Supported: all | build | pack | inspect"
        exit 2
    }
}