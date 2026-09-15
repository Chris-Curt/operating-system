#!/usr/bin/env bash
set -euo pipefail

OUTPUT_DIR="${1:-.rauc-pki}"

command -v openssl >/dev/null || { echo "ERROR: openssl not found" >&2; exit 1; }
command -v base64 >/dev/null || { echo "ERROR: base64 not found" >&2; exit 1; }
command -v sha256sum >/dev/null || { echo "ERROR: sha256sum not found" >&2; exit 1; }

if [[ -e "${OUTPUT_DIR}" ]]; then
  echo "ERROR: Refusing to overwrite existing path: ${OUTPUT_DIR}" >&2
  echo "Move or remove it explicitly before generating a new RAUC PKI." >&2
  exit 1
fi

umask 077
mkdir -p "${OUTPUT_DIR}"

KEY_FILE="${OUTPUT_DIR}/key.pem"
CERT_FILE="${OUTPUT_DIR}/cert.pem"
CERT_B64_FILE="${OUTPUT_DIR}/RAUC_CERTIFICATE_B64.txt"
KEY_B64_FILE="${OUTPUT_DIR}/RAUC_PRIVATE_KEY_B64.txt"
FINGERPRINT_FILE="${OUTPUT_DIR}/certificate-fingerprint.txt"

openssl genpkey \
  -algorithm RSA \
  -pkeyopt rsa_keygen_bits:4096 \
  -out "${KEY_FILE}"

openssl req \
  -x509 \
  -new \
  -key "${KEY_FILE}" \
  -sha256 \
  -days 3650 \
  -subj "/O=HAOS Fork/CN=HAOS Fork RAUC Signing" \
  -out "${CERT_FILE}"

openssl x509 -in "${CERT_FILE}" -noout >/dev/null
openssl pkey -in "${KEY_FILE}" -check -noout >/dev/null

cert_pub="$(openssl x509 -in "${CERT_FILE}" -pubkey -noout | openssl pkey -pubin -outform DER 2>/dev/null | sha256sum | cut -d' ' -f1)"
key_pub="$(openssl pkey -in "${KEY_FILE}" -pubout -outform DER 2>/dev/null | sha256sum | cut -d' ' -f1)"

if [[ "${cert_pub}" != "${key_pub}" ]]; then
  echo "ERROR: Generated certificate and private key do not match." >&2
  exit 1
fi

base64 < "${CERT_FILE}" | tr -d '\n' > "${CERT_B64_FILE}"
base64 < "${KEY_FILE}" | tr -d '\n' > "${KEY_B64_FILE}"
openssl x509 -in "${CERT_FILE}" -noout -fingerprint -sha256 > "${FINGERPRINT_FILE}"

chmod 600 "${KEY_FILE}" "${KEY_B64_FILE}"
chmod 644 "${CERT_FILE}" "${CERT_B64_FILE}" "${FINGERPRINT_FILE}"

echo
echo "RAUC PKI created in: ${OUTPUT_DIR}"
echo "Certificate fingerprint:"
cat "${FINGERPRINT_FILE}"
echo
echo "Create these GitHub Actions repository secrets:"
echo "  RAUC_CERTIFICATE_B64  <- ${CERT_B64_FILE}"
echo "  RAUC_PRIVATE_KEY_B64  <- ${KEY_B64_FILE}"
echo
echo "Keep ${KEY_FILE} and ${KEY_B64_FILE} private and backed up securely."
echo "Do not regenerate this PKI for each release; installed systems need the same trust chain for future RAUC updates."
