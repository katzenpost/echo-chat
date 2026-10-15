#!/bin/sh
# SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
# SPDX-License-Identifier: AGPL-3.0-only
set -eu
WORK=$(mktemp -d)
export WORK
# ALSA's null device, as a microphone and speaker that need no hardware.
printf 'pcm.!default { type null }\nctl.!default { type hw card 0 }\n' > "$WORK/asound.conf"
export ALSA_CONFIG_PATH="$WORK/asound.conf"
trap 'rm -rf "$WORK"' EXIT
env -u WAYLAND_DISPLAY xvfb-run -a -s "-screen 0 1280x800x24" sh "$(dirname "$0")/offline-session.sh"
