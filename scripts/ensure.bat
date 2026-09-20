@echo off
cd /d "%~dp0.."
pwsh -NoProfile -File "%~dp0ensure.ps1" %*
exit /b %ERRORLEVEL%
