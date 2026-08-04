#!/usr/bin/env bash
# Install the shim for the Steam client. Runs entirely as the normal user:
# no sudo, no writes outside $HOME, nothing in the read-only rootfs.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$ROOT/build"
DROPIN_DIR="$HOME/.config/systemd/user/steam-launcher.service.d"

[ -f "$OUT/libnorcvbuf32.so" ] && [ -f "$OUT/libnorcvbuf64.so" ] || "$ROOT/build.sh"

install -Dm755 "$OUT/libnorcvbuf32.so" "$HOME/.local/lib/libnorcvbuf.so"
install -Dm755 "$OUT/libnorcvbuf64.so" "$HOME/.local/lib64/libnorcvbuf.so"

# The Steam client binary is 32-bit while its children are mixed. glibc does not
# expand $LIB inside LD_PRELOAD, so both paths are listed; the loader takes the
# matching ELF class and logs "wrong ELF class" for the other one.
mkdir -p "$DROPIN_DIR"
cat > "$DROPIN_DIR/norcvbuf.conf" <<EOF
[Service]
Environment=LD_PRELOAD=$HOME/.local/lib/libnorcvbuf.so:$HOME/.local/lib64/libnorcvbuf.so
EOF

systemctl --user daemon-reload

echo "installed:"
echo "  $HOME/.local/lib/libnorcvbuf.so"
echo "  $HOME/.local/lib64/libnorcvbuf.so"
echo "  $DROPIN_DIR/norcvbuf.conf"
echo
echo "apply with:  systemctl --user restart steam-launcher.service"
