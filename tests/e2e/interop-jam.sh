#!/bin/sh
# SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
# SPDX-License-Identifier: AGPL-3.0-only
#
#   JAM=path/to/jam DAEMON=@katzenpost ROLE=host|guest sh tests/e2e/interop-jam.sh
set -eu
: "${JAM:?the jam program to run}"
WORK=$(mktemp -d)
export WORK JAM
trap 'rm -rf "$WORK"' EXIT
env -u WAYLAND_DISPLAY xvfb-run -a -s "-screen 0 1280x800x24" sh "$(dirname "$0")/interop-jam-session.sh"
