#!/bin/sh
# SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
# SPDX-License-Identifier: AGPL-3.0-only
#
# Keeps each member's logs and state when a check fails, and says where.
set -eu
WORK=$(mktemp -d "${TMPDIR:-/tmp}/glint-mixnet.XXXXXX")
export WORK
if env -u WAYLAND_DISPLAY xvfb-run -a -s "-screen 0 3200x2300x24" sh "$(dirname "$0")/mixnet-session.sh"; then
  rm -rf "$WORK"
else
  echo "logs kept in $WORK"
  exit 1
fi
