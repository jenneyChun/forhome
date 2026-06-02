@echo off
chcp 65001 > nul
cd /d "%~dp0"
echo.
echo Sending Kakao daily summary...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0send_kakao.ps1"
echo.
if %ERRORLEVEL% == 0 (
    echo Kakao send complete.
) else (
    echo Kakao send failed. Check the error above.
)
echo.
pause
