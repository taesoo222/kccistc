@echo off
chcp 65001 > nul
cd /d "%~dp0"
echo ==============================================
echo   ELV Monitor : 필요한 패키지 설치
echo   (pyserial, customtkinter)
echo ==============================================
where py > nul 2> nul
if %errorlevel%==0 (
    py -m pip install pyserial customtkinter
) else (
    python -m pip install pyserial customtkinter
)
echo.
echo 끝. 위에 Successfully installed 또는 already satisfied 가 보이면 성공
pause
