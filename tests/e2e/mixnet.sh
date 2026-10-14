#!/bin/sh
# SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
# SPDX-License-Identifier: AGPL-3.0-only
set -eu
WORK=$(mktemp -d)
export WORK
trap 'rm -rf "$WORK"' EXIT
env -u WAYLAND_DISPLAY xvfb-run -a -s "-screen 0 3200x2300x24" sh "$(dirname "$0")/mixnet-session.sh"
