# Eigene Update- und Versionsquelle

Ein eigener HAOS-Build allein ist noch keine vollständig eigene Update-Kette. Der aktuelle HAOS-Bootstrap und der aktuelle Supervisor lesen ihre Versionsdaten standardmäßig von `version.home-assistant.io`. Außerdem enthält der Manifest-Datensatz die Download-URL der HAOS-RAUC-Bundles und die Container-Images für Supervisor, Core und Plugins.

Für eine dauerhaft kontrollierte Fork-Linie werden daher mindestens drei Repositories benötigt:

1. `operating-system` – bereits vorhandener HAOS-Fork
2. `supervisor` – eigene Versionsquelle im laufenden Supervisor
3. `version` – eigene `stable.json`, `beta.json`, `dev.json` und AppArmor-Dateien

`core` ist erst erforderlich, wenn Home Assistant Core selbst geändert werden soll.

## 1. Supervisor- und Version-Fork anlegen

Mit authentifizierter GitHub CLI:

```bash
bash fork/scripts/setup-control-plane-forks.sh \
  --workspace "$HOME/src/ha-fork"
```

Optional zusätzlich Core:

```bash
bash fork/scripts/setup-control-plane-forks.sh \
  --workspace "$HOME/src/ha-fork" \
  --with-core
```

Das Skript akzeptiert vorhandene Repositories nur, wenn GitHub sie als Fork des exakt erwarteten Home-Assistant-Repositories meldet. Es überschreibt keine gleichnamigen, unabhängigen Repositories.

Erwartete Upstream-Branches für diese Fork-Linie:

- `home-assistant/supervisor`: `main`
- `home-assistant/version`: `master`
- `home-assistant/core`: `dev`

## 2. Gemeinsame Manifest-Basis festlegen

Für den Benutzer `Chris-Curt` ist die vorgesehene öffentliche Basis nach Erzeugung des Version-Forks:

```text
https://raw.githubusercontent.com/Chris-Curt/version/master
```

Diese Basis muss in HAOS und Supervisor gemeinsam verwendet werden.

```bash
bash fork/scripts/configure-control-plane.sh \
  --manifest-base https://raw.githubusercontent.com/Chris-Curt/version/master \
  --haos "$HOME/src/ha-fork/operating-system" \
  --supervisor "$HOME/src/ha-fork/supervisor"
```

Das Skript ändert genau:

- HAOS `HASSIO_VERSION_URL`
- Supervisor `URL_HASSIO_VERSION`
- Supervisor `URL_HASSIO_APPARMOR`

Wenn eine der erwarteten Zuweisungen nach einem Upstream-Update nicht mehr eindeutig vorhanden ist, bricht das Skript ab. Änderungen in beiden Repositories gemeinsam reviewen und committen.

## 3. Sicheren amd64-Supervisor-Workflow installieren

Für Proxmox/OVA und generic-x86-64 wird ausschließlich `amd64` benötigt. Der Overlay-Workflow übernimmt die sicherheitsrelevanten Teile des aktuellen Upstream-Builds:

- lokale `musllinux_1_2`-Wheels für amd64,
- Supervisor-Source-Hash,
- keyless Cosign-Bundle für den Source-Hash,
- Verifikation des offiziellen Home-Assistant-Base-Images,
- Buildx/GitHub-Actions-Cache,
- signierten GHCR-Container über den aktuellen Home-Assistant-Builder.

Installation in den Supervisor-Fork:

```bash
bash fork/scripts/install-supervisor-overlay.sh \
  --supervisor "$HOME/src/ha-fork/supervisor"
```

Danach im Supervisor-Fork den neuen Workflow reviewen, committen und nach `main` bringen. Ein Publish wird absichtlich nur manuell mit einer expliziten Version gestartet, zum Beispiel:

```bash
gh workflow run fork-supervisor-build.yml \
  --repo Chris-Curt/supervisor \
  --ref main \
  -f version=YOUR_SUPERVISOR_VERSION
```

Der Workflow akzeptiert nur Docker-kompatible Tags und veröffentlicht:

```text
ghcr.io/chris-curt/amd64-hassio-supervisor:YOUR_SUPERVISOR_VERSION
```

Nach dem ersten Publish muss dieses GHCR-Package öffentlich lesbar sein, bevor ein HAOS-System im Manifest darauf verweist. Ein privates Package würde beim unauthentifizierten Container-Pull des installierten Systems scheitern.

