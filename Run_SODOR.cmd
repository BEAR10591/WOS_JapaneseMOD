@echo off
chcp 65001 >nul
setlocal EnableExtensions

rem Double-click launcher for PowerShell script.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0WOS_JapaneseMOD_SODOR.ps1"
set "RC=%ERRORLEVEL%"
echo.
if "%RC%"=="0" (
  echo [OK] 終了しました。
) else (
  echo [FAILED] 終了コード: %RC%
)
pause
exit /b %RC%

