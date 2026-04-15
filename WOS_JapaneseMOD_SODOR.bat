@echo off
chcp 65001 >nul
setlocal EnableExtensions

rem =============================================================================
rem  Build TS2Prototype-WindowsNoEditor.pak (Windows) - SODOR
rem  repak is downloaded from GitHub releases
rem =============================================================================

rem --- Config ---------------------------------------------------------------
rem Repo root = this .bat directory
set "REPO_ROOT=%~dp0"

rem repak directory (expanded under repo root)
set "REPAK_DIR=%REPO_ROOT%repak_cli-x86_64-pc-windows-msvc"
set "REPAK_EXE=%REPAK_DIR%\repak.exe"

rem 1=skip download if repak.exe exists / 0=always try download
set "SKIP_REPAK_DL_IF_PRESENT=1"
rem 1=force re-download (overwrite)
set "FORCE_REPAK_DL=0"

rem staging (currently unused)
set "STAGING_DIR=%TEMP%\wos_font_pak_staging"

rem game pak path resolution:
rem fixed candidates only (no wildcard search), decided in :FIND_GAME_PAK via PowerShell

rem original pak storage location (fixed per-user backup dir)
set "ORIGINAL_PAK_DIR="
set "ORIGINAL_PAK="
set "ORIGINAL_SODOR_CORE_PAK="
set "ORIGINAL_JAMES_CORE_PAK="

rem work root (deleted on success)
set "PACK_WORK_ROOT=%REPO_ROOT%WOS_pack_work_SODOR"

rem repak unpack --output (directory)
set "UNPACK_OUTPUT_DIR=%PACK_WORK_ROOT%\TS2Prototype-WindowsNoEditor"
set "UNPACK_CORE_OUTPUT_DIR=%PACK_WORK_ROOT%\TS2Prototype-WindowsNoEditor-Sodor-coredata"
set "UNPACK_JAMES_CORE_OUTPUT_DIR=%PACK_WORK_ROOT%\TS2Prototype-WindowsNoEditor-James-coredata"

rem pack input directory
set "TS2_UNPACKED_DIR=%UNPACK_OUTPUT_DIR%"
set "TS2_CORE_UNPACKED_DIR=%UNPACK_CORE_OUTPUT_DIR%"
set "TS2_JAMES_CORE_UNPACKED_DIR=%UNPACK_JAMES_CORE_OUTPUT_DIR%"

rem pack output pak path
set "OUTPUT_PAK=%PACK_WORK_ROOT%\TS2Prototype-WindowsNoEditor.pak"
set "OUTPUT_CORE_PAK=%PACK_WORK_ROOT%\TS2Prototype-WindowsNoEditor-Sodor-coredata.pak"
set "OUTPUT_JAMES_CORE_PAK=%PACK_WORK_ROOT%\TS2Prototype-WindowsNoEditor-James-coredata.pak"

set "MOD_OVERLAY_DIR=%REPO_ROOT%WOS_JapaneseMOD_SODOR\TS2Prototype-WindowsNoEditor"
set "MOD_OVERLAY_SODOR_CORE_DIR=%REPO_ROOT%WOS_JapaneseMOD_SODOR\TS2Prototype-WindowsNoEditor-Sodor-coredata"
set "MOD_OVERLAY_JAMES_CORE_DIR=%REPO_ROOT%WOS_JapaneseMOD_SODOR\TS2Prototype-WindowsNoEditor-James-coredata"

rem unused (reserved)
set "GAME_CONTENT_MOUNT="

rem 1=skip early repak.exe check / 0=require repak.exe before steps
set "SKIP_REPAK_CHECK=1"

rem 1=delete work dirs on success / 0=keep (debug)
set "CLEANUP_AFTER_BUILD=1"

rem --- Pre-check ------------------------------------------------------------
if "%SKIP_REPAK_CHECK%"=="0" (
  if not exist "%REPAK_EXE%" (
    echo [ERROR] repak が見つかりません: "%REPAK_EXE%"
    exit /b 1
  )
)

rem --- Steps ---------------------------------------------------------------
call :STEP_DOWNLOAD_REPAK
if errorlevel 1 goto :FAILED

call :STEP_MIGRATE_V010_BACKUP
if errorlevel 1 goto :FAILED

call :STEP_BACKUP_ORIGINAL_PAK
if errorlevel 1 goto :FAILED

