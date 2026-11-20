#!/bin/bash
# Scripts/make-local-signing-identity.sh: a code signing identity of this Mac's own, "Sill Viewer Local
# Signing", for a Mac with no Apple Development or Developer ID identity. Run it once, by hand: it adds a
# self-signed certificate and its private key to the login keychain (macOS may ask for the keychain's
# password), and changes nothing else (no trust setting, nothing system-wide).
#
# Why: an ad hoc signature changes with every build, and macOS keys a privacy grant (Accessibility,
# shown as Device Control, and Local Network) to the signature's designated requirement, so each ad hoc
# build of Sill Viewer is a new app to it and asks again, while System Settings shows the old build's
# switch on. Signed with this identity, the requirement names the certificate, which stays the same:
# a grant made once lasts across rebuilds. Scripts/make-client-app.sh uses it by itself when it finds it
# (after SILL_SIGN_IDENTITY, Developer ID and Apple Development). Only this Mac trusts nothing about it:
# Gatekeeper still treats the app as an unnotarized test build, as before.
#
# Undo: Keychain Access › login › My Certificates, delete "Sill Viewer Local Signing".
set -euo pipefail
name="Sill Viewer Local Signing"
if security find-identity -p codesigning 2>/dev/null | grep -q "\"$name\""; then
    echo "\"$name\" is already in the keychain."
    exit 0
fi
dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT
cat > "$dir/cert.conf" <<EOF
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = $name
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$dir/cert.conf" \
    -keyout "$dir/key.pem" -out "$dir/cert.pem" 2>/dev/null
pass="$(openssl rand -hex 16)"
openssl pkcs12 -export -inkey "$dir/key.pem" -in "$dir/cert.pem" -name "$name" \
    -out "$dir/identity.p12" -passout "pass:$pass"
security import "$dir/identity.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P "$pass" -T /usr/bin/codesign
echo "Added \"$name\" to the login keychain. The next Scripts/make-client-app.sh build signs with it."
