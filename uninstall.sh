#!/usr/bin/env bash
set -euo pipefail

DROPIN="$HOME/.config/systemd/user/steam-launcher.service.d/norcvbuf.conf"

rm -f "$DROPIN"
rmdir --ignore-fail-on-non-empty "$(dirname "$DROPIN")" 2>/dev/null || true
rm -f "$HOME/.local/lib/libnorcvbuf.so" "$HOME/.local/lib64/libnorcvbuf.so"

systemctl --user daemon-reload

echo "removed. apply with:  systemctl --user restart steam-launcher.service"
