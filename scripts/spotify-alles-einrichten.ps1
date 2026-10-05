# ============================================================
#  Spotify Komplett-Einrichtung fuer JEDEN PC
#  ------------------------------------------------------------
#  Macht in einem Durchgang:
#    1. Spotify installieren (falls fehlt)
#    2. Updates dauerhaft blockieren (Registry + Dienste + Dateien)
#    3. Spicetify installieren (inkl. Marketplace)
#    4. Patch anwenden
#    5. Selbstheilungs-Waechter als geplanten Task eintragen
#    6. Alles verifizieren
#
#  AUFRUFB:
#    Right-click -> Run with PowerShell  ODER
#    powershell -ExecutionPolicy Bypass -File .\spotify-alles-einrichten.ps1
#
#  NUR PRUEFEN, NICHTS AENDERN:
#    powershell -ExecutionPolicy Bypass -File .\spotify-alles-einrichten.ps1 -Check
# ============================================================
[CmdletBinding()]
param(
    [switch]$Check,                 # Nur Status melden, nichts aendern
    [switch]$InstallOnly,           # Phase 1: nur Spotify installieren (ohne Admin)
    [switch]$SetupOnly,             # Phase 2: Sperre + Spicetify + Waechter (mit Admin)
    [string]$WantedVersion = '1.3.1.234'
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

$script:Spots  = @()
$script:Fails  = @()

function Step($n, $text) {
    Write-Host ''
    Write-Host ("[$n] $text") -ForegroundColor Cyan
}
function Ok($t)   { Write-Host "    OK   $t" -ForegroundColor Green
                    $script:Spots += $t }
function Warn($t) { Write-Host "    !    $t" -ForegroundColor Yellow
                    $script:Spots += "WARNUNG: $t" }
function Bad($t)  { Write-Host "    X    $t" -ForegroundColor Red
                    $script:Fails += $t }

# ------------------------------------------------------------
# 0) Administrator-Rechte (mit Auto-Elevation)
# ------------------------------------------------------------
# Wichtig: winget verweigert den Administratorskontext
# ("Das Installationsprogramm kann nicht in einem Administratorkontext
#  ausgefuehrt werden"). Deshalb laeuft die Installation bewusst OHNE
# Admin (Spotify legt sich unter %APPDATA% an), und nur die Sperre
# braucht Admin.
function Test-Admin {
    $p = New-Object System.Security.Principal.WindowsPrincipal(
            [System.Security.Principal.WindowsIdentity]::GetCurrent())
    $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

$isAdmin = Test-Admin

if ($InstallOnly) {
    # Phase 1 braucht KEIN Admin - und wird abgelehnt, wenn elevated
    if ($isAdmin) {
        Write-Host ""
        Write-Host "Phase 1 laeuft absichtlich ohne Administratorrechte." -ForegroundColor Yellow
        Write-Host "winget lehnt den Administratorkontext ab. Bitte die Datei" -ForegroundColor Yellow
        Write-Host "normal per Doppelklick starten, nicht als Administrator." -ForegroundColor Yellow
        exit 3
    }
    $isAdmin = $false   # Phase 1 ist nie elevated
}
elseif ($SetupOnly) {
    if (-not $isAdmin) {
        Write-Host ""
        Write-Host "Phase 2 braucht Administratorrechte - ich bitte den Benutzer einmalig." -ForegroundColor Yellow
        $self = $MyInvocation.MyCommand.Path
        try {
            Start-Process -FilePath 'powershell' -Verb RunAs -ArgumentList @(
                '-NoProfile', '-ExecutionPolicy', 'Bypass',
                '-File', ('"{0}"' -f $self), '-SetupOnly'
            ) -Wait
            exit 0
        } catch {
            Bad "Elevation fehlgeschlagen: $($_.Exception.Message)"
            exit 1
        }
    }
}
elseif (-not $isAdmin) {
    if ($Check) {
        Write-Host "Nur-Pruefen-Modus laeuft ohne Admin. Fuer die echte Einrichtung bitte" -ForegroundColor Yellow
        Write-Host "als Administrator starten." -ForegroundColor Yellow
    } else {
        Write-Host "Administratorrechte fehlen - ich bitte den Benutzer einmalig." -ForegroundColor Yellow
        $self = $MyInvocation.MyCommand.Path
        try {
            Start-Process -FilePath 'powershell' -Verb RunAs -ArgumentList @(
                '-NoProfile', '-ExecutionPolicy', 'Bypass',
                '-File', ('"{0}"' -f $self)
            ) -Wait
            exit 0
        } catch {
            Bad "Elevation fehlgeschlagen: $($_.Exception.Message)"
            exit 1
        }
    }
}

Write-Host '============================================================'
Write-Host ' Spotify Komplett-Einrichtung'
Write-Host (" Modus: " + $(if ($Check) { 'NUR PRUEFEN' } else { 'EINRICHTEN' }))
Write-Host (" Admin: " + $(if ($isAdmin) { 'ja' } else { 'nein' }))
Write-Host '============================================================'

$spice = Join-Path $env:APPDATA 'spicetify'

# ------------------------------------------------------------
# Spotify-Ordner automatisch finden
# ------------------------------------------------------------
# Je nach Installationsart liegt Spotify an verschiedenen Orten:
#   1. klassische .exe-Installation:  %APPDATA%\Spotify
#   2. Microsoft-Store-/MSIX-Paket:   %LOCALAPPDATA%\Packages\SpotifyAB.SpotifyMusic_*\LocalCache\Roaming\Spotify
# Deshalb wird nicht blind ein fester Pfad angenommen.
function Get-SpotifyDir {
    $c = @(
        (Join-Path $env:APPDATA 'Spotify'),
        (Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Packages') -Filter 'SpotifyAB.SpotifyMusic*' `
            -Directory -ErrorAction SilentlyContinue |
         ForEach-Object { Join-Path $_.FullName 'LocalCache\Roaming\Spotify' }),
        (Join-Path $env:LOCALAPPDATA 'Spotify')
    ) | Where-Object { $_ -and (Test-Path $_) }

    # Bester Kandidat: der Ordner, in dem auch die XPUI-Dateien liegen.
    foreach ($p in $c) {
        if (Test-Path (Join-Path $p 'Apps\xpui\index.html')) { return $p }
    }
    # Sonst der erste, in dem wenigstens Spotify.exe liegt.
    foreach ($p in $c) {
        if (Test-Path (Join-Path $p 'Spotify.exe')) { return $p }
    }
    # Sonst der erste existierende Pfad als Ausgangswert.
    foreach ($p in $c) { return $p }
    return (Join-Path $env:APPDATA 'Spotify')   # Fallback fuer die Fehlermeldung
}

$spot = Get-SpotifyDir
$exe  = Join-Path $spot  'Spotify.exe'
$idx  = Join-Path $spot  'Apps\xpui\index.html'

function Get-SpotifyVersion {
    $r = Get-ItemProperty `
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' `
            -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -eq 'Spotify' } | Select-Object -First 1
    if ($r -and $r.DisplayVersion) { return $r.DisplayVersion }
    if (Test-Path $exe) { return (Get-Item $exe).VersionInfo.ProductVersion }
    return $null
}

function Get-SpiceBin {
    $c = @(
        (Join-Path $env:LOCALAPPDATA 'spicetify\spicetify.exe'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\spicetify.exe')
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($c) { return $c }
    return (Get-Command spicetify -ErrorAction SilentlyContinue).Source
}

# ------------------------------------------------------------
# 1) Spotify installieren
# ------------------------------------------------------------
Step 1 'Spotify'
$ver = Get-SpotifyVersion
if ($ver) {
    Ok "Spotify $ver vorhanden"
} elseif ($Check) {
    Warn 'Spotify ist NICHT installiert'
} else {
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if (-not $winget) {
            Bad 'winget fehlt - Spotify bitte manuell von spotify.com installieren'
        } else {
            Write-Host '    Installiere Spotify via winget (kann 2-5 Minuten dauern) ...' -ForegroundColor DarkGray
            $out = & winget install --id Spotify.Spotify --exact --silent `
                --accept-package-agreements --accept-source-agreements 2>&1
            $txt = $out -join ' '
            if ($LASTEXITCODE -eq 0 -or $txt -match 'already installed') {
                Start-Sleep -Seconds 5
                $ver = Get-SpotifyVersion
                if ($ver) { Ok "Spotify $ver installiert" }
                else { Bad 'winget meldet Erfolg, aber Spotify ist nicht auffindbar - bitte neu anmelden' }
            } elseif ($txt -match 'Administratorkontext|elevat|Administrator') {
                # winget-Beschraenkung: Installation MUSS ohne Admin laufen
                Bad 'winget lehnt den Administratorkontext ab.'
                Write-Host '' -ForegroundColor Yellow
                Write-Host '        Das ist eine Windows-Eigenheit von winget, kein Fehler' -ForegroundColor Yellow
                Write-Host '        im Paket. Spotify MUSS ohne Administratorrechte' -ForegroundColor Yellow
                Write-Host '        installiert werden.' -ForegroundColor Yellow
                Write-Host '' -ForegroundColor Yellow
                Write-Host '        Bitte "Spotify einrichten.cmd" NORMAL doppelklicken,' -ForegroundColor Yellow
                Write-Host '        also NICHT ueber "Als Administrator ausfuehren".' -ForegroundColor Yellow
                Write-Host '' -ForegroundColor Yellow
            } else {
                Bad "winget-Installation fehlgeschlagen: $txt"
            }
        }
}

# Phase 1 endet hier - Sperre und Patch brauchen Admin und
# werden erst in Phase 2 gemacht.
if ($InstallOnly) {
    Write-Host ''
    if ($script:Fails.Count -eq 0) {
        Write-Host ' Phase 1 abgeschlossen. Phase 2 startet gleich mit Admin-Rechten.' -ForegroundColor Green
        exit 0
    }
    Write-Host ' Phase 1 hat Probleme - bitte die Meldung oben lesen.' -ForegroundColor Yellow
    exit 1
}

# ------------------------------------------------------------
# 2) Update-Sperre
# ------------------------------------------------------------
Step 2 'Update-Sperre'
if (-not $isAdmin) {
    Warn 'Registry-/Dienst-Sperre braucht Admin - uebersprungen'
} else {
    $k = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Installer'
    $cur = (Get-ItemProperty -Path $k -Name 'DisableAutomaticUpdates' `
              -ErrorAction SilentlyContinue).DisableAutomaticUpdates
    if ($cur -eq 1) {
        Ok 'HKLM DisableAutomaticUpdates = 1 (schon gesetzt)'
    } elseif ($Check) {
        Warn 'HKLM DisableAutomaticUpdates ist NICHT gesetzt'
    } else {
        New-Item -Path $k -Force | Out-Null
        Set-ItemProperty -Path $k -Name 'DisableAutomaticUpdates' -Value 1 -Type DWord
        $cur = (Get-ItemProperty -Path $k -Name 'DisableAutomaticUpdates').DisableAutomaticUpdates
        if ($cur -eq 1) { Ok 'HKLM DisableAutomaticUpdates = 1 gesetzt' }
        else { Bad 'Registry-Write hat nicht gegriffen' }
    }

    foreach ($svc in 'wuauserv', 'UsoSvc') {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if (-not $s) { continue }
        if ($s.StartType -eq 'Disabled') { Ok "$svc ist deaktiviert (schon)" ; continue }
        if ($Check) { Warn "$svc laeuft noch ($($s.StartType))" ; continue }
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        try {
            Set-Service -Name $svc -StartupType Disabled -ErrorAction Stop
            Ok "$svc deaktiviert"
        } catch {
            Warn "$svc konnte nicht deaktiviert werden: $($_.Exception.Message)"
        }
    }
}

# Spotify-eigene Update-Schalter
if ($Check) {
    $eu = $null
    # Get-ItemPropertyValue wirft bei fehlendem Wert trotz -ErrorAction
    try { $eu = Get-ItemPropertyValue 'HKCU:\Software\Spotify' -Name 'EnableUpdate' -ErrorAction Stop }
    catch { $eu = $null }
    if ($null -eq $eu) { Warn 'HKCU\Software\Spotify EnableUpdate ist nicht gesetzt' }
    else { Ok "HKCU EnableUpdate = $eu" }
} else {
    New-Item -Path 'HKCU:\Software\Spotify' -Force | Out-Null
    Set-ItemProperty 'HKCU:\Software\Spotify' -Name 'EnableUpdate'   -Value 0 -Type DWord -Force
    Set-ItemProperty 'HKCU:\Software\Spotify' -Name 'AutoUpdate'     -Value 0 -Type DWord -Force
    Set-ItemProperty 'HKCU:\Software\Spotify' -Name 'DisableUpdate'  -Value 1 -Type DWord -Force
    Ok 'Spotify-interne Update-Schalter auf 0/0/1'
}

# ------------------------------------------------------------
# 3) Spicetify installieren
# ------------------------------------------------------------
Step 3 'Spicetify'
$sb = Get-SpiceBin
if ($sb) {
    $sv = (& $sb --version 2>&1 | Select-Object -First 1)
    Ok "Spicetify gefunden: $sb ($sv)"
} elseif ($Check) {
    Warn 'Spicetify ist nicht installiert'
} else {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        Bad 'winget fehlt - Spicetify bitte manuell von spicetify.app installieren'
    } else {
        Write-Host '    Installiere Spicetify via winget ...' -ForegroundColor DarkGray
        $out = & winget install --id Spicetify.Spicetify --exact --silent `
                --accept-package-agreements --accept-source-agreements 2>&1
        $sb = Get-SpiceBin
        if ($sb) { Ok "Spicetify installiert: $sb" }
        else { Bad "Spicetify-Installation fehlgeschlagen: $($out -join ' ')" }
    }
}

# ------------------------------------------------------------
# 4) Konfiguration + Patch
# ------------------------------------------------------------
Step 4 'Spicetify-Konfiguration und Patch'
if (-not $sb) {
    Bad 'Ohne Spicetify kann der Patch nicht angewendet werden'
} elseif (-not (Test-Path $idx)) {
    Bad 'index.html nicht gefunden - Spotify-Ordner fehlt'
    Write-Host '        Das Skript laeuft nur, wenn Phase 1 (Installation)' -ForegroundColor Yellow
    Write-Host '        erfolgreich war. Bitte die Meldung in Schritt 1 lesen.' -ForegroundColor Yellow
} else {
    $cfg = Join-Path $spice 'config-xpui.ini'
    if ($Check) {
        if (Test-Path $cfg) {
            $ini = Get-Content $cfg -Raw
            # Spicetify polstert mit Leerzeichen ("custom_apps           = marketplace")
            $wanted = @(
                @{ Key = 'current_theme';       Val = 'marketplace' },
                @{ Key = 'custom_apps';         Val = 'marketplace' },
                @{ Key = 'experimental_features'; Val = '1' }
            )
            foreach ($w in $wanted) {
                $label = "$($w.Key) = $($w.Val)"
                $re = '(?m)^' + [regex]::Escape($w.Key) + '\s*=\s*' + [regex]::Escape($w.Val) + '\s*$'
                if ($ini -match $re) { Ok "config: $label" }
                else { Warn "config fehlt: $label" }
            }
        } else { Warn 'config-xpui.ini fehlt' }
    } else {
        if (-not (Test-Path $cfg)) {
            & $sb config current_theme marketplace 2>&1 | Out-Null
            & $sb config custom_apps  marketplace 2>&1 | Out-Null
            & $sb config experimental_features 1    2>&1 | Out-Null
            Ok 'config-xpui.ini neu geschrieben'
        } else {
            $ini = Get-Content $cfg -Raw
            if ($ini -notmatch 'current_theme\s*=\s*marketplace') {
                & $sb config current_theme marketplace 2>&1 | Out-Null }
            if ($ini -notmatch 'custom_apps\s*=\s*marketplace') {
                & $sb config custom_apps marketplace 2>&1 | Out-Null }
            if ($ini -notmatch 'experimental_features\s*=\s*1') {
                & $sb config experimental_features 1 2>&1 | Out-Null }
            Ok 'config-xpui.ini ist aktuell'
        }
    }

    # Patch pruefen / anwenden
    $cur = Get-Content $idx -Raw
    $hasPatch = ($cur -match 'Spicetify\.Config')
    if ($hasPatch) { Ok 'Patch ist bereits in index.html' }
    elseif ($Check) { Warn 'Patch FEHLT in index.html' }
    else {
        Write-Host '    Wende Patch an (backup + apply) ...' -ForegroundColor DarkGray
        & $sb backup 2>&1 | Out-Null
        & $sb apply  2>&1 | Out-Null
        $after = Get-Content $idx -Raw
        if ($after -match 'Spicetify\.Config') { Ok 'Patch erfolgreich angewendet' }
        else { Bad 'Patch auch nach apply nicht vorhanden - Spicetify-Log pruefen' }
    }

    # Marketplace-CustomApp
    $mk = Join-Path $spice 'CustomApps\marketplace\extension.js'
    if (Test-Path $mk) { Ok 'Marketplace-CustomApp vorhanden' }
    elseif ($Check) { Warn 'Marketplace-CustomApp fehlt' }
    else { Warn 'Marketplace-CustomApp fehlt - ggf. ueber Spicetify Marketplace nachinstallieren' }
}

# ------------------------------------------------------------
# 5) Selbstheilungs-Waechter
# ------------------------------------------------------------
Step 5 'Selbstheilungs-Waechter'
$task = Get-ScheduledTask -TaskName 'SpotifyUpdateGuard' -ErrorAction SilentlyContinue
$guardSrc = Join-Path $PSScriptRoot 'spotify-update-guard.ps1'
$guardDst = Join-Path $env:LOCALAPPDATA 'spotify-update-guard.ps1'

if ($Check) {
    if ($task) { Ok "Task SpotifyUpdateGuard: $($task.State)" }
    else { Warn 'Task SpotifyUpdateGuard fehlt' }
    if (Test-Path $guardDst) { Ok "Waechter-Skript: $guardDst" }
    else { Warn 'Waechter-Skript fehlt unter LOCALAPPDATA' }
} elseif ($task) {
    Ok "Task SpotifyUpdateGuard existiert ($($task.State)) - Skript wird aktualisiert"
    if (Test-Path $guardSrc) { Copy-Item $guardSrc $guardDst -Force; Ok 'Waechter-Skript aktualisiert' }
    else { Warn 'spotify-update-guard.ps1 liegt nicht neben diesem Skript' }
} else {
    if (-not (Test-Path $guardSrc)) {
        Bad 'spotify-update-guard.ps1 nicht gefunden - bitte neben dieses Skript legen'
    } else {
        Copy-Item $guardSrc $guardDst -Force
        $act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument `
               "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$guardDst`""
        $trg = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
        $trg2 = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) `
                -RepetitionInterval (New-TimeSpan -Hours 1)
        $st = 'AtLogOn'
        $pr = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive `
                -RunLevel Limited
        Register-ScheduledTask -TaskName 'SpotifyUpdateGuard' `
            -Action $act -Trigger @($trg, $trg2) -Principal $pr `
            -Description 'Haelt Spotify-Update-Sperre und Spicetify-Patch intakt' `
            -Force | Out-Null
        $check = Get-ScheduledTask -TaskName 'SpotifyUpdateGuard'
        if ($check) { Ok "Task registriert: $($check.State)" }
        else { Bad 'Task-Registrierung fehlgeschlagen' }
    }
}

# ------------------------------------------------------------
# 6) Abschluss-Verifikation
# ------------------------------------------------------------
Step 6 'Verifikation'
$ver = Get-SpotifyVersion
if ($ver) {
    $match = ($ver -like "$WantedVersion*")
    if ($match) { Ok "Version $ver - wie gewuenscht" }
    else {
        # Kein Fehler: auf einem fremden PC ist die aktuelle Version
        # etwas anderes. Das ist kein Schaden, nur eine Abweichung.
        Warn "Version $ver - abweichend von $WantedVersion"
        Write-Host '        Kein Problem: der Waechter bekommt diese Version' -ForegroundColor DarkGray
        Write-Host '        neu zugeteilt, damit er nicht dauerhaft warnt.' -ForegroundColor DarkGray
    }
} else { Warn 'Spotify-Version nicht ermittelbar' }

# Waechter auf die tatsaechlich vorhandene Version einstellen.
# Sonst meldet er bei jedem Lauf eine vermeintliche Abweichung.
if (-not $Check -and $ver) {
    $short = ($ver -split '\.g')[0]
    $gsrc = Join-Path $PSScriptRoot 'spotify-update-guard.ps1'
    $gdst = Join-Path $env:LOCALAPPDATA 'spotify-update-guard.ps1'
    foreach ($gf in @($gsrc, $gdst)) {
        if (-not (Test-Path $gf)) { continue }
        try {
            $txt = Get-Content $gf -Raw
            $neu = [regex]::Replace($txt,
                "(?m)^\`$WANTED_VERSION\s*=\s*'[^']*'", "`$WANTED_VERSION = '$short'")
            if ($neu -ne $txt) {
                Set-Content -Path $gf -Value $neu -Encoding UTF8 -NoNewline
                Ok "Waechter auf Version $short eingestellt ($([IO.Path]::GetFileName($gf)))"
            }
        } catch {
            Warn "Waechter-Version konnte nicht gesetzt werden: $($_.Exception.Message)"
        }
    }
}

