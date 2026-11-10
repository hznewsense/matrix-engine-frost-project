@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ============================================================
REM Matrix Engine Frost Project - Android Environment Setup
REM 只准备 Android 构建链: JDK / SDK / NDK / Gradle wrapper.
REM 本工程不编译原生扩展, 也不导出 PCK, 因此不需要 Python / SCons / 编辑器.
REM ============================================================

for /F "delims=" %%E in ('echo prompt $E^| cmd') do set "ESC=%%E"
set "COLOR_RESET=%ESC%[0m"
set "COLOR_RED=%ESC%[91m"
set "COLOR_YELLOW=%ESC%[93m"
set "COLOR_GREEN=%ESC%[92m"
set "COLOR_CYAN=%ESC%[96m"

REM ---------- Toolchain targets ----------
REM 与 MEFrostAndroid/app/build.gradle 的默认值保持一致.
set "NDK_VERSION=29.0.14206865"
set "GRADLE_VERSION=8.4"
set "ANDROID_COMPILE_SDK=36"
set "ANDROID_BUILD_TOOLS=36.1.0"

REM ---------- Paths ----------
set "REPO_ROOT=%~dp0"
if "%REPO_ROOT:~-1%"=="\" set "REPO_ROOT=%REPO_ROOT:~0,-1%"
set "USER_ENV_FILE=%REPO_ROOT%\.setup-user-env.cmd"
set "ANDROID_DIR=%REPO_ROOT%\MEFrostAndroid"
set "HOST_DIR=%ANDROID_DIR%\host"
set "APP_DIR=%ANDROID_DIR%\app"

set "SKIP_JDK=0"
set "SKIP_WINGET=0"
set "PERSIST_ENV=0"
set "NO_PAUSE=0"
set "WINGET_CMD="

if exist "%USER_ENV_FILE%" call "%USER_ENV_FILE%"

goto main

REM ---------- Entry ----------
:main
REM 预扫 --no-pause 和 --help: 参数解析在遇到它们之前就可能提前返回.
call :prescan_pause_flags %*
call :run_setup %*
set "FINAL_EXIT_CODE=%ERRORLEVEL%"
echo.
if not "%NO_PAUSE%"=="1" pause
exit /b %FINAL_EXIT_CODE%

:prescan_pause_flags
if "%~1"=="" exit /b 0
if /I "%~1"=="--no-pause" set "NO_PAUSE=1"
if /I "%~1"=="--help" set "NO_PAUSE=1"
shift
goto prescan_pause_flags

:run_setup
goto parse_args

:parse_args
if "%~1"=="" goto args_done
if /I "%~1"=="--skip-jdk" set "SKIP_JDK=1"
if /I "%~1"=="--skip-winget" set "SKIP_WINGET=1"
if /I "%~1"=="--persist-env" set "PERSIST_ENV=1"
if /I "%~1"=="--no-pause" set "NO_PAUSE=1"
if /I "%~1"=="--help" goto usage
shift
goto parse_args

:args_done
call :print_header

call :resolve_winget

call :check_project_files
if errorlevel 1 goto failed

call :check_host_gradle
if errorlevel 1 goto failed

if "%SKIP_JDK%"=="0" (
    call :resolve_java_home
    if errorlevel 1 goto failed
) else (
    call :log_info "Skipping JDK check (--skip-jdk)."
)

call :resolve_android_sdk
if errorlevel 1 goto failed

call :ensure_android_sdk_packages
if errorlevel 1 goto failed

call :resolve_android_ndk
if errorlevel 1 goto failed

if "%PERSIST_ENV%"=="1" (
    call :persist_env "ANDROID_HOME" "%ANDROID_HOME%"
    call :persist_env "ANDROID_SDK_ROOT" "%ANDROID_SDK_ROOT%"
    call :persist_env "ANDROID_NDK_ROOT" "%ANDROID_NDK_ROOT%"
    if "%SKIP_JDK%"=="0" call :persist_env "JAVA_HOME" "%JAVA_HOME%"
) else (
    call :log_info "Environment variables only apply to this setup process."
    call :log_info "Use --persist-env to write them with setx."
)
call :save_user_build_env

