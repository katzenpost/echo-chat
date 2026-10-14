#!/bin/sh
# SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
# SPDX-License-Identifier: AGPL-3.0-only
#
# Two glint windows on one X display, against a client daemon, driven with xdotool as two people
# would: Alice founds a group, Bob joins it with a voucher code he copies, Alice invites him, they
# exchange messages, and Bob's next message acknowledges Alice's. Run by mixnet.sh inside Xvfb.
# DAEMON is the daemon's socket; MINUTES bounds each wait on the network.
set -u
cd "$(dirname "$0")/../.."
. tests/e2e/lib.sh
DAEMON=${DAEMON:-@katzenpost}
SECONDS_NET=$(( ${MINUTES:-10} * 60 ))

start_glint alice --daemon "$DAEMON" --name alice --state "$WORK/alice"
start_glint bob --daemon "$DAEMON" --name bob --state "$WORK/bob"
WA=$(xdotool search --sync --pid "$PID_alice" | head -n 1)
WB=$(xdotool search --sync --pid "$PID_bob" | head -n 1)
# Side by side: with no window manager, a click goes to whichever window is on top there.
xdotool windowmove --sync "$WA" 0 0
xdotool windowmove --sync "$WB" 1050 0
wait_for "$WORK/alice.layout" '^new-group ' || { fail "alice's window is up"; exit 1; }
wait_for "$WORK/bob.layout" '^new-group ' || { fail "bob's window is up"; exit 1; }
sleep 1

# Clicks the widget keyed $2 in member $1's window, which is given keyboard focus first.
click() {
  w=$WA; [ "$1" = bob ] && w=$WB
  xdotool windowfocus --sync "$w"
  set -- $(center "$1" "$2")
  xdotool mousemove --window "$w" "$1" "$2" click 1
  sleep 0.7
}

type_in() {
  w=$WA; [ "$1" = bob ] && w=$WB
  xdotool windowfocus --sync "$w"
  sleep 0.6
  xdotool type --delay 20 "$2"
  sleep 0.3
}

stop_all() {
  kill "$PID_alice" "$PID_bob" 2>/dev/null
  exit $FAILED
}

expect_idle alice "an idle glint does not wake"

click alice new-group
click alice dialog-field
type_in alice g
click alice accept
expect alice 'chats=\[g\[joined=true' "alice founds a group" 60 || stop_all

click bob join-group
click bob dialog-field
type_in bob g
click bob accept
expect bob 'code=[A-Za-z0-9+/=]\{8,\}' "bob's window shows a voucher code" "$SECONDS_NET" || stop_all
CODE=$(tail -n 1 "$WORK/bob.log" | sed 's/.*code=\([^ ]*\) .*/\1/')
sleep 1
click bob copy-voucher
if [ "$(xclip -o -selection clipboard 2>/dev/null)" = "$CODE" ]; then ok "Copy puts the code on the clipboard"
else fail "Copy puts the code on the clipboard"; fi

click alice invite
click alice dialog-field
type_in alice "$CODE"
click alice accept
expect bob 'chats=\[g\[joined=true' "bob joins" "$SECONDS_NET" || stop_all
expect alice 'members=1 ' "alice reads bob" "$SECONDS_NET" || stop_all

click bob draft
type_in bob "hello from bob"
click bob send
click alice draft
type_in alice "hello from alice"
click alice send
expect alice '~bob:hello from bob' "alice reads bob's message" "$SECONDS_NET"
expect bob '~alice:hello from alice' "bob reads alice's message" "$SECONDS_NET"
expect alice 'me✓:hello from alice' "alice's message is written" "$SECONDS_NET"
click bob draft
type_in bob "bob read you"
click bob send
expect alice 'me✓✓:hello from alice' "bob's next message acknowledges it" "$SECONDS_NET"

xdotool windowfocus --sync "$WA"
xdotool key ctrl+q
sleep 2
if kill -0 "$PID_alice" 2>/dev/null; then fail "Ctrl+Q quits"; else ok "Ctrl+Q quits"; fi
stop_all
