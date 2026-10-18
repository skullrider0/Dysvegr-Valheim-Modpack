#!/usr/bin/env bash
# Import the exact Dysvegr 1.0 world folder from the user's uploaded RAR
# (repacked as world-Dysvegr.zip). This does NOT reinstall mods.
set -Eeuo pipefail

CONTAINER="${CONTAINER:-Valheim}"
ARCHIVE="${1:-/mnt/user/appdata/world-Dysvegr.zip}"
CHECK_ONLY=0
if [[ "$ARCHIVE" == "--check" ]]; then
  CHECK_ONLY=1
  ARCHIVE="${2:-/mnt/user/appdata/world-Dysvegr.zip}"
elif [[ "${2:-}" == "--check" ]]; then
  CHECK_ONLY=1
fi
[[ "$EUID" == 0 ]] || { echo 'Run as root in the Unraid terminal.' >&2; exit 1; }
for cmd in docker unzip tar mv mktemp find stat; do
  command -v "$cmd" >/dev/null || { echo "Missing $cmd" >&2; exit 1; }
done
[[ -f "$ARCHIVE" ]] || {
  echo "Cannot find $ARCHIVE" >&2
  echo 'Download world-Dysvegr.zip from ChatGPT and upload it to the Unraid appdata share.' >&2
  exit 1
}
docker inspect "$CONTAINER" >/dev/null 2>&1 || {
  echo "Valheim container '$CONTAINER' not found." >&2; exit 1;
}
GAME_DIR="$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/serverdata/serverfiles"}}{{.Source}}{{end}}{{end}}' "$CONTAINER")"
[[ -n "$GAME_DIR" && -d "$GAME_DIR" ]] || {
  echo 'Cannot find ich777 /serverdata/serverfiles bind mount; refusing to guess save path.' >&2
  exit 1
}

# ich777's Valheim service saves under this persistent data mount by default.
WORLD_ROOT=''
for candidate in \
  "$GAME_DIR/.config/unity3d/IronGate/Valheim/worlds_local" \
  "$(dirname "$GAME_DIR")/.config/unity3d/IronGate/Valheim/worlds_local"; do
  if [[ -d "$candidate" ]]; then WORLD_ROOT="$(cd "$candidate" && pwd -P)"; break; fi
done
[[ -n "$WORLD_ROOT" ]] || {
  echo 'worlds_local was not found. No files changed. Show me:' >&2
  echo "find '$GAME_DIR' -type d -name worlds_local -print" >&2
  exit 1
}

WORLD_NAME="$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$CONTAINER" |
  grep '^WORLD_NAME=' | tail -1 | cut -d= -f2- || true)"
if [[ -n "$WORLD_NAME" && "$WORLD_NAME" != Dysvegr ]]; then
  echo "Container WORLD_NAME=$WORLD_NAME, but imported world is Dysvegr." >&2
  echo 'Change World Name to Dysvegr in the Unraid Docker template first.' >&2
  exit 1
fi
echo "[Dysvegr] World save location: $WORLD_ROOT"
echo "[Dysvegr] Container world name: ${WORLD_NAME:-not exposed; verify in Unraid template}"
echo "[Dysvegr] Archive: $ARCHIVE"

