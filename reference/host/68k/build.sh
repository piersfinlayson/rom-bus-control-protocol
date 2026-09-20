#!/bin/sh
# build.sh — builds the six Amiga images amiga.json names.
#
# usage: build.sh [clean]
#
# clean removes each application's build directory instead.
#
# Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>

set -e

cd "$(dirname "$0")"

target=$1
if [ $# -gt 1 ] || { [ -n "$target" ] && [ "$target" != clean ]; }; then
    echo "usage: $0 [clean]" >&2
    exit 1
fi

config=amiga.json
[ -f "$config" ] || { echo "$config: not found" >&2; exit 1; }

# Each image's path in the config gives the application to build and the size
# to build it at.
images=$(sed -n 's|.*"file"[[:space:]]*:[[:space:]]*"\([^"]*\)".*|\1|p' "$config")
[ -n "$images" ] || { echo "$config names no images" >&2; exit 1; }

for image in $images; do
    if [ "$target" = clean ]; then
        make -C "${image%%/*}" clean
    else
        make -C "${image%%/*}" "${image#*/}"
    fi
done
