# ============================================================
#  Spotify Update-Guard
#  Laeuft bei jeder Anmeldung und danach stuendlich.
#  Log: %APPDATA%\spicetify\update-guard.log
#
#  ------------------------------------------------------------
#  WARUM DAS UPDATE DAMALS DURCHKAM - und warum die Dateisperre
#  allein grundlegend falsch war:
#
#  Gesperrt waren nur die .exe-DATEIEN (IsReadOnly + kein
#  Schreibrecht). Der ORDNER %APPDATA%\Spotify behielt fuer den
#  Benutzer aber FullControl. FullControl auf einem Ordner
#  enthaelt das Recht, Dateien darin zu LOESCHEN.
#
#  Gesperrte Dateien werden von Spotify nicht ueberschrieben,
#  sondern geloescht und neu angelegt. Die neue Datei erbt
#  wieder die vollen Rechte - die Sperre ist damit wertlos.
#  Genau das ist am 05.10.2026 passiert (13:09:51, alle 6 EXE
#  neu geschrieben, 1.3.1.234 -> 1.3.3.264).
#
#  ------------------------------------------------------------
#  DIE RICHTIGE MASSNAHME: der ORDNER, nicht die Datei
#
#  Dem Benutzer wird im Spotify-Ordner das Loesch-Recht
#  ENTZOGEN. Er darf dort noch:
#    - lesen und ausfuehren
#    - neue Dateien und Ordner ANLEGEN (Cache, Logs)
#  Er darf dort NICHT mehr:
#    - Dateien oder Ordner loeschen
#
#  Damit kann Spotify seine eigenen Programmdateien nicht mehr
#  entfernen und nicht durch neue ersetzen.
#
#  Drei Stolperfallen, alle hier empirisch getestet:
#
#  1. "icacls /deny ... (D)" NICHT verwenden. icacls haengt an
#     (D) automatisch Synchronize an - und ohne Synchronize
#     laesst sich die Datei nicht einmal mehr oeffnen.
#     Getestet: Lesen schlug fehl, Spotify startete nicht mehr.
#
#  2. "Set-Acl" mit FileSystemAccessRule NICHT fuer die
#     Ordnerrechte verwenden. Set-Acl verlangt dafuer das
#     Recht SeSecurityPrivilege und bricht mit
#     "PrivilegeNotHeldException" ab. Die Rechte werden dann
#     nur teilweise geschrieben - im Test fehlten die
#     Administrator-Regeln. icacls arbeitet ohne dieses Recht.
#
#  3. Vererbung muss abgeschaltet und die Rechte explizit
#     gesetzt werden (icacls /inheritance:r /grant:r).
#     Ein RemoveAccessRule auf geerbte Regeln hat keine
#     Wirkung - FullControl kam vom Elternordner und blieb
#     dadurch stehen.
#
#  Nachgefuehrt wird jede Aktion mit echten Gegenproben:
#    - Anlegen muss klappen (sonst ist der Cache blockiert)
#    - Loeschen muss scheitern (sonst ist die Sperre nutzlos)
#    - Lesen muss klappen (sonst startet Spotify nicht)
#  Schlaegt eine Probe fehl, steht das im Log. Es wird nichts
#  stillschweigend als "in Ordnung" gemeldet.
# ============================================================
$ErrorActionPreference = 'SilentlyContinue'
$spice = "$env:APPDATA\spicetify"
$bin   = "$env:LOCALAPPDATA\spicetify\spicetify.exe"
$log   = "$spice\update-guard.log"

