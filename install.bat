@echo off
rem ============================================================================
rem  Hermes Agent 一键安装 (国内加速版)  — 双击运行即可
rem ============================================================================
setlocal
title Hermes Agent Installer (CN Mirror)
cd /d "%~dp0"

where powershell >nul 2>nul
if errorlevel 1 (
  echo [X] PowerShell not found. Windows 10/11 required.
  pause
  exit /b 1
)

echo.
echo ============================================================
echo   Hermes Agent  -  CN Mirror Installer
echo   GitHub proxy / npm / PyPI / Node / rg / ffmpeg / Chromium / cua-driver
echo ============================================================
echo.
echo Launching installer... (this window stays open when finished)
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-hermes-cn.ps1" %*
set "RC=%errorlevel%"

echo.
echo ------------------------------------------------------------
echo  Installer finished (exit code %RC%).
echo  Open a NEW PowerShell window, then type:  hermes
echo ------------------------------------------------------------
pause
endlocal
