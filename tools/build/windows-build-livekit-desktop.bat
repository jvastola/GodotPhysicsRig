@echo off
setlocal
powershell -ExecutionPolicy Bypass -File "%~dp0windows-build-livekit-desktop.ps1" %*
exit /b %ERRORLEVEL%

