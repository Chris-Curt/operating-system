# RAUC-PKI für den eigenen HAOS-Fork

Für einzelne Test-Builds kann HAOS selbst ein Development-Zertifikat erzeugen. Für eine dauerhaft updatefähige eigene Installation reicht das nicht: Ein bereits installiertes System muss auch den Signaturschlüssel späterer `.raucb`-Updates vertrauen.

## 1. Einmalig eine eigene PKI erzeugen

Im Root-Verzeichnis dieses Repositorys:

```bash
bash fork/scripts/generate-rauc-pki.sh
```

Das Skript erzeugt standardmäßig `.rauc-pki/` mit:

- `cert.pem` – öffentliches RAUC-Signaturzertifikat
- `key.pem` – privater Signaturschlüssel
- `RAUC_CERTIFICATE_B64.txt` – Base64-Wert für GitHub Actions
- `RAUC_PRIVATE_KEY_B64.txt` – Base64-Wert für GitHub Actions
- `certificate-fingerprint.txt` – SHA-256-Fingerprint des Zertifikats

`.rauc-pki/` und `*.pem` sind über `.gitignore` ausgeschlossen. Den privaten Schlüssel trotzdem separat und verschlüsselt sichern. Ohne diesen Schlüssel kann dieselbe OTA-Vertrauenskette nicht fortgeführt werden.

## 2. GitHub Actions Secrets anlegen

In GitHub unter `Settings -> Secrets and variables -> Actions` zwei Repository-Secrets anlegen:

- `RAUC_CERTIFICATE_B64`: kompletter Inhalt von `.rauc-pki/RAUC_CERTIFICATE_B64.txt`
- `RAUC_PRIVATE_KEY_B64`: kompletter Inhalt von `.rauc-pki/RAUC_PRIVATE_KEY_B64.txt`

Mit bereits authentifizierter GitHub CLI können beide Secrets ohne Copy/Paste gesetzt werden:

```bash
gh secret set RAUC_CERTIFICATE_B64 --repo Chris-Curt/operating-system < .rauc-pki/RAUC_CERTIFICATE_B64.txt
gh secret set RAUC_PRIVATE_KEY_B64 --repo Chris-Curt/operating-system < .rauc-pki/RAUC_PRIVATE_KEY_B64.txt
```

Die Dateien mit den Secret-Werten danach nicht verschicken oder committen. Der private Schlüssel und dessen Base64-Darstellung müssen wie Zugangsdaten behandelt werden.

Der Fork-Workflow dekodiert beide Werte zu `cert.pem` und `key.pem`, prüft Zertifikat und Private Key sowie deren öffentlichen Schlüssel gegeneinander und löscht das Schlüsselmaterial nach dem Build wieder vom Runner.

Die alten Secrets `RAUC_CERTIFICATE` und `RAUC_PRIVATE_KEY` werden vorerst weiter unterstützt. Für neue Setups sollen ausschließlich die Base64-Secrets verwendet werden.

## 3. Wichtige Regel für Updates

Die PKI nicht bei jedem Release neu erzeugen. Solange installierte Geräte Updates aus dieser Fork-Linie erhalten sollen, muss die Vertrauenskette stabil bleiben.

Ein Build ohne konfigurierte Repository-Secrets ist weiterhin möglich. HAOS erzeugt dann ein selbstsigniertes Development-Zertifikat. Ein solches Build eignet sich für Tests und Erstentwicklung, aber nicht als Grundlage einer dauerhaft reproduzierbaren eigenen OTA-Release-Kette.

## 4. Rotation eines Schlüssels

Eine Schlüsselrotation darf nicht dadurch erfolgen, dass einfach ein neuer Private Key in GitHub hinterlegt wird. Zuerst muss ein Übergangs-Image ausgeliefert werden, dessen RAUC-Keyring sowohl dem alten als auch dem neuen Zertifikat vertraut. Erst nachdem alle relevanten Systeme dieses Übergangs-Image installiert haben, kann ausschließlich mit dem neuen Schlüssel signiert werden.
