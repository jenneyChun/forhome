@echo off
chcp 65001 > nul
cd /d "%~dp0\.."
echo.
echo ForHome PostgreSQL API server starting...
echo Open http://localhost:8080 after startup.
echo If login fails, set PGPASSWORD in data\db.env.ps1 and run: npm run setup:db
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1" -Port 8080
pause
