@echo off
setlocal enabledelayedexpansion
cd /d C:\Users\wodyd\Project\NewDolphin

for %%P in (Hub Lobby Stage1 Stage2 Stage3 Stage4 Stage5 Stage1Quiz) do (
  echo.
  echo ==============================
  echo [%%P] _port -> src + project.json
  echo ==============================

  rem 0) places/%%P 폴더 보장
  if not exist "places\%%P" mkdir "places\%%P"

  rem 1) _port\src 있으면 4개 서비스만 src로 복사
  if exist "places\%%P\_port\src" (
    if not exist "places\%%P\src" mkdir "places\%%P\src"

    for %%S in (ReplicatedStorage ServerScriptService StarterPlayer StarterGui) do (
      if exist "places\%%P\_port\src\%%S" (
        robocopy "places\%%P\_port\src\%%S" "places\%%P\src\%%S" /E >nul
        echo [OK] copied %%S
      ) else (
        echo [WARN] missing: places\%%P\_port\src\%%S
      )
    )

    rem 2) _port 삭제
    rmdir /S /Q "places\%%P\_port"
    echo [DEL] places\%%P\_port
  ) else (
    echo [SKIP] places\%%P\_port\src 없음 (변환 안 했으면 정상)
  )

  rem 3) project.json 생성(Workspace 마운트 없음) - 항상 덮어씀
  > "places\%%P\%%P.project.json" (
    echo {
    echo   "name": "%%P",
    echo   "tree": {
    echo     "$className": "DataModel",
    echo     "ReplicatedStorage": { "$path": "src/ReplicatedStorage" },
    echo     "ServerScriptService": { "$path": "src/ServerScriptService" },
    echo     "StarterPlayer": { "$path": "src/StarterPlayer" },
    echo     "StarterGui": { "$path": "src/StarterGui" }
    echo   }
    echo }
  )
  echo [OK] wrote places\%%P\%%P.project.json

  rem 4) src 확인 출력
  if exist "places\%%P\src" (
    echo [DIR] places\%%P\src
    dir "places\%%P\src"
  ) else (
    echo [WARN] places\%%P\src 없음
  )
)

echo.
echo All done.
endlocal
pause
