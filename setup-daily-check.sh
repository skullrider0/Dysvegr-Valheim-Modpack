#!/usr/bin/env bash
# Register the update checker as a persistent Unraid User Scripts entry.
# Scheduling is selected once in Unraid's Settings > User Scripts UI.
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
[[ "$EUID" -eq 0 ]] || { echo 'Run as root in Unraid.' >&2; exit 1; }
[[ -d /boot/config ]] || { echo "Unraid USB flash configuration not found." >&2; exit 1; }
TARGET="/boot/config/plugins/user.scripts/scripts/DysvegrModUpdateCheck"
mkdir -p "$TARGET"
cat > "$TARGET/script" <<EOF
#!/bin/bash
#name=DysvegrModUpdateCheck
#description=Check Thunderstore mods daily (report only, never installs)
#backgroundOnly=true
#arrayStarted=false
bash "$ROOT/update-mods.sh" check >> "$ROOT/.dysvegr-updates/daily.log" 2>&1
EOF
chmod 755 "$TARGET/script"
echo "[Dysvegr] Created Unraid User Scripts entry: $TARGET/script"
echo 'IMPORTANT: In Unraid Web UI go to Settings -> User Scripts,'
echo 'find DysvegrModUpdateCheck and set Schedule to DAILY, then click Apply.'
echo 'This only checks; it does NOT replace DLLs or restart Valheim.'
echo "Report file: $ROOT/.dysvegr-updates/latest-report.txt"