call :STEP_BACKUP_ORIGINAL_CORE_PAK
if errorlevel 1 goto :FAILED

call :STEP_BACKUP_ORIGINAL_JAMES_CORE_PAK
if errorlevel 1 goto :FAILED

call :STEP_UNPACK_BACKUP_PAK
if errorlevel 1 goto :FAILED

call :STEP_UNPACK_BACKUP_CORE_PAK
if errorlevel 1 goto :FAILED

call :STEP_UNPACK_BACKUP_JAMES_CORE_PAK
if errorlevel 1 goto :FAILED

call :STEP_OVERLAY_MOD_TO_TS2
if errorlevel 1 goto :FAILED

call :STEP_PREPARE_STAGING
if errorlevel 1 goto :FAILED

call :STEP_COPY_OR_GENERATE_FONT_ASSETS
if errorlevel 1 goto :FAILED

call :STEP_BUILD_RESPONSE_FILE
if errorlevel 1 goto :FAILED

call :STEP_RUN_REPAK_PACK
if errorlevel 1 goto :FAILED

call :STEP_VERIFY_OUTPUT
if errorlevel 1 goto :FAILED

call :STEP_INSTALL_TO_GAME
if errorlevel 1 goto :FAILED

call :STEP_CLEANUP_WORK
if errorlevel 1 goto :FAILED

echo.
echo [OK] 完了: ゲームに配置しました。
exit /b 0

:FAILED
echo.
echo [FAILED] 上記のエラーを修正してから再実行してください。
exit /b 1

rem =============================================================================
rem
rem =============================================================================

:STEP_DOWNLOAD_REPAK
  echo.
  echo [1/10] repak 最新版の取得 ^(GitHub Releases^) ...
  if "%FORCE_REPAK_DL%"=="0" (
    if "%SKIP_REPAK_DL_IF_PRESENT%"=="1" (
      if exist "%REPAK_EXE%" (
        echo        既存の repak を使用: "%REPAK_EXE%"
        exit /b 0
      )
    )
  )
rem
  powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ErrorActionPreference = 'Stop';" ^
    "$d = $env:REPAK_DIR;" ^
    "if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force };" ^
    "New-Item -ItemType Directory -Path $d -Force | Out-Null;" ^
    "$api = 'https://api.github.com/repos/trumank/repak/releases/latest';" ^
    "$r = Invoke-RestMethod -Uri $api -Headers @{'User-Agent' = 'wonders-of-sodor-mod/WOS_JapaneseMOD_SODOR.bat'};" ^
    "$name = 'repak_cli-x86_64-pc-windows-msvc.zip';" ^
    "$a = @($r.assets | Where-Object { $_.name -eq $name })[0];" ^
    "if (-not $a) { throw ('Release asset not found: ' + $name) };" ^
    "$tag = [string]$r.tag_name -replace '[^a-zA-Z0-9._-]', '_';" ^
    "$z = Join-Path $env:TEMP ('repak_cli_' + $tag + '.zip');" ^
    "Invoke-WebRequest -Uri $a.browser_download_url -OutFile $z;" ^
    "Expand-Archive -LiteralPath $z -DestinationPath $d -Force;" ^
    "$top = @(Get-ChildItem -LiteralPath $d -Force);" ^
    "if ($top.Count -eq 1 -and $top[0].PSIsContainer) {" ^
    "  $nested = $top[0].FullName;" ^
    "  Get-ChildItem -LiteralPath $nested -Force | ForEach-Object { Move-Item -LiteralPath $_.FullName -Destination $d -Force };" ^
    "  Remove-Item -LiteralPath $nested -Force -Recurse;" ^
    "};" ^
    "if (-not (Test-Path -LiteralPath (Join-Path $d 'repak.exe'))) { throw ('repak.exe not found under: ' + $d) }"
  if errorlevel 1 (
    echo [ERROR] repak のダウンロードまたは展開に失敗しました。
    exit /b 1
  )
  if not exist "%REPAK_EXE%" (
    echo [ERROR] repak.exe が配置されていません: "%REPAK_EXE%"
    exit /b 1
  )
  echo        配置完了: "%REPAK_EXE%"
  exit /b 0

