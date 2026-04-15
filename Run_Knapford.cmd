@echo off
chcp 65001 >nul
setlocal EnableExtensions

rem Double-click launcher for PowerShell script.
rem This keeps complex logic out of .bat to avoid cmd.exe parsing pitfalls.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0WOS_JapaneseMOD_Knapford.ps1"
set "RC=%ERRORLEVEL%"
echo.
if "%RC%"=="0" (
  echo [OK] 終了しました。
) else (
  echo [FAILED] 終了コード: %RC%
)
pause
exit /b %RC%

