#!/usr/bin/env bash
# Build both ELF classes of the shim. SteamOS ships no compiler and keeps the
# rootfs read-only, so the build runs in a throwaway rootless podman container.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$ROOT/build"
IMAGE="${NORCVBUF_IMAGE:-docker.io/library/debian:12}"

command -v podman >/dev/null || { echo "podman is required" >&2; exit 1; }

mkdir -p "$OUT"
cp "$ROOT/src/norcvbuf.c" "$OUT/"

podman run --rm -v "$OUT:/work" "$IMAGE" bash -c '
	set -e
	apt-get update -qq >/dev/null 2>&1
	DEBIAN_FRONTEND=noninteractive apt-get install -y -qq gcc-multilib >/dev/null 2>&1
	cd /work
	gcc -m32 -shared -fPIC -O2 -o libnorcvbuf32.so norcvbuf.c -ldl
	gcc -m64 -shared -fPIC -O2 -o libnorcvbuf64.so norcvbuf.c -ldl
'

rm -f "$OUT/norcvbuf.c"
file "$OUT"/libnorcvbuf*.so

if [ "${NORCVBUF_KEEP_IMAGE:-0}" != 1 ]; then
	podman rmi "$IMAGE" >/dev/null 2>&1 || true
fi

echo "built into $OUT"