# ------------------------------------------------------------
# Spotify-Ordner finden: klassisch unter %APPDATA%, bei
# Store-/MSIX-Installation unter LocalAppData\Packages\...
# ------------------------------------------------------------
$spot = $null
$cands = @("$env:APPDATA\Spotify",
           (Get-ChildItem "$env:LOCALAPPDATA\Packages" -Filter 'SpotifyAB.SpotifyMusic*' `
               -Directory -EA SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName 'LocalCache\Roaming\Spotify' }),
           "$env:LOCALAPPDATA\Spotify") |
        Where-Object { $_ -and (Test-Path $_) }
foreach ($c in $cands) { if (Test-Path "$c\Apps\xpui\index.html") { $spot = $c; break } }
if (-not $spot) { foreach ($c in $cands) { if (Test-Path "$c\Spotify.exe") { $spot = $c; break } } }
if (-not $spot) { if ($cands.Count -gt 0) { $spot = $cands[0] } else { $spot = "$env:APPDATA\Spotify" } }

# Diese Version soll dauerhaft laufen. Alles andere heisst: Update war erfolgreich.
$WANTED_VERSION = '1.3.1.234'

$SYS = '*S-1-5-18'        # NT AUTHORITY\SYSTEM
$ADM = '*S-1-5-32-544'    # BUILTIN\Administrators

function Log($t) {
    Add-Content -Path $log -Value ("[" + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + "] $t") -Encoding UTF8
    if ((Test-Path $log) -and ((Get-Item $log).Length -gt 200KB)) {
        Move-Item $log "$log.old" -Force
    }
}

function Get-UserSid {
    (New-Object System.Security.Principal.NTAccount($env:USERDOMAIN, $env:USERNAME)).
        Translate([System.Security.Principal.SecurityIdentifier]).Value
}

$sid = Get-UserSid
$USER = "*$sid"

# Rechte des Benutzers im Ordner: lesen, anlegen - aber KEIN loeschen.
# (OI)(CI) = an Unterordner und Dateien vererben.
# WD = WriteData/CreateFiles, AD = AppendData/CreateDirectories.
$USER_GRANT = "$USER`:(OI)(CI)(RX,WD,AD)"

function Set-FolderLock {
    # Vererbung aus und Rechte explizit setzen. Ohne /inheritance:r
    # bleibt das geerbte FullControl vom Elternordner stehen.
    & icacls $spot /inheritance:r `
        /grant:r "$USER_GRANT" "$SYS`:(OI)(CI)(F)" "$ADM`:(OI)(CI)(F)" 2>&1 | Out-Null
}

function Test-FolderLock {
    # WICHTIG: Die Probe muss DIREKT im Spotify-Ordner angelegt werden.
    # Ein Verschieben aus %TEMP% traegt die Rechte des TEMP-Ordners
    # in den Spotify-Ordner - die Sperre wuerde dann faelschlich als
    # unwirksam gemeldet, obwohl sie greift.
    # Fester Dateiname: bei aktiver Sperre kann der Waechter seine
    # eigene Probe-Datei nicht loeschen. Mit festem Namen bleibt
    # dauerhaft genau eine Datei liegen statt bei jedem Lauf eine
    # neue anzuhaufen.
    $dst = "$spot\__guard_probe.tmp"

    # 1) Anlegen muss klappen - sonst waere der Cache blockiert.
    $canCreate = $false
    try { Set-Content -Path $dst -Value 'x' -EA Stop; $canCreate = $true } catch { $canCreate = $false }

    # 2) Loeschen muss scheitern - sonst ist die Sperre nutzlos.
    $deleteBlocked = $false
    if ($canCreate) {
        try {
            Remove-Item -Path $dst -Force -EA Stop
            $deleteBlocked = $false     # Loeschen klappte -> Sperre fehlt
        } catch { $deleteBlocked = $true }
    } else {
        # Nicht anlegbar: Loeschen kann der Benutzer ohnehin nicht.
        $deleteBlocked = $true
    }
    return @{ CanCreate = $canCreate; DeleteBlocked = $deleteBlocked }
}

# ------------------------------------------------------------
# 0b) UPDATER-RESTE ENTFERNEN
#
#     Wichtig, am 05.10.2026 empirisch gefunden:
#     Die Sperre verhindert nur das ERSETZEN der Dateien. Sie
#     verhindert nicht, dass Spotify die neue Version vorher
#     HERUNTERLAEDT und teilweise auspackt. Beim Klick auf
#     "Updaten" passiert folgendes:
#       1. 156 MB neues Paket werden nach %LOCALAPPDATA%\Spotify\Update
#       2. die neue login.spa landet in Apps\
#       3. erst beim Ersetzen der EXE-Dateien scheitert es
#     Ergebnis: halb neu, halb alt. Spotify startet nicht mehr
#     (getestet: beendet sich mit ExitCode 0), und ~1 GB
#     ~TMP_*-Dateien bleiben im Ordner liegen.
#
#     Deshalb wird hier aufgeraeumt - und zwar VOR dem Setzen
#     der Sperre, weil danach nicht mehr geloescht werden kann.
# ------------------------------------------------------------
# a) Haengenden Updater beenden. Er haelt die Datei offen,
#    sonst laesst sie sich auch mit Admin nicht loeschen.
$instProcs = @(Get-Process -EA SilentlyContinue | Where-Object { $_.Name -like 'spotify_installer*' })
if ($instProcs.Count -gt 0) {
    foreach ($p in $instProcs) {
        Log "Haengender Updater wird beendet: PID $($p.Id) $($p.Name)"
        try { Stop-Process -Id $p.Id -Force -EA Stop } catch { Log "  konnte nicht beendet werden: $($_.Exception.Message)" }
    }
    Start-Sleep -Seconds 3
}

# b) Heruntergeladenes Update-Paket entfernen (liegt ausserhalb
#    des gesperrten Ordners, darum direkt loeschbar).
$updDir = "$env:LOCALAPPDATA\Spotify\Update"
if (Test-Path $updDir) {
    $upd = @(Get-ChildItem $updDir -Force -EA SilentlyContinue)
    if ($upd.Count -gt 0) {
        $mb = [math]::Round((($upd | Measure-Object Length -Sum).Sum / 1MB), 1)
        Log "Heruntergeladenes Update-Paket wird entfernt: $($upd.Count) Dateien, $mb MB"
        foreach ($f in $upd) { Remove-Item $f.FullName -Force -Recurse -EA SilentlyContinue }
    }
    Remove-Item $updDir -Recurse -Force -EA SilentlyContinue
    if (Test-Path $updDir) { Log "WARNUNG: Update-Ordner konnte nicht entfernt werden" }
}

# c) Reste im Spotify-Ordner. Dafuer muss die Sperre kurz
#    aufgehoben werden - sie blockiert sonst das Loeschen.
$tmpRest = @(Get-ChildItem $spot -Filter '~TMP_*' -Force -EA SilentlyContinue)
# login.spa gehoert zur NEUEN Version, die gepinnte 1.3.1.234
# nutzt den Ordner Apps\login. Bleibt die Datei liegen, startet
# die gepinnte Version nicht.
$staleSpa = @(Get-ChildItem "$spot\Apps" -Filter 'login.spa' -Force -EA SilentlyContinue)
if ($tmpRest.Count -gt 0 -or $staleSpa.Count -gt 0) {
    $mbTmp = [math]::Round((($tmpRest | Measure-Object Length -Sum).Sum / 1MB), 1)
    Log "Update-Reste im Ordner: $($tmpRest.Count) ~TMP_-Dateien ($mbTmp MB), $($staleSpa.Count) login.spa - werden entfernt"
    & icacls $spot /inheritance:e /grant "$USER`:(OI)(CI)(F)" 2>&1 | Out-Null
    foreach ($f in $tmpRest) { Remove-Item $f.FullName -Force -EA SilentlyContinue }
    foreach ($f in $staleSpa) { Remove-Item $f.FullName -Force -EA SilentlyContinue }
    $leftTmp = @(Get-ChildItem $spot -Filter '~TMP_*' -Force -EA SilentlyContinue).Count
    $leftSpa = @(Get-ChildItem "$spot\Apps" -Filter 'login.spa' -Force -EA SilentlyContinue).Count
    if ($leftTmp -gt 0 -or $leftSpa -gt 0) {
        Log "WARNUNG: Reste nicht entfernbar ($leftTmp ~TMP_, $leftSpa login.spa). Rechte im Detail pruefen."
    } else {
        Log 'Update-Reste entfernt.'
    }
}

# ------------------------------------------------------------
# 1) Ordner-Sperre setzen und pruefen
# ------------------------------------------------------------
Set-FolderLock
$t1 = Test-FolderLock
if (-not $t1.CanCreate -or -not $t1.DeleteBlocked) {
    # Nochmal versuchen (manchmal ist die ACL noch nicht durch)
    Set-FolderLock
    $t2 = Test-FolderLock
    if ($t2.CanCreate -and $t2.DeleteBlocked) { $t1 = $t2 }
}
Log ("Ordner-Sperre: anlegen=$($t1.CanCreate) loeschen-blockiert=$($t1.DeleteBlocked)  [$spot]")

# Eigene Probe-Dateien aus VORHERIGEN Laeufen wegraeumen.
# Bei aktiver Sperre kann der Waechter sie nicht loeschen - darum
# wird die Sperfuer dieses Fenster kurz aufgehoben. Ohne diesen
# Schritt sammeln sich __guard_probe_*.tmp ueber die Zeit im
# Spotify-Ordner.
$oldProbes = @(Get-ChildItem $spot -Filter '__guard_probe*.tmp' -Force -EA SilentlyContinue)
$oldProbes += @(Get-ChildItem $spot -Filter '__check_probe*.tmp' -Force -EA SilentlyContinue)
if ($oldProbes.Count -gt 0) {
    & icacls $spot /inheritance:e /grant "$USER`:(OI)(CI)(F)" 2>&1 | Out-Null
    foreach ($f in $oldProbes) { Remove-Item $f.FullName -Force -EA SilentlyContinue }
    Set-FolderLock
    Log "Aufgeraeumt: $($oldProbes.Count) alte Probe-Datei(en)"
}
if (-not $t1.CanCreate) {
    Log 'KRITISCH: Anlegen blockiert - Spotify kann nicht arbeiten. Rechte werden zurueckgesetzt.'
    & icacls $spot /inheritance:e /reset 2>&1 | Out-Null
    $t3 = Test-FolderLock
    Log "Nach Zuruecksetzen: anlegen=$($t3.CanCreate) loeschen-blockiert=$($t3.DeleteBlocked)"
}

# ------------------------------------------------------------
# 2) EXE-Sperre gegen Ueberschreiben.
#    Reihenfolge: erst Schreibrecht temporaer zurueckgeben, dann
#    ReadOnly setzen, dann wieder entziehen. Ohne den Zwischenschritt
#    schlaegt IsReadOnly fehl, weil der Benutzer sich die
#    Schreibrechte selbst entzogen hat.
# ------------------------------------------------------------
$exes = @(Get-ChildItem $spot -Filter '*.exe' -Recurse -EA SilentlyContinue)
foreach ($e in $exes) {
    & icacls $e.FullName /grant:r "$USER`:(M)" 2>&1 | Out-Null
    try { $e.IsReadOnly = $true } catch {}
    & icacls $e.FullName /inheritance:r `
        /grant:r "$USER`:(RX)" "$SYS`:(F)" "$ADM`:(F)" 2>&1 | Out-Null
}
$writeBlocked = $false
try {
    $fs = [System.IO.File]::Open("$spot\Spotify.exe", 'Open', 'Write', 'None'); $fs.Close()
    $writeBlocked = $false
} catch { $writeBlocked = $true }

# Lesen MUSS klappen, sonst startet Spotify nicht.
$readOk = $false
try {
    $fs = [System.IO.File]::Open("$spot\Spotify.exe", 'Open', 'Read', 'ReadWrite'); $fs.Close()
    $readOk = $true
} catch { $readOk = $false }

Log "EXE-Sperre: $($exes.Count) Dateien, ueberschreiben-blockiert=$writeBlocked lesen-moeglich=$readOk"
if (-not $readOk) {
    Log 'KRITISCH: Lesen blockiert - Spotify wuerde nicht starten. EXE-ACL wird zurueckgesetzt.'
    foreach ($e in $exes) {
        & icacls $e.FullName /inheritance:e /reset 2>&1 | Out-Null
        & icacls $e.FullName /grant:r "$USER`:(RX)" "$SYS`:(F)" "$ADM`:(F)" 2>&1 | Out-Null
        try { $e.IsReadOnly = $false } catch {}
    }
    $fs = [System.IO.File]::Open("$spot\Spotify.exe", 'Open', 'Read', 'ReadWrite')
    $fs.Close()
    Log 'EXE-ACL zurueckgesetzt, Lesen klappt wieder.'
}

# ------------------------------------------------------------
# 3) Spotify-interne Update-Schalter - bei JEDEM Lauf neu setzen.
#    Spotify entfernt diese Werte beim Update wieder.
# ------------------------------------------------------------
# Wichtig: "New-Item -Force" auf einem BEREITS EXISTIERENDEN
# Registry-Schluessel loescht dessen Werte. Deshalb nur anlegen,
# wenn er fehlt - sonst bleibt am Ende nur der letzte Wert stehen.
# (Genau das ist passiert: EnableUpdate und AutoUpdate waren
#  trotz korrektem Code nicht gesetzt.)
if (-not (Test-Path 'HKCU:\Software\Spotify')) {
    New-Item -Path 'HKCU:\Software\Spotify' -Force -EA SilentlyContinue | Out-Null
}
$regOk = 0
foreach ($pair in @(@('EnableUpdate', 0), @('AutoUpdate', 0), @('DisableUpdate', 1))) {
    try {
        Set-ItemProperty 'HKCU:\Software\Spotify' -Name $pair[0] -Value $pair[1] -Type DWord -Force -EA Stop
        $regOk++
    } catch { Log "FEHLER: HKCU $($pair[0]) nicht setzbar - $($_.Exception.Message)" }
}
# Gegenprobe: stehen die Werte danach wirklich drin?
$regCheck = (Get-ItemProperty 'HKCU:\Software\Spotify' -EA SilentlyContinue)
$regOk = 0
foreach ($n in 'EnableUpdate', 'AutoUpdate', 'DisableUpdate') {
    if ($null -ne $regCheck.$n) { $regOk++ } else { Log "FEHLER: HKCU $n fehlt nach dem Setzen weiterhin" }
}
Log "Update-Schalter in HKCU: $regOk von 3 gesetzt"

# ------------------------------------------------------------
# 4) Versionspruefung - ein Update darf hier NICHT still durchgehen.
#    Der alte Text ("der Waechter bekommt diese Version neu
#    zugeteilt") hat ein echtes Update als Erfolg gemeldet.
# ------------------------------------------------------------
$current = ''
if (Test-Path "$spot\Spotify.exe") {
    $current = (Get-Item "$spot\Spotify.exe").VersionInfo.ProductVersion
}
if ($current -and $current -ne $WANTED_VERSION) {
    Log "WARNUNG: Spotify ist auf $current, gepinnt ist $WANTED_VERSION - Update hat stattgefunden."
    $alert = "$env:USERPROFILE\Desktop\Spotify wurde aktualisiert.txt"
    @(
        "Spotify wurde auf Version $current aktualisiert.",
        "Gepinnte Version: $WANTED_VERSION",
        "",
        "Die Update-Sperre wurde durchbrochen.",
        "",
        "Zurueckrollen: 'Spotify Spicetify reparieren.cmd' in diesem Paket",
        "starten, danach 'Status anzeigen.cmd' zur Kontrolle.",
        "",
        "Erkannt am: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    ) | Set-Content -Path $alert -Encoding UTF8
} else {
    Log "Version $current ist die gepinnte Version."
}

# ------------------------------------------------------------
# 5) Spicetify-Patch pruefen und ggf. neu anwenden
# ------------------------------------------------------------
$idxPath = "$spot\Apps\xpui\index.html"
$patched = $false
if (Test-Path $idxPath) {
    $idx = Get-Content $idxPath -Raw
    $patched = ($idx -match 'Spicetify\.Config') -and ($idx -match 'xpui-modules\.js')
}

if (-not $patched) {
    Log "Spicetify-Patch fehlt - wird neu angewendet"
    Get-Process Spotify -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 4

    New-Item -ItemType Directory -Force -Path "$spice\Themes\marketplace" | Out-Null
    if (-not (Test-Path "$spice\Themes\marketplace\color.ini")) { Set-Content "$spice\Themes\marketplace\color.ini" -Value '[Marketplace]' }
    if (-not (Test-Path "$spice\Themes\marketplace\user.css"))  { New-Item -ItemType File -Path "$spice\Themes\marketplace\user.css" -Force | Out-Null }

    & $bin config experimental_features 1 | Out-Null
    & $bin config current_theme marketplace      | Out-Null
    & $bin config custom_apps marketplace        | Out-Null
    & $bin backup | Out-Null
    & $bin apply  | Out-Null

    $idx2 = Get-Content $idxPath -Raw
    if (($idx2 -match 'Spicetify\.Config') -and ($idx2 -match 'xpui-modules\.js')) {
        Log "Patch erfolgreich wiederhergestellt"
    } else {
        Log "FEHLER: Patch weiterhin nicht vorhanden"
    }

    # Sperre nach dem Apply erneut setzen (Apply schreibt in den Ordner)
    Set-FolderLock
    foreach ($e in @(Get-ChildItem $spot -Filter '*.exe' -Recurse -EA SilentlyContinue)) {
        & icacls $e.FullName /grant:r "$USER`:(M)" 2>&1 | Out-Null
        try { $e.IsReadOnly = $true } catch {}
        & icacls $e.FullName /inheritance:r `
            /grant:r "$USER`:(RX)" "$SYS`:(F)" "$ADM`:(F)" 2>&1 | Out-Null
    }
    Start-Process "$spot\Spotify.exe"
} else {
    Log "Patch intakt - keine Aktion noetig"
}