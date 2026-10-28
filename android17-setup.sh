#!/usr/bin/env bash
# Installs the Android 17 phone: a Pixel 10 Pro with Google Play, run by Google's Android emulator
# and shown in a window by scrcpy. No sudo. Safe to run again: it never touches the phone's apps,
# accounts or files, it only adds what is missing and re-applies android17.ini.
#
#   ./android17-setup.sh          install, or re-apply the settings (also after moving this folder)
#   ./android17-setup.sh update   also update Android, the emulator and adb to Google's latest
#
# Everything goes into data/ next to this script (about 4 GB, plus what the phone stores):
#   data/sdk/     Google's emulator, adb and the Android 17 Google Play system image
#   data/avd/     the phone itself: its storage, apps and accounts
#   data/home/    the emulator's settings, the phone's adb key and Google's installer (android CLI)
#   data/scrcpy/  scrcpy, the window that shows the phone
# Start the phone: ./android17.sh     Remove all of it: delete this folder.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
DIR=$PWD/data
SDK=$DIR/sdk
AVD=Android17
DEVICE=pixel_10_pro
# Android 17 with the normal 4 KB memory pages, as real phones run it (the newer 37.1/37.2 builds
# come only as 16 KB-page test images, which some apps don't run on).
IMAGE=system-images/android-37.0/google_apis_playstore/x86_64
TOOLS_ZIP=commandlinetools-linux-16111833_latest.zip
TOOLS_SHA1=e025545c62a8e64c7559119566a569fb1dec5f60
SCRCPY_VERSION=v5.0.1
SCRCPY_SHA256=9f969d30cc574816077edecda65719c1c70b0aee1df1ba5fa00779ac07b8fd6e
export ANDROID_HOME=$SDK ANDROID_SDK_ROOT=$SDK ANDROID_USER_HOME=$DIR/home ANDROID_AVD_HOME=$DIR/avd
mkdir -p "$SDK" "$ANDROID_USER_HOME" "$ANDROID_AVD_HOME"
# Google's installer; it sends usage statistics unless told not to.
ANDROID_CLI=("$SDK/cmdline-tools/latest/bin/android" --no-metrics --sdk="$SDK")

for tool in curl unzip tar awk sha1sum sha256sum flock systemd-run; do
  command -v "$tool" >/dev/null || { echo "Missing $tool: install it with your package manager."; exit 1; }
done
[ "$(uname -m)" = x86_64 ] || { echo "Needs a 64-bit Intel/AMD PC (x86_64)."; exit 1; }

echo "== 1/4 Google's command-line tools"
if [ -x "${ANDROID_CLI[0]}" ]; then
  echo "already there"
else
  tmp=$(mktemp -d)
  curl -fL --progress-bar -o "$tmp/tools.zip" "https://dl.google.com/android/repository/$TOOLS_ZIP"
  echo "$TOOLS_SHA1  $tmp/tools.zip" | sha1sum -c --quiet
  unzip -q "$tmp/tools.zip" -d "$tmp"
  mkdir -p "$SDK/cmdline-tools"
  mv "$tmp/cmdline-tools" "$SDK/cmdline-tools/latest"
  rm -r "$tmp"
fi

echo "== 2/4 Emulator, adb and Android 17 (the first time about 2.5 GB to download)"
"${ANDROID_CLI[@]}" sdk install platform-tools emulator "$IMAGE"
if [ "${1:-}" = update ]; then
  "${ANDROID_CLI[@]}" sdk update
fi

echo "== 3/4 scrcpy $SCRCPY_VERSION, the window that shows the phone"
if [ "$(cat "$DIR/scrcpy/VERSION" 2>/dev/null)" = "$SCRCPY_VERSION" ]; then
  echo "already there"
else
  tmp=$(mktemp -d)
  curl -fL --progress-bar -o "$tmp/scrcpy.tar.gz" \
    "https://github.com/Genymobile/scrcpy/releases/download/$SCRCPY_VERSION/scrcpy-linux-x86_64-$SCRCPY_VERSION.tar.gz"
  echo "$SCRCPY_SHA256  $tmp/scrcpy.tar.gz" | sha256sum -c --quiet
  tar -xzf "$tmp/scrcpy.tar.gz" -C "$tmp"
  rm -rf "$DIR/scrcpy"
  mv "$tmp/scrcpy-linux-x86_64-$SCRCPY_VERSION" "$DIR/scrcpy"
  echo "$SCRCPY_VERSION" >"$DIR/scrcpy/VERSION"
  rm -r "$tmp"
fi

echo "== 4/4 The phone"
config=$ANDROID_AVD_HOME/$AVD.avd/config.ini
if [ -f "$config" ]; then
  echo "already there (apps, accounts and files kept)"
else
  # avdmanager needs Java: Android Studio's own copy (snap) or any installed one.
  if [ -z "${JAVA_HOME:-}" ] && ! command -v java >/dev/null; then
    for j in /snap/android-studio/current/jbr /opt/android-studio/jbr /usr/lib/jvm/*; do
      if [ -x "$j/bin/java" ]; then export JAVA_HOME=$j; break; fi
    done
  fi
  [ -n "${JAVA_HOME:-}" ] || command -v java >/dev/null ||
    { echo "Creating the phone needs Java once, e.g.: sudo apt install openjdk-21-jre-headless"; exit 1; }
  echo no | "$SDK/cmdline-tools/latest/bin/avdmanager" --silent create avd \
    --name "$AVD" --package "${IMAGE//\//;}" --device "$DEVICE"
fi
# Where the phone is, written every time so that a moved folder works after running this again.
target=${IMAGE#system-images/}
printf 'avd.ini.encoding=UTF-8\npath=%s\ntarget=%s\n' "$ANDROID_AVD_HOME/$AVD.avd" "${target%%/*}" \
  >"$ANDROID_AVD_HOME/$AVD.ini"
# Each key in android17.ini replaces the same key in config.ini, or is added.
awk '
  function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
  FNR == NR { if ($0 ~ /^[ \t]*(#|$)/ || index($0, "=") == 0) next
              k = trim(substr($0, 1, index($0, "=") - 1))
              v = trim(substr($0, index($0, "=") + 1))
              want[k] = v; order[++n] = k; next }
  { k = trim(substr($0, 1, index($0, "=") - 1))
    if (k in want) { if (!(k in done)) print k "=" want[k]; done[k] = 1; next }
    print }
  END { for (i = 1; i <= n; i++) if (!(order[i] in done)) print order[i] "=" want[order[i]] }
' android17.ini "$config" >"$config.new"
mv "$config.new" "$config"
# The adb key the emulator hands the phone (android17.sh gives it to adb too).
[ -f "$ANDROID_USER_HOME/adbkey" ] || "$SDK/platform-tools/adb" keygen "$ANDROID_USER_HOME/adbkey" >/dev/null 2>&1
grep -E '^(hw\.(ramSize|cpu\.ncore|gpu\.mode|lcd\.(width|height|density))|disk\.dataPartition\.size|image\.sysdir\.1)=' "$config"

echo
if [ ! -e /dev/kvm ]; then
  echo "Installed, but the phone can't start yet: the CPU's virtualization is off in the BIOS/UEFI."
  echo "Turn on \"SVM Mode\" (AMD) or \"Intel Virtualization Technology\" (Intel), save and restart."
  echo "After that, start it with:"
else
  echo "Done. Start the phone with:"
fi
echo "  $PWD/android17.sh"
