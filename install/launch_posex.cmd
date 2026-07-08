@echo off
rem Always run PosEx with the app folder as working directory (required for data\ and DLLs).
cd /d "%~dp0"
start "" "%~dp0posex_app.exe"