echo.
call :log_ok "Environment setup complete."
echo.
echo Resolved environment:
echo   ANDROID_HOME     = %ANDROID_HOME%
echo   ANDROID_SDK_ROOT = %ANDROID_SDK_ROOT%
echo   ANDROID_NDK_ROOT = %ANDROID_NDK_ROOT%
if "%SKIP_JDK%"=="0" echo   JAVA_HOME        = %JAVA_HOME%
echo.
call :log_ok "You can now run: build.bat"
exit /b 0

:usage
echo.
echo Usage:
echo   setup.bat [options]
echo.
echo Options:
echo   --skip-jdk           Skip JDK detection and persistence
echo   --skip-winget        Disable automatic winget installs
echo   --persist-env        Persist resolved environment variables with setx
echo   --no-pause           Exit immediately after finishing
echo   --help               Show help
echo.
exit /b 0

:print_header
echo ============================================================
echo Matrix Engine Frost Project - Environment Setup
echo ============================================================
echo Repository Root : %REPO_ROOT%
echo Target NDK      : %NDK_VERSION%
echo Target Gradle   : %GRADLE_VERSION%
echo Target JDK      : 17
echo Compile SDK     : %ANDROID_COMPILE_SDK%
echo Build Tools     : %ANDROID_BUILD_TOOLS%
echo ============================================================
echo.
exit /b 0

REM ---------- Bundled assets ----------
:check_project_files
call :log_info "Checking bundled Android project files..."

if not exist "%APP_DIR%\build.gradle" (
    call :log_error "Application module not found: %APP_DIR%\build.gradle"
    exit /b 1
)
if not exist "%APP_DIR%\src\main\AndroidManifest.xml" (
    call :log_error "AndroidManifest.xml not found: %APP_DIR%\src\main\AndroidManifest.xml"
    exit /b 1
)
if not exist "%APP_DIR%\libs\MatrixSdk_Integrated_*.aar" (
    call :log_error "MatrixSdk AAR not found under: %APP_DIR%\libs"
    call :log_error "Expected MatrixSdk_Integrated_<version>.aar (about 22 MB)."
    exit /b 1
)
if not exist "%APP_DIR%\src\main\assets\frost.pck" (
    call :log_error "frost.pck not found: %APP_DIR%\src\main\assets\frost.pck"
    call :log_error "It is stored with Git LFS. Restore it with: git lfs pull"
    exit /b 1
)
if not exist "%APP_DIR%\src\main\jniLibs\arm64-v8a\libMEFrost.android.template_release.arm64.so" (
    call :log_error "Native extension not found under: %APP_DIR%\src\main\jniLibs\arm64-v8a"
    exit /b 1
)
if not exist "%APP_DIR%\src\main\jniLibs\arm64-v8a\libzmq.so" (
    call :log_error "libzmq.so not found under: %APP_DIR%\src\main\jniLibs\arm64-v8a"
    exit /b 1
)
call :log_ok "Bundled AAR, frost.pck and native libraries are ready"
exit /b 0

REM ---------- Host Gradle ----------
:check_host_gradle
call :log_info "Checking the bundled Gradle %GRADLE_VERSION% wrapper..."
set "WRAPPER_JAR=%HOST_DIR%\gradle\wrapper\gradle-wrapper.jar"
set "WRAPPER_PROPS=%HOST_DIR%\gradle\wrapper\gradle-wrapper.properties"

if not exist "%WRAPPER_JAR%" (
    call :log_error "Gradle wrapper jar not found: %WRAPPER_JAR%"
    exit /b 1
)
if not exist "%WRAPPER_PROPS%" (
    call :log_error "Gradle wrapper properties not found: %WRAPPER_PROPS%"
    exit /b 1
)

