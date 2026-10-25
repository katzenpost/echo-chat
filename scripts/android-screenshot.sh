#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
#
# docs/android.png: frank_chat on an Android emulator, offline, showing the conversation of the
# README's picture from a saved state. Needs the APK for the emulator installed
# (`make apk ANDROID_ABI=x86_64`, then `adb install -r`) and `adb root`, as on an emulator's
# google_apis image, to put the state in the app's private directory.
set -eu
cd "$(dirname "$0")/.."
PKG=org.katzenpost.frank_chat
FILES=/data/data/$PKG/files
STATE=$FILES/.local/share/frank_chat/default
WORK=.lake/android-screenshot

rm -rf "$WORK"
lake exe frank_chat_test --readme-state "$WORK"

adb root >/dev/null
adb wait-for-device
adb shell am force-stop $PKG
owner=$(adb shell stat -c %u:%g $FILES)
adb shell rm -rf "$FILES/.local"
adb shell mkdir -p "$STATE"
adb push "$WORK/state.cbor" "$STATE/state.cbor" >/dev/null
adb shell chown -R "$owner" "$FILES/.local"
adb shell restorecon -R "$FILES/.local" 2>/dev/null

# The README's times are in UTC; the status bar shows a quiet morning.
adb shell setprop persist.sys.timezone UTC
adb shell settings put global sysui_demo_allowed 1
demo() { adb shell am broadcast -a com.android.systemui.demo -e command "$@" >/dev/null; }
demo enter
demo clock -e hhmm 0925
demo battery -e level 100 -e plugged false
demo network -e wifi show -e level 4 -e fully true
demo network -e mobile show -e datatype none -e level 4 -e fully true
demo notifications -e visible false

adb shell setprop debug.paw.args --offline
adb shell setprop debug.paw.test_layout layout.txt
adb shell setprop debug.paw.reduce_motion 1
adb shell rm -f $FILES/layout.txt
adb shell am start -n $PKG/com.google.androidgamesdk.GameActivity >/dev/null

i=0
until adb exec-out cat $FILES/layout.txt 2>/dev/null | grep -q '^group:friends '; do
  i=$((i + 1))
  if [ $i -gt 300 ]; then echo "frank_chat did not show its groups" >&2; exit 1; fi
  sleep 0.2
done
# Where the window starts on the screen, and how many pixels a logical pixel is.
adb shell uiautomator dump /sdcard/frank-ui.xml >/dev/null 2>&1
set -- $(adb exec-out cat /sdcard/frank-ui.xml |
  sed -n 's/.*content-desc="frank_chat"[^>]*bounds="\[\([0-9]*\),\([0-9]*\)\].*/\1 \2/p')
OX=${1:-0}
OY=${2:-0}
SCALE=$(adb shell wm density | awk '{ d = $NF } END { print d / 160 }')
# A tap counts once the widget has been still for half a second.
sleep 1
xy=$(adb exec-out cat $FILES/layout.txt | awk -v s="$SCALE" -v ox="$OX" -v oy="$OY" \
  '$1 == "group:friends" { printf "%d %d\n", ox + ($2 + $4) / 2 * s, oy + ($3 + $5) / 2 * s }')
adb shell input tap $xy
sleep 2
adb exec-out screencap -p > docs/android.png

demo exit
adb shell setprop debug.paw.args "''"
adb shell setprop debug.paw.test_layout "''"
adb shell setprop debug.paw.reduce_motion "''"
ls -l docs/android.png
