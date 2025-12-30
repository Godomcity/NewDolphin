@echo off
setlocal enabledelayedexpansion
cd /d C:\Users\wodyd\Project\NewDolphin

set "ROJO=%USERPROFILE%\.rokit\bin\rojo.exe"

rem 포트 배정(원하면 숫자만 바꿔도 됨)
set "PORT_Hub=34870"
set "PORT_Lobby=34871"
set "PORT_Stage1=34872"
set "PORT_Stage2=34873"
set "PORT_Stage3=34874"
set "PORT_Stage4=34875"
set "PORT_Stage5=34876"

:menu
echo.
echo =========================================
echo   Rojo Multi Serve Launcher (ports fixed)
echo =========================================
echo  1) Start Hub    (port %PORT_Hub%)
echo  2) Start Lobby  (port %PORT_Lobby%)
echo  3) Start Stage1 (port %PORT_Stage1%)
echo  4) Start Stage2 (port %PORT_Stage2%)
echo  5) Start Stage3 (port %PORT_Stage3%)
echo  6) Start Stage4 (port %PORT_Stage4%)
echo  7) Start Stage5 (port %PORT_Stage5%)
echo  8) Start ALL (7 windows)
echo  9) Stop ALL (kills all rojo.exe)  [주의]
echo  0) Exit
echo.
set /p CHOICE=Select (0-9): 

if "%CHOICE%"=="1" call :start Hub %PORT_Hub% & goto :menu
if "%CHOICE%"=="2" call :start Lobby %PORT_Lobby% & goto :menu
if "%CHOICE%"=="3" call :start Stage1 %PORT_Stage1% & goto :menu
if "%CHOICE%"=="4" call :start Stage2 %PORT_Stage2% & goto :menu
if "%CHOICE%"=="5" call :start Stage3 %PORT_Stage3% & goto :menu
if "%CHOICE%"=="6" call :start Stage4 %PORT_Stage4% & goto :menu
if "%CHOICE%"=="7" call :start Stage5 %PORT_Stage5% & goto :menu

if "%CHOICE%"=="8" (
  call :start Hub %PORT_Hub%
  call :start Lobby %PORT_Lobby%
  call :start Stage1 %PORT_Stage1%
  call :start Stage2 %PORT_Stage2%
  call :start Stage3 %PORT_Stage3%
  call :start Stage4 %PORT_Stage4%
  call :start Stage5 %PORT_Stage5%
  goto :menu
)

if "%CHOICE%"=="9" (
  echo [WARN] 모든 rojo.exe 프로세스를 종료합니다.
  taskkill /IM rojo.exe /F >nul 2>&1
  echo [DONE] stopped.
  goto :menu
)

if "%CHOICE%"=="0" goto :eof

echo [ERROR] Invalid choice.
goto :menu

:start
set "PLACE=%~1"
set "PORT=%~2"
set "PROJ=places\%PLACE%\%PLACE%.project.json"

if not exist "%ROJO%" (
  echo [ERROR] Rojo not found: %ROJO%
  exit /b 1
)

if not exist "%PROJ%" (
  echo [ERROR] Project file not found: %PROJ%
  exit /b 1
)

echo [RUN] %PLACE% on port %PORT%
start "Rojo-%PLACE%:%PORT%" cmd /k ""%ROJO%" serve --port %PORT% "%PROJ%""
exit /b 0