set "WRAPPER_VERSION_OK="
for /f "delims=" %%L in ('findstr /i /c:"gradle-%GRADLE_VERSION%-" "%WRAPPER_PROPS%"') do set "WRAPPER_VERSION_OK=1"
if not defined WRAPPER_VERSION_OK (
    call :log_error "Bundled Gradle wrapper is not %GRADLE_VERSION%:"
    findstr /i "distributionUrl" "%WRAPPER_PROPS%"
    exit /b 1
)
call :log_ok "Gradle wrapper %GRADLE_VERSION% ready"
exit /b 0

REM ---------- Android SDK ----------
:resolve_android_sdk
call :log_info "Resolving Android SDK..."
set "SDK_CANDIDATE="

if defined ANDROID_SDK_ROOT if exist "%ANDROID_SDK_ROOT%" set "SDK_CANDIDATE=%ANDROID_SDK_ROOT%"
if not defined SDK_CANDIDATE if defined ANDROID_HOME if exist "%ANDROID_HOME%" set "SDK_CANDIDATE=%ANDROID_HOME%"
if not defined SDK_CANDIDATE if exist "%LOCALAPPDATA%\Android\Sdk" set "SDK_CANDIDATE=%LOCALAPPDATA%\Android\Sdk"
if not defined SDK_CANDIDATE call :try_set_sdk_candidate "%USERPROFILE%\AppData\Local\Android\Sdk"
if not defined SDK_CANDIDATE call :try_set_sdk_candidate "%ProgramFiles%\Android\Sdk"
if not defined SDK_CANDIDATE call :try_set_sdk_candidate "D:\Android\Sdk"
if not defined SDK_CANDIDATE call :try_set_sdk_candidate "D:\WorkTools\SDK"
if not defined SDK_CANDIDATE call :try_set_sdk_candidate "D:\SDK\Android"
if not defined SDK_CANDIDATE call :try_set_sdk_candidate "E:\Android\Sdk"

if not defined SDK_CANDIDATE (
    call :prompt_for_android_sdk
)
if not defined SDK_CANDIDATE (
    call :confirm_android_sdk_install
    if errorlevel 1 (
        call :log_error "Android SDK not found. Install it or rerun setup and provide the SDK path."
        exit /b 1
    )
    call :install_android_sdk
    if errorlevel 1 exit /b 1
    if defined ANDROID_SDK_ROOT if exist "%ANDROID_SDK_ROOT%" set "SDK_CANDIDATE=%ANDROID_SDK_ROOT%"
    if not defined SDK_CANDIDATE call :prompt_for_android_sdk
)
if not defined SDK_CANDIDATE (
    call :log_error "Android SDK still not found."
    exit /b 1
)

set "ANDROID_HOME=%SDK_CANDIDATE%"
set "ANDROID_SDK_ROOT=%SDK_CANDIDATE%"
call :log_ok "Android SDK: %ANDROID_SDK_ROOT%"
exit /b 0

:try_set_sdk_candidate
if defined SDK_CANDIDATE exit /b 0
if "%~1"=="" exit /b 0
if not exist "%~1" exit /b 0
if exist "%~1\platform-tools" set "SDK_CANDIDATE=%~1"
if not defined SDK_CANDIDATE if exist "%~1\cmdline-tools" set "SDK_CANDIDATE=%~1"
if not defined SDK_CANDIDATE if exist "%~1\build-tools" set "SDK_CANDIDATE=%~1"
if not defined SDK_CANDIDATE if exist "%~1\platforms" set "SDK_CANDIDATE=%~1"
exit /b 0

:prompt_for_android_sdk
set "SDK_INPUT="
echo.
set /p SDK_INPUT=Enter an existing Android SDK path, or press Enter to continue:
if not defined SDK_INPUT exit /b 0
if not exist "%SDK_INPUT%" (
    call :log_warn "The provided Android SDK path does not exist: %SDK_INPUT%"
    exit /b 0
)
set "SDK_CANDIDATE=%SDK_INPUT%"
call :log_ok "Using user-provided Android SDK path: %SDK_INPUT%"
exit /b 0

