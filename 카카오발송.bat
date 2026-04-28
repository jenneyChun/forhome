@echo off
chcp 65001 > nul
echo.
echo  카카오톡 일일 요약 발송 중...
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0send_kakao.ps1"
echo.
if %ERRORLEVEL% == 0 (
    echo  카카오톡 발송 완료! 나에게 보낸 메시지함을 확인하세요.
) else (
    echo  발송 실패. 오류 내용을 확인해주세요.
)
echo.
pause
