# Spotify Update-Sperre, die wirklich haelt — mit Spicetify

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://learn.microsoft.com/powershell/)
[![Windows](https://img.shields.io/badge/Windows-10%20%2F%2011-0078D6.svg)](https://www.microsoft.com/windows)

> **Kurzfassung:** Wer Spotify auf eine feste Version nageln will, hat es
> mit einer Schreibschutz-Sperre auf den `.exe`-Dateien versucht. Das
> funktioniert nicht. Spotify **löscht** die gesperrten Dateien und legt
> sie neu an — die Sperre ist damit wertlos. Die Abhilfe steht in diesem
> Repo, samt den drei Windows-Fallen, die einen selbst in eine halb
> installierte Spotify-Version laufen lassen.

> **Womit das getestet ist — und womit nicht:** Alle Messungen in diesem
> README stammen von **einem** Rechner: Windows 11 Pro x64 mit der
> **klassischen Spotify-Installation** (also der `.exe` aus dem
> Spotify-Installer, installiert nach `%APPDATA%\Spotify`). PowerShell 5.1,
> Spicetify 2.45.3, auf 1.3.1.234 festgenagelt.
>
> **Ungeprüft ist die Microsoft-Store-Variante** (MSIX-Paket). Dort liegen
> die Dateien in einem geschützten `WindowsApps`-Verzeichnis statt in
> `%APPDATA%\Spotify`; Ordnerpfad, ACLs und Rechtevererbung sind anders, und
> der Installer gehorcht anderen Regeln. Auf Store-Installationen kann dieses
> Skript **nichts** verheißen — dort bitte nicht blind laufen lassen.
>
> Auch innerhalb der klassischen Installation ist ein Teil empirisch, ein
> Teil plausibel geschlossen. Was gemessen wurde und was nicht, steht in
> [Bekannte Grenzen](#bekannte-grenzen).

---

## Inhalt

- [Das Problem](#das-problem)
- [Die eigentliche Ursache](#die-eigentliche-ursache)
- [Die zweite Hälfte: das halb installierte Update](#die-zweite-hälfte-das-halb-installierte-update)
- [Was dieses Repo macht](#was-dieses-repo-macht)
- [Schnellstart](#schnellstart)
- [Die Dateien](#die-dateien)
- [Technische Details](#technische-details)
- [Drei Windows-Fallen](#drei-windows-fallen)
- [Prüfen, ob es hält](#prüfen-ob-es-hält)
- [Reboot-Test](#reboot-test)
- [Alles rückgängig machen](#alles-rückgängig-machen)
- [Bekannte Grenzen](#bekannte-grenzen)
- [Mitmachen](#mitmachen)

---

## Das Problem

Wer Spicetify mit Marketplace nutzt, hat ein Interesse daran, dass Spotify
**genau die Version** behält, auf der Spicetify getestet wurde. Spicetify
patcht die Oberfläche direkt in den Spotify-Bundle. Aktualisiert sich Spotify,
ist der Patch weg — oder schlimmer, Spotify startet gar nicht mehr.

Der naheliegende Fix: die Programmdateien schützen. Read-only-Flag
setzen, Schreibrechte entziehen, Registry-Schalter setzen, Dienste
abschalten. Das lässt sich alsSkript schreiben, das „grün" meldet.

**Und genau hier wird es gefährlich:** Das Skript meldet Erfolg, während
die Sperre nichts tut.

---

## Die eigentliche Ursache

Der Fehler ist nicht im Code, sondern im Denkmodell. Ein kleines
Experiment genügt:

```
# Datei schreibgeschützt machen und Schreibrechte entziehen
icacls Spotify.exe /inheritance:r /grant:r *<SID>:(RX)

# Gegenprobe: Datei löschen
Remove-Item Spotify.exe -Force
```

**Das Löschen klappt.** Und damit ist alles erledigt.

`FullControl` auf einem **Ordner** enthält das Recht `FILE_DELETE_CHILD`.
Solange der Benutzer dieses Recht im Ordner hat, kann er dort Dateien
löschen — auch Dateien, die selbst gegen Löschung geschützt sind. Die
Schutzrechte *an der Datei* werden umgangen, indem man die Datei weglöscht
und eine neue schreibt. Die neue erbt wieder die vollen Rechte.

Bedeutung: **Eine Schreibschutz-Sperre auf Dateien ist gegen einen Installer
grundsätzlich wirkungslos.** Richtig ist, den *Ordner* zu sperren:

```
icacls "%APPDATA%\Spotify" /inheritance:r /grant:r \
    *<SID>:(OI)(CI)(RX,WD,AD)  *S-1-5-18:(OI)(CI)(F)  *S-1-5-32-544:(OI)(CI)(F)
```

| Recht | Wirkung |
|---|---|
| `RX` | lesen und ausführen — Spotify startet normal |
| `WD`, `AD` | neue Dateien und Ordner **anlegen** — Cache und Logs funktionieren |
| *kein* `D`, *kein* `DC` | **löschen ist unmöglich** — hier scheitert das Update |

Die Sperre ist damit keine Bremse gegen das Update, sondern gegen
selbstverschuldetes Durcheinanderbringen.

---

## Die zweite Hälfte: das halb installierte Update

Die Ordner-Sperre verhindert das *Ersetzen* der Dateien. Sie hindert Spotify
aber **nicht** am Herunterladen. Klickt der Benutzer im Spotify-Menü auf
*Update prüfen*, passiert Folgendes:

1. ~150 MB neues Paket landen in `%LOCALAPPDATA%\Spotify\Update\`
2. die neue `Apps\login.spa` wird geschrieben (gehört zur **neuen** Version)
3. **erst beim Ersetzen der `.exe`-Dateien scheitert es**

Übrig bleibt eine **halb neue, halb alte** Installation. Die gepinnte
Version findet eine fremde `login.spa`, startet nicht mehr und beendet sich
mit **Exit-Code 0** — also ohne jede Fehlermeldung. Dazu bleiben rund
1 GB `~TMP_`-Dateien im Installationsordner zurück.

Das ist die unangenehmste denkbare Fehlerform: kein Fehler, nur ein totes
Programm. Wer nicht weiß, wonach er suchen muss, vermutet Spotify selbst.

Der mitgelieferte Wächter räumt das beim nächsten Lauf selbst auf — Details
in [Was dieses Repo macht](#was-dieses-repo-macht).

---

## Was dieses Repo macht

Ein geprüfter Selbstheilungs-Wächter, der stündlich und bei jeder Anmeldung läuft:

1. **Hängenden Updater beenden** — er hält das Installationspaket offen,
   sonst lässt es sich nicht einmal mit Administratorrechten löschen.
2. **Update-Reste entfernen** — `~TMP_*-Dateien`, das heruntergeladene
   Paket und eine fremde `login.spa`.
3. **Ordner-Sperre setzen** und mit echten Gegenproben prüfen:
   *Anlegen* muss klappen, *Löschen* muss scheitern, *Lesen* muss klappen.
4. **Registry-Schalter** (`EnableUpdate`/`AutoUpdate`/`DisableUpdate`) bei
   jedem Lauf neu setzen — Spotify löscht sie beim Update wieder.
5. **Versionswechsel laut melden** statt ihn stillschweigend zu akzeptieren.
6. **Spicetify-Patch** wiederherstellen, falls er verloren ging.

Schlägt eine Gegenprobe fehl, steht das im Log. Der Wächter meldet nichts
als „in Ordnung", was nicht stimmt — und wenn eine Sperre zu dicht ist,
setzt er sie selbst zurück, damit Spotify in jedem Fall startet.

---

## Schnellstart

**Voraussetzungen:** Windows 10/11, PowerShell 5.1 (ist dabei), Internet
für die Erstinstallation.

```
git clone https://github.com/fallenangelsys/spotify-spicetify-fix.git
cd spotify-spicetify-fix\scripts
```

Dann [Spotify einrichten.cmd](scripts/Spotify%20einrichten.cmd) **doppelklicken**.

> **Wichtig:** *nicht* über „Als Administrator ausführen" starten.
> Das Skript fragt die Rechte selbst an. Manuell elevated überspringt die
> Installation, weil winget den Administratorkontext ablehnt:
> *„Das Installationsprogramm kann nicht in einem Administratorkontext
> ausgeführt werden."*

Der Ablauf ist zweistufig und dauert 5–15 Minuten:

| Phase | Aufgabe | Rechte |
|---|---|---|
| 1 | Spotify installieren | normale Benutzerrechte |
| 2 | Update-Sperre, Spicetify, Wächter | Administrator (Skript fragt) |

**Spicetify-Version:** Für Spotify 1.3.x wird **2.45.3** empfohlen
(aktuellste stabile Version). winget liefert derzeit nur 2.45.1 — das
Skript nimmt diese Variante, damit auf einem fremden PC überhaupt erst mal
etwas läuft. Wer exakt 2.45.3 möchte, lädt sie vorher selbst:

```
https://github.com/spicetify/cli/releases/latest
→ spicetify-2.45.3-windows-x64.zip
```

Nach dem Entpacken den Ordner `%LOCALAPPDATA%\spicetify` in den PATH
aufnehmen, dann `spicetify --version` prüfen (meldet `2.45.3`).

---

## Die Dateien

| Datei | Zweck |
|---|---|
| [`scripts/Spotify einrichten.cmd`](scripts/Spotify%20einrichten.cmd) | Hauptskript. Einfach doppelklicken. |
| [`scripts/Status anzeigen.cmd`](scripts/Status%20anzeigen.cmd) | Prüft alles, ändert nichts. Braucht kein Admin. |
| [`scripts/Updates wieder erlauben.cmd`](scripts/Updates%20wieder%20erlauben.cmd) | Hebt **alles** auf und prüft die Freigabe danach. |
| [`scripts/spotify-alles-einrichten.ps1`](scripts/spotify-alles-einrichten.ps1) | Das Skript hinter den Doppelklick-Dateien. |
| [`scripts/spotify-update-guard.ps1`](scripts/spotify-update-guard.ps1) | Der Selbstheilungs-Wächter. Läuft stündlich. |
| [`scripts/spotify-updates-freigeben.ps1`](scripts/spotify-updates-freigeben.ps1) | Gegenstück, hebt die Sperre vollständig auf. |
| [`scripts/repair-spicetify.ps1`](scripts/repair-spicetify.ps1) | Rollback auf die gepinnte Version. |
| [`docs/LIES-MICH.txt`](docs/LIES-MICH.txt) | Anleitung für Endanwender, ohne Fachbegriffe. |

Direkt aufrufbar:

```powershell
# Einrichtung
powershell -ExecutionPolicy Bypass -File .\scripts\spotify-alles-einrichten.ps1

# Nur prüfen, nichts ändern (kein Admin nötig)
powershell -ExecutionPolicy Bypass -File .\scripts\spotify-alles-einrichten.ps1 -Check

# Wächter einmalig ausführen
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\spotify-update-guard.ps1"
```

---

## Technische Details

**Ordner-ACL von `%APPDATA%\Spotify`:**

| Principals | Rechte | Wirkung |
|---|---|---|
| angemeldeter Benutzer | `RX, WD, AD` | lesen, ausführen, anlegen — löschen: nein |
| `S-1-5-18` (SYSTEM) | `FullControl` | Dienste dürfen arbeiten |
| `S-1-5-32-544` (Administratoren) | `FullControl` | Reparatur bleibt möglich |

Die Vererbung wird abgeschaltet (`/inheritance:r`), weil sonst das vom
Elternordner geerbte `FullControl` stehen bleibt — und `RemoveAccessRule`
kann geerbte Regeln nicht entfernen.

**Registry-Schalter**

| Schlüssel | Wert | Zweck |
|---|---|---|
| `HKCU\Software\Spotify\EnableUpdate` | `0` | Spotify-interne Selbstupdates aus |
| `HKCU\Software\Spotify\AutoUpdate` | `0` | dito |
| `HKCU\Software\Spotify\DisableUpdate` | `1` | dito |

**Geplanter Task `SpotifyUpdateGuard`**

| Eigenschaft | Wert |
|---|---|
| Trigger | Anmeldung + stündlich |
| Aktion | `powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File %LOCALAPPDATA%\spotify-update-guard.ps1` |
| RunLevel | `Limited` — die Ordnerrechte gehören dem Benutzer, Admin ist nicht nötig |

**Log:** `%APPDATA%\spicetify\update-guard.log` — eine Zeile je Lauf:

```
[2026-10-05 14:14:49] Heruntergeladenes Update-Paket wird entfernt: 1 Dateien, 149.4 MB
[2026-10-05 14:14:49] Update-Reste im Ordner: 40 ~TMP_-Dateien, 1 login.spa - werden entfernt
[2026-10-05 14:14:49] Update-Reste entfernt.
[2026-10-05 14:14:49] Ordner-Sperre: anlegen=True loeschen-blockiert=True
[2026-10-05 14:14:50] EXE-Sperre: 6 Dateien, ueberschreiben-blockiert=True lesen-moeglich=True
[2026-10-05 14:14:50] Update-Schalter in HKCU: 3 von 3 gesetzt
[2026-10-05 14:14:50] Version 1.3.1.234 ist die gepinnte Version.
[2026-10-05 14:14:50] Patch intakt - keine Aktion noetig
```

---

## Drei Windows-Fallen

Alle drei sind hier aufgelaufen und empirisch geprüft. Sie sind der Grund,
warum die Skripte so aussehen, wie sie aussehen.

**1. `icacls /deny ... (D)` nimmt den Prozess mit.** icacls hängt an `(D)`
automatisch `Synchronize` an. Ohne `Synchronize` lässt sich die Datei nicht
einmal mehr *öffnen*. Getestet: Lesen schlug fehl, Spotify startete nicht
mehr. Deshalb wird die Sperre über eine positive `Allow`-Regel gesetzt.

**2. `Set-Acl` bricht mit `PrivilegeNotHeldException` ab.** Der
`FileSystemAccessRule`-Weg verlangt `SeSecurityPrivilege`. Die Rechte werden
dann nur *teilweise* geschrieben — im Test fehlten die Administrator-Regeln
und der Ordner war anschließend halb gesperrt. `icacls` braucht dieses
Recht nicht.

**3. `New-Item -Force` auf existierenden Registry-Schlüsseln löscht deren
Werte.** Wer in einer Schleife `New-Item -Force` voranstellt, stellt am Ende
nur den *letzten* Wert fest. Getestet: `EnableUpdate` und `AutoUpdate` waren
trotz korrektem Skriptcode nicht gesetzt. Abhilfe: nur anlegen, wenn der
Schlüssel fehlt.

---

## Prüfen, ob es hält

`Status anzeigen.cmd` doppelklicken — ändert nichts, braucht kein Admin:

```
[6] Verifikation
    OK   Version 1.3.1.234.g59d6bf59 - wie gewuenscht
    OK   6 EXE-Dateien sind schreibgeschuetzt
    OK   Ordner-Sperre haelt: Loeschen im Spotify-Ordner ist blockiert
    OK   Spicetify-Patch sitzt
```

Entscheidend ist die dritte Zeile. Steht dort ein Fehler, hat die Sperre
nicht gegriffen — dann lohnt auch der Rest nichts.

---

## Reboot-Test

Durchgeführt am **5.10.2026**, Rechner heruntergefahren und wieder
gestartet. Der Wächter läuft über den Anmelde-Trigger und war **29
Sekunden** nach dem Booten durch (`LastBootUpTime 20:32:08`, erster
Log-Eintrag `20:32:37`):

```
[2026-10-05 20:32:37] Ordner-Sperre: anlegen=True loeschen-blockiert=True
[2026-10-05 20:32:38] EXE-Sperre: 6 Dateien, ueberschreiben-blockiert=True lesen-moeglich=True
[2026-10-05 20:32:38] Update-Schalter in HKCU: 3 von 3 gesetzt
[2026-10-05 20:32:38] Version 1.3.1.234 ist die gepinnte Version.
[2026-10-05 20:32:38] Patch intakt - keine Aktion noetig
```

Zusätzlich von Hand nachgemessen:

| Was | Ergebnis nach dem Neustart |
|---|---|
| `Spotify.exe` | `1.3.1.234`, Zeitstempel **13:24:14** — unverändert, nie neu deployed |
| Ordner-ACL | `5gtag:(OI)(CI)(RX,WD,AD)` — Sperre intakt, kein Delete |
| Registry | `EnableUpdate=0`, `AutoUpdate=0`, `DisableUpdate=1` |
| `%LOCALAPPDATA%\Spotify\Update` | existiert nicht — es wurde **kein** Update geladen |
| `~TMP_*` im Spotify-Ordner | 0 |
| Task | `State: Ready`, `LastTaskResult: 0` |

Entscheidend ist, was **fehlt**: In den Log-Einträgen nach dem Neustart
steht keine einzige Zeile `Heruntergeladenes Update-Paket wird entfernt`.
Vor dem Neustart, am 5.10. um 15:20, steht genau eine — mit 149,4 MB, die
der Wächter weggeräumt hat. Nach dem Neustart wurde also nicht einmal ein
Paket heruntergeladen. Das ist der Unterschied zwischen * Bremse* und
*Abwehr*, und er ist hier gemessen.

Die Einschränkung bleibt: Der Wächter setzt die Sperre bei jeder Anmeldung
neu. Der Test belegt also, dass der **Zustand** nach einem Reboot stimmt —
nicht, dass Windows die Rechte von allein bewahrt. Gegen einen Angreifer,
der zwischen zwei Wächterläufen (stündlich) handelt, schützt das nicht.

---

## Alles rückgängig machen

`Updates wieder erlauben.cmd` hebt **alles** auf: Ordner-Sperre,
EXE-Schutz, Registry, Dienste und den geplanten Task. Das Skript prüft
zum Schluss selbst, dass der Ordner wieder löschbar ist, und sagt es dir.

Es wird **nichts gelöscht** — keine Datei, keine Spotify-Einstellung.
Deine Playlist und dein Account bleiben unberührt.

---

## Bekannte Grenzen

Ehrlich benannt, statt hinter Erfolgsmeldungen versteckt:

- **Kein Riegel, nur eine Bremse.** Ein Klick auf *Update prüfen* lädt
  weiterhin ~150 MB herunter. Der Wächter räumt die Reste innerhalb einer
  Stunde weg, aber der Download selbst passiert.
- **Gilt für den angemeldeten Benutzer.** Wer Spotify als Administrator
  startet, umgeht die Sperre — die Administratoren behalten bewusst
  Vollzugriff, sonst käme Spotify nicht mehr an seine eigenen Daten und
  der Wächter nicht an die Reparatur.
- **Gegen Windows Update ist sie nicht immun.** Die geprüfte Version ist
  `1.3.1.234`; auf einem anderen Stand installiert das Skript die jeweils
  aktuelle Version und nagelt sie fest.
- **Nur auf der klassischen Installation getestet.** Siehe den Hinweis oben:
  gemessen wurde auf Windows 11 mit der `.exe`-Installation nach
  `%APPDATA%\Spotify`. Die Store-/MSIX-Variante ist ein anderer
  Installationspfad mit anderen Rechten und **ungeprüft**.
- **Der Reboot ist getestet, aber mit einer Einschränkung.** Der
  Endzustand nach einem Neustart stimmt — siehe
  [Reboot-Test](#reboot-test). Was dabei *nicht* bewiesen ist: ob Windows
  die ACL von allein behält. Der Wächter setzt sie bei jeder Anmeldung neu,
  also wäre ein Verlust unsichtbar. Gemessen ist der Zustand, nicht seine
  Lebensdauer.
- **`Updates wieder erlauben.cmd` wurde nie ausgeführt.** Das Skript
  dahinter ist geschrieben und syntaktisch geprüft, aber ein Test des
  Widerrufs steht aus. Vor dem ersten Gebrauch also mit einem Blick in die
  Log-Ausgabe prüfen.
- **Die Zielversion ist ein Startwert, kein Versprechen.** In
  `spotify-alles-einrichten.ps1` und im Wächter steht `1.3.1.234`. Das
  Skript lädt **keinen** alten Installer nach. Findet es nach der
  Installation eine andere Version, meldet das nur eine Abweichung
  („Kein Problem") und schreibt die tatsächlich vorhandene Version in den
  Wächter — **gepinnt wird also, was gerade installiert ist.** Wer bewusst
  eine alte Version braucht, installiert sie vorher von Hand und startet
  danach erst dieses Skript.
- **Spotify und Spicetify sind Fremdmarken.** Dieses Projekt steht in
  keiner Verbindung zu Spotify AB oder Spicetify.

---

## Mitmachen

Beiträge sind willkommen, besonders wenn du einen der folgenden Fälle
unter Windows 10 oder 11 reproduzieren und dokumentieren kannst:

- ein Reboot-Test auf **Windows 10** (hier nur auf Windows 11 gemessen)
- ob die ACL einen Neustart *ohne* den Wächter übersteht, also mit
  deaktiviertem Task — so lässt sich die beiden Wirkungen trennen
- Verhalten unter Windows 11 mit den Store-/MSIX-Installation von Spotify
- Verhalten bei frisch installiertem Spotify ohne Vorinstallation

Fehlerberichte mit Auszug aus `%APPDATA%\spicetify\update-guard.log` helfen
am schnellsten.

```powershell
# Lokal testen, ohne zu installieren
powershell -ExecutionPolicy Bypass -File .\scripts\spotify-alles-einrichten.ps1 -Check
```

---

## Haftungsausschluss

Dieses Projekt wird ohne jede Gewährleistung bereitgestellt. Es greift in
eine laufende Anwendung ein, setzt Zugriffsrechte und verwaltet einen
geplanten Task. **Erstelle vor der Nutzung einen vollständigen Backup.**

Verwendet auf eigene Gefahr.

---

## Sprache

Dieses README ist auf Deutsch verfasst. Die ausführliche
Anleitung für Endanwender ohne Fachkenntnisse liegt in
[`docs/LIES-MICH.txt`](docs/LIES-MICH.txt).

---

<div align="center">

**Made with determination against one specific Windows ACL bug.**

`MIT` · [Issues](https://github.com/fallenangelsys/spotify-spicetify-fix/issues) · [`main`](https://github.com/fallenangelsys/spotify-spicetify-fix)

</div>