:confirm_android_sdk_install
echo.
set "SDK_INSTALL_CONFIRM="
set /p SDK_INSTALL_CONFIRM=Android SDK was not found. Type Y to install it with winget; press Enter to cancel:
if /I "%SDK_INSTALL_CONFIRM%"=="Y" exit /b 0
if /I "%SDK_INSTALL_CONFIRM%"=="YES" exit /b 0
exit /b 1

:install_android_sdk
if "%SKIP_WINGET%"=="1" (
    call :log_error "Automatic Android SDK install requires winget, but --skip-winget is enabled."
    exit /b 1
)
if not defined WINGET_CMD (
    call :log_error "Automatic Android SDK install needs winget, which is unavailable here."
    exit /b 1
)
call :log_info "Installing Android CLI via winget. This may take several minutes."
call "%WINGET_CMD%" install --id Google.AndroidCLI -e --accept-package-agreements --accept-source-agreements --disable-interactivity
if errorlevel 1 (
    call :log_error "winget failed while installing Android CLI."
    exit /b 1
)
set "ANDROID_CLI_CMD="
where android >nul 2>nul
if not errorlevel 1 for /f "delims=" %%A in ('where android') do if not defined ANDROID_CLI_CMD set "ANDROID_CLI_CMD=%%~fA"
if not defined ANDROID_CLI_CMD if exist "%LOCALAPPDATA%\Microsoft\WinGet\Links\android.exe" set "ANDROID_CLI_CMD=%LOCALAPPDATA%\Microsoft\WinGet\Links\android.exe"
if not defined ANDROID_CLI_CMD (
    call :log_error "Android CLI install completed, but the android command is still unavailable."
    exit /b 1
)
set "SDK_INSTALL_ROOT=%LOCALAPPDATA%\Android\Sdk"
if defined ANDROID_SDK_ROOT set "SDK_INSTALL_ROOT=%ANDROID_SDK_ROOT%"
if defined ANDROID_HOME set "SDK_INSTALL_ROOT=%ANDROID_HOME%"
if not exist "%SDK_INSTALL_ROOT%" mkdir "%SDK_INSTALL_ROOT%" >nul 2>nul
call :log_info "Target SDK root: %SDK_INSTALL_ROOT%"
call "%ANDROID_CLI_CMD%" --sdk="%SDK_INSTALL_ROOT%" sdk install cmdline-tools/latest platform-tools platforms/android-%ANDROID_COMPILE_SDK% build-tools/%ANDROID_BUILD_TOOLS%
if errorlevel 1 (
    call :log_error "Android CLI failed while installing Android SDK packages."
    exit /b 1
)
set "ANDROID_SDK_ROOT=%SDK_INSTALL_ROOT%"
set "ANDROID_HOME=%SDK_INSTALL_ROOT%"
call :log_ok "Android SDK install completed"
exit /b 0

:ensure_android_sdk_packages
call :log_info "Checking Android SDK platform and build tools..."

set "SDK_PACKAGES_MISSING=0"
if not exist "%ANDROID_SDK_ROOT%\platforms\android-%ANDROID_COMPILE_SDK%\android.jar" set "SDK_PACKAGES_MISSING=1"
if not exist "%ANDROID_SDK_ROOT%\build-tools\%ANDROID_BUILD_TOOLS%\aapt2.exe" set "SDK_PACKAGES_MISSING=1"
if "%SDK_PACKAGES_MISSING%"=="0" (
    call :log_ok "Android SDK platform and build tools are ready"
    exit /b 0
)

call :resolve_sdkmanager
if errorlevel 1 (
    call :log_error "sdkmanager.bat not found. Android command-line tools are required."
    exit /b 1
)
call :prepare_java_for_sdkmanager
if errorlevel 1 (
    call :log_error "JDK not found. sdkmanager requires a JDK to manage Android SDK packages."
    exit /b 1
)

