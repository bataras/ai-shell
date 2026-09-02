#!/bin/sh
# Run the install checks in virgin Debian and Ubuntu containers.
#
#   test/docker-install.sh                     # debian:stable-slim, ubuntu:24.04
#   test/docker-install.sh debian:12 fedora:41 # any image with a POSIX sh
#   AI_SHELL_TEST_OFFLINE=1 test/docker-install.sh   # skip the phase that
#                                                    # needs the network
#
# The checkout is mounted read-only, so a container can't write back into it.
# test/in-container.sh holds the checks themselves.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

command -v docker >/dev/null 2>&1 || {
  echo "docker not found — this test needs it" >&2
  exit 2
}

if [ $# -gt 0 ]; then
  images="$*"
else
  images="debian:stable-slim ubuntu:24.04"
fi

status=0
for img in $images; do
  printf '\n########## %s ##########\n' "$img"
  docker run --rm \
    -e AI_SHELL_TEST_OFFLINE="${AI_SHELL_TEST_OFFLINE:-0}" \
    -v "$root:/src:ro" \
    "$img" /src/test/in-container.sh || status=1
done

printf '\n'
if [ "$status" -eq 0 ]; then echo "all images passed"; else echo "FAILURES above" >&2; fi
exit "$status"
