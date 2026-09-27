@echo off
setlocal EnableDelayedExpansion

:: =====================================================================
::  ONE-CLICK DEPLOY / INCREMENTAL UPDATE SCRIPT
:: =====================================================================
::  First run  : clones the repository (full download, one-time cost).
::  Later runs : runs "git pull"-equivalent so ONLY new/changed/missing
::                files are transferred, not the entire ~6,000-file tree.
::
::  Falls back to a full zip download (curl + tar) automatically if
::  Git for Windows is not installed on the machine.
:: =====================================================================

:: --------------------- USER CONFIGURATION ----------------------------
:: >>> EDIT THESE TWO VALUES <<<
set "GITHUB_USER=mirraiee"
set "GITHUB_REPO=pat-pummel-party"

:: >>> EDIT THIS to match your actual executable file name <<<
set "MAIN_EXECUTABLE=PummelParty.exe"

:: >>> Process name to check for before updating (usually the same as
:: MAIN_EXECUTABLE, but change this if the game launches under a
:: different process name, e.g. a launcher stub vs. the real game exe).
set "GAME_EXE=PummelParty.exe"

:: Branch to track
set "BRANCH=main"
:: -----------------------------------------------------------------------

set "TARGET_DIR=%~dp0"
set "REPO_URL=https://github.com/%GITHUB_USER%/%GITHUB_REPO%.git"
set "ZIP_URL=https://github.com/%GITHUB_USER%/%GITHUB_REPO%/archive/refs/heads/%BRANCH%.zip"

:: --------------------- AUTO LONG-PATH FIX (no manual commands needed) --
:: Deeply nested asset paths can exceed Windows' old 260-character path
:: limit, which shows up as the clone/checkout stalling or failing with
:: "Filename too long". This fixes it automatically, once, per machine.
if "%~1"=="/longpath-elevated" (
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v LongPathsEnabled /t REG_DWORD /d 1 /f >nul 2>&1
    exit /b
)

git config --global core.longpaths true >nul 2>&1

reg query "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v LongPathsEnabled 2>nul | find "0x1" >nul
if errorlevel 1 (
    echo =====================================================================
    echo   One-time setup needed: enabling Windows long file path support.
    echo   A Windows permission prompt will appear next - click "Yes" to allow it.
    echo =====================================================================
    echo.
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '/longpath-elevated' -Verb RunAs -Wait"
    echo Setup complete - continuing automatically...
    echo.
)
:: -------------------------------------------------------------------------

cd /d "%TARGET_DIR%"

:: --------------------- YOUR SIGNATURE / ASCII ART -----------------------
:: Keep art to 80 columns wide max - that's the one width guaranteed safe
:: on every Windows machine (classic cmd default), regardless of terminal
:: app or screen size. Forcing a resize via "mode con" was removed - it
:: only works in the legacy console host, not Windows Terminal (the
:: default on most Windows 11 PCs), so it did more harm than good.

