#!/bin/sh
# SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
# SPDX-License-Identifier: AGPL-3.0-only
#
# A sigil window and a jam terminal in one group, through one client daemon. As host, sigil founds
# the group and invites jam; as guest, jam founds it and invites sigil. Then each reads the other,
# and jam's next message acknowledges sigil's. Run by interop-jam.sh inside Xvfb, with jam in tmux.
set -u
cd "$(dirname "$0")/../.."
. tests/e2e/lib.sh
DAEMON=${DAEMON:-@katzenpost}
ROLE=${ROLE:-host}
SECONDS_NET=$(( ${MINUTES:-10} * 60 ))
T=sigil-interop-$$

start_sigil sigil --daemon "$DAEMON" --name sigil --state "$WORK/sigil"
tmux new-session -d -s "$T" -x 160 -y 45 \
  "TERM=xterm-256color $JAM --daemon $DAEMON --name jam --state $WORK/jam; sleep 600"
W=$(xdotool search --sync --pid "$PID_sigil" | head -n 1)
xdotool windowfocus --sync "$W"
wait_for "$WORK/sigil.layout" '^new-group ' || { fail "sigil's window is up"; exit 1; }
sleep 1

stop_all() {
  kill "$PID_sigil" 2>/dev/null
  tmux kill-session -t "$T" 2>/dev/null
  exit $FAILED
}

click() {
  set -- $(center sigil "$1")
  xdotool mousemove --window "$W" "$1" "$2" click 1
  sleep 0.7
}

type_in() { sleep 0.6; xdotool type --delay 20 "$1"; sleep 0.3; }

jam_line() { tmux send-keys -t "$T" -l "$1"; tmux send-keys -t "$T" Enter; }

# Waits for jam's screen to show a line matching the extended regular expression $1.
jam_shows() {
  i=0
  while ! tmux capture-pane -t "$T" -p -J | grep -qE -- "$1"; do
    i=$((i + 1))
    if [ $i -gt $(( $3 * 2 )) ]; then fail "$2"; tmux capture-pane -t "$T" -p | tail -n 15; return 1; fi
    sleep 0.5
  done
  ok "$2"
}

sleep 3
if [ "$ROLE" = host ]; then
  click new-group; click dialog-field; type_in g; click accept
  expect sigil 'chats=\[g\[joined=true' "sigil founds a group" 60 || stop_all
  jam_line "/join g"
  wait_for "$WORK/jam/voucher-g.txt" . "$SECONDS_NET" || { fail "jam mints a voucher"; stop_all; }
  ok "jam mints a voucher"
  click invite; click dialog-field; type_in "$(cat "$WORK/jam/voucher-g.txt")"; click accept
  jam_shows "joined the group" "jam joins sigil's group" "$SECONDS_NET" || stop_all
  expect sigil 'members=1 ' "sigil reads jam" "$SECONDS_NET" || stop_all
else
  jam_line "/new g"
  jam_shows "a new group" "jam founds a group" 60 || stop_all
  click join-group; click dialog-field; type_in g; click accept
  expect sigil 'code=[A-Za-z0-9+/=]\{8,\}' "sigil shows a voucher code" "$SECONDS_NET" || stop_all
  CODE=$(tail -n 1 "$WORK/sigil.log" | sed 's/.*code=\([^ ]*\) .*/\1/')
  jam_line "/invite $CODE"
  expect sigil 'chats=\[g\[joined=true' "sigil joins jam's group" "$SECONDS_NET" || stop_all
  jam_shows "added ~sigil" "jam adds sigil" "$SECONDS_NET" || stop_all
fi

jam_line "hello from jam"
click draft; type_in "hello from sigil"; click send
expect sigil '~jam:hello from jam' "sigil reads jam's message" "$SECONDS_NET"
jam_shows "~sigil +hello from sigil" "jam reads sigil's message" "$SECONDS_NET"
jam_line "jam read you"
expect sigil 'me✓✓:hello from sigil' "jam's next message acknowledges sigil's" "$SECONDS_NET"
stop_all