:STEP_BACKUP_ORIGINAL_PAK
  echo.
  echo [2/10] ゲーム元 pak のバックアップ (2種) ...
  call :FIND_GAME_PAK
  if errorlevel 1 exit /b 1
  set "ORIGINAL_PAK_DIR=%LOCALAPPDATA%\WOS_JapaneseMOD\Backup"
  set "ORIGINAL_PAK=%ORIGINAL_PAK_DIR%\TS2Prototype-WindowsNoEditor.pak"
  set "ORIGINAL_SODOR_CORE_PAK=%ORIGINAL_PAK_DIR%\TS2Prototype-WindowsNoEditor-Sodor-coredata.pak"
  set "ORIGINAL_JAMES_CORE_PAK=%ORIGINAL_PAK_DIR%\TS2Prototype-WindowsNoEditor-James-coredata.pak"
  if exist "%ORIGINAL_PAK%" (
    echo        既にバックアップがあります。再コピー・Backup の作り直しはしません。
    echo        "%ORIGINAL_PAK%"
    exit /b 0
  )
  echo        検出: "%GAME_INSTALL_PAK%"
  if not exist "%ORIGINAL_PAK_DIR%" mkdir "%ORIGINAL_PAK_DIR%"
  copy /Y "%GAME_INSTALL_PAK%" "%ORIGINAL_PAK%" >nul
  if errorlevel 1 (
    echo [ERROR] Backup フォルダへのコピーに失敗しました。
    echo        コピー元: "%GAME_INSTALL_PAK%"
    echo        コピー先: "%ORIGINAL_PAK%"
    exit /b 1
  )
  echo        保存しました: "%ORIGINAL_PAK%"
  exit /b 0

:STEP_BACKUP_ORIGINAL_CORE_PAK
  echo.
  echo [2/10] ゲーム元 coredata pak のバックアップ ...
  call :FIND_GAME_PAK
  if errorlevel 1 exit /b 1
  set "ORIGINAL_PAK_DIR=%LOCALAPPDATA%\WOS_JapaneseMOD\Backup"
  set "ORIGINAL_PAK=%ORIGINAL_PAK_DIR%\TS2Prototype-WindowsNoEditor.pak"
  set "ORIGINAL_SODOR_CORE_PAK=%ORIGINAL_PAK_DIR%\TS2Prototype-WindowsNoEditor-Sodor-coredata.pak"
  set "ORIGINAL_JAMES_CORE_PAK=%ORIGINAL_PAK_DIR%\TS2Prototype-WindowsNoEditor-James-coredata.pak"
  if exist "%ORIGINAL_SODOR_CORE_PAK%" (
    echo        既にバックアップがあります。再コピー・Backup の作り直しはしません。
    echo        "%ORIGINAL_SODOR_CORE_PAK%"
    exit /b 0
  )
  echo        検出: "%GAME_INSTALL_CORE_PAK%"
  if not exist "%ORIGINAL_PAK_DIR%" mkdir "%ORIGINAL_PAK_DIR%"
  copy /Y "%GAME_INSTALL_CORE_PAK%" "%ORIGINAL_SODOR_CORE_PAK%" >nul
  if errorlevel 1 (
    echo [ERROR] Backup フォルダへのコピーに失敗しました。
    echo        コピー元: "%GAME_INSTALL_CORE_PAK%"
    echo        コピー先: "%ORIGINAL_SODOR_CORE_PAK%"
    exit /b 1
  )
  echo        保存しました: "%ORIGINAL_SODOR_CORE_PAK%"
  exit /b 0