call :log_warn "Installing Android SDK packages: platforms;android-%ANDROID_COMPILE_SDK%, build-tools;%ANDROID_BUILD_TOOLS%"
call :log_info "sdkmanager may take several minutes before new lines appear."
set "SDKMANAGER_INPUT=%TEMP%\frost-sdkmanager-input-%RANDOM%.txt"
> "%SDKMANAGER_INPUT%" (
    echo y
    echo y
    echo y
    echo y
)
cmd /d /c ""%JAVA_HOME%\bin\java.exe" -version & call "%SDKMANAGER_CMD%" --sdk_root="%ANDROID_SDK_ROOT%" "platforms;android-%ANDROID_COMPILE_SDK%" "build-tools;%ANDROID_BUILD_TOOLS%" < "%SDKMANAGER_INPUT%""
set "SDKMANAGER_RESULT=%ERRORLEVEL%"
del /q "%SDKMANAGER_INPUT%" >nul 2>nul

if not "%SDKMANAGER_RESULT%"=="0" (
    call :log_error "sdkmanager failed while installing Android platform/build-tools."
    call :log_error "Check network or proxy access, or install these packages manually:"
    call :log_error "  platforms;android-%ANDROID_COMPILE_SDK%"
    call :log_error "  build-tools;%ANDROID_BUILD_TOOLS%"
    exit /b 1
)
if not exist "%ANDROID_SDK_ROOT%\platforms\android-%ANDROID_COMPILE_SDK%\android.jar" (
    call :log_error "Android platform android-%ANDROID_COMPILE_SDK% is still missing."
    exit /b 1
)
if not exist "%ANDROID_SDK_ROOT%\build-tools\%ANDROID_BUILD_TOOLS%\aapt2.exe" (
    call :log_error "Android build-tools %ANDROID_BUILD_TOOLS% is still missing."
    exit /b 1
)
call :log_ok "Android SDK platform and build tools are ready"
exit /b 0

:resolve_sdkmanager
set "SDKMANAGER_CMD="
if exist "%ANDROID_SDK_ROOT%\cmdline-tools\latest\bin\sdkmanager.bat" set "SDKMANAGER_CMD=%ANDROID_SDK_ROOT%\cmdline-tools\latest\bin\sdkmanager.bat"
if not defined SDKMANAGER_CMD (
    for /d %%D in ("%ANDROID_SDK_ROOT%\cmdline-tools\*") do (
        if not defined SDKMANAGER_CMD if exist "%%~fD\bin\sdkmanager.bat" set "SDKMANAGER_CMD=%%~fD\bin\sdkmanager.bat"
    )
)
if not defined SDKMANAGER_CMD if exist "%ANDROID_SDK_ROOT%\tools\bin\sdkmanager.bat" set "SDKMANAGER_CMD=%ANDROID_SDK_ROOT%\tools\bin\sdkmanager.bat"
if not defined SDKMANAGER_CMD exit /b 1
call :log_info "Using sdkmanager: %SDKMANAGER_CMD%"
exit /b 0

:prepare_java_for_sdkmanager
if defined JAVA_HOME if exist "%JAVA_HOME%\bin\java.exe" (
    call :check_java_version "%JAVA_HOME%\bin\java.exe"
    if "!JAVA_VERSION_OK!"=="1" exit /b 0
)
call :resolve_java_home
if errorlevel 1 exit /b 1
exit /b 0

REM ---------- Android NDK ----------
:resolve_android_ndk
call :log_info "Resolving Android NDK %NDK_VERSION%..."
set "NDK_CANDIDATE="
set "NDK_CLANG="

