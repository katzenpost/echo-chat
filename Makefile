# SPDX-License-Identifier: AGPL-3.0-only

export PATH := $(HOME)/.cargo/bin:$(HOME)/.elan/bin:$(PATH)

katzenpost_ref?=2405aa1119404b1e27cce0566729141102d769f0
katzenpost_dir?=.katzenpost

.PHONY: build test run shots e2e e2e-offline test-integration ci

build:
	lake exe cache get && lake build glint

# In one process, with no daemon or window.
test:
	lake exe cache get && lake build glint-test && lake exe glint-test

run:
	lake exe glint

# Pictures of the window, drawn offscreen, in shots/.
shots:
	lake build glint-test && lake exe glint-test --shot shots

e2e: e2e-offline

# A saved state shown in a real window on Xvfb, driven with xdotool.
e2e-offline:
	lake build glint glint-test && sh tests/e2e/offline.sh

ci: test e2e
