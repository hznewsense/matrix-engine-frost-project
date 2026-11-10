@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ============================================================
REM Matrix Engine Frost Project - APK Build
REM 单 APK 流水线: Gradle 组装 -> 产物归位到 Apks\
REM 引擎 AAR / game.pck / 原生库都已随仓库提供, 脚本不再编译或导出.
REM ============================================================

for /F "delims=" %%E in ('echo prompt $E^| cmd') do set "ESC=%%E"
set "COLOR_RESET=%ESC%[0m"
set "COLOR_RED=%ESC%[91m"
set "COLOR_YELLOW=%ESC%[93m"
set "COLOR_GREEN=%ESC%[92m"
set "COLOR_CYAN=%ESC%[96m"

REM ---------- Product identity (与 MEFrostJava/app/build.gradle 的默认值一致) ----------
set "PRODUCT_NAME=MEFrost"
set "APPLICATION_ID=com.ns.mefrost"
set "VERSION_NAME=1.0.0"
set "VERSION_CODE=1"
set "ANDROID_ABI=arm64-v8a"
set "COMPILE_SDK=36"
set "MIN_SDK=30"
set "TARGET_SDK=36"
set "NDK_VERSION=29.0.14206865"
set "APK_VARIANT=release"

REM ---------- Paths ----------
set "REPO_ROOT=%~dp0"
if "%REPO_ROOT:~-1%"=="\" set "REPO_ROOT=%REPO_ROOT:~0,-1%"
set "ANDROID_DIR=%REPO_ROOT%\MEFrostJava"
set "HOST_DIR=%ANDROID_DIR%\host"
set "APP_DIR=%ANDROID_DIR%\app"
set "WRAPPER_JAR=%HOST_DIR%\gradle\wrapper\gradle-wrapper.jar"
set "APKS_DIR=%REPO_ROOT%\Apks"
set "LOG_DIR=%REPO_ROOT%\.build-logs"
set "USER_ENV_FILE=%REPO_ROOT%\.setup-user-env.cmd"

set "APK_GRADLE_OUTPUT=%APP_DIR%\build\outputs\apk\%APK_VARIANT%\MEFrost.apk"

REM setup.bat 解析出的 SDK / NDK / JDK 路径, 让没继承 PATH 改动的终端也能构建.
if exist "%USER_ENV_FILE%" call "%USER_ENV_FILE%"

goto main

REM ---------- Entry ----------
:main
set "BUILD_APK=1"
set "CLEAN_ALL=0"
set "CLEAN_HOST=0"
set "PLAN_ONLY=0"
set "NO_PAUSE=0"
REM 预扫 --no-pause 和 --help: 参数解析在遇到它们之前就可能提前返回.
call :prescan_pause_flags %*
call :run_build %*
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

:run_build
goto parse_args

:parse_args
if "%~1"=="" goto args_done
set "ARG_HANDLED=0"
if /I "%~1"=="--apk" (
    set BUILD_APK=1
    set "ARG_HANDLED=1"
)
if /I "%~1"=="--clean" (
    set CLEAN_ALL=1
    set BUILD_APK=0
    set "ARG_HANDLED=1"
)
if /I "%~1"=="--all" (
    set CLEAN_ALL=1
    set BUILD_APK=1
    set "ARG_HANDLED=1"
)
if /I "%~1"=="--clean-host" (
    set CLEAN_HOST=1
    set "ARG_HANDLED=1"
)
if /I "%~1"=="--plan" (
    set PLAN_ONLY=1
    set "ARG_HANDLED=1"
)
if /I "%~1"=="--no-pause" (
    set "ARG_HANDLED=1"
)
if /I "%~1"=="--help" goto usage
if "%ARG_HANDLED%"=="0" (
    call :log_error "Unknown option: %~1"
    echo.
    echo Run `build.bat --help` to see available options.
    exit /b 1
)
shift
goto parse_args