if defined ANDROID_NDK_ROOT if exist "%ANDROID_NDK_ROOT%\source.properties" set "NDK_CANDIDATE=%ANDROID_NDK_ROOT%"
if not defined NDK_CANDIDATE if exist "%ANDROID_SDK_ROOT%\ndk\%NDK_VERSION%\source.properties" set "NDK_CANDIDATE=%ANDROID_SDK_ROOT%\ndk\%NDK_VERSION%"
if not defined NDK_CANDIDATE if defined ANDROID_HOME if exist "%ANDROID_HOME%\ndk\%NDK_VERSION%\source.properties" set "NDK_CANDIDATE=%ANDROID_HOME%\ndk\%NDK_VERSION%"

if not defined NDK_CANDIDATE (
    call :install_android_ndk
    if errorlevel 1 exit /b 1
    if defined ANDROID_NDK_ROOT if exist "%ANDROID_NDK_ROOT%\source.properties" set "NDK_CANDIDATE=%ANDROID_NDK_ROOT%"
    if not defined NDK_CANDIDATE if exist "%ANDROID_SDK_ROOT%\ndk\%NDK_VERSION%\source.properties" set "NDK_CANDIDATE=%ANDROID_SDK_ROOT%\ndk\%NDK_VERSION%"
)
if not defined NDK_CANDIDATE (
    call :log_error "Android NDK %NDK_VERSION% not found."
    exit /b 1
)

set "NDK_CLANG=%NDK_CANDIDATE%\toolchains\llvm\prebuilt\windows-x86_64\bin\clang++.exe"
if not exist "%NDK_CLANG%" (
    call :log_error "Android NDK is incomplete or invalid: %NDK_CANDIDATE%"
    call :log_error "Missing toolchain: %NDK_CLANG%"
    exit /b 1
)

set "ANDROID_NDK_ROOT=%NDK_CANDIDATE%"
set "ANDROID_NDK_HOME=%NDK_CANDIDATE%"
call :log_ok "Android NDK: %ANDROID_NDK_ROOT%"
exit /b 0

:install_android_ndk
call :log_warn "Android NDK %NDK_VERSION% not found. Installing via sdkmanager..."
call :resolve_sdkmanager
if errorlevel 1 (
    call :log_error "sdkmanager.bat not found. Install Android command-line tools first."
    exit /b 1
)
call :prepare_java_for_sdkmanager
if errorlevel 1 (
    call :log_error "JDK not found. sdkmanager requires a JDK to install the Android NDK."
    exit /b 1
)
set "SDKMANAGER_INPUT=%TEMP%\frost-sdkmanager-input-%RANDOM%.txt"
> "%SDKMANAGER_INPUT%" (
    echo y
    echo y
    echo y
    echo y
)
cmd /d /c ""%JAVA_HOME%\bin\java.exe" -version & call "%SDKMANAGER_CMD%" --sdk_root="%ANDROID_SDK_ROOT%" "ndk;%NDK_VERSION%" < "%SDKMANAGER_INPUT%""
set "SDKMANAGER_RESULT=%ERRORLEVEL%"
del /q "%SDKMANAGER_INPUT%" >nul 2>nul
if not "%SDKMANAGER_RESULT%"=="0" (
    call :log_error "sdkmanager failed while installing Android NDK %NDK_VERSION%."
    exit /b 1
)
call :log_ok "sdkmanager install completed for ndk;%NDK_VERSION%"
exit /b 0

REM ---------- JDK ----------
:resolve_java_home
call :log_info "Resolving JDK 17+..."
call :locate_java_home
if errorlevel 1 (
    call :log_warn "JDK 17+ not found. Attempting automatic install..."
    call :install_jdk
    if errorlevel 1 (
        call :log_error "JDK not found and automatic install is unavailable or failed."
        exit /b 1
    )
    call :locate_java_home
    if errorlevel 1 (
        call :log_error "JDK install completed, but JDK 17+ is still unavailable."
        exit /b 1
    )
)
set "JAVA_HOME=%JAVA_CANDIDATE%"
call :log_ok "JAVA_HOME: %JAVA_HOME%"
exit /b 0

:locate_java_home
set "JAVA_CANDIDATE="
set "JAVA_VERSION_OK="

