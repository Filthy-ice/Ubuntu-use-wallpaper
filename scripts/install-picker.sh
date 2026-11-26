#!/bin/bash
set -euo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESK="$HOME/.local/share/applications/winwall-picker.desktop"
mkdir -p "$(dirname "$DESK")"
sed "s|@KIT@|$KIT|g" "$KIT/picker/winwall-picker.desktop.in" > "$DESK"
chmod 644 "$DESK"
echo "installed -> $DESK"
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$(dirname "$DESK")" 2>/dev/null || true
fi
