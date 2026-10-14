#!/bin/sh
# SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
# SPDX-License-Identifier: AGPL-3.0-only
#
# A glint window and a jam terminal in one group, through one client daemon. As host, glint founds
# the group and invites jam; as guest, jam founds it and invites glint. Then each reads the other,
# and jam's next message acknowledges glint's. Run by interop-jam.sh inside Xvfb, with jam in tmux.
set -u
cd "$(dirname "$0")/../.."
. tests/e2e/lib.sh
DAEMON=${DAEMON:-@katzenpost}
ROLE=${ROLE:-host}
SECONDS_NET=$(( ${MINUTES:-10} * 60 ))
T=glint-interop-$$

start_glint glint --daemon "$DAEMON" --name glint --state "$WORK/glint"
tmux new-session -d -s "$T" -x 160 -y 45 \
  "TERM=xterm-256color $JAM --daemon $DAEMON --name jam --state $WORK/jam; sleep 600"
W=$(xdotool search --sync --pid "$PID_glint" | head -n 1)
xdotool windowfocus --sync "$W"
wait_for "$WORK/glint.layout" '^new-group ' || { fail "glint's window is up"; exit 1; }
sleep 1

stop_all() {
  kill "$PID_glint" 2>/dev/null
  tmux kill-session -t "$T" 2>/dev/null
  exit $FAILED
}

click() {
  set -- $(center glint "$1")
  xdotool mousemove --window "$W" "$1" "$2" click 1
  sleep 0.7
}

type_in() { sleep 0.6; xdotool type --delay 20 "$1"; sleep 0.3; }

jam_line() { tmux send-keys -t "$T" -l "$1"; tmux send-keys -t "$T" Enter; }

# Waits for jam's screen to show $1.
jam_shows() {
  i=0
  while ! tmux capture-pane -t "$T" -p -J | grep -qF -- "$1"; do
    i=$((i + 1))
    if [ $i -gt $(( $3 * 2 )) ]; then fail "$2"; tmux capture-pane -t "$T" -p | tail -n 15; return 1; fi
    sleep 0.5
  done
  ok "$2"
}

sleep 3
if [ "$ROLE" = host ]; then
  click new-group; click dialog-field; type_in g; click accept
  expect glint 'chats=\[g\[joined=true' "glint founds a group" 60 || stop_all
  jam_line "/join g"
  wait_for "$WORK/jam/voucher-g.txt" . "$SECONDS_NET" || { fail "jam mints a voucher"; stop_all; }
  ok "jam mints a voucher"
  click invite; click dialog-field; type_in "$(cat "$WORK/jam/voucher-g.txt")"; click accept
  jam_shows "joined the group" "jam joins glint's group" "$SECONDS_NET" || stop_all
  expect glint 'members=1 ' "glint reads jam" "$SECONDS_NET" || stop_all
else
  jam_line "/new g"
  jam_shows "a new group" "jam founds a group" 60 || stop_all
  click join-group; click dialog-field; type_in g; click accept
  expect glint 'code=[A-Za-z0-9+/=]\{8,\}' "glint shows a voucher code" "$SECONDS_NET" || stop_all
  CODE=$(tail -n 1 "$WORK/glint.log" | sed 's/.*code=\([^ ]*\) .*/\1/')
  jam_line "/invite $CODE"
  expect glint 'chats=\[g\[joined=true' "glint joins jam's group" "$SECONDS_NET" || stop_all
  jam_shows "added ~glint" "jam adds glint" "$SECONDS_NET" || stop_all
fi

jam_line "hello from jam"
click draft; type_in "hello from glint"; click send
expect glint '~jam:hello from jam' "glint reads jam's message" "$SECONDS_NET"
jam_shows "~glint: hello from glint" "jam reads glint's message" "$SECONDS_NET"
jam_line "jam read you"
expect glint 'me✓✓:hello from glint' "jam's next message acknowledges glint's" "$SECONDS_NET"
stop_all
