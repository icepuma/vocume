#!/bin/bash
# A stable code-signing identity for local builds, so macOS privacy permissions (Screen Recording,
# etc.) survive rebuilds. Ad-hoc signatures change with every build, and macOS ties permissions to
# the signature, so each ad-hoc build looks like a new app. This identity is the same every time.
#
#   scripts/dev-signing.sh          create it (once; safe to rerun)
#   scripts/dev-signing.sh --sign <app>   sign an app bundle with it (used by build.sh)
#   scripts/dev-signing.sh --remove       delete it
#
# It lives in its own keychain (not your login keychain) with a random local password, and is
# self-signed without changing any trust settings — codesign doesn't need trust, and the
# signature's designated requirement pins this exact certificate.
set -euo pipefail

NAME="Vocume Local Development"
DIR="$HOME/Library/Application Support/dev.icepuma.vocume"
KEYCHAIN="$DIR/dev-signing.keychain-db"
PASSWORD_FILE="$DIR/dev-signing.password"

unlock() { security unlock-keychain -p "$(cat "$PASSWORD_FILE")" "$KEYCHAIN"; }
exists() { [[ -f "$KEYCHAIN" && -f "$PASSWORD_FILE" ]]; }

case "${1:-}" in
  --sign)
    exists || { echo "No dev signing identity; run scripts/dev-signing.sh" >&2; exit 1; }
    unlock
    codesign --force --keychain "$KEYCHAIN" --sign "$NAME" "$2"
    exit 0
    ;;
  --remove)
    exists && security delete-keychain "$KEYCHAIN" || true
    rm -rf "$DIR"
    echo "Removed $NAME"
    exit 0
    ;;
  --check)
    exists
    exit $?
    ;;
esac

if exists; then
  echo "$NAME already set up ($KEYCHAIN)"
  exit 0
fi

mkdir -p "$DIR" && chmod 700 "$DIR"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
openssl rand -hex 24 > "$PASSWORD_FILE" && chmod 600 "$PASSWORD_FILE"
password=$(cat "$PASSWORD_FILE")

cat > "$work/codesign.cnf" <<CNF
[req]
prompt = no
distinguished_name = dn
x509_extensions = codesign
[dn]
CN = $NAME
[codesign]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
CNF
openssl req -newkey rsa:2048 -nodes -keyout "$work/key.pem" -x509 -days 3650 \
  -out "$work/cert.pem" -config "$work/codesign.cnf" >/dev/null 2>&1
openssl pkcs12 -export -legacy -inkey "$work/key.pem" -in "$work/cert.pem" -name "$NAME" \
  -out "$work/identity.p12" -passout "pass:$password" >/dev/null 2>&1

security create-keychain -p "$password" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"  # no auto-lock; build.sh unlocks it anyway
security unlock-keychain -p "$password" "$KEYCHAIN"
security import "$work/identity.p12" -k "$KEYCHAIN" -P "$password" -T /usr/bin/codesign >/dev/null
# Let codesign use the key without a keychain prompt.
security set-key-partition-list -S apple-tool:,apple: -s -k "$password" "$KEYCHAIN" >/dev/null

echo "Created $NAME in $KEYCHAIN"
