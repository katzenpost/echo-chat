#!/bin/sh
# SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
# SPDX-License-Identifier: AGPL-3.0-only
set -eu
WORK=$(mktemp -d)
export WORK
trap 'rm -rf "$WORK"' EXIT
xvfb-run -a -s "-screen 0 1280x800x24" sh "$(dirname "$0")/offline-session.sh"
