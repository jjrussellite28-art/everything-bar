@echo off
rem Double-click to update Everything Bar (get code, build, make installer, install).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0update.ps1"
echo.
pause
