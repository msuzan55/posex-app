@echo off
setlocal enableextensions
rem Always run PosEx with the app folder as working directory (required for data\ and DLLs).
cd /d "%~dp0"

set "SYS32=%SystemRoot%\System32"
if not exist "%SYS32%\vcruntime140.dll" goto need_redist
if not exist "%SYS32%\vcruntime140_1.dll" goto need_redist
if not exist "%SYS32%\msvcp140.dll" goto need_redist
goto launch

:need_redist
if exist "%~dp0vc_redist.x64.exe" (
  echo PosEx: installing Microsoft Visual C++ Runtime...
  "%~dp0vc_redist.x64.exe" /install /quiet /norestart
  if errorlevel 1 (
    echo PosEx: Visual C++ install failed. Run vc_redist.x64.exe manually as Administrator.
    pause
    exit /b 1
  )
  goto launch
)
echo.
echo PosEx cannot start because Microsoft Visual C++ Runtime is missing.
echo.
echo Fix: download and run:
echo   https://aka.ms/vs/17/release/vc_redist.x64.exe
echo.
pause
exit /b 1

:launch
start "" "%~dp0posex_app.exe"