**Noch nicht auf die eigene Manifest-Quelle umschalten, solange dieser Container nicht erfolgreich veröffentlicht, öffentlich lesbar und geprüft wurde.**

## 4. Manifest für zwei Targets vorbereiten

Erst wenn eine konkrete eigene Supervisor-Version veröffentlicht ist, den gewünschten Kanal im Version-Fork aktualisieren. Beispiel für Stable:

```bash
python3 fork/scripts/prepare-version-manifest.py \
  --version-repo "$HOME/src/ha-fork/version" \
  --channel stable \
  --os-version 18.4 \
  --supervisor-version YOUR_SUPERVISOR_VERSION \
  --github-owner Chris-Curt
```

Das Skript verlangt explizite Versionswerte und erfindet keine Versionsnummern. Es setzt:

```text
hassos:
  ova: <OS-Version>
  generic-x86-64: <OS-Version>

homeassistant:
  default: <bestehender Core-Wert>
  qemux86-64: <bestehender Core-Wert>
  generic-x86-64: <bestehender Core-Wert>

images.supervisor:
  ghcr.io/chris-curt/{arch}-hassio-supervisor

ota:
  https://github.com/Chris-Curt/operating-system/releases/download/{version}/{os_name}_{board}-{version}.raucb
```

Die übrigen aktuellen Plugin- und Upgrade-Werte aus dem Quellmanifest bleiben erhalten.

Für `beta` oder `dev` entsprechend `--channel beta` bzw. `--channel dev` verwenden und ausschließlich tatsächlich veröffentlichte HAOS-/Supervisor-Versionen eintragen.

## 5. Optional: eigener Core

Solange Core nicht verändert wird, können die vorhandenen Home-Assistant-Core-Versionen und Images im Version-Fork unverändert bleiben. Das reduziert die Fork-Oberfläche erheblich.

Wenn später ein eigener Core-Container veröffentlicht wird, kann der Generator beide Werte gemeinsam umstellen:

```bash
python3 fork/scripts/prepare-version-manifest.py \
  --version-repo "$HOME/src/ha-fork/version" \
  --channel stable \
  --os-version 18.4 \
  --supervisor-version YOUR_SUPERVISOR_VERSION \
  --github-owner Chris-Curt \
  --core-version YOUR_CORE_VERSION \
  --core-image-template 'ghcr.io/chris-curt/{machine}-homeassistant'
```

`--core-version` und `--core-image-template` müssen absichtlich gemeinsam gesetzt werden, damit ein Manifest nicht auf eine Version zeigt, für die kein passendes Image veröffentlicht wurde.

## 6. Reihenfolge für eine echte Umstellung

Die sichere Reihenfolge ist:

1. HAOS-Build für OVA und generic-x86-64 vollständig erfolgreich verifizieren.
2. Dauerhafte RAUC-PKI konfigurieren und sichern.
3. Guarded GitHub-Release-Pfad aktivieren und ein Test-/RC-Release erzeugen.
4. Supervisor- und Version-Fork anlegen.
5. Versions- und AppArmor-URLs im Supervisor-Fork vorbereiten.
6. amd64-Supervisor-Overlay installieren und den eigenen Container bauen/signieren/veröffentlichen.
7. GHCR-Supervisor-Package öffentlich lesbar machen und den exakten Tag verifizieren.
8. Version-Fork auf diesen realen Supervisor-Tag sowie reale HAOS-Release-Artefakte setzen.
9. HAOS-Bootstrap auf dieselbe Version-Fork-URL umstellen.
10. Neue HAOS-Installation in Proxmox testen: erster Boot, Supervisor, Core, AppArmor, Update-Prüfung.
11. RAUC-Update von einer eigenen Version auf die nächste testen.
12. Erst danach USB/Bare-Metal-Upgradepfad freigeben.

Damit gibt es zu keinem Zeitpunkt ein Manifest, das auf noch nicht existierende Images oder Bundles verweist.

## 7. Was weiterhin offiziell bleiben kann

Solange diese Komponenten nicht verändert werden, können die offiziellen Container für DNS, Audio, CLI, Multicast und Observer im Manifest bleiben. Das hat keinen Einfluss darauf, dass nur Proxmox/OVA und generic-x86-64 als HAOS-Installationsziele unterstützt werden.

Eine zusätzliche Fork-Schicht für unveränderte Plugins erhöht Wartungsaufwand und Angriffsfläche ohne funktionalen Nutzen.
