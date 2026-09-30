#!/bin/sh
# Install the pinned SDCC (the official amd64 Linux binary release) into
# $1 (default: $HOME/.cache/sdcc-$SDCC_VERSION) and print its bin directory.
# Already there: nothing downloaded.  The tarball is checked against its
# SHA-256.
#
# SDCC's output depends on how SDCC itself was built, not only on its
# version: the same 4.6.0 #16555 from a distribution package allocates
# registers differently, so the release images are built with this one.
set -eu

SDCC_VERSION=4.6.0
SDCC_SHA256=f6b929c62ed3082a26087885e0f1f9bf41878602ef1f57e40b11b4a01bf4f366
TARBALL=sdcc-$SDCC_VERSION-amd64-unknown-linux2.5.tar.bz2
URL=https://sourceforge.net/projects/sdcc/files/sdcc-linux-amd64/$SDCC_VERSION/$TARBALL/download

dest=${1:-$HOME/.cache/sdcc-$SDCC_VERSION}
if [ ! -x "$dest/bin/sdcc" ]; then
	tmp=$(mktemp -d)
	trap 'rm -rf "$tmp"' EXIT
	curl -fsSL --retry 3 -o "$tmp/$TARBALL" "$URL"
	echo "$SDCC_SHA256  $tmp/$TARBALL" | sha256sum -c - >&2
	mkdir -p "$dest"
	tar -xjf "$tmp/$TARBALL" -C "$dest" --strip-components=1
fi
"$dest/bin/sdcc" --version | grep -q " $SDCC_VERSION " || {
	echo "install-sdcc.sh: $dest/bin/sdcc is not $SDCC_VERSION" >&2
	exit 1
}
echo "$dest/bin"
