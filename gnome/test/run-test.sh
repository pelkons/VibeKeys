#!/bin/bash
# End-to-end check of the GNOME extension in a headless GNOME Shell (used by CI; run it inside
# `dbus-run-session`). Types "abc" into a zenity entry, clicks the panel's Backspace with a virtual
# mouse, long-presses Space and slides onto "?", clicks Enter, and expects zenity to print "ab?".
# Then, in a second entry, holds Backspace to wipe "xyz" and expects "ok" after typing it.
# That only works if clicking the panel leaves the keyboard focus in the zenity window.
# Usage: run-test.sh [output-dir]   (screenshots and logs go there)
set -euo pipefail

OUT=${1:-/tmp/vibekeys-test}
mkdir -p "$OUT"
UUID=vibekeys@pelkons.github.io
HERE=$(cd "$(dirname "$0")/.." && pwd)

EXT_DIR=~/.local/share/gnome-shell/extensions
mkdir -p "$EXT_DIR"
rm -rf "${EXT_DIR:?}/$UUID"
cp -r "$HERE/$UUID" "$EXT_DIR/"
gsettings set org.gnome.shell disable-extension-version-validation true
gsettings set org.gnome.shell enabled-extensions "['$UUID']"
gsettings set org.gnome.shell welcome-dialog-last-shown-version '999999'

export VIBEKEYS_TEST=1
gnome-shell --headless --wayland --no-x11 --virtual-monitor 1280x800 >"$OUT/shell.log" 2>&1 &
SHELL_PID=$!
trap 'kill $SHELL_PID 2>/dev/null || true' EXIT

echo "Waiting for the extension's test interface..."
gdbus wait --session --timeout 90 io.github.pelkons.VibeKeys.Test

call() {
  gdbus call --session --dest io.github.pelkons.VibeKeys.Test --object-path /io/github/pelkons/VibeKeys/Test \
    --method "io.github.pelkons.VibeKeys.Test.$1" "${@:2}" >/dev/null
}
center() {
  gdbus call --session --dest io.github.pelkons.VibeKeys.Test --object-path /io/github/pelkons/VibeKeys/Test \
    --method io.github.pelkons.VibeKeys.Test.Center "$1" | tr -d '(),'
}
click() {
  read -r x y <<<"$(center "$1")"
  call PointerMove "$x" "$y"; sleep 0.2
  call PointerButton true; sleep 0.1
  call PointerButton false; sleep 0.5
}

sleep 2
call HideOverview
sleep 1

export WAYLAND_DISPLAY=wayland-0 GDK_BACKEND=wayland
zenity --entry --title "VibeKeys test" --text "Type here" >"$OUT/zenity.txt" 2>"$OUT/zenity.log" &
ZENITY_PID=$!
sleep 4
call Screenshot "$OUT/1-start.png"; sleep 1

call TypeText abc; sleep 0.5
click backspace                                     # "abc" -> "ab"

read -r x y <<<"$(center space)"                    # long press Space, slide onto "?", release
call PointerMove "$x" "$y"; sleep 0.2
call PointerButton true; sleep 0.9
read -r px py <<<"$(center popup:1)"
call PointerMove "$px" "$py"; sleep 0.5
call Screenshot "$OUT/2-popup.png"; sleep 1
call PointerButton false; sleep 0.5
call Screenshot "$OUT/3-typed.png"; sleep 1

click enter                                         # zenity prints the entry and exits
timeout 10 tail --pid=$ZENITY_PID -f /dev/null || true

fail() {
  echo "FAIL: $1"
  grep -i -E "vibekeys|error|exception" "$OUT/shell.log" | tail -40 || true
  exit 1
}

result=$(cat "$OUT/zenity.txt")
echo "zenity printed: '$result'"
[ "$result" = "ab?" ] || fail "expected 'ab?'"

# Held Backspace repeats: "xyz" is wiped out by one long hold, so the entry ends up as just "ok"
zenity --entry --title "VibeKeys test 2" --text "Type here" >"$OUT/zenity2.txt" 2>>"$OUT/zenity.log" &
ZENITY_PID=$!
sleep 3
call TypeText xyz; sleep 0.5
read -r x y <<<"$(center backspace)"
call PointerMove "$x" "$y"; sleep 0.2
call PointerButton true; sleep 1.5
call PointerButton false; sleep 0.5
call TypeText ok; sleep 0.5
click enter
timeout 10 tail --pid=$ZENITY_PID -f /dev/null || true

result=$(cat "$OUT/zenity2.txt")
echo "zenity printed: '$result'"
[ "$result" = "ok" ] || fail "expected 'ok' (held Backspace should delete all of 'xyz')"
echo "PASS"
