#!/bin/sh
# SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
# SPDX-License-Identifier: AGPL-3.0-only
#
# N glint windows on one X display, against one client daemon, driven with xdotool as N people
# would. The first founds a group; the others join it in waves, each member already in inviting
# one joiner at a time, with the voucher code copied from the joiner's window. Then everyone sends,
# everyone reads everyone, and a second round of messages acknowledges the first.
# Run by mixnet.sh inside Xvfb. DAEMON is the daemon's socket, N the members (2 to 8), and
# MINUTES bounds each wait on the network.
set -u
cd "$(dirname "$0")/../.."
. tests/e2e/lib.sh
DAEMON=${DAEMON:-@katzenpost}
N=${N:-5}
SECONDS_NET=$(( ${MINUTES:-10} * 60 ))
ALL=$(echo alice bob carol dave erin frank grace heidi | cut -d' ' -f1-"$N")
FIRST=alice

i=0
for m in $ALL; do
  start_glint "$m" --daemon "$DAEMON" --name "$m" --state "$WORK/$m"
  w=$(xdotool search --sync --pid "$(eval echo "\$PID_$m")" | head -n 1)
  eval "W_$m=$w"
  # Three to a row: with no window manager, a click goes to whichever window is on top there.
  xdotool windowmove --sync "$w" $(( i % 3 * 1050 )) $(( i / 3 * 750 ))
  i=$((i + 1))
done
for m in $ALL; do
  wait_for "$WORK/$m.layout" '^new-group ' || { fail "$m's window is up"; exit 1; }
done
sleep 1

stop_all() {
  for m in $ALL; do kill "$(eval echo "\$PID_$m")" 2>/dev/null; done
  exit $FAILED
}

# Clicks the widget keyed $2 in member $1's window, which is given keyboard focus first.
click() {
  w=$(eval echo "\$W_$1")
  xdotool windowfocus --sync "$w"
  set -- $(center "$1" "$2")
  xdotool mousemove --window "$w" "$1" "$2" click 1
  sleep 0.7
}

type_in() {
  xdotool windowfocus --sync "$(eval echo "\$W_$1")"
  sleep 0.6
  xdotool type --delay 20 "$2"
  sleep 0.3
}

# Fills member $1's open dialog with $2 and accepts it.
answer() {
  click "$1" dialog-field
  type_in "$1" "$2"
  click "$1" accept
}

others() { for o in $ALL; do [ "$o" != "$1" ] && printf '%s ' "$o"; done; }

expect_idle alice "an idle glint does not wake"

click $FIRST new-group
answer $FIRST g
expect $FIRST 'chats=\[g\[joined=true' "$FIRST founds a group" 60 || stop_all

# Everyone else asks to join at once; minting a voucher takes a trip across the mixnet.
WAITING=$(others $FIRST)
for m in $WAITING; do
  click "$m" join-group
  answer "$m" g
done
for m in $WAITING; do
  expect "$m" 'code=[A-Za-z0-9+/=]\{8,\} ' "$m's window shows a voucher code" "$SECONDS_NET" || stop_all
done

IN=$FIRST
copied=no
while [ -n "$WAITING" ]; do
  # Each member in invites one joiner; they are in once all of this wave have joined.
  wave=""
  for inviter in $IN; do
    set -- $WAITING
    [ $# -eq 0 ] && break
    joiner=$1; shift
    WAITING="$*"
    code=$(tail -n 1 "$WORK/$joiner.log" | sed 's/.*code=\([^ ]*\) .*/\1/')
    if [ $copied = no ]; then
      click "$joiner" copy-voucher
      if [ "$(xclip -o -selection clipboard 2>/dev/null)" = "$code" ]; then ok "Copy puts the code on the clipboard"
      else fail "Copy puts the code on the clipboard"; fi
      copied=yes
    fi
    click "$inviter" invite
    answer "$inviter" "$code"
    echo "     $inviter invites $joiner"
    wave="$wave $joiner"
  done
  for joiner in $wave; do
    expect "$joiner" 'chats=\[g\[joined=true' "$joiner joins" "$SECONDS_NET" || stop_all
  done
  IN="$IN$wave"
done

# Members hear of those others added through Introductions.
for m in $ALL; do
  expect "$m" "members=$((N - 1)) " "$m reads all $((N - 1)) others" "$SECONDS_NET" || stop_all
done

for m in $ALL; do
  click "$m" draft
  type_in "$m" "hello from $m"
  click "$m" send
done
for m in $ALL; do
  for o in $(others "$m"); do
    expect "$m" "~$o:hello from $o" "$m reads $o" "$SECONDS_NET"
  done
done

# Each next message acknowledges everything its sender has read.
for m in $ALL; do
  click "$m" draft
  type_in "$m" "$m read everyone"
  click "$m" send
done
for m in $ALL; do
  expect "$m" "me✓✓:hello from $m" "$m's first message is acknowledged" "$SECONDS_NET"
done

xdotool windowfocus --sync "$(eval echo "\$W_$FIRST")"
xdotool key ctrl+q
sleep 2
if kill -0 "$PID_alice" 2>/dev/null; then fail "Ctrl+Q quits"; else ok "Ctrl+Q quits"; fi
stop_all
