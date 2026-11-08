@echo off
setlocal
cd /d "%~dp0"

REM 1. Prefer the project Node version installed by nvm-windows.
if defined NVM_HOME if exist "%NVM_HOME%\v24.18.0\node.exe" (
  set "PATH=%NVM_HOME%\v24.18.0;%PATH%"
)

REM Keep the version change inside this window so other projects keep their Node version.

REM 2. Check the runtime before starting the map.
where node.exe >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Node.js was not found. Install Node.js and try again.
  pause
  exit /b 1
)

where npm.cmd >nul 2>nul
if errorlevel 1 (
  echo [ERROR] npm was not found. Reinstall Node.js and try again.
  pause
  exit /b 1
)

node.exe -e "const [major, minor] = process.versions.node.split('.').map(Number); process.exit((major === 20 && minor >= 19) || (major === 22 && minor >= 12) || major > 22 ? 0 : 1)"
if errorlevel 1 (
  echo [ERROR] Vite 8 requires Node.js 20.19+ or 22.12+.
  echo [ERROR] Install Node.js 24.18.0 with nvm-windows and try again.
  pause
  exit /b 1
)

REM 3. Install the locked dependencies only when they are missing.
if not exist "node_modules\" (
  echo Installing dependencies...
  call npm.cmd ci
  if errorlevel 1 (
    echo.
    echo [ERROR] Dependency installation failed.
    pause
    exit /b 1
  )
)

REM 4. Start Vite and open the code map in the default browser.
echo Starting the code map...
echo Close this window or press Ctrl+C to stop the server.
call npm.cmd run dev -- --open
if errorlevel 1 (
  echo.
  echo [ERROR] The code map failed to start.
  pause
  exit /b 1
)

endlocal
