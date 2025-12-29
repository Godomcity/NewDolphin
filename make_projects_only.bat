@echo off
setlocal
cd /d C:\Users\wodyd\Project\NewDolphin

for %%P in (Hub Lobby Stage1 Stage2 Stage3 Stage4 Stage5 Stage1Quiz) do (
  if not exist "places\%%P" mkdir "places\%%P"

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

  echo [OK] places\%%P\%%P.project.json
)

echo All done.
endlocal
pause
