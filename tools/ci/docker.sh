#!/bin/sh
# Run the CI pipeline (tools/ci/check.sh) locally in a clean Ubuntu 24.04
# container, as the GitHub runner would: the working tree (tracked and
# untracked files, not the ignored build output, also of the emu/
# submodule) and .git (for the tag make ref needs) are copied in, SDCC is
# the pinned binary release.
# DOCKER=podman to use podman; CPUS=4 to limit the container as a GitHub
# runner is.  The SDCC download is kept in a volume; the packaged files
# (tools/ci/package.sh) are copied back into dist/.
set -eu

DOCKER=${DOCKER:-docker}
IMAGE=docker.io/library/ubuntu:24.04
root=$(git rev-parse --show-toplevel)
cd "$root"

{ git ls-files -co --exclude-standard -z | grep -zvx emu
  git -C emu ls-files -co --exclude-standard -z | sed -z 's|^|emu/|'
  printf '.git\0'; } |
	tar --null -T - -c |
	$DOCKER run --rm -i ${CPUS:+--cpus=$CPUS} -v r58-sdcc-cache:/root/.cache $IMAGE sh -euc '
		export DEBIAN_FRONTEND=noninteractive
		apt-get update -qq >&2
		apt-get install -qq -y --no-install-recommends \
			build-essential python3 python3-numpy curl ca-certificates bzip2 git >/dev/null
		mkdir /work && cd /work && tar -x
		git config --global --add safe.directory /work
		PATH=$(tools/ci/install-sdcc.sh):$PATH
		export PATH
		tools/ci/check.sh >&2
		tools/ci/package.sh local-$(git rev-parse --short HEAD) >&2
		tar -c dist
	' | tar -x