if defined JAVA_HOME if exist "%JAVA_HOME%\bin\java.exe" (
    call :check_java_version "%JAVA_HOME%\bin\java.exe"
    if "!JAVA_VERSION_OK!"=="1" set "JAVA_CANDIDATE=%JAVA_HOME%"
)
if not defined JAVA_CANDIDATE if exist "%ProgramFiles%\Microsoft" (
    for /d %%D in ("%ProgramFiles%\Microsoft\jdk-*") do (
        if not defined JAVA_CANDIDATE if exist "%%~fD\bin\java.exe" (
            call :check_java_version "%%~fD\bin\java.exe"
            if "!JAVA_VERSION_OK!"=="1" set "JAVA_CANDIDATE=%%~fD"
        )
    )
)
if not defined JAVA_CANDIDATE if exist "%ProgramFiles%\Eclipse Adoptium" (
    for /d %%D in ("%ProgramFiles%\Eclipse Adoptium\jdk-*") do (
        if not defined JAVA_CANDIDATE if exist "%%~fD\bin\java.exe" (
            call :check_java_version "%%~fD\bin\java.exe"
            if "!JAVA_VERSION_OK!"=="1" set "JAVA_CANDIDATE=%%~fD"
        )
    )
)
if not defined JAVA_CANDIDATE if exist "%ProgramFiles%\Java" (
    for /d %%D in ("%ProgramFiles%\Java\jdk-*") do (
        if not defined JAVA_CANDIDATE if exist "%%~fD\bin\java.exe" (
            call :check_java_version "%%~fD\bin\java.exe"
            if "!JAVA_VERSION_OK!"=="1" set "JAVA_CANDIDATE=%%~fD"
        )
    )
)
call :scan_java_candidates "%ProgramFiles%\Android"
call :scan_java_candidates "%ProgramFiles%"
call :scan_java_candidates "%LOCALAPPDATA%\Programs"
call :scan_jetbrains_jdks "%USERPROFILE%\.jdks"

if not defined JAVA_CANDIDATE (
    for /f "delims=" %%J in ('where java 2^>nul') do (
        if not defined JAVA_CANDIDATE if exist "%%~fJ" (
            call :check_java_version "%%~fJ"
            if "!JAVA_VERSION_OK!"=="1" for %%K in ("%%~dpJ..") do set "JAVA_CANDIDATE=%%~fK"
        )
    )
)
if not defined JAVA_CANDIDATE exit /b 1
exit /b 0

:scan_java_candidates
if defined JAVA_CANDIDATE exit /b 0
if "%~1"=="" exit /b 0
if not exist "%~1" exit /b 0
for /d %%D in ("%~1\Android Studio*") do (
    if not defined JAVA_CANDIDATE if exist "%%~fD\jbr\bin\java.exe" (
        call :check_java_version "%%~fD\jbr\bin\java.exe"
        if "!JAVA_VERSION_OK!"=="1" set "JAVA_CANDIDATE=%%~fD\jbr"
    )
)
exit /b 0

:scan_jetbrains_jdks
if defined JAVA_CANDIDATE exit /b 0
if "%~1"=="" exit /b 0
if not exist "%~1" exit /b 0
for /d %%D in ("%~1\jbr-*") do (
    if not defined JAVA_CANDIDATE if exist "%%~fD\bin\java.exe" (
        call :check_java_version "%%~fD\bin\java.exe"
        if "!JAVA_VERSION_OK!"=="1" set "JAVA_CANDIDATE=%%~fD"
    )
)
for /d %%D in ("%~1\jdk-*") do (
    if not defined JAVA_CANDIDATE if exist "%%~fD\bin\java.exe" (
        call :check_java_version "%%~fD\bin\java.exe"
        if "!JAVA_VERSION_OK!"=="1" set "JAVA_CANDIDATE=%%~fD"
    )
)
exit /b 0