echo.
echo                                    :-=
echo                                 -+##@=
echo                              :+#%%####
echo                            .+%%%%######
echo                  .        =%%########%%-
echo                          *%%#########+*:
echo                         +%%#########*:-+=
echo                        .%%######*###=-+*#*.         ..
echo                        +%%#####=#%%+=+#####%%-         .
echo                        ###*=*=##=-#%%*#####%%*
echo                       :*+***-:+-:*++*######%%#+.   .::---====+===---:.
echo                       -%%#*#=:--.:-+##########***###%%%%%%%%%%#######*##%%%%%%#+
echo                      :*%%+:=+++#+*=*#*#######+++#%%#######**+***+*#%%*+:.
echo                   :==+%%*+++===+%%#***#####*++++*########***+**#%%#+:
echo         .       :=+=-*+==+-----+==+*##**++++*#%%########****##*-
echo       .        .*--=-=*=-=---=--=*#++++++**##########**+*##+.
echo                +==+-=*+=---=-::-==#++**############*++*#%%-
echo             .-#**##+##====-=======+%%############**++#%%#===
echo           -*#**#######*#*#==#%%################*++*##*-...+=      .
echo         -*#****#####*+=+##*################*++*###=:.-.:-:*:     :.
echo       .*#**####***++=--:=+***##########*****##*#*..::-:::=:*    .:.
echo       ##+*#####***+-::-==****######*****###*++-:*-:-.-.:.--=-    .
echo       %%*+*#######**#=+*#*##%%#******####*+=-:.-#-**=-:=.::.=:*.
echo       -##**********+=**=.. -#*#####+++-=-:--+=+**=#:=*=.:.=-:+.
echo         =*########***#*    -%%#*+==-=++=..--#*=-*+.+-**#+.:-+::=-.
echo           .-+**##*%%#*##.   +#:..    . .    -=:::-==+#+=%%=:-*#=-=+++=.
echo         .       :=+==+==.  --+..:-=-           .=+#*+*%%**:-++= .:::.
echo        ..    :=**+++*-.:=::- *%%*=-:            :-+*+==*+#-=+-*-
echo         .    .:: .*=#.:.-=. .*%%#=---.....:::-===-+*==++=***==-*+.
echo                 :+--%%+---..-*%%##%%%%:=-.-***#*+==--*-:-+++=**=++=+*-.
echo               .=+::=%%**++***%%%%%%%%%%*:=  :-  .-=.:+-+=:-*==-== .-==+***=
echo           .:=++=-==--*+*****++=++++:-+#+===-+*==-*#+:*===+-       ...
echo           :==-:::.   .=====------=*+%%%%++*++++#%%=-*=+=*===+.
echo                    .-========----=%%*##*=+=+=+#%%*#*-=#++===
echo                  :-++==++========+%%##%%%%##***%%@@#%%%%*=+=+=+.
echo                  ................-=========++-=====.. ..
echo             deploy script - by mirraiee
echo.
:: -------------------------------------------------------------------------

:: --------------------- GAME-RUNNING CHECK (before anything destructive) --
call :check_game_running
:: -------------------------------------------------------------------------

:: Number of automatic retry attempts if a download stalls or fails
:: (used by both the git path and the zip-fallback path below).
set "MAX_RETRIES=3"

:: Git connection stability settings, applied per-command via -c so they
:: don't alter the machine's global git config:
::  - http.postBuffer: bigger buffer, avoids failures on large transfers
::  - http.lowSpeedLimit / http.lowSpeedTime: aborts a stalled/dead
::    connection after 60s below 1 KB/s, instead of hanging forever
set "GIT_STABILITY_OPTS=-c http.postBuffer=524288000 -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=60"

echo =====================================================================
echo   Deploying %GITHUB_USER%/%GITHUB_REPO% (%BRANCH%)
echo   Target directory: %TARGET_DIR%
echo =====================================================================
echo.

:: --------------------- CHECK FOR GIT ---------------------------------
where git >nul 2>&1
if errorlevel 1 (
    echo Git not found on this machine — falling back to full zip download.
    goto :zip_fallback
)

:: --------------------- GIT PATH ---------------------------------------
if exist "%TARGET_DIR%.git" (
    echo [1/3] Existing repo detected. Pulling only changed files...

    set "ATTEMPT=0"
    :retry_fetch
    set /a ATTEMPT+=1
    git %GIT_STABILITY_OPTS% fetch origin "%BRANCH%" --progress
    if errorlevel 1 (
        if !ATTEMPT! lss %MAX_RETRIES% (
            echo       Fetch attempt !ATTEMPT! failed or stalled - retrying...
            timeout /t 5 /nobreak >nul
            goto :retry_fetch
        )
        goto :git_error
    )

    git reset --hard "origin/%BRANCH%"
    if errorlevel 1 goto :git_error

    :: -e excludes this script itself so "git clean" never deletes the
    :: very file being run to perform the update.
    git clean -fd -e "%~nx0"
    echo       Update complete ^(incremental^).
) else (
    echo [1/3] No local repo found. Performing one-time full clone...
    echo       ^(This first run downloads everything; later runs will be incremental.^)

    set "TEMP_CLONE=%TARGET_DIR%_clone_tmp"
    if exist "!TEMP_CLONE!" rmdir /s /q "!TEMP_CLONE!"

    set "ATTEMPT=0"
    :retry_clone
    set /a ATTEMPT+=1
    if exist "!TEMP_CLONE!" rmdir /s /q "!TEMP_CLONE!"
    git %GIT_STABILITY_OPTS% clone --branch "%BRANCH%" --progress "%REPO_URL%" "!TEMP_CLONE!"
    if errorlevel 1 (
        if !ATTEMPT! lss %MAX_RETRIES% (
            echo       Clone attempt !ATTEMPT! failed or stalled - retrying...
            timeout /t 5 /nobreak >nul
            goto :retry_clone
        )
        goto :git_error
    )

    robocopy "!TEMP_CLONE!" "%TARGET_DIR%." /E /MOVE
    if errorlevel 8 (
        echo.
        echo ERROR: File copy from temporary clone failed. Leaving
        echo        "!TEMP_CLONE!" in place so no data is lost — you can
        echo        inspect it manually, then delete it and re-run this script.
        goto :error_exit
    )
    rmdir /s /q "!TEMP_CLONE!" >nul 2>&1

    echo       Initial clone complete.
)

