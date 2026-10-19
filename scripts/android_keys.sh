#!/usr/bin/env bash
# Android signing keys for Throttle.
#
# Google Sign-In on Android only works if the SHA-1 of the key that signed the
# APK is registered (with the package name) as an Android OAuth client in
# Google Cloud. This script creates the release key and prints every
# fingerprint you need to register.
#
#   scripts/android_keys.sh           Print SHA-1/SHA-256 for the debug key, the
#                                     release key, and the APK you last built.
#   scripts/android_keys.sh create    Create the release (upload) keystore once
#                                     and wire it into the Gradle build.
#
# Options (environment variables):
#   THROTTLE_KEYSTORE       Keystore path   (default: ~/.android/throttle-upload.jks)
#   THROTTLE_KEY_ALIAS      Key alias       (default: upload)
#   THROTTLE_KEY_DNAME      Certificate name (default: "CN=Throttle, O=WheelsClub")
#   THROTTLE_KEY_PROPERTIES key.properties  (default: android/key.properties)
#   THROTTLE_KEYSTORE_PASSWORD  Use this password instead of prompting (CI).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEYSTORE="${THROTTLE_KEYSTORE:-$HOME/.android/throttle-upload.jks}"
ALIAS="${THROTTLE_KEY_ALIAS:-upload}"
DNAME="${THROTTLE_KEY_DNAME:-CN=Throttle, O=WheelsClub}"
KEY_PROPERTIES="${THROTTLE_KEY_PROPERTIES:-$ROOT/android/key.properties}"
DEBUG_KEYSTORE="$HOME/.android/debug.keystore"
APK="$ROOT/build/app/outputs/flutter-apk/app-release.apk"

die() { echo "error: $*" >&2; exit 1; }

command -v keytool >/dev/null || die "keytool not found. Install a JDK (or use the one bundled with Android Studio)."

package_name() {
  sed -nE 's/.*applicationId *= *"([^"]+)".*/\1/p' "$ROOT/android/app/build.gradle.kts" | head -1
}

# Reads one value from key.properties.
prop() {
  sed -nE "s/^$1=(.*)$/\1/p" "$KEY_PROPERTIES" | head -1
}

# Prints the SHA-1 and SHA-256 lines of a keystore entry.
# Passwords go through the environment, never the command line.
fingerprints() {
  local store="$1" alias="$2" password="$3"
  KS_PASS="$password" keytool -list -v -keystore "$store" -alias "$alias" \
    -storepass:env KS_PASS 2>/dev/null |
    sed -nE 's/^[[:space:]]*(SHA1|SHA256): (.*)$/  \1: \2/p'
}

apksigner_bin() {
  local sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
  ls -d "$sdk"/build-tools/*/apksigner 2>/dev/null | sort -V | tail -1
}

# APK certificates are reported as plain hex; show them colon-separated like
# Google Cloud expects.
colonize() { echo "$1" | tr '[:lower:]' '[:upper:]' | sed -E 's/(..)/\1:/g; s/:$//'; }

cmd_create() {
  [[ -e "$KEYSTORE" ]] && die "$KEYSTORE already exists. Never replace a release key you've shipped with; delete it yourself only if no build signed with it was ever shared."

  local password="${THROTTLE_KEYSTORE_PASSWORD:-}"
  if [[ -z "$password" ]]; then
    local again
    read -r -s -p "New keystore password (6+ characters): " password; echo
    read -r -s -p "Repeat password: " again; echo
    [[ "$password" == "$again" ]] || die "passwords don't match"
  fi
  [[ ${#password} -ge 6 ]] || die "password must be at least 6 characters"
  # key.properties is a Java properties file, where backslashes are escapes.
  [[ "$password" != *\\* ]] || die "password can't contain a backslash"

  mkdir -p "$(dirname "$KEYSTORE")"
  KS_PASS="$password" keytool -genkeypair -v \
    -keystore "$KEYSTORE" -storetype PKCS12 \
    -alias "$ALIAS" -keyalg RSA -keysize 2048 -validity 10000 \
    -dname "$DNAME" \
    -storepass:env KS_PASS -keypass:env KS_PASS >/dev/null 2>&1 ||
    die "keytool couldn't create the keystore"
  chmod 600 "$KEYSTORE"

  # Read by android/app/build.gradle.kts. Gitignored; keep it that way.
  umask 077
  cat >"$KEY_PROPERTIES" <<EOF
storePassword=$password
keyPassword=$password
keyAlias=$ALIAS
storeFile=$KEYSTORE
EOF

  echo "Created release keystore: $KEYSTORE"
  echo "Wrote $KEY_PROPERTIES (release builds now sign with it)"
  echo
  echo "BACK UP the keystore file and its password somewhere safe (e.g. a password"
  echo "manager). Without them you can't ship updates signed with the same key."
  echo
  cmd_print
}

cmd_print() {
  local pkg
  pkg="$(package_name)"
  echo "Package name: ${pkg:-<not found in android/app/build.gradle.kts>}"
  echo

  echo "Debug key ($DEBUG_KEYSTORE) — flutter run / debug builds:"
  if [[ -f "$DEBUG_KEYSTORE" ]]; then
    fingerprints "$DEBUG_KEYSTORE" androiddebugkey android
  else
    echo "  (not created yet — build or run the app once in debug mode)"
  fi
  echo

  echo "Release key — flutter build apk / appbundle:"
  if [[ -f "$KEY_PROPERTIES" ]]; then
    local store alias password
    store="$(prop storeFile)"; alias="$(prop keyAlias)"; password="$(prop storePassword)"
    [[ -f "$store" ]] || die "key.properties points to $store, which doesn't exist"
    echo "  keystore: $store (alias $alias)"
    fingerprints "$store" "$alias" "$password"
  else
    echo "  (none yet: release builds are signed with the DEBUG key)"
    echo "  Create one with: scripts/android_keys.sh create"
  fi
  echo

  if [[ -f "$APK" ]]; then
    echo "Last built APK ($APK) is signed with:"
    local signer
    signer="$(apksigner_bin)"
    if [[ -n "$signer" ]]; then
      local out sha1 sha256
      out="$("$signer" verify --print-certs "$APK" 2>/dev/null)"
      sha1="$(echo "$out" | sed -nE 's/.*certificate SHA-1 digest: ([0-9a-f]+).*/\1/p' | head -1)"
      sha256="$(echo "$out" | sed -nE 's/.*certificate SHA-256 digest: ([0-9a-f]+).*/\1/p' | head -1)"
      echo "  SHA1: $(colonize "$sha1")"
      echo "  SHA256: $(colonize "$sha256")"
    else
      keytool -printcert -jarfile "$APK" 2>/dev/null |
        sed -nE 's/^[[:space:]]*(SHA1|SHA256): (.*)$/  \1: \2/p'
    fi
    echo
  fi

  cat <<EOF
Register each SHA-1 you build with (debug for testing, release for the APK you
share) in Google Cloud Console → APIs & Services → Credentials →
Create credentials → OAuth client ID → Android:
  Package name: ${pkg:-com.wheelsclub.wheelsclub}
  SHA-1 certificate fingerprint: <one of the SHA1 values above>
Use the same Google Cloud project as the Web client ID the app passes as
serverClientId. If you later publish on Google Play, also register the
"App signing key" SHA-1 from Play Console → Test and release → App integrity.
EOF
}

case "${1:-print}" in
  create) cmd_create ;;
  print) cmd_print ;;
  *) die "unknown command: $1 (use: create | print)" ;;
esac
