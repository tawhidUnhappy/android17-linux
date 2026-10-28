# Android 17 on Linux

Use Android 17 on your Linux PC like a phone: a Pixel 10 Pro with Google Play, in a window you
control with mouse gestures. One script starts it. When you close the window or power the phone off,
everything stops: nothing keeps running in the background.

It runs Google's official Android emulator and Android 17 Google Play system image, and shows the
phone's screen with [scrcpy](https://github.com/Genymobile/scrcpy). No sudo needed, and everything
stays inside this folder.

## What you need

- A 64-bit Intel or AMD PC running Linux with systemd (made on Ubuntu 26.04, GNOME on Wayland,
  Ryzen 5 5600G, RTX 3060)
- Virtualization turned on in the BIOS/UEFI: **SVM Mode** on AMD, **Intel Virtualization Technology**
  (VT-x) on Intel. Many boards ship with it off.
- 8 GB of RAM or more (the phone uses 6 GB, see [Settings](#settings)) and about 10 GB of free disk
- bash 5.1 or newer, curl, unzip and tar
- Java, once, to create the phone. Android Studio's own copy is found by itself; otherwise
  `sudo apt install openjdk-21-jre-headless` (or your distribution's equivalent)

## Install

```bash
git clone https://github.com/tawhidUnhappy/android17-linux.git
cd android17-linux
./android17-setup.sh
```

The first run downloads about 2.7 GB into `data/`: Google's command-line tools, emulator, adb and
the Android 17 image, plus scrcpy. Every download is checked against its published checksum.
Installing Google's packages means accepting the
[Android SDK License Agreement](https://developer.android.com/studio/terms).

## Use

```bash
./android17.sh
```

The window opens once Android has started, about 20 seconds after you start it. Sign in to the Play Store with your Google account and install apps as on a phone. Apps made
only for phone (ARM) processors work too, because the image translates them.

| To | Do |
| --- | --- |
| Go home | Drag up from the bottom edge, or middle-click |
| See recent apps | Drag up from the bottom edge and hold |
| Go back | Drag in from the left or right edge, or right-click |
| Type | Use your PC keyboard |
| Press the power button | Alt+P (screen off/on) |
| Change the volume | Alt+Up / Alt+Down |
| Install an APK | Drag the file onto the window (other files go to Download) |

## Turning it off

- **Power off in the phone:** swipe down twice from the top, tap the power icon, then Power off.
- **Close the window** (or press Alt+Q, or Ctrl+C in the terminal): it is off at once, like pulling
  the battery.

Either way the script stops everything the phone started (the emulator, adb, and the emulator's
Wi-Fi/Bluetooth simulator). Your apps, accounts and files stay, like on a real phone. Every start is
a real start-up, and nothing is saved when it closes.

## Settings

The phone's settings are in [`android17.ini`](android17.ini): CPU cores, RAM, storage, graphics,
cameras. Change one, run `./android17-setup.sh` again, and start the phone. On a smaller PC, lower
`hw.cpu.ncore` and `hw.ramSize`. If the phone crashes or stays black with your graphics card, set
`hw.gpu.mode = swiftshader` (drawn by the CPU, so slower, but it works everywhere).

## Update, move, remove

- `./android17-setup.sh update` updates Android, the emulator and adb to Google's latest.
- Moved the folder? Run `./android17-setup.sh` once.
- To remove all of it, delete the folder.

## Good to know

- Banking and payment apps, Google Wallet and some games with anti-cheat refuse to run on any
  emulator: they check Play Integrity. Most other apps work.
- This is Android 17's main release (API 37.0). Google publishes the newer 37.1 and 37.2 builds only
  as 16 KB-page test images, which some apps don't run on.
- The emulator's own window (Pixel frame plus a button bar) crashed with an NVIDIA card on Wayland,
  so the emulator runs without it and scrcpy shows the screen instead.
- The phone uses its own adb port (5038), so it never interferes with a real phone you use with adb.
- Usage statistics are off for Google's installer and for the emulator.

## Files

| File | What it is |
| --- | --- |
| `android17.sh` | Starts the phone |
| `android17-setup.sh` | Installs it, re-applies the settings, updates |
| `android17.ini` | The phone's settings |
| `data/` | Everything downloaded, and the phone itself (not in git) |