echo.

goto :verify_and_launch

:git_error
echo.
echo ERROR: Git operation failed. Check your network connection and that
echo        %GITHUB_USER%/%GITHUB_REPO% ^(branch "%BRANCH%"^) is correct
echo        and accessible.
goto :error_exit

:: --------------------- ZIP FALLBACK (full download every time) --------
:zip_fallback
echo [1/3] Downloading full archive ^(no git available^)...
set "ARCHIVE_PATH=%TARGET_DIR%repo_update.zip"

set "ATTEMPT=0"
:retry_curl
set /a ATTEMPT+=1
if exist "%ARCHIVE_PATH%" del /f /q "%ARCHIVE_PATH%" >nul 2>&1
:: --connect-timeout / --max-time / --retry give curl its own stall
:: protection so a dead connection fails cleanly instead of hanging.
curl -L --fail --progress-bar --connect-timeout 15 --max-time 1800 --retry 2 -o "%ARCHIVE_PATH%" "%ZIP_URL%"

if not exist "%ARCHIVE_PATH%" (
    if !ATTEMPT! lss %MAX_RETRIES% (
        echo       Download attempt !ATTEMPT! failed - retrying...
        timeout /t 5 /nobreak >nul
        goto :retry_curl
    )
    echo ERROR: Download failed. Check the URL and your connection.
    goto :error_exit
)

echo [2/3] Extracting...
tar -xf "%ARCHIVE_PATH%" -C "%TARGET_DIR%." --strip-components=1
if errorlevel 1 (
    echo ERROR: Extraction failed.
    goto :error_exit
)
del /f /q "%ARCHIVE_PATH%" >nul 2>&1
echo       Done. ^(Tip: install Git for Windows so future runs only
echo       download changed files instead of the full archive.^)
echo.

:: --------------------- VERIFY -------------------------------------------
:verify_and_launch
echo [3/3] Verifying main executable...
if not exist "%TARGET_DIR%%MAIN_EXECUTABLE%" (
    echo.
    echo ERROR: Expected executable "%MAIN_EXECUTABLE%" was not found in
    echo        %TARGET_DIR%
    echo        Update the MAIN_EXECUTABLE variable at the top of this script
    echo        if the file name or path has changed.
    goto :error_exit
)

echo       Found "%MAIN_EXECUTABLE%".

echo =====================================================================
echo   Deployment complete.
echo =====================================================================
echo.
pause
goto :eof

:error_exit
echo.
echo Deployment did not complete successfully.
pause
exit /b 1

:: =====================================================================
::  SUBROUTINE: check_game_running
::  Blocks here (with Retry/Cancel) until the game process is not
::  running. Called before any git clone/reset/clean happens.
:: =====================================================================
:check_game_running
tasklist /FI "IMAGENAME eq %GAME_EXE%" 2>nul | find /I "%GAME_EXE%" >nul
if not errorlevel 1 (
    cls
    echo ============================================
    echo           GAME IS CURRENTLY RUNNING
    echo ============================================
    echo.
    echo Please close the game before updating.
    echo.
    echo [R] Retry
    echo [C] Cancel
    echo.
    set "GAME_CHOICE="
    set /p "GAME_CHOICE=Choose an option: "
    if /i "!GAME_CHOICE!"=="R" goto :check_game_running
    if /i "!GAME_CHOICE!"=="C" (
        echo.
        echo Update cancelled. No changes were made.
        pause
        exit /b 0
    )
    goto :check_game_running
)
exit /b 0
