#!/usr/bin/env bash
# Dysvegr Thunderstore maintenance for ich777 Valheim / Unraid.
# "check" only reads Thunderstore; "update" requires confirmation and backs up.
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
CACHE="$ROOT/.dysvegr-updates"
MODE="${1:-check}"
shift || true
YES=0
for option in "$@"; do
  case "$option" in
    --yes) YES=1 ;;
    *) echo "Unknown argument: $option" >&2; exit 2 ;;
  esac
done
mkdir -p "$CACHE"
if command -v flock >/dev/null; then
  exec 8>"$CACHE/update.lock"
  flock -n 8 || { echo "Another Dysvegr update/check is already running." >&2; exit 1; }
fi
run_scanner() {
  if command -v python3 >/dev/null; then
    python3 "$ROOT/check-updates.py" "$@"
  elif command -v docker >/dev/null; then
    echo '[Dysvegr] Python3 missing on host; using temporary python:3.12-alpine container.'
    docker run --rm -v "$ROOT:/app:rw" -w /app python:3.12-alpine python /app/check-updates.py "$@"
  else
    echo 'Neither Python3 nor Docker is available for update checking.' >&2
    return 1
  fi
}
case "$MODE" in
  check)
    run_scanner check --all
    echo "Saved report: $CACHE/latest-report.txt"
    ;;
  update)
    [[ $EUID -eq 0 ]] || { echo "Run the updater as root in Unraid." >&2; exit 1; }
    # Download fresh metadata; any API or dependency error blocks installation.
    run_scanner prepare
    PENDING="$CACHE/pending-mods.tsv"
    CURRENT="$CACHE/current-mods.tsv"
    if [[ ! -s "$PENDING" ]]; then
      echo '[Dysvegr] Server mods are already at their selected latest versions.'
      exit 0
    fi
    [[ -s "$CURRENT" ]] || { echo 'No current manifest was recorded; aborting.' >&2; exit 1; }
    echo '===== PROPOSED SERVER VERSION CHANGES ====='
    while IFS=$'\t' read -r package new mode; do
      [[ -z "$package" || "$package" == \#* || "$mode" != server ]] && continue
      old="$(awk -F '\t' -v pkg="$package" '$1==pkg { print $2; exit }' "$CURRENT")"
      if [[ -n "$old" && "$old" != "$new" ]]; then
        printf '  %s: %s -> %s\n' "$package" "$old" "$new"
      fi
    done < "$PENDING"
    if [[ $YES -ne 1 ]]; then
      echo
      echo 'ALL PLAYERS may need to update matching multiplayer mods.'
      echo 'Installing will stop and restart Valheim, after world+BepInEx backups.'
      read -r -p "Type UPDATE to continue (anything else cancels): " response
      [[ "$response" == UPDATE ]] || { echo "Cancelled; server unchanged."; exit 0; }
    fi
    echo '[Dysvegr] Downloading and applying approved versions...'
    DYSG_MANIFEST="$PENDING" DYSG_OLD_MANIFEST="$CURRENT" \
      bash "$ROOT/install-unraid.sh" --mods-only
    # Record the last successful versions locally. This file is .gitignored:
    # future git pulls can still update the curated base manifest and scripts.
    cp "$PENDING" "$ROOT/mods.local.tsv.tmp"
    mv -f "$ROOT/mods.local.tsv.tmp" "$ROOT/mods.local.tsv"
    echo "[Dysvegr] Approved installed versions saved in $ROOT/mods.local.tsv"
    echo '[Dysvegr] Check the BepInEx logs and have all clients update as needed.'
    ;;
  *)
    echo 'Usage: bash update-mods.sh check | update [--yes]' >&2; exit 2 ;;
esac
