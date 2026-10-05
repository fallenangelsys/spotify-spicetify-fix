$ErrorActionPreference = 'SilentlyContinue'
$spot  = "$env:APPDATA\Spotify"
$spice = "$env:APPDATA\spicetify"
$bin   = "$env:LOCALAPPDATA\spicetify\spicetify.exe"
$WANTED_VERSION = '1.3.1.234'
$installer = "$env:LOCALAPPDATA\spotify-update-guard\spotify-1.3.1.234-installer.exe"

function Schritt($t) { Write-Host "-> $t" -ForegroundColor Cyan }

# ------------------------------------------------------------
# 0) Fremde Version? -> erst zurueckrollen
#    Wichtig: die Version wird aus der MSI-Registry gelesen, nicht
#    aus der Spotify.exe. Die EXE-Version ist waehrend eines laufenden
#    Installers unzuverlaessig und zeigt kurzzeitig die neue Version,
#    waehrend die alte noch aktiv ist.
# ------------------------------------------------------------
function Get-SpotifyVersion {
    $r = Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                         'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                         'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
         Where-Object { $_.DisplayName -eq 'Spotify' } | Select-Object -First 1
    if ($r -and $r.DisplayVersion) { return $r.DisplayVersion }
    return (Get-Item "$spot\Spotify.exe" -ErrorAction SilentlyContinue).VersionInfo.ProductVersion
}

$current = Get-SpotifyVersion
if ($current -and ($current -notlike "$WANTED_VERSION*")) {
    Schritt "Spotify ist auf $current - wird auf $WANTED_VERSION zurueckgerollt"
    Get-Process Spotify -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 4

    if (Test-Path $installer) {
        Start-Process -FilePath $installer -ArgumentList '/S'
        Write-Host "   Installer laeuft, warte ..." -ForegroundColor Cyan
        for ($i = 0; $i -lt 30; $i++) {
            Start-Sleep -Seconds 5
            $v = Get-SpotifyVersion
            if ($v -and ($v -like "$WANTED_VERSION*")) { break }
        }
        Get-Process Spotify -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Seconds 4
    } else {
        Write-Host "   Installer fehlt: $installer" -ForegroundColor Red
    }

    # Dateisperre aufheben, damit der Installer schreiben konnte
    $sid = (New-Object System.Security.Principal.NTAccount($env:USERDOMAIN, $env:USERNAME)).
           Translate([System.Security.Principal.SecurityIdentifier]).Value
    Get-ChildItem $spot -Filter '*.exe' -Recurse | ForEach-Object {
        $_.IsReadOnly = $false
        & icacls $_.FullName /inheritance:e /reset 2>&1 | Out-Null
        & icacls $_.FullName /grant:r "*$sid`:(F)" '*S-1-5-18:(F)' '*S-1-5-32-544:(F)' 2>&1 | Out-Null
    }
} else {
    Schritt "Version $current ist korrekt"
}

# ------------------------------------------------------------
# 1) Theme-Platzhalter sicherstellen
# ------------------------------------------------------------
Schritt "Theme 'marketplace' wird sichergestellt"
New-Item -ItemType Directory -Force -Path "$spice\Themes\marketplace" | Out-Null
if (-not (Test-Path "$spice\Themes\marketplace\color.ini")) { Set-Content "$spice\Themes\marketplace\color.ini" -Value "[Marketplace]" }
if (-not (Test-Path "$spice\Themes\marketplace\user.css"))  { New-Item -ItemType File -Path "$spice\Themes\marketplace\user.css" -Force | Out-Null }

# ------------------------------------------------------------
# 2) Kritische Config-Werte erzwingen
# ------------------------------------------------------------
Schritt "Konfiguration wird gesetzt"
& $bin config experimental_features 1
& $bin config current_theme marketplace
& $bin config custom_apps marketplace
& $bin config home_config 0
& $bin config sidebar_config 0

# ------------------------------------------------------------
# 3) Backup + Apply
# ------------------------------------------------------------
Schritt "Spicetify Backup wird erstellt"
& $bin backup | Out-Null
Schritt "Spicetify wird angewendet"
& $bin apply | Out-Null

# ------------------------------------------------------------
# 4) Verifikation
# ------------------------------------------------------------
$idx = Get-Content "$spot\Apps\xpui\index.html" -Raw
if ($idx -match 'Spicetify\.Config' -and $idx -match 'xpui-modules\.js') {
    Write-Host "   Patch bestaetigt: Injektion ist vorhanden." -ForegroundColor Green
} else {
    Write-Host "   WARNUNG: Injektion fehlt - bitte Screenshot machen." -ForegroundColor Yellow
}
Write-Host ("   Version jetzt: " + (Get-SpotifyVersion)) -ForegroundColor Green

# ------------------------------------------------------------
# 5) Update-Sperre wiederherstellen
# ------------------------------------------------------------
Schritt "Update-Sperre wird gesetzt"
$sid = (New-Object System.Security.Principal.NTAccount($env:USERDOMAIN, $env:USERNAME)).
       Translate([System.Security.Principal.SecurityIdentifier]).Value
$rxAce = '*' + $sid + ':(RX)'
Get-ChildItem $spot -Filter '*.exe' -Recurse | ForEach-Object {
    $_.IsReadOnly = $true
    & icacls $_.FullName /inheritance:r /grant:r $rxAce '*S-1-5-18:(F)' '*S-1-5-32-544:(F)' 2>&1 | Out-Null
}
Write-Host "   Benutzer hat nur noch Lesen+Ausfuehren." -ForegroundColor Green

# Warnhinweis-Datei vom Wächter entfernen
Remove-Item "$env:USERPROFILE\Desktop\Spotify wurde aktualisiert.txt" -ErrorAction SilentlyContinue

# ------------------------------------------------------------
# 6) Starten
# ------------------------------------------------------------
Schritt "Spotify startet"
Start-Process "$spot\Spotify.exe"