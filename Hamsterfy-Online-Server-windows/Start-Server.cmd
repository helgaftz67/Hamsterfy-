@echo off
setlocal
cd /d "%~dp0"
if not exist "music" mkdir "music"
"%~dp0dartaotruntime.exe" "%~dp0server.aot" --music "%~dp0music" %*
pause
