#!/bin/sh
# SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
# SPDX-License-Identifier: AGPL-3.0-only
#
# glint showing a saved state, with no daemon, driven with xdotool. Run by offline.sh inside Xvfb.
set -u
cd "$(dirname "$0")/../.."
. tests/e2e/lib.sh

.lake/build/bin/glint-test --fixture "$WORK/state"
start_glint alice --offline --state "$WORK/state"
W=$(xdotool search --sync --name "^glint$" | head -n 1)
xdotool windowfocus --sync "$W"
wait_for "$WORK/alice.layout" '^group:second ' || { fail "glint reported its layout"; exit 1; }
sleep 1

click() {
  set -- $(center alice "$1")
  xdotool mousemove --window "$W" "$1" "$2" click 1
  sleep 0.7
}

expect alice 'selected=g ' "the saved state's first group is selected"
expect alice 'lines=\[—:~alice added ~bob, ~bob:hello alice\]' "its lines are shown"
expect_idle alice "an idle glint does not wake"
click group:second
expect alice 'selected=second ' "a click selects another group"
xdotool key ctrl+q
sleep 1
if kill -0 "$PID_alice" 2>/dev/null; then fail "Ctrl+Q quits"; kill "$PID_alice"; else ok "Ctrl+Q quits"; fi
exit $FAILED