$locked = 0
if (Test-Path $spot) {
    $locked = @(Get-ChildItem $spot -Filter '*.exe' -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.IsReadOnly }).Count
}
if ($locked -gt 0) { Ok "$locked EXE-Dateien sind schreibgeschuetzt" }
else { Warn 'Keine EXE-Datei als schreibgeschuetzt markiert' }

# Ordner-Sperre pruefen. Ohne sie ist die EXE-Sperre nutzlos:
# Spotify loescht die gesperrten Dateien und legt sie neu an.
#
# WICHTIG: eigener Dateiname je Lauf. Bei aktiver Sperre kann diese
# Datei nicht geloescht werden. Ein fester Name wuerde beim
# zweiten Aufruf daran scheitern, die Datei zu ueberschreiben -
# und der Test wuerde dann faelschlich "Cache blockiert" melden,
# obwohl alles in Ordnung ist. Das Praefix __guard_probe_ sorgt
# dafuer, dass spotify-update-guard.ps1 den Rest beim naechsten
# Lauf wegraeumt.
if (Test-Path $spot) {
    $probe = Join-Path $spot ('__guard_probe_status_' + [guid]::NewGuid().ToString('N').Substring(0,8) + '.tmp')
    $made = $false
    try { Set-Content -Path $probe -Value 'x' -ErrorAction Stop; $made = $true } catch { $made = $false }
    if (-not $made) {
        Bad 'Im Spotify-Ordner kann nichts angelegt werden - Cache waere blockiert'
    } else {
        try {
            Remove-Item -Path $probe -Force -ErrorAction Stop
            Bad 'Ordner-Sperre fehlt: Dateien im Spotify-Ordner lassen sich loeschen.'
            Bad 'Damit kann Spotify seine EXE-Dateien ersetzen. Sperre ist unwirksam.'
            Write-Host '        Loest das Skript spotify-update-guard.ps1 auf, das' -ForegroundColor Yellow
            Write-Host '        normalerweise beim Anmelden laeuft.' -ForegroundColor Yellow
        } catch {
            Ok 'Ordner-Sperre haelt: Loeschen im Spotify-Ordner ist blockiert'
        }
    }
}

