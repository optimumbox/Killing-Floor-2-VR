@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Install KF2-VR for Epic Killing Floor 2
rem Finds the Epic Games (or Heroic) copy of Killing Floor 2 and copies the
rem KF2VR folder next to this file into its KFGame\BrewedPC folder.
rem Nothing is downloaded and nothing else is changed.

set "PACK=%~dp0KF2VR"
set "MANIFESTS=%ProgramData%\Epic\EpicGamesLauncher\Data\Manifests"
set "HEROIC=%APPDATA%\heroic\legendaryConfig\legendary\installed.json"
if defined KF2VR_TEST_MANIFESTS set "MANIFESTS=%KF2VR_TEST_MANIFESTS%"
if defined KF2VR_TEST_HEROIC set "HEROIC=%KF2VR_TEST_HEROIC%"

echo.
echo  KF2-VR pack for Epic Games players
echo  ==================================
echo.

for %%F in (KF2VR.u KF2VRNet.u KF2VRHands.upk) do if not exist "%PACK%\%%F" (
    echo  The KF2VR folder is missing next to this file.
    echo  Extract the whole ZIP first ^(right-click it, Extract All^), then run
    echo  this file from the extracted folder.
    goto :fail
)

set "GAME="
rem A folder passed in (drag and drop onto this file, or the elevated rerun).
if not "%~1"=="" call :try "%~1"
if defined GAME goto :found

rem Epic Games Launcher: every installed game has a manifest with its folder.
if exist "%MANIFESTS%\*.item" for %%M in ("%MANIFESTS%\*.item") do (
    if not defined GAME for /f usebackq^ tokens^=4^ delims^=^" %%L in (`type "%%~fM" ^| findstr /c:"\"InstallLocation\""`) do call :try "%%L"
)
if defined GAME goto :found

rem Heroic Games Launcher on Windows.
if exist "%HEROIC%" for /f usebackq^ tokens^=4^ delims^=^" %%L in (`type "%HEROIC%" ^| findstr /c:"\"install_path\""`) do (
    if not defined GAME call :try "%%L"
)
if defined GAME goto :found

rem Usual folders on every drive.
for %%D in (C D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
    if not defined GAME if exist "%%D:\" (
        call :try "%%D:\Program Files\Epic Games\KillingFloor2"
        call :try "%%D:\Epic Games\KillingFloor2"
        call :try "%%D:\Games\Epic Games\KillingFloor2"
        call :try "%%D:\Games\KillingFloor2"
    )
)
if defined GAME goto :found

echo  Could not find the Epic copy of Killing Floor 2 automatically.
echo.
echo  Open the Epic Games Launcher, go to Library, click the three dots on
echo  Killing Floor 2, choose Manage, and click the folder icon next to the
echo  install path. Then drag that KillingFloor2 folder into this window
echo  and press Enter.
echo.
set "ASKED="
set /p "ASKED=  Folder: "
if not defined ASKED goto :fail
set "ASKED=%ASKED:"=%"
call :try "%ASKED%"
if defined GAME goto :found
echo.
echo  That folder does not contain Killing Floor 2 ^(Binaries\Win64\KFGame.exe^).
goto :fail

:found
set "DEST=%GAME%\KFGame\BrewedPC\KF2VR"
echo  Found Killing Floor 2:
echo    %GAME%
echo.

tasklist /fi "imagename eq KFGame.exe" 2>nul | find /i "KFGame.exe" >nul && (
    echo  Killing Floor 2 is running. Close it, then press any key to continue.
    pause >nul
)

if not exist "%DEST%" mkdir "%DEST%" 2>nul
copy /y nul "%DEST%\.kf2vr-write-test" >nul 2>&1
if errorlevel 1 goto :elevate
del "%DEST%\.kf2vr-write-test" >nul 2>&1

echo  Copying KF2-VR files...
for %%F in (KF2VR.u KF2VRNet.u KF2VRHands.upk) do (
    copy /y "%PACK%\%%F" "%DEST%\%%F" >nul
    if errorlevel 1 (
        echo  Could not copy %%F. Make sure Killing Floor 2 is closed and try again.
        goto :fail
    )
)
for %%F in (KF2VR.u KF2VRNet.u KF2VRHands.upk) do call :same "%PACK%\%%F" "%DEST%\%%F" || (
    echo  %%F did not copy correctly. Try again.
    goto :fail
)

echo.
echo  Done. KF2-VR is installed in:
echo    %DEST%
echo.
echo  Start Killing Floor 2 from Epic and join the KF2-VR server from the
echo  server browser. When the mod updates, download the newest Epic pack
echo  and run this file again.
echo  To remove it, delete that KF2VR folder.
echo.
pause
exit /b 0

:elevate
if /i "%~2"=="elevated" (
    echo  Windows did not allow copying into the game folder, even as administrator.
    goto :fail
)
echo  The game folder needs administrator permission. Windows will ask you now.
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '\"%GAME%\" elevated' -Verb RunAs" >nul 2>&1
if errorlevel 1 (
    echo  Administrator permission was not given, so nothing was copied.
    goto :fail
)
exit /b 0

:try
rem Accepts a folder written with / or \\ separators and keeps it only if it
rem holds Killing Floor 2.
if defined GAME exit /b 0
set "CAND=%~1"
set "CAND=%CAND:/=\%"
set "CAND=%CAND:\\=\%"
if "%CAND:~-1%"=="\" set "CAND=%CAND:~0,-1%"
if exist "%CAND%\Binaries\Win64\KFGame.exe" if exist "%CAND%\KFGame\BrewedPC\" set "GAME=%CAND%"
exit /b 0

:same
if not exist "%~2" exit /b 1
if not "%~z1"=="%~z2" exit /b 1
exit /b 0

:fail
echo.
pause
exit /b 1
