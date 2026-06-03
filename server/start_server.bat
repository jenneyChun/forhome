@echo off
chcp 65001 > nul
cd /d "%~dp0"
echo.
echo ForHome static test server starting...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1" -Port 8080
pause
