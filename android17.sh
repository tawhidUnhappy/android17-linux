#!/usr/bin/env bash
# Starts the Android 17 phone (Pixel 10 Pro with Google Play) in its own window. No sudo.
#
#   ./android17.sh
#
# The window shows just the phone's screen. Use it with gestures by dragging with the mouse: up from
# the bottom edge = home, up and hold = recent apps, in from the left or right edge = back.
# Right-click is back too, middle-click is home. Alt+P is the power button, Alt+Up/Down the volume.
#
# It starts up like a phone that was off. Turning it off ends everything it started, so nothing
# keeps running in the background afterwards:
#   Power off in the phone   swipe down twice from the top, tap the power icon, Power off
#   Close the window         off at once, like pulling the battery (Alt+Q does the same)
#   Ctrl+C here              the same
# Apps, accounts and files stay, like on a real phone. Install or change settings: android17-setup.sh
set -uo pipefail
(( BASH_VERSINFO[0] * 100 + BASH_VERSINFO[1] >= 501 )) || { echo "Needs bash 5.1 or newer."; exit 1; }
cd "$(dirname "$(readlink -f "$0")")"
DIR=$PWD/data
export ANDROID_HOME=$DIR/sdk ANDROID_SDK_ROOT=$DIR/sdk ANDROID_AVD_HOME=$DIR/avd
export ANDROID_USER_HOME=$DIR/home ANDROID_EMULATOR_HOME=$DIR/home
# Its own adb port: it never meets another adb (a real phone's), and its adb ends with it.
# adb always reads ~/.android, so it is also given the key the emulator hands the phone (no "Allow
# USB debugging?" prompts), and its log goes here too.
export ANDROID_ADB_SERVER_PORT=5038 ADB_VENDOR_KEYS=$DIR/home/adbkey ANDROID_ADB_LOG_PATH=$DIR/home/adb.log
export ADB=$ANDROID_HOME/platform-tools/adb PATH=$ANDROID_HOME/platform-tools:$PATH
EMULATOR=$ANDROID_HOME/emulator/emulator
SCRCPY=$DIR/scrcpy/scrcpy
RUNNING=${XDG_RUNTIME_DIR:-/run/user/$UID}/avd/running
LOG=$DIR/last-run.log
WINDOW_LOG=$DIR/last-run-window.log

if [ ! -x "$EMULATOR" ] || [ ! -x "$SCRCPY" ] || [ ! -f "$ANDROID_AVD_HOME/Android17.ini" ]; then
  echo "Not installed yet: $PWD/android17-setup.sh"
  exit 1
fi
if [ ! -e /dev/kvm ]; then
  echo "The phone needs the CPU's virtualization, which is off in the BIOS/UEFI. Turn on"
  echo "\"SVM Mode\" (AMD) or \"Intel Virtualization Technology\" (Intel), save and restart."
  exit 1
fi
if [ ! -w /dev/kvm ]; then
  echo "No access to /dev/kvm. Run: sudo usermod -aG kvm $USER   then log out and back in."
  exit 1
fi

# One phone at a time (the lock goes away by itself when this script ends).
exec 9>"$DIR/.running"
if ! flock -n 9; then
  echo "Android 17 is already running."
  exit 0
fi

# The emulator runs in its own systemd scope, so whatever it starts (adb, the Bluetooth/Wi-Fi
# simulator netsimd, the crash reporter) is stopped with it, even what detaches itself.
unit=android17-$$
emulator_pid= window_pid=
off() {
  trap - EXIT INT TERM HUP
  [ -n "$window_pid" ] && kill "$window_pid" 2>/dev/null
  systemctl --user stop "$unit.scope" 2>/dev/null
  "$ADB" kill-server 2>/dev/null   # the adb on the phone's own port, whoever started it
  pkill -f -- "$DIR/" 2>/dev/null  # anything that escaped the scope
  # After a crash the emulator can't remove its "I'm running" note for Android Studio.
  [ -n "$emulator_pid" ] && rm -rf "$RUNNING/$emulator_pid" "$RUNNING/pid_$emulator_pid.ini"
  echo "Android 17 is off. Nothing of it is running."
}
trap off EXIT
trap 'exit 130' INT TERM HUP

echo "Starting Android 17. Power it off or close its window to turn it off."
# -no-window: scrcpy shows the phone instead (no button bar; the emulator's own window also
#   crashed with an NVIDIA card on Wayland).
# -no-snapshot: a real start-up every time, and nothing is saved when it closes.
# -allow-host-audio: the PC's microphone reaches the phone (without it the phone hears silence).
# -no-metrics: no usage statistics to Google.
systemd-run --user --scope --collect --quiet --unit="$unit" -p TimeoutStopSec=5 \
  "$EMULATOR" -avd Android17 -no-window -no-snapshot -allow-host-audio -no-metrics 9>&- >"$LOG" 2>&1 &
emulator_pid=$!

# The window opens once Android draws its boot animation. The emulator's note for Android Studio
# says which port it got.
serial= ready=
for _ in $(seq 600); do
  kill -0 "$emulator_pid" 2>/dev/null || break
  if [ -z "$serial" ]; then
    port=$(sed -n 's/^port\.serial=//p' "$RUNNING/pid_$emulator_pid.ini" 2>/dev/null)
    [ -n "$port" ] && serial=emulator-$port
  elif "$ADB" -s "$serial" shell 'getprop init.svc.bootanim; getprop sys.boot_completed' 2>/dev/null |
       grep -qE '^(running|1)'; then
    ready=1
    break
  fi
  sleep 0.5
done
if [ -z "$ready" ]; then
  echo "The phone did not start. Last lines of $LOG:"
  tail -n 15 "$LOG"
  exit 1
fi

# --no-audio: the emulator plays the sound itself. --max-size 1024: about the size it shows at on
# a 1080p screen, so the phone spends little CPU on sending the picture.
"$SCRCPY" --serial="$serial" --window-title="Android 17" --no-audio --max-size=1024 \
  --video-bit-rate=16M 9>&- >"$WINDOW_LOG" 2>&1 &
window_pid=$!
# Whichever ends first, the phone (powered off, or crashed) or the window (closed), ends both.
ended=
wait -n -p ended
status=$?
if [ "$ended" = "$window_pid" ] && [ "$status" -eq 2 ]; then
  # The phone went away by itself. Give it a moment to finish, to tell a crash from a power-off.
  for _ in $(seq 20); do kill -0 "$emulator_pid" 2>/dev/null || break; sleep 0.5; done
  if ! kill -0 "$emulator_pid" 2>/dev/null; then
    ended=$emulator_pid
    wait "$emulator_pid"
    status=$?
  fi
fi
if [ "$ended" = "$emulator_pid" ] && [ "$status" -ne 0 ]; then
  echo "The emulator stopped with an error ($status). Last lines of $LOG:"
  tail -n 15 "$LOG"
elif [ "$ended" = "$window_pid" ] && [ "$status" -eq 1 ]; then
  echo "The window could not connect to the phone. Last lines of $WINDOW_LOG:"
  tail -n 15 "$WINDOW_LOG"
fi