:args_done
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" >nul 2>nul

call :init_artifact_meta
call :print_header

if "%CLEAN_ALL%"=="1" (
    call :clean_host
    if errorlevel 1 goto failed
    call :log_info "Deleting packaged outputs in Apks\."
    if exist "%APKS_DIR%" (
        del /q "%APKS_DIR%\*.apk" >nul 2>nul
    )
    call :log_ok "Clean complete."
)
if "%CLEAN_HOST%"=="1" (
    call :clean_host
    if errorlevel 1 goto failed
)

if "%BUILD_APK%"=="0" goto build_done

call :detect_tools
if errorlevel 1 goto failed

if "%PLAN_ONLY%"=="1" (
    call :print_plan
    goto build_done
)

call :compose_apk
if errorlevel 1 goto failed

echo.
call :log_ok "Build complete."
echo.
echo Output files:
echo   APK : %APK_OUT%
echo.
goto build_done

:usage
echo.
echo Usage:
echo   build.bat [options]
echo.
echo Options:
echo   (no option)      Build the release APK into Apks\
echo   --apk            Same as no option
echo   --clean          Delete host build caches and packaged APKs, then exit
echo   --all            Clean everything first, then build
echo   --clean-host     Delete Gradle build outputs and caches
echo   --plan           Print the resolved plan and exit
echo   --no-pause       Exit immediately after finishing
echo   --help           Show help
echo.
echo Examples:
echo   build.bat                 - Build the release APK
echo   build.bat --plan          - Show the resolved plan
echo   build.bat --all           - Clean then build
echo.
exit /b 0

:print_header
echo ============================================================
echo Matrix Engine Frost Project - Build
echo ============================================================
echo Repository Root : %REPO_ROOT%
echo Product         : %PRODUCT_NAME% %VERSION_NAME% (%APPLICATION_ID%)
echo APK Output      : %APK_OUT%
echo ============================================================
echo.
exit /b 0

:print_plan
echo ---- Build plan -------------------------------------------------
echo ANDROID_SDK_ROOT  : %ANDROID_SDK_ROOT%
echo ANDROID_NDK_ROOT  : %ANDROID_NDK_ROOT%
echo ANDROID_NDK       : %NDK_VERSION%
echo JAVA_HOME         : %JAVA_HOME%
echo GRADLE_WRAPPER    : %WRAPPER_JAR%
echo ----------------------------------------------------------------
if "%BUILD_APK%"=="1" echo [build] APK package      -^> %APK_OUT%
echo ----------------------------------------------------------------
call :log_info "Plan only, no build was performed."
exit /b 0

REM ---------- Artifact naming ----------
:init_artifact_meta
REM 与 Matrix Engine 示例工程保持相同的字段组合: <项目>_<版本>_<git>_<variant>
call :read_git_commit
set "ARTIFACT_BASE=%PRODUCT_NAME%_%VERSION_NAME%_%GIT_COMMIT%_%APK_VARIANT%"
set "APK_OUT=%APKS_DIR%\%ARTIFACT_BASE%.apk"
call :log_info "Artifact name: %ARTIFACT_BASE%"
exit /b 0

:read_git_commit
set "GIT_COMMIT="
for /f "delims=" %%C in ('git -C "%REPO_ROOT%" rev-parse --short HEAD 2^>nul') do if not defined GIT_COMMIT set "GIT_COMMIT=%%C"
if not defined GIT_COMMIT set "GIT_COMMIT=unknown"
exit /b 0

REM ---------- Toolchain ----------
:detect_tools
call :log_info "Detecting build tools..."

call :resolve_java_home
if errorlevel 1 exit /b 1
call :resolve_android_sdk
if errorlevel 1 exit /b 1
call :resolve_android_ndk
if errorlevel 1 exit /b 1
call :resolve_gradle_wrapper
if errorlevel 1 exit /b 1
call :require_project_assets
if errorlevel 1 exit /b 1

