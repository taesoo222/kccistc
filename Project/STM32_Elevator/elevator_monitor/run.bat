@echo off
chcp 65001 > nul
cd /d "%~dp0"
where py > nul 2> nul
if %errorlevel%==0 (
    py main.py
) else (
    python main.py
)
if not %errorlevel%==0 (
    echo.
    echo 실행 중 문제가 생겼습니다. 위 메시지를 확인하세요.
    echo 패키지가 없다고 나오면 install.bat 을 먼저 실행하세요.
    pause
)
