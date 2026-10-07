#!/bin/sh
# Run the CI pipelines (tools/ci/check-r58.sh, check-r40.sh) locally in a
# clean Ubuntu 24.04 container, as the GitHub runners would: the working
# tree (tracked and untracked files, not the ignored build output, also
# of the emu/ submodule) and .git (for the tag make ref needs) are copied
# in, SDCC is the pinned binary release.
#
#   tools/ci/docker.sh            # both
#   tools/ci/docker.sh r40        # one
#
# DOCKER=podman to use podman; CPUS=4 to limit the container as a GitHub
# runner is.  The SDCC download and the R40 toolchain build are kept in
# volumes; the packaged files (tools/ci/package.sh) are copied back into
# dist/.
set -eu

DOCKER=${DOCKER:-docker}
IMAGE=docker.io/library/ubuntu:24.04
FW=${*:-r58 r40}
root=$(git rev-parse --show-toplevel)
cd "$root"

# the tree is copied first, so editing it during the run changes nothing
snap=$(mktemp)
trap 'rm -f "$snap"' EXIT
{ git ls-files -co --exclude-standard -z | grep -zvx emu
  git -C emu ls-files -co --exclude-standard -z | sed -z 's|^|emu/|'
  printf '.git\0'; } |
	tar --null -T - -c > "$snap"
$DOCKER run --rm -i ${CPUS:+--cpus=$CPUS} -e FW="$FW" \
		-v r58-sdcc-cache:/root/.cache -v r40-toolchain:/work/reference/toolchain \
		$IMAGE sh -euc '
		export DEBIAN_FRONTEND=noninteractive
		apt-get update -qq >&2
		apt-get install -qq -y --no-install-recommends \
			build-essential python3 python3-numpy curl ca-certificates bzip2 git byacc >/dev/null
		mkdir -p /work && cd /work && tar -x
		git config --global --add safe.directory /work
		git config --global --add safe.directory /work/reference/toolchain/lcc
		v=local-$(git rev-parse --short HEAD)
		for fw in $FW; do
			case $fw in r58) PATH=$(tools/ci/install-sdcc.sh):$PATH; export PATH ;; esac
			tools/ci/check-$fw.sh >&2
			tools/ci/package.sh "$fw" "$v" >&2
		done
		tar -c dist
	' < "$snap" | tar -x