if (Test-Path $idx) {
    if ((Get-Content $idx -Raw) -match 'Spicetify\.Config') { Ok 'Spicetify-Patch sitzt' }
    else { Bad 'Spicetify-Patch fehlt' }
}

# ------------------------------------------------------------
# Auswertung
# ------------------------------------------------------------
Write-Host ''
Write-Host '============================================================'
# WARNUNGEN MITZAHLEN. Vorher wurde "alles in Ordnung" gemeldet,
# obwohl oben Warnungen standen - zum Beispiel als die
# Update-Sperre unwirksam war. Genau deshalb wurde ein
# durchgekommenes Update zu spaet erkannt.
$warnCount = @($script:Spots | Where-Object { $_ -like 'WARNUNG:*' }).Count
if ($script:Fails.Count -eq 0 -and $warnCount -eq 0) {
    Write-Host ' ERGEBNIS: alles in Ordnung.' -ForegroundColor Green
} elseif ($script:Fails.Count -eq 0) {
    Write-Host " ERGEBNIS: laeuft, aber mit $warnCount Warnung(en) - bitte lesen:" -ForegroundColor Yellow
    $script:Spots | Where-Object { $_ -like 'WARNUNG:*' } |
        ForEach-Object { Write-Host "  - $($_.Substring(9))" -ForegroundColor Yellow }
} else {
    Write-Host ' ERGEBNIS: es gibt offene Punkte:' -ForegroundColor Red
    $script:Fails | ForEach-Object { Write-Host "  FEHLER: $_" -ForegroundColor Red }
    $script:Spots | Where-Object { $_ -like 'WARNUNG:*' } |
        ForEach-Object { Write-Host "  WARNUNG: $($_.Substring(9))" -ForegroundColor Yellow }
}
Write-Host '============================================================'
Write-Host ''
Write-Host 'Nach jedem erzwungenen Update: Waechter laeuft automatisch bei'
Write-Host 'der Anmeldung und repariert den Patch. Manuell auch so:'
Write-Host ('  powershell -ExecutionPolicy Bypass -File "' + $guardDst + '"')
Write-Host ''
Write-Host 'Widerruf (Updates wieder erlauben):'
Write-Host ('  powershell -ExecutionPolicy Bypass -File "' +
           (Join-Path $PSScriptRoot 'spotify-updates-freigeben.ps1') + '"')

if ($script:Fails.Count -gt 0) { exit 1 } else { exit 0 }