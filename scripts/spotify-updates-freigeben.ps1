# ============================================================
#  Spotify Update-Freigabe  (als Administrator ausfuehren)
#  Nimmt ALLES zurueck, was die Sperre gesetzt hat:
#    1. Windows Installer Auto-Updates wieder aktivieren
#    2. Update-Dienste wiedereinschalten
#    3. Spotify-interne Update-Schalter entfernen
#    4. Ordner-Sperre aufheben (Loesch-Recht zurueckgeben)
#    5. Dateisperre auf den EXE-Dateien aufheben
#    6. Selbstheilungs-Waechter entfernen
# ============================================================
$ErrorActionPreference = 'Continue'

# ------------------------------------------------------------
# 0) Administrator-Pruefung mit Auto-Elevation
# ------------------------------------------------------------
function Test-Admin {
    $p = New-Object System.Security.Principal.WindowsPrincipal(
            [System.Security.Principal.WindowsIdentity]::GetCurrent())
    $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Test-Admin)) {
    Write-Host "Administratorrechte fehlen - ich bitte den Benutzer einmalig." -ForegroundColor Yellow
    $self = $MyInvocation.MyCommand.Path
    try {
        Start-Process -FilePath 'powershell' -Verb RunAs -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $self)
        )
        exit 0
    } catch {
        Write-Host "FEHLER: Elevation fehlgeschlagen - bitte Rechtsklick > Als Administrator." -ForegroundColor Red
        exit 1
    }
}

$spot = Join-Path $env:APPDATA 'Spotify'

# ------------------------------------------------------------
# 1) Registry: Installer Auto-Updates aktivieren
# ------------------------------------------------------------
Write-Host "1) Windows Installer Auto-Updates werden wieder aktiviert ..." -ForegroundColor Cyan
foreach ($k in 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Installer',
               'HKCU:\SOFTWARE\Policies\Microsoft\Windows\Installer') {
    New-Item -Path $k -Force | Out-Null
    Set-ItemProperty -Path $k -Name 'DisableAutomaticUpdates' -Value 0 -Type DWord
    Write-Host ("   $k = 0") -ForegroundColor DarkGray
}

