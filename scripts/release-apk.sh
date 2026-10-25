#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
#
# Builds the release APK for phones, unsigned, so that anyone with the same toolchains gets the
# same bytes, and writes it with its UNSIGNED-SHA256SUMS to the directory given (dist/ by default).
# The release workflow signs it once both of its builds agree.
#
# Needs what `make apk` does, with the NDK, build-tools and android.jar the release workflow pins
# given as ANDROID_NDK_HOME, BUILD_TOOLS and ANDROID_JAR.
set -eu

out=${1:-dist}
cd "$(dirname "$0")/.."

export RUSTUP_TOOLCHAIN=1.99.0
export PATH="$HOME/.cargo/bin:$HOME/.elan/bin:$PATH"
export SOURCE_DATE_EPOCH="$(git log -1 --format=%ct)"
export LC_ALL=C TZ=UTC

version="$(git describe --tags --always)"
# Android compares versionCode, which an update must not lower: v1.2.3 is 10203.
code=$(echo "$version" | sed -n 's/^v\([0-9]*\)\.\([0-9]*\)\.\([0-9]*\).*/\1 \2 \3/p' |
	awk '{ print $1 * 10000 + $2 * 100 + $3 }')

KEYSTORE=none VERSION_NAME="${version#v}" VERSION_CODE="${code:-1}" make apk ANDROID_ABI=arm64-v8a

mkdir -p "$out"
cp .lake/android/frank_chat-arm64-v8a-unsigned.apk "$out/frank_chat-$version-arm64-unsigned.apk"
cd "$out"
sha256sum "frank_chat-$version-arm64-unsigned.apk" > UNSIGNED-SHA256SUMS
cat UNSIGNED-SHA256SUMS
