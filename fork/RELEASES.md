# Releases für den Proxmox- und USB-Fork

Dieser Fork veröffentlicht ausschließlich die beiden unterstützten Installationsformen plus deren RAUC-Update-Bundles:

- `haos_ova-<version>.qcow2.xz`
- `haos_ova-<version>.raucb`
- `haos_generic-x86-64-<version>.img.xz`
- `haos_generic-x86-64-<version>.raucb`
- `SHA256SUMS`

Andere VM-Formate werden nicht erzeugt oder veröffentlicht.

## Voraussetzungen

Vor dem ersten echten Release muss eine dauerhafte RAUC-PKI eingerichtet sein. Siehe `fork/RAUC-PKI.md`.

Der Release-Workflow verweigert einen GitHub-Release, wenn kein permanentes RAUC-Zertifikat/Private-Key-Paar hinterlegt ist. Für Release-Builds gibt es keinen Development-Self-Signed-Fallback. Das Zertifikat muss außerdem noch mindestens 760 Tage gültig sein.

Vor einem Release müssen die normalen Fork-Checks und mindestens ein erfolgreicher Entwicklungs-Build für beide Targets vorliegen.

## Release Candidate

Beispiel für `18.4.rc1`:

```bash
bash fork/scripts/prepare-release-meta.sh rc 1
git diff -- buildroot-external/meta
```

Erwartete Metadaten:

```text
VERSION_MAJOR="18"
VERSION_MINOR="4"
VERSION_SUFFIX="rc1"
DEPLOYMENT="staging"
```

Die Änderung normal per Branch/PR nach `dev` bringen. Anschließend auf genau diesem gemergten Commit einen GitHub-Release mit Tag `18.4.rc1` erstellen und als **Prerelease** markieren.

Der Release-Workflow akzeptiert einen Prerelease nur, wenn:

- GitHub-Tag und HAOS-Metadatenversion exakt übereinstimmen,
- `DEPLOYMENT="staging"` gesetzt ist,
- `VERSION_SUFFIX` dem Format `rcN` entspricht,
- die permanente RAUC-PKI vorhanden und gültig ist,
- beide Ziel-Builds erfolgreich sind.

Erst danach werden die fünf Release-Dateien an den bestehenden GitHub-Release angehängt.

## Stable Release

Für das stabile `18.4`:

```bash
bash fork/scripts/prepare-release-meta.sh stable
git diff -- buildroot-external/meta
```

Erwartete Metadaten:

```text
VERSION_MAJOR="18"
VERSION_MINOR="4"
VERSION_SUFFIX=""
DEPLOYMENT="production"
```

Die Änderung wieder per Branch/PR nach `dev` bringen. Danach einen normalen GitHub-Release mit dem exakten Tag `18.4` erstellen; **nicht** als Prerelease markieren.

Stable wird verweigert, wenn der Suffix nicht leer oder das Deployment nicht `production` ist.

## Zurück in den Entwicklungsmodus

Nach einem RC oder Stable Release muss `dev` wieder auf Entwicklungsmetadaten gesetzt werden, bevor normale Weiterentwicklung fortgesetzt wird:

```bash
bash fork/scripts/prepare-release-meta.sh dev
git diff -- buildroot-external/meta
```

Erwartet:

```text
VERSION_SUFFIX="dev0"
DEPLOYMENT="development"
```

Diese Reset-Änderung ebenfalls committen und nach `dev` mergen. Der automatische Development-Workflow ersetzt `dev0` für jeden Build durch einen eindeutigen `dev<run-number>`-Suffix.

## Release-Artefakte prüfen

Der Workflow prüft vor Veröffentlichung:

1. exakt ein QCOW2-XZ und ein OVA-RAUC-Bundle,
2. exakt ein generic-x86-64 IMG-XZ und ein generic RAUC-Bundle,
3. Dateinamen müssen exakt zum Release-Tag passen,
4. beide XZ-Dateien müssen `xz -t` bestehen,
5. aus genau diesen vier Binärdateien wird eine gemeinsame `SHA256SUMS` erzeugt.

Die Veröffentlichung erfolgt erst nach zwei erfolgreichen Matrix-Builds. Damit kann kein teilweise gebauter Release veröffentlicht werden.

## Schlüsselrotation

Einen RAUC-Schlüssel niemals unmittelbar ersetzen und danach einfach einen neuen Release veröffentlichen. Für eine Rotation ist zuerst ein Übergangs-Image erforderlich, das altem und neuem Zertifikat vertraut. Details stehen in `fork/RAUC-PKI.md`.
