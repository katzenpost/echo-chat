#!/bin/sh
# SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
# SPDX-License-Identifier: AGPL-3.0-only
#
# A frank_chat window and a jam terminal in one group, through one client daemon. As host, frank_chat founds
# the group and invites jam; as guest, jam founds it and invites frank_chat. Then they trade a few
# messages, each acknowledging what it has read of the other's. Run by interop-jam.sh inside Xvfb, with jam in tmux.
set -u
cd "$(dirname "$0")/../.."
. tests/e2e/lib.sh
DAEMON=${DAEMON:-@katzenpost}
ROLE=${ROLE:-host}
SECONDS_NET=$(( ${MINUTES:-10} * 60 ))
T=frank_chat-interop-$$

start_frank_chat frank_chat --daemon "$DAEMON" --name frank_chat --state "$WORK/frank_chat"
tmux new-session -d -s "$T" -x 160 -y 45 \
  "TERM=xterm-256color $JAM --daemon $DAEMON --name jam --state $WORK/jam; sleep 600"
W=$(xdotool search --sync --pid "$PID_frank_chat" | head -n 1)
xdotool windowfocus --sync "$W"
wait_for "$WORK/frank_chat.layout" '^new-group ' || { fail "frank_chat's window is up"; exit 1; }
sleep 1

stop_all() {
  kill "$PID_frank_chat" 2>/dev/null
  tmux kill-session -t "$T" 2>/dev/null
  exit $FAILED
}

click() {
  set -- $(center frank_chat "$1")
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
  click new-group; click dialog-field; type_in g; click dialog-me; type_in frank_chat; click accept
  expect frank_chat 'chats=\[g\[joined=true' "frank_chat founds a group" 60 || stop_all
  jam_line "/join g"
  wait_for "$WORK/jam/voucher-g.txt" . "$SECONDS_NET" || { fail "jam mints a voucher"; stop_all; }
  ok "jam mints a voucher"
  click invite; click dialog-field; type_in "$(cat "$WORK/jam/voucher-g.txt")"; click accept
  jam_shows "joined the group" "jam joins frank_chat's group" "$SECONDS_NET" || stop_all
  expect frank_chat 'members=1 ' "frank_chat reads jam" "$SECONDS_NET" || stop_all
else
  jam_line "/new g"
  jam_shows "a new group" "jam founds a group" 60 || stop_all
  click join-group; click dialog-field; type_in g; click dialog-me; type_in frank_chat; click accept
  expect frank_chat 'code=[A-Za-z0-9+/=]\{8,\}' "frank_chat shows a voucher code" "$SECONDS_NET" || stop_all
  CODE=$(tail -n 1 "$WORK/frank_chat.log" | sed 's/.*code=\([^ ]*\) .*/\1/')
  jam_line "/invite $CODE"
  expect frank_chat 'chats=\[g\[joined=true' "frank_chat joins jam's group" "$SECONDS_NET" || stop_all
  jam_shows "added ~frank_chat" "jam adds frank_chat" "$SECONDS_NET" || stop_all
fi

jam_line "hello from jam"
click draft; type_in "hello from frank_chat"; click send
expect frank_chat '~jam:hello from jam' "frank_chat reads jam's message" "$SECONDS_NET"
jam_shows "~frank_chat +hello from frank_chat" "jam reads frank_chat's message" "$SECONDS_NET"

# Each reply acknowledges what its sender has read, so a few rounds each way give both sides
# their second mark.
for n in 1 2 3; do
  jam_line "jam $n"
  expect frank_chat "~jam:jam $n" "frank_chat reads jam $n" "$SECONDS_NET"
  click draft; type_in "frank_chat $n"; click send
  jam_shows "~frank_chat +frank_chat $n" "jam reads frank_chat $n" "$SECONDS_NET"
done
expect frank_chat 'me✓✓:hello from frank_chat' "jam acknowledges frank_chat's messages" "$SECONDS_NET"
jam_shows "me +jam 2 √√" "frank_chat acknowledges jam's messages" "$SECONDS_NET"
stop_all
