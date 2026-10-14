@echo off
setlocal
cd /d "%~dp0"
py -3 -c "import win32com.client; import playwright; import psutil; import PIL; import tkinter" >nul 2>&1
if errorlevel 1 (
 py -3 -m pip install -r requirements.txt
 if errorlevel 1 (
  pause
  exit /b 1
 )
)
echo [PC BUILD] PPT_AUTO_HUD3
echo [PC FOLDER] %~dp0
py -3 server.py
pause
