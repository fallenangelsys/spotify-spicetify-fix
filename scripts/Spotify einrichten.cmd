@echo off
REM ============================================================
REM  Spotify Komplett-Einrichtung
REM  Diese Datei einfach DOPPELKLICKEN.
REM
REM  WICHTIG: Den ZIP-Ordner zuerst vollstaendig entpacken
REM  (Rechtsklick > In Ordner entpacken). Wird die Datei direkt
REM  aus dem ZIP gestartet, kopiert sie sich selbst automatisch
REM  an einen festen Platz und laeuft von dort weiter.
REM ============================================================
setlocal EnableExtensions EnableDelayedExpansion
title Spotify Komplett-Einrichtung
color 0B

set "SEL=%~f0"
set "DIR=%~dp0"
set "ZIEL=%LOCALAPPDATA%\SpotifySetup"

REM --- Lauf aus einem ZIP-Mount erkennen (TEMP + .zip. im Pfad) ---
REM ZIP-Mount erkennen: der eindeutige Marker ".zip." im Pfad.
REM Ein normal entpackter Ordner enthaelt diese Zeichenfolge nicht.
set "AUSZIP=0"
echo %DIR%| findstr /i /c:".zip." >nul && set "AUSZIP=1"

if "%AUSZIP%"=="1" (
    echo.
    echo  Starte aus einem ZIP heraus - Paket wird kopiert nach
    echo  %ZIEL%
    echo.
    if not exist "%ZIEL%" mkdir "%ZIEL%" >nul 2>&1
    copy /y "%DIR%*.cmd" "%ZIEL%\" >nul 2>&1
    copy /y "%DIR%*.ps1" "%ZIEL%\" >nul 2>&1
    copy /y "%DIR%*.txt" "%ZIEL%\" >nul 2>&1
    if not exist "%ZIEL%spotify-alles-einrichten.ps1" goto FEHLT
    call "%ZIEL%\Spotify einrichten.cmd" geh-weiter
    exit /b %ERRORLEVEL%
)

if "%~1"=="geh-weiter" goto START

:START
if not exist "%DIR%spotify-alles-einrichten.ps1" goto FEHLT

echo.
echo  ============================================================
echo   Spotify wird eingerichtet
echo   Das kann 5 bis 15 Minuten dauern.
echo  ============================================================
echo.

REM ---------------------------------------------------------------
REM  Phase 1: Spotify installieren - BEWUSST OHNE Administratorrechte.
REM  winget verweigert den Administratorkontext, deshalb darf dieser
REM  Schritt nicht elevated laufen.
REM ---------------------------------------------------------------
echo  Phase 1 von 2: Spotify wird installiert ...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%DIR%spotify-alles-einrichten.ps1" -InstallOnly
set "RC1=%ERRORLEVEL%"

if not "%RC1%"=="0" (
    echo.
    echo  ============================================================
    echo   Spotify konnte nicht installiert werden.
    echo   Bitte die Meldung oben lesen und die Datei erneut
    echo   starten. Spotify muss VOR der Update-Sperre installiert sein.
    echo  ============================================================
    echo.
    pause
    exit /b 1
)

REM ---------------------------------------------------------------
REM  Phase 2: Sperre, Spicetify und Waechter - braucht Administratorrechte.
REM  Das Skript fragt die Rechte selbst an.
REM ---------------------------------------------------------------
echo.
echo  Phase 2 von 2: Update-Sperre und Spicetify werden gesetzt ...
echo  (Es folgt eine Administrator-Abfrage - bitte "Ja" klicken.)
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%DIR%spotify-alles-einrichten.ps1" -SetupOnly
set "RC=%ERRORLEVEL%"

echo.
if "%RC%"=="0" (
  echo  ============================================================
  echo   FERTIG - alles eingerichtet.
  echo  ============================================================
) else (
  echo  ============================================================
  echo   Fertig, aber es gibt offene Punkte - siehe Meldungen oben.
  echo  ============================================================
)
echo.
echo  Pruefen jederzeit mit:  "Status anzeigen.cmd"
echo.
pause
exit /b %RC%

:FEHLT
echo.
echo  ============================================================
echo   FEHLER: Die Skript-Datei wurde nicht gefunden.
echo  ============================================================
echo.
echo   Der Ordner ist unvollstaendig oder wurde nicht entpackt.
echo.
echo   Bitte so vorgehen:
echo     1. Rechtsklick auf die ZIP-Datei
echo     2. "In Ordner entpacken" / "Hier entpacken"
echo     3. Den entpackten Ordner oeffnen
echo     4. "Spotify einrichten.cmd" DOPPELKLICKEN
echo.
pause
exit /b 1