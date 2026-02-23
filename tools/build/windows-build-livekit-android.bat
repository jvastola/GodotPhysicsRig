@echo off
setlocal
powershell -ExecutionPolicy Bypass -File "%~dp0windows-build-livekit-android.ps1" %*
exit /b %ERRORLEVEL%