:STEP_BACKUP_ORIGINAL_JAMES_CORE_PAK
  echo.
  echo [2/10] ゲーム元 James coredata pak のバックアップ ...
  call :FIND_GAME_PAK
  if errorlevel 1 exit /b 1
  set "ORIGINAL_PAK_DIR=%LOCALAPPDATA%\WOS_JapaneseMOD\Backup"
  set "ORIGINAL_PAK=%ORIGINAL_PAK_DIR%\TS2Prototype-WindowsNoEditor.pak"
  set "ORIGINAL_SODOR_CORE_PAK=%ORIGINAL_PAK_DIR%\TS2Prototype-WindowsNoEditor-Sodor-coredata.pak"
  set "ORIGINAL_JAMES_CORE_PAK=%ORIGINAL_PAK_DIR%\TS2Prototype-WindowsNoEditor-James-coredata.pak"
  if exist "%ORIGINAL_JAMES_CORE_PAK%" (
    echo        既にバックアップがあります。再コピー・Backup の作り直しはしません。
    echo        "%ORIGINAL_JAMES_CORE_PAK%"
    exit /b 0
  )
  echo        検出: "%GAME_INSTALL_JAMES_CORE_PAK%"
  if not exist "%ORIGINAL_PAK_DIR%" mkdir "%ORIGINAL_PAK_DIR%"
  copy /Y "%GAME_INSTALL_JAMES_CORE_PAK%" "%ORIGINAL_JAMES_CORE_PAK%" >nul
  if errorlevel 1 (
    echo [ERROR] Backup フォルダへのコピーに失敗しました。
    echo        コピー元: "%GAME_INSTALL_JAMES_CORE_PAK%"
    echo        コピー先: "%ORIGINAL_JAMES_CORE_PAK%"
    exit /b 1
  )
  echo        保存しました: "%ORIGINAL_JAMES_CORE_PAK%"
  exit /b 0

:FIND_GAME_PAK
  set "GAME_INSTALL_PAK="
  set "GAME_INSTALL_PAK_DIR="
  set "GAME_INSTALL_CORE_PAK="
  set "GAME_INSTALL_JAMES_CORE_PAK="
  for /f "usebackq delims=" %%P in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $rel='Thomas & Friends™ Wonders of Sodor\WindowsNoEditor\TS2Prototype\Content\Paks\TS2Prototype-WindowsNoEditor.pak'; $c=@(Join-Path 'C:\Program Files (x86)\Steam\steamapps\common' $rel; Join-Path 'C:\Program Files\Steam\steamapps\common' $rel); foreach($p in $c){ if(Test-Path -LiteralPath $p){ Write-Output $p; break } }"`) do (
    set "GAME_INSTALL_PAK=%%P"
    set "GAME_INSTALL_PAK_DIR=%%~dpP"
    goto :FOUND_GAME_PAK
  )
  if not defined GAME_INSTALL_PAK (
    echo [ERROR] ゲーム側の TS2Prototype-WindowsNoEditor.pak が見つかりません（Steam のインストール先を確認してください）。
    echo        "C:\Program Files (x86)\Steam\steamapps\common\Thomas & Friends™ Wonders of Sodor\WindowsNoEditor\TS2Prototype\Content\Paks\TS2Prototype-WindowsNoEditor.pak"
    echo        "C:\Program Files\Steam\steamapps\common\Thomas & Friends™ Wonders of Sodor\WindowsNoEditor\TS2Prototype\Content\Paks\TS2Prototype-WindowsNoEditor.pak"
    exit /b 1
  )
:FOUND_GAME_PAK
  if defined GAME_INSTALL_PAK_DIR (
    set "GAME_INSTALL_CORE_PAK=%GAME_INSTALL_PAK_DIR%TS2Prototype-WindowsNoEditor-Sodor-coredata.pak"
    set "GAME_INSTALL_JAMES_CORE_PAK=%GAME_INSTALL_PAK_DIR%TS2Prototype-WindowsNoEditor-James-coredata.pak"
  )
  if not exist "%GAME_INSTALL_CORE_PAK%" goto :ERR_MISSING_GAME_CORE_PAK
  if not exist "%GAME_INSTALL_JAMES_CORE_PAK%" goto :ERR_MISSING_GAME_JAMES_CORE_PAK
  exit /b 0

:ERR_MISSING_GAME_CORE_PAK
  echo [ERROR] ゲーム側の TS2Prototype-WindowsNoEditor-Sodor-coredata.pak が見つかりません（Steam のインストール先を確認してください）。
  echo        "%GAME_INSTALL_CORE_PAK%"
  exit /b 1

:ERR_MISSING_GAME_JAMES_CORE_PAK
  echo [ERROR] ゲーム側の TS2Prototype-WindowsNoEditor-James-coredata.pak が見つかりません（Steam のインストール先を確認してください）。
  echo        "%GAME_INSTALL_JAMES_CORE_PAK%"
  exit /b 1

