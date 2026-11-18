@echo off
setlocal
cd /d "%~dp0"
where curl.exe >nul 2>&1 || goto fail
if not exist ".venv\Scripts\python.exe" (
 py -3 -m venv .venv || goto fail
)
.venv\Scripts\python.exe -m pip install "PySide6>=6.7,<7" || goto fail
.venv\Scripts\python.exe -m compileall -q v8 || goto fail
.venv\Scripts\python.exe -m v8.control_center
if errorlevel 1 goto fail
exit /b 0
:fail
echo Setup failed. Install Python 3.11 or 3.12 and ensure curl.exe is available.
pause
exit /b 1
