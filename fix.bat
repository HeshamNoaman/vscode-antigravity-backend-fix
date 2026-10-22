@echo off
setlocal
echo ==========================================================
echo    VS Code Google Antigravity Backend Re-download Fixer   
echo ==========================================================
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0fix.ps1" %*
pause
