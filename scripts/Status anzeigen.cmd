@echo off
REM ============================================================
REM  Status anzeigen - aendert NICHTS am PC
REM  Prueft: Version, Update-Sperre, Spicetify-Patch, Waechter
REM  Kein Admin noetig.
REM
REM  Aus dem ZIP gestartet wird das Paket automatisch nach
REM  %LOCALAPPDATA%\SpotifySetup kopiert.
REM ============================================================
setlocal EnableExtensions EnableDelayedExpansion
title Spotify Status
color 0E

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
    if not exist "%ZIEL%spotify-alles-einrichten.ps1" goto FEHLT
    call "%ZIEL%\Status anzeigen.cmd" geh-weiter
    exit /b %ERRORLEVEL%
)

if "%~1"=="geh-weiter" goto START

:START
if not exist "%DIR%spotify-alles-einrichten.ps1" goto FEHLT

echo.
echo  ============================================================
echo   Spotify Status
echo  ============================================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%DIR%spotify-alles-einrichten.ps1" -Check

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