echo.
call :log_info "Build dependencies:"
echo   ANDROID_SDK_ROOT  = %ANDROID_SDK_ROOT%
echo   ANDROID_NDK_ROOT  = %ANDROID_NDK_ROOT%
echo   JAVA_HOME         = %JAVA_HOME%
echo   GRADLE_WRAPPER    = %WRAPPER_JAR%
echo.
exit /b 0

:resolve_java_home
if defined JAVA_HOME if exist "%JAVA_HOME%\bin\java.exe" exit /b 0
call :log_error "JAVA_HOME is not set to a JDK. Run setup.bat first."
exit /b 1

:resolve_android_sdk
if defined ANDROID_SDK_ROOT if exist "%ANDROID_SDK_ROOT%\platforms" exit /b 0
if defined ANDROID_HOME if exist "%ANDROID_HOME%\platforms" (
    set "ANDROID_SDK_ROOT=%ANDROID_HOME%"
    exit /b 0
)
call :log_error "Android SDK not found. Run setup.bat first."
exit /b 1

:resolve_android_ndk
if defined ANDROID_NDK_ROOT if exist "%ANDROID_NDK_ROOT%\source.properties" exit /b 0
if exist "%ANDROID_SDK_ROOT%\ndk\%NDK_VERSION%\source.properties" (
    set "ANDROID_NDK_ROOT=%ANDROID_SDK_ROOT%\ndk\%NDK_VERSION%"
    exit /b 0
)
call :log_error "Android NDK %NDK_VERSION% not found. Run setup.bat first."
exit /b 1

:resolve_gradle_wrapper
if exist "%WRAPPER_JAR%" exit /b 0
call :log_error "Gradle wrapper jar not found: %WRAPPER_JAR%"
exit /b 1

:require_project_assets
if not exist "%APP_DIR%\src\main\assets\game.pck" (
    call :log_error "game.pck not found: %APP_DIR%\src\main\assets\game.pck"
    call :log_error "It is stored with Git LFS. Restore it with: git lfs pull"
    exit /b 1
)
if not exist "%APP_DIR%\libs\MatrixSdk_Integrated_*.aar" (
    call :log_error "MatrixSdk AAR not found under: %APP_DIR%\libs"
    exit /b 1
)
exit /b 0

REM ---------- APK ----------
:compose_apk
call :log_info "Building the APK..."

if not exist "%APP_DIR%\build.gradle" (
    call :log_error "Application module not found: %APP_DIR%"
    exit /b 1
)

REM 先删除旧 APK: Gradle 可能报告 UP-TO-DATE 并留下上一次的产物.
if exist "%APK_GRADLE_OUTPUT%" del /q "%APK_GRADLE_OUTPUT%" >nul 2>nul

call :log_info "Gradle task: :app:assembleRelease"
call :log_info "Gradle output will be streamed below."
pushd "%HOST_DIR%"
"%JAVA_HOME%\bin\java.exe" -classpath "%WRAPPER_JAR%" org.gradle.wrapper.GradleWrapperMain --no-daemon --console plain -Pexport_package_name=%APPLICATION_ID% -Pexport_version_name=%VERSION_NAME% -Pexport_version_code=%VERSION_CODE% -Pexport_compile_sdk=%COMPILE_SDK% -Pexport_min_sdk=%MIN_SDK% -Pexport_target_sdk=%TARGET_SDK% -Pexport_ndk_version=%NDK_VERSION% -Pexport_enabled_abis=%ANDROID_ABI% :app:assembleRelease
set "GRADLE_RESULT=%ERRORLEVEL%"
popd

