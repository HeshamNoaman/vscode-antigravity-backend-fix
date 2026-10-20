@echo off
echo Running Antigravity Backend Fixer...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0fix.ps1" %*
pause