:STEP_UNPACK_BACKUP_PAK
  echo.
  echo [3/10] バックアップ pak の展開 (3種) ^(repak unpack --output^) ...
  if not exist "%REPAK_EXE%" (
    echo [ERROR] repak が見つかりません。先に [1/10] で取得してください: "%REPAK_EXE%"
    exit /b 1
  )
  if not exist "%ORIGINAL_PAK%" (
    echo [ERROR] バックアップ pak がありません: "%ORIGINAL_PAK%"
    exit /b 1
  )
  if not exist "%UNPACK_OUTPUT_DIR%\" mkdir "%UNPACK_OUTPUT_DIR%"
  "%REPAK_EXE%" unpack "%ORIGINAL_PAK%" --output "%UNPACK_OUTPUT_DIR%" --force
  if errorlevel 1 (
    echo [ERROR] repak unpack に失敗しました。
    exit /b 1
  )
  echo        展開先: "%UNPACK_OUTPUT_DIR%"
  exit /b 0

:STEP_UNPACK_BACKUP_CORE_PAK
  echo.
  echo [3/10] バックアップ coredata pak の展開 ^(repak unpack --output^) ...
  if not exist "%REPAK_EXE%" (
    echo [ERROR] repak が見つかりません。先に [1/10] で取得してください: "%REPAK_EXE%"
    exit /b 1
  )
  if not exist "%ORIGINAL_SODOR_CORE_PAK%" (
    echo [ERROR] バックアップ coredata pak がありません: "%ORIGINAL_SODOR_CORE_PAK%"
    exit /b 1
  )
  if not exist "%UNPACK_CORE_OUTPUT_DIR%\" mkdir "%UNPACK_CORE_OUTPUT_DIR%"
  "%REPAK_EXE%" unpack "%ORIGINAL_SODOR_CORE_PAK%" --output "%UNPACK_CORE_OUTPUT_DIR%" --force
  if errorlevel 1 (
    echo [ERROR] repak unpack (coredata) に失敗しました。
    exit /b 1
  )
  echo        展開先: "%UNPACK_CORE_OUTPUT_DIR%"
  exit /b 0

:STEP_UNPACK_BACKUP_JAMES_CORE_PAK
  echo.
  echo [3/10] バックアップ James coredata pak の展開 ^(repak unpack --output^) ...
  if not exist "%REPAK_EXE%" (
    echo [ERROR] repak が見つかりません。先に [1/10] で取得してください: "%REPAK_EXE%"
    exit /b 1
  )
  if not exist "%ORIGINAL_JAMES_CORE_PAK%" (
    echo [ERROR] バックアップ James coredata pak がありません: "%ORIGINAL_JAMES_CORE_PAK%"
    exit /b 1
  )
  if not exist "%UNPACK_JAMES_CORE_OUTPUT_DIR%\" mkdir "%UNPACK_JAMES_CORE_OUTPUT_DIR%"
  "%REPAK_EXE%" unpack "%ORIGINAL_JAMES_CORE_PAK%" --output "%UNPACK_JAMES_CORE_OUTPUT_DIR%" --force
  if errorlevel 1 (
    echo [ERROR] repak unpack (James coredata) に失敗しました。
    exit /b 1
  )
  echo        展開先: "%UNPACK_JAMES_CORE_OUTPUT_DIR%"
  exit /b 0

:STEP_OVERLAY_MOD_TO_TS2
  echo.
  echo [4/10] WOS_JapaneseMOD_SODOR を pak 展開先 (3種) に上書きコピー ...
  if not exist "%MOD_OVERLAY_DIR%\" (
    echo [ERROR] 差し替え元フォルダがありません: "%MOD_OVERLAY_DIR%"
    exit /b 1
  )
  if not exist "%TS2_UNPACKED_DIR%\" (
    echo [ERROR] unpack 済みの TS2Prototype-WindowsNoEditor がありません: "%TS2_UNPACKED_DIR%"
    exit /b 1
  )
  if not exist "%TS2_CORE_UNPACKED_DIR%\" (
    echo [ERROR] unpack 済みの TS2Prototype-WindowsNoEditor-Sodor-coredata がありません: "%TS2_CORE_UNPACKED_DIR%"
    exit /b 1
  )
  if not exist "%TS2_JAMES_CORE_UNPACKED_DIR%\" (
    echo [ERROR] unpack 済みの TS2Prototype-WindowsNoEditor-James-coredata がありません: "%TS2_JAMES_CORE_UNPACKED_DIR%"
    exit /b 1
  )