# Validate all members belong inside Dysvegr/ and all generation-62 metadata exists.
unzip -tqq "$ARCHIVE" >/dev/null || { echo 'World archive failed CRC check' >&2; exit 1; }
while IFS= read -r path; do
  [[ "$path" == Dysvegr/* ]] || { echo "Unexpected archive path: $path" >&2; exit 1; }
  [[ "$path" != *\\* && "$path" != *"../"* && "$path" != *"/./"* ]] ||
    { echo "Unsafe archive path: $path" >&2; exit 1; }
done < <(unzip -Z1 "$ARCHIVE")
for required in \
  Dysvegr/_main.62.db2 \
  Dysvegr/_main.62.fwl2 \
  Dysvegr/_main.62.chunks \
  Dysvegr/_main.62.ok; do
  unzip -Z1 "$ARCHIVE" | grep -qxF "$required" || {
    echo "Missing essential world file: $required" >&2; exit 1;
  }
done

if [[ -d "$WORLD_ROOT/Dysvegr" ]]; then
  echo '[Dysvegr] An existing Dysvegr folder WILL BE BACKED UP before replacement.'
else
  echo '[Dysvegr] No existing Dysvegr directory found.'
fi
if [[ "$CHECK_ONLY" == 1 ]]; then
  echo '[Dysvegr] Archive and destination verified. No changes made.'
  exit 0
fi

STAGE="$(mktemp -d "$WORLD_ROOT/.dysvegr-import.XXXXXXXX")"
STAGE_CREATED=1
WAS_RUNNING="$(docker inspect -f '{{.State.Running}}' "$CONTAINER")"
STOPPED=0
OLD_MOVED=0
NEW_ACTIVE=0
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_ROOT="$(dirname "$GAME_DIR")/Dysvegr-world-backups"
PREVIOUS="$BACKUP_ROOT/Dysvegr-previous-$STAMP"
cleanup() {
  rc=$?
  trap - EXIT
  if (( rc != 0 && ( OLD_MOVED == 1 || NEW_ACTIVE == 1 ) )); then
    echo '[Dysvegr] Import failed: attempting to restore the previous world.' >&2
    if (( NEW_ACTIVE == 1 )) && [[ -d "$WORLD_ROOT/Dysvegr" ]]; then
      mv "$WORLD_ROOT/Dysvegr" "$BACKUP_ROOT/Dysvegr-failed-import-$STAMP" || true
    fi
    if (( OLD_MOVED == 1 )) && [[ -d "$PREVIOUS" ]]; then
      mv "$PREVIOUS" "$WORLD_ROOT/Dysvegr" || true
    fi
  fi
  if [[ -n "${STAGE:-}" && -d "$STAGE" ]]; then rm -rf -- "$STAGE"; fi
  if (( STOPPED == 1 )) && [[ "$WAS_RUNNING" == true ]]; then
    echo '[Dysvegr] Starting Valheim container...'
    docker start "$CONTAINER" || true
  fi
  exit "$rc"
}
trap cleanup EXIT

echo '[Dysvegr] Extracting into a staging folder...'
unzip -qq "$ARCHIVE" -d "$STAGE"
[[ -f "$STAGE/Dysvegr/_main.62.db2" && -f "$STAGE/Dysvegr/_main.62.ok" ]] ||
  { echo 'Staged world is incomplete' >&2; exit 1; }
mkdir -p "$BACKUP_ROOT"
if [[ "$WAS_RUNNING" == true ]]; then
  echo '[Dysvegr] Stopping Valheim before world change...'
  docker stop -t 120 "$CONTAINER"
  STOPPED=1
fi

# Make a full backup of all worlds, then also retain the old Dysvegr folder.
BACKUP="$BACKUP_ROOT/worlds_local-before-import-$STAMP.tar.gz"
echo "[Dysvegr] Backing up worlds to $BACKUP"
tar -czf "$BACKUP" -C "$WORLD_ROOT" --exclude='./.dysvegr-import.*' .
tar -tzf "$BACKUP" >/dev/null || { echo 'World backup validation failed!' >&2; exit 1; }
if [[ -e "$WORLD_ROOT/Dysvegr" ]]; then
  [[ -d "$WORLD_ROOT/Dysvegr" ]] || { echo 'Dysvegr exists but is not a directory' >&2; exit 1; }
  mv "$WORLD_ROOT/Dysvegr" "$PREVIOUS"
  OLD_MOVED=1
fi
mv "$STAGE/Dysvegr" "$WORLD_ROOT/Dysvegr"
NEW_ACTIVE=1

OWNER_UID="$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$CONTAINER" |
  grep '^UID=' | tail -1 | cut -d= -f2 || true)"
OWNER_GID="$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$CONTAINER" |
  grep '^GID=' | tail -1 | cut -d= -f2 || true)"
if [[ "$OWNER_UID" =~ ^[0-9]+$ && "$OWNER_GID" =~ ^[0-9]+$ ]]; then
  chown -R "$OWNER_UID:$OWNER_GID" "$WORLD_ROOT/Dysvegr"
else
  chown -R "$(stat -c '%u:%g' "$WORLD_ROOT")" "$WORLD_ROOT/Dysvegr"
fi
echo '[Dysvegr] Imported original world successfully!'
echo "[Dysvegr] Existing worlds backup: $BACKUP"
[[ "$OLD_MOVED" == 0 ]] || echo "[Dysvegr] Previous Dysvegr folder: $PREVIOUS"
echo '[Dysvegr] Remember: if any placed ItemDrawers exist, keep a backup until compatibility is resolved.'
