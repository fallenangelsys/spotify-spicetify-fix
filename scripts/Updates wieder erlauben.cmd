@echo off
REM ============================================================
REM  Updates wieder erlauben - macht ALLES rueckgaengig
REM  Entfernt Sperre, Dienst-Blockade, Dateisperre und Waechter.
REM  Muss als Administrator laufen (fragt selbst nach).
REM ============================================================
setlocal EnableExtensions EnableDelayedExpansion
title Spotify Updates wieder erlauben
color 0C

set "DIR=%~dp0"
set "ZIEL=%LOCALAPPDATA%\SpotifySetup"

REM ZIP-Mount erkennen: der eindeutige Marker ".zip." im Pfad.
REM Ein normal entpackter Ordner enthaelt diese Zeichenfolge nicht.
set "AUSZIP=0"
echo %DIR%| findstr /i /c:".zip." >nul && set "AUSZIP=1"

if "%AUSZIP%"=="1" (
    if not exist "%ZIEL%" mkdir "%ZIEL%" >nul 2>&1
    copy /y "%DIR%*.cmd" "%ZIEL%\" >nul 2>&1
    copy /y "%DIR%*.ps1" "%ZIEL%\" >nul 2>&1
    copy /y "%DIR%*.txt" "%ZIEL%\" >nul 2>&1
    if not exist "%ZIEL%spotify-updates-freigeben.ps1" goto FEHLT
    call "%ZIEL%\Updates wieder erlauben.cmd" geh-weiter
    exit /b %ERRORLEVEL%
)

if "%~1"=="geh-weiter" goto START

:START
if not exist "%DIR%spotify-updates-freigeben.ps1" goto FEHLT

echo.
echo  ============================================================
echo   Update-Sperre wird vollstaendig aufgehoben
echo   Spotify kann sich danach wieder aktualisieren.
echo  ============================================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%DIR%spotify-updates-freigeben.ps1"

echo.
pause
exit /b 0

:FEHLT
echo.
echo  FEHLER: Skript-Datei nicht gefunden.
echo  Bitte den ZIP-Ordner zuerst vollstaendig entpacken.
echo.
pause
exit /b 1