@echo off
chcp 65001 >nul
setlocal EnableExtensions

rem Double-click launcher for PowerShell script.
rem This keeps complex logic out of .bat to avoid cmd.exe parsing pitfalls.

set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%PS_EXE%" goto :HAVE_PS
set "PS_EXE=%SystemRoot%\System32\pwsh.exe"
if exist "%PS_EXE%" goto :HAVE_PS
set "PS_EXE=powershell"
where /q "%PS_EXE%" && goto :HAVE_PS
set "PS_EXE=pwsh"
where /q "%PS_EXE%" && goto :HAVE_PS
echo [ERROR] PowerShell が見つかりません（powershell.exe / pwsh.exe）。
echo        Windows PowerShell または PowerShell 7 をインストールしてください。
pause
exit /b 1

:HAVE_PS
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0WOS_JapaneseMOD_Knapford.ps1"
set "RC=%ERRORLEVEL%"
echo.
if "%RC%"=="0" (
  echo [OK] 終了しました。
) else (
  echo [FAILED] 終了コード: %RC%
)
pause
exit /b %RC%