# ------------------------------------------------------------
# 2) Update-Dienste wieder einschalten
# ------------------------------------------------------------
Write-Host "2) Update-Dienste werden wieder aktiviert ..." -ForegroundColor Cyan
foreach ($svc in 'wuauserv', 'UsoSvc') {
    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if (-not $s) { continue }
    try {
        Set-Service -Name $svc -StartupType Manual -ErrorAction Stop
        Start-Service -Name $svc -ErrorAction SilentlyContinue
        Write-Host "   $svc = Manual, laeuft" -ForegroundColor DarkGray
    } catch {
        Write-Host "   $svc konnte nicht reaktiviert werden: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# ------------------------------------------------------------
# 3) Spotify-interne Schalter entfernen
# ------------------------------------------------------------
Write-Host "3) Spotify-Update-Schalter werden entfernt ..." -ForegroundColor Cyan
$ks = 'HKCU:\Software\Spotify'
New-Item -Path $ks -Force | Out-Null
foreach ($n in @('EnableUpdate', 'AutoUpdate', 'DisableUpdate')) {
    Remove-ItemProperty -Path $ks -Name $n -ErrorAction SilentlyContinue
}
Write-Host "   EnableUpdate / AutoUpdate / DisableUpdate entfernt" -ForegroundColor DarkGray

# ------------------------------------------------------------
# 4) Ordner-Sperre aufheben
#    Das ist der wichtigste Schritt: solange dem Benutzer das
#    Loesch-Recht im Ordner fehlt, kann Spotify seine Dateien
#    nicht ersetzen und der PC bleibt halb gesperrt.
# ------------------------------------------------------------
Write-Host "4) Ordner-Sperre wird aufgehoben (Loesch-Recht zurueck) ..." -ForegroundColor Cyan
if (Test-Path $spot) {
    & icacls $spot /inheritance:e /reset 2>&1 | Out-Null
    # Besitz sichern, damit /reset durchgaengig klappt
    takeown /F $spot /A /D Y 2>&1 | Out-Null
    & icacls $spot /reset 2>&1 | Out-Null
    # Probe: muss sich jetzt loeschen lassen
    $probe = Join-Path $spot ("__freigabe_" + [guid]::NewGuid().ToString('N').Substring(0,8) + ".tmp")
    $frei = $false
    try {
        Set-Content -Path $probe -Value 'x' -ErrorAction Stop
        Remove-Item -Path $probe -Force -ErrorAction Stop
        $frei = $true
    } catch {
        Write-Host "   Ordner-Sperre noch aktiv: $($_.Exception.Message)" -ForegroundColor Yellow
        # Notloesung: Rechte direkt zurueckgeben
        $sid = (New-Object System.Security.Principal.NTAccount($env:USERDOMAIN, $env:USERNAME)).
                Translate([System.Security.Principal.SecurityIdentifier]).Value
        & icacls $spot /grant "*$sid`:(OI)(CI)(F)" 2>&1 | Out-Null
        try { Remove-Item $probe -Force -ErrorAction SilentlyContinue } catch {}
    }
    if ($frei) { Write-Host "   Loesch-Recht wieder da - Ordner entschuerzt" -ForegroundColor DarkGray }
    else { Write-Host "   ACHTUNG: Ordner ist weiterhin gesperrt" -ForegroundColor Yellow }
} else {
    Write-Host "   Spotify-Ordner nicht gefunden - uebersprungen" -ForegroundColor Yellow
}

# ------------------------------------------------------------
# 5) Dateisperre aufheben
# ------------------------------------------------------------
Write-Host "5) Dateisperre auf den EXE-Dateien wird aufgehoben ..." -ForegroundColor Cyan
if (Test-Path $spot) {
    $n = 0
    foreach ($e in (Get-ChildItem $spot -Filter '*.exe' -Recurse -ErrorAction SilentlyContinue)) {
        try {
            # Standardrechte wiederherstellen
            & icacls $e.FullName /reset 2>&1 | Out-Null
            # Vererbung wieder aktivieren, Besitz uebernehmen
            & icacls $e.FullName /inheritance:e /grant:r '*S-1-5-18:(F)' '*S-1-5-32-544:(F)' 2>&1 | Out-Null
            # Read-only-Flag raus
            $e.IsReadOnly = $false
            $n++
        } catch {
            Write-Host "   $($e.Name): $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    Write-Host "   $n EXE-Dateien entschuerzt" -ForegroundColor DarkGray
} else {
    Write-Host "   Spotify-Ordner nicht gefunden - uebersprungen" -ForegroundColor Yellow
}

# ------------------------------------------------------------
# 6) Waechter-Task entfernen
# ------------------------------------------------------------
Write-Host "6) Selbstheilungs-Waechter wird entfernt ..." -ForegroundColor Cyan
$t = Get-ScheduledTask -TaskName 'SpotifyUpdateGuard' -ErrorAction SilentlyContinue
if ($t) {
    Unregister-ScheduledTask -TaskName 'SpotifyUpdateGuard' -Confirm:$false
    Write-Host "   Task SpotifyUpdateGuard geloescht" -ForegroundColor DarkGray
} else {
    Write-Host "   Task war nicht vorhanden" -ForegroundColor DarkGray
}
$g = Join-Path $env:LOCALAPPDATA 'spotify-update-guard.ps1'
if (Test-Path $g) {
    Remove-Item $g -Force -ErrorAction SilentlyContinue
    Write-Host "   Waechter-Skript geloescht" -ForegroundColor DarkGray
}

# ------------------------------------------------------------
# Verifikation
# ------------------------------------------------------------
Write-Host ""
Write-Host "FERTIG - Spotify kann wieder aktualisieren." -ForegroundColor Green
Write-Host "===========================================================" -ForegroundColor Green
Write-Host "Verifizierung:" -ForegroundColor Cyan
Write-Host ("  Installer-Sperre HKLM : " +
    (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Installer').DisableAutomaticUpdates) -ForegroundColor DarkGray
foreach ($svc in 'wuauserv', 'UsoSvc') {
    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($s) { Write-Host ("  Dienst $svc".PadRight(25) + ": " + $s.StartType) -ForegroundColor DarkGray }
}
if (Test-Path $spot) {
    $ro = @(Get-ChildItem $spot -Filter '*.exe' -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.IsReadOnly }).Count
    Write-Host ("  Schreibgeschuetzte EXE: " + $ro) -ForegroundColor DarkGray
    $probe2 = Join-Path $spot ("__vfy_" + [guid]::NewGuid().ToString('N').Substring(0,8) + ".tmp")
    $ok = $false
    try {
        Set-Content -Path $probe2 -Value 'x' -ErrorAction Stop
        Remove-Item $probe2 -Force -ErrorAction Stop
        $ok = $true
    } catch { $ok = $false }
    Write-Host ("  Ordner loeschbar     : " + $(if ($ok) { 'ja - Sperre aufgehoben' } else { 'NEIN - noch gesperrt' })) -ForegroundColor DarkGray
}
$tv = Get-ScheduledTask -TaskName 'SpotifyUpdateGuard' -ErrorAction SilentlyContinue
Write-Host ("  Waechter-Task         : " + $(if ($tv) { 'noch da' } else { 'entfernt' })) -ForegroundColor DarkGray
Write-Host "===========================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Hinweis: Der Spicetify-Patch in index.html bleibt erhalten."
Write-Host "Nach dem naechsten Update bitte einmal:" -ForegroundColor Cyan
Write-Host ("  powershell -ExecutionPolicy Bypass -File `"$PSScriptRoot\spotify-alles-einrichten.ps1`"")

exit 0