rem coredata only: delete existing Japanese story assets (cleanup before MOD overlay)
  powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ErrorActionPreference='Stop';" ^
    "$root = $env:TS2_CORE_UNPACKED_DIR;" ^
    "if (-not (Test-Path -LiteralPath $root)) { throw ('coredata dir not found: ' + $root) };" ^
    "$re = '.*_S_(?:\d+|StoryName)_ja\.(?:uasset|uexp)$';" ^
    "$files = Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object { $_.FullName -match $re };" ^
    "foreach($f in $files){ Remove-Item -LiteralPath $f.FullName -Force };" ^
    "Write-Output ('       coredata: 削除 ' + $files.Count + ' ファイル');"
  if errorlevel 1 (
    echo [ERROR] coredata 側の不要ファイル削除に失敗しました。
    exit /b 1
  )
  powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ErrorActionPreference='Stop';" ^
    "$root = $env:TS2_JAMES_CORE_UNPACKED_DIR;" ^
    "if (-not (Test-Path -LiteralPath $root)) { throw ('coredata dir not found: ' + $root) };" ^
    "$re = '.*_S_(?:\d+|StoryName)_ja\.(?:uasset|uexp)$';" ^
    "$files = Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object { $_.FullName -match $re };" ^
    "foreach($f in $files){ Remove-Item -LiteralPath $f.FullName -Force };" ^
    "Write-Output ('       James coredata: 削除 ' + $files.Count + ' ファイル');"
  if errorlevel 1 (
    echo [ERROR] James coredata 側の不要ファイル削除に失敗しました。
    exit /b 1
  )
rem
  robocopy "%MOD_OVERLAY_DIR%" "%TS2_UNPACKED_DIR%" /E /IS /IT /R:2 /W:2 /NFL /NDL /NJH /NJS /NP
  if errorlevel 8 (
    echo [ERROR] 上書きコピー ^(robocopy^) に失敗しました。
    exit /b 1
  )
  if exist "%MOD_OVERLAY_SODOR_CORE_DIR%\" (
    robocopy "%MOD_OVERLAY_SODOR_CORE_DIR%" "%TS2_CORE_UNPACKED_DIR%" /E /IS /IT /R:2 /W:2 /NFL /NDL /NJH /NJS /NP
    if errorlevel 8 (
      echo [ERROR] 上書きコピー ^(robocopy^, Sodor coredata^) に失敗しました。
      exit /b 1
    )
  ) else (
    echo [WARN] Sodor coredata 用の差し替え元フォルダがありません。スキップします: "%MOD_OVERLAY_SODOR_CORE_DIR%"
  )
  if exist "%MOD_OVERLAY_JAMES_CORE_DIR%\" (
    robocopy "%MOD_OVERLAY_JAMES_CORE_DIR%" "%TS2_JAMES_CORE_UNPACKED_DIR%" /E /IS /IT /R:2 /W:2 /NFL /NDL /NJH /NJS /NP
    if errorlevel 8 (
      echo [ERROR] 上書きコピー ^(robocopy^, James coredata^) に失敗しました。
      exit /b 1
    )
  ) else (
    echo [WARN] James coredata 用の差し替え元フォルダがありません。スキップします: "%MOD_OVERLAY_JAMES_CORE_DIR%"
  )
  echo        反映先: "%TS2_UNPACKED_DIR%"
  echo        反映先: "%TS2_CORE_UNPACKED_DIR%"
  echo        反映先: "%TS2_JAMES_CORE_UNPACKED_DIR%"
  exit /b 0

:STEP_PREPARE_STAGING
  echo.
  echo [5/10] ステージング準備 ...
rem
  exit /b 0

:STEP_COPY_OR_GENERATE_FONT_ASSETS
  echo.
  echo [6/10] フォントアセットの配置 ...
rem
  exit /b 0

:STEP_BUILD_RESPONSE_FILE
  echo.
  echo [7/10] pak 用ファイル一覧の準備 ...
rem
  exit /b 0