:check_java_version
set "JAVA_VERSION_OK="
set "JAVA_VERSION_OUTPUT="
for /f "delims=" %%V in ('"%~1" -version 2^>^&1') do (
    if not defined JAVA_VERSION_OUTPUT set "JAVA_VERSION_OUTPUT=%%V"
)
if not defined JAVA_VERSION_OUTPUT exit /b 0
echo(!JAVA_VERSION_OUTPUT!| findstr /r /c:"\"1[7-9]\." /c:"\"[2-9][0-9]\." >nul
if not errorlevel 1 set "JAVA_VERSION_OK=1"
exit /b 0

:install_jdk
if "%SKIP_WINGET%"=="1" (
    call :log_error "Automatic JDK install requires winget, but --skip-winget is enabled."
    exit /b 1
)
if not defined WINGET_CMD (
    call :log_error "Automatic JDK install needs winget, which is unavailable here."
    exit /b 1
)
call :log_info "Installing JDK 17 via winget (preferred source: Microsoft.OpenJDK.17)."
call "%WINGET_CMD%" install --id Microsoft.OpenJDK.17 -e --accept-package-agreements --accept-source-agreements --disable-interactivity
if errorlevel 1 (
    call :log_warn "Microsoft.OpenJDK.17 install failed, falling back to EclipseAdoptium.Temurin.17.JDK."
    call "%WINGET_CMD%" install --id EclipseAdoptium.Temurin.17.JDK -e --accept-package-agreements --accept-source-agreements --disable-interactivity
    if errorlevel 1 (
        call :log_error "winget failed while installing JDK 17."
        exit /b 1
    )
)
call :log_ok "JDK install completed"
exit /b 0

REM ---------- winget ----------
:resolve_winget
set "WINGET_CMD="
if "%SKIP_WINGET%"=="1" exit /b 0
where winget >nul 2>nul
if not errorlevel 1 set "WINGET_CMD=winget"
exit /b 0

REM ---------- Persistence ----------
:persist_env
set "ENV_NAME=%~1"
set "ENV_VALUE=%~2"
if not defined ENV_VALUE exit /b 0
call set "CURRENT_VALUE=%%%ENV_NAME%%%"
if /I "%CURRENT_VALUE%"=="%ENV_VALUE%" (
    call :log_info "%ENV_NAME% already set"
    exit /b 0
)
setx %ENV_NAME% "%ENV_VALUE%" >nul
if errorlevel 1 (
    call :log_warn "Failed to persist %ENV_NAME%. The current run still uses the resolved value."
    exit /b 0
)
call :log_ok "Persisted %ENV_NAME%"
exit /b 0

:save_user_build_env
REM build.bat 读取该文件, 让没继承到安装器 PATH 改动的终端也能找到 SDK / JDK.
> "%USER_ENV_FILE%" (
    echo @echo off
    if defined ANDROID_HOME echo set "ANDROID_HOME=%ANDROID_HOME%"
    if defined ANDROID_SDK_ROOT echo set "ANDROID_SDK_ROOT=%ANDROID_SDK_ROOT%"
    if defined ANDROID_NDK_ROOT echo set "ANDROID_NDK_ROOT=%ANDROID_NDK_ROOT%"
    if defined JAVA_HOME echo set "JAVA_HOME=%JAVA_HOME%"
)
call :log_ok "Saved build environment for future runs: %USER_ENV_FILE%"
exit /b 0

REM ---------- Logging ----------
:log_info
echo %COLOR_CYAN%[INFO] %~1%COLOR_RESET%
exit /b 0

:log_warn
echo %COLOR_YELLOW%[WARN] %~1%COLOR_RESET%
exit /b 0

:log_error
echo %COLOR_RED%[ERR ] %~1%COLOR_RESET%
exit /b 0

:log_ok
echo %COLOR_GREEN%[ OK ] %~1%COLOR_RESET%
exit /b 0

:failed
echo.
call :log_error "Environment setup failed."
call :log_error "build.bat cannot run until setup completes successfully."
echo.
exit /b 1
