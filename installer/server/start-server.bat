@echo off
rem Starts the Procedural World dedicated server (Windows). Settings: server.cfg beside
rem this file (made on first start). Flags are passed on, e.g. --port=24600
cd /d "%~dp0"
ProceduralWorldServer.console.exe --headless -- --server %*
pause