:STEP_RUN_REPAK_PACK
  echo.
  echo [8/10] repak pack (3種) ^(--compression Zlib --version V11^) ...
  if not exist "%REPAK_EXE%" (
    echo [ERROR] repak が見つかりません: "%REPAK_EXE%"
    exit /b 1
  )
  if not exist "%TS2_UNPACKED_DIR%\" (
    echo [ERROR] パック対象がありません: "%TS2_UNPACKED_DIR%"
    exit /b 1
  )
  if not exist "%TS2_CORE_UNPACKED_DIR%\" (
    echo [ERROR] パック対象 (coredata) がありません: "%TS2_CORE_UNPACKED_DIR%"
    exit /b 1
  )
  if not exist "%TS2_JAMES_CORE_UNPACKED_DIR%\" (
    echo [ERROR] パック対象 (James coredata) がありません: "%TS2_JAMES_CORE_UNPACKED_DIR%"
    exit /b 1
  )
rem
  "%REPAK_EXE%" pack --compression Zlib --version V11 "%TS2_UNPACKED_DIR%" "%OUTPUT_PAK%"
  if errorlevel 1 (
    echo [ERROR] repak pack に失敗しました。
    exit /b 1
  )
  "%REPAK_EXE%" pack --compression Zlib --version V11 "%TS2_CORE_UNPACKED_DIR%" "%OUTPUT_CORE_PAK%"
  if errorlevel 1 (
    echo [ERROR] repak pack (coredata) に失敗しました。
    exit /b 1
  )
  "%REPAK_EXE%" pack --compression Zlib --version V11 "%TS2_JAMES_CORE_UNPACKED_DIR%" "%OUTPUT_JAMES_CORE_PAK%"
  if errorlevel 1 (
    echo [ERROR] repak pack (James coredata) に失敗しました。
    exit /b 1
  )
  echo        出力: "%OUTPUT_PAK%"
  echo        出力: "%OUTPUT_CORE_PAK%"
  echo        出力: "%OUTPUT_JAMES_CORE_PAK%"
  exit /b 0

:STEP_VERIFY_OUTPUT
  echo.
  echo [9/10] 出力確認 (3種) ...
  if not exist "%OUTPUT_PAK%" (
    echo [ERROR] 出力 pak が生成されていません: "%OUTPUT_PAK%"
    exit /b 1
  )
  if not exist "%OUTPUT_CORE_PAK%" (
    echo [ERROR] 出力 coredata pak が生成されていません: "%OUTPUT_CORE_PAK%"
    exit /b 1
  )
  if not exist "%OUTPUT_JAMES_CORE_PAK%" (
    echo [ERROR] 出力 James coredata pak が生成されていません: "%OUTPUT_JAMES_CORE_PAK%"
    exit /b 1
  )
  exit /b 0

:STEP_INSTALL_TO_GAME
  echo.
  echo [10/10] ゲームの pak を差し替え (3種) ...
  if not exist "%OUTPUT_PAK%" (
    echo [ERROR] 配置する pak がありません: "%OUTPUT_PAK%"
    exit /b 1
  )
  if not exist "%OUTPUT_CORE_PAK%" (
    echo [ERROR] 配置する coredata pak がありません: "%OUTPUT_CORE_PAK%"
    exit /b 1
  )
  if not exist "%OUTPUT_JAMES_CORE_PAK%" (
    echo [ERROR] 配置する James coredata pak がありません: "%OUTPUT_JAMES_CORE_PAK%"
    exit /b 1
  )
  call :FIND_GAME_PAK
  if errorlevel 1 exit /b 1
  copy /Y "%OUTPUT_PAK%" "%GAME_INSTALL_PAK%" >nul
  if errorlevel 1 (
    echo [ERROR] ゲームフォルダへのコピーに失敗しました（権限・ファイル使用中の可能性があります）。
    echo        コピー元: "%OUTPUT_PAK%"
    echo        コピー先: "%GAME_INSTALL_PAK%"
    echo        管理者として実行するか、ゲーム・ランチャーを終了してから再試行してください。
    exit /b 1
  )
  copy /Y "%OUTPUT_CORE_PAK%" "%GAME_INSTALL_CORE_PAK%" >nul
  if errorlevel 1 (
    echo [ERROR] ゲームフォルダへのコピーに失敗しました（権限・ファイル使用中の可能性があります）。
    echo        コピー元: "%OUTPUT_CORE_PAK%"
    echo        コピー先: "%GAME_INSTALL_CORE_PAK%"
    echo        管理者として実行するか、ゲーム・ランチャーを終了してから再試行してください。
    exit /b 1
  )
  echo        配置先: "%GAME_INSTALL_PAK%"
  echo        配置先: "%GAME_INSTALL_CORE_PAK%"
  copy /Y "%OUTPUT_JAMES_CORE_PAK%" "%GAME_INSTALL_JAMES_CORE_PAK%" >nul
  if errorlevel 1 (
    echo [ERROR] ゲームフォルダへのコピーに失敗しました（権限・ファイル使用中の可能性があります）。
    echo        コピー元: "%OUTPUT_JAMES_CORE_PAK%"
    echo        コピー先: "%GAME_INSTALL_JAMES_CORE_PAK%"
    echo        管理者として実行するか、ゲーム・ランチャーを終了してから再試行してください。
    exit /b 1
  )
  echo        配置先: "%GAME_INSTALL_JAMES_CORE_PAK%"
  exit /b 0

