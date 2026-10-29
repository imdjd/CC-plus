@echo off
setlocal
set "SCRIPT=%~dp0CCPlusTool.ps1"

if not exist "%SCRIPT%" (
    echo Could not find CCPlusTool.ps1 next to this launcher.
    pause
    exit /b 1
)

"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -STA -File "%SCRIPT%"

if errorlevel 1 (
    echo.
    echo The app exited with an error.
    pause
)
