@echo off
setlocal
title Fix display after MUX switch
cd /d "%~dp0"

set "PS1=%~dp0fix-display-after-mux-switch.ps1"

if not exist "%PS1%" (
    echo.
    echo   fix-display-after-mux-switch.ps1 was not found next to this file.
    echo   Keep RUN-FIX.cmd in the same folder as the .ps1 and try again.
    echo.
    pause
    exit /b 1
)

echo.
echo   Opening an administrator window...
echo   Click Yes on the Windows prompt.
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Start-Process -FilePath powershell.exe -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-NoExit','-File','%PS1%')"

if errorlevel 1 (
    echo.
    echo   Could not open the administrator window.
    echo   UAC was probably cancelled.
    echo.
    echo   Try instead: right-click RUN-FIX.cmd, then "Run as administrator".
    echo.
    pause
)

exit /b 0