if not "%GRADLE_RESULT%"=="0" (
    call :log_error "Gradle APK build failed."
    exit /b 1
)
if not exist "%APK_GRADLE_OUTPUT%" (
    call :log_error "Gradle reported success but no APK was produced: %APK_GRADLE_OUTPUT%"
    exit /b 1
)
if not exist "%APKS_DIR%" mkdir "%APKS_DIR%" >nul 2>nul
call :copy_file_retry "%APK_GRADLE_OUTPUT%" "%APK_OUT%"
if errorlevel 1 exit /b 1
for %%A in ("%APK_OUT%") do set "APK_SIZE=%%~zA"
call :verify_apk_payload "%APK_OUT%" "!APK_SIZE!"
if errorlevel 1 exit /b 1
call :log_ok "APK built: %APK_OUT% (!APK_SIZE! bytes)"
exit /b 0

:verify_apk_payload
REM 未 strip 的原生库会把 APK 撑到数百 MB; PCK 缺失则说明 assets 没被打进去.
if %~2 LSS 524288000 goto verify_apk_payload_ok
call :log_error "APK is %~2 bytes -- native libraries were NOT stripped."
call :log_error "Gradle logged 'Unable to strip the following libraries', which means it"
call :log_error "could not run llvm-strip from the Android NDK %NDK_VERSION%."
call :log_error "Check that ANDROID_NDK_ROOT exists, then run: build.bat --clean-host"
exit /b 1

:verify_apk_payload_ok
if %~2 GTR 52428800 exit /b 0
call :log_error "APK is only %~2 bytes -- game.pck or the native libraries are missing."
call :log_error "Check MEFrostJava/app/src/main/assets/game.pck and MEFrostJava/app/src/main/jniLibs/arm64-v8a."
exit /b 1

:copy_file_retry
REM 杀软, OneDrive 或 Gradle 文件监听会短暂占用刚写入的文件, 让 copy 报错 1224.
set "COPY_SRC=%~1"
set "COPY_DST=%~2"
if not exist "%COPY_SRC%" (
    call :log_error "Source file not found: %COPY_SRC%"
    exit /b 1
)
set "COPY_DST_DIR=%~dp2"
if not exist "%COPY_DST_DIR%" mkdir "%COPY_DST_DIR%" >nul 2>nul
set "COPY_ATTEMPTS=5"
for /l %%N in (1,1,%COPY_ATTEMPTS%) do (
    copy /Y "!COPY_SRC!" "!COPY_DST!" >nul 2>&1
    if not errorlevel 1 exit /b 0
    if %%N lss %COPY_ATTEMPTS% (
        call :log_warn "Copy attempt %%N failed, retrying: %~nx2"
        ping -n 2 127.0.0.1 >nul 2>&1
    )
)
call :log_error "Copy failed after %COPY_ATTEMPTS% attempts: %~nx2"
exit /b 1

REM ---------- Clean ----------
:clean_host
call :log_info "Deleting Gradle build outputs and caches..."
if exist "%APP_DIR%\build" call :remove_tree "%APP_DIR%\build"
if exist "%APP_DIR%\.gradle" call :remove_tree "%APP_DIR%\.gradle"
if exist "%HOST_DIR%\.gradle" call :remove_tree "%HOST_DIR%\.gradle"
call :log_ok "Host build caches removed."
exit /b 0

:remove_tree
REM Gradle 文件锁会短暂阻止删除, 重试几次再放弃.
set "REMOVE_TARGET=%~1"
for /l %%N in (1,1,5) do (
    if not exist "!REMOVE_TARGET!" exit /b 0
    rd /s /q "!REMOVE_TARGET!" >nul 2>&1
    if not exist "!REMOVE_TARGET!" exit /b 0
    ping -n 2 127.0.0.1 >nul 2>&1
)
if exist "!REMOVE_TARGET!" (
    call :log_error "Failed to delete: !REMOVE_TARGET!"
    call :log_error "Close Android Studio or any process holding the directory, then retry."
    exit /b 1
)
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

:build_done
exit /b 0

:failed
echo.
call :log_error "Build failed. Please check the errors above."
echo.
exit /b 1