:STEP_CLEANUP_WORK
  echo.
  echo [cleanup] WOS_pack_work_Knapford / WOS_pack_work_SODOR をフォルダごと削除（容量削減） ...
  if "%CLEANUP_AFTER_BUILD%"=="0" (
    echo        CLEANUP_AFTER_BUILD=0 のためスキップしました。
    exit /b 0
  )
  if exist "%REPO_ROOT%WOS_pack_work_Knapford\" (
    rmdir /S /Q "%REPO_ROOT%WOS_pack_work_Knapford" >nul 2>&1
    if errorlevel 1 (
      echo [WARN] 作業フォルダの削除に失敗しました: "%REPO_ROOT%WOS_pack_work_Knapford"
    ) else (
      echo        削除: "%REPO_ROOT%WOS_pack_work_Knapford"
    )
  )
  if exist "%REPO_ROOT%WOS_pack_work_SODOR\" (
    rmdir /S /Q "%REPO_ROOT%WOS_pack_work_SODOR" >nul 2>&1
    if errorlevel 1 (
      echo [WARN] 作業フォルダの削除に失敗しました: "%REPO_ROOT%WOS_pack_work_SODOR"
    ) else (
      echo        削除: "%REPO_ROOT%WOS_pack_work_SODOR"
    )
  )
  exit /b 0

:STEP_MIGRATE_V010_BACKUP
  echo.
  echo [migrate] v0.1.0 の Backup を v0.1.1 の保存先へ移行 ...
  set "OLD_BACKUP_DIR=%REPO_ROOT%Backup"
  set "NEW_BACKUP_DIR=%LOCALAPPDATA%\WOS_JapaneseMOD\Backup"
  if not exist "%OLD_BACKUP_DIR%\" exit /b 0
  if not exist "%NEW_BACKUP_DIR%\" mkdir "%NEW_BACKUP_DIR%" >nul 2>&1
  call :_MIGRATE_ONE "%OLD_BACKUP_DIR%\TS2Prototype-WindowsNoEditor.pak" "%NEW_BACKUP_DIR%\TS2Prototype-WindowsNoEditor.pak"
  if errorlevel 1 exit /b 1
  call :_MIGRATE_ONE "%OLD_BACKUP_DIR%\TS2Prototype-WindowsNoEditor-Sodor-coredata.pak" "%NEW_BACKUP_DIR%\TS2Prototype-WindowsNoEditor-Sodor-coredata.pak"
  if errorlevel 1 exit /b 1
  call :_MIGRATE_ONE "%OLD_BACKUP_DIR%\TS2Prototype-WindowsNoEditor-James-coredata.pak" "%NEW_BACKUP_DIR%\TS2Prototype-WindowsNoEditor-James-coredata.pak"
  if errorlevel 1 exit /b 1
  rmdir "%OLD_BACKUP_DIR%" >nul 2>&1
  exit /b 0

:_MIGRATE_ONE
  set "SRC=%~1"
  set "DST=%~2"
  if exist "%SRC%" (
    if not exist "%DST%" (
      echo        移動: "%SRC%"
      echo          -> "%DST%"
      move /Y "%SRC%" "%DST%" >nul
      if errorlevel 1 (
        echo [ERROR] 移行（move）に失敗しました。
        echo        SRC: "%SRC%"
        echo        DST: "%DST%"
        exit /b 1
      )
    ) else (
      echo        既に新しいバックアップがあります。旧を保持します: "%DST%"
    )
  )
  exit /b 0
