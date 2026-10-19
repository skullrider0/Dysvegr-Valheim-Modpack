#!/usr/bin/env bash
# Unraid cleanup: read-only by default. Keep last backup per dated family.
set -Eeuo pipefail
CACHE_ROOT="${CACHE_ROOT:-/mnt/cache}"
APPDATA="$CACHE_ROOT/appdata"
TEMPLATE_DIR=/boot/config/plugins/dockerMan/templates-user
APPLY=0
PURGE_ORPHANS=0
INCLUDE_TEMPLATE=0
usage() {
 cat <<'USAGE'
Usage: bash disk-cleanup-unraid.sh [--apply] [--purge-orphans] [--include-template-orphans]
  (none)                     Preview. Nothing is deleted.
  --apply                    Delete older date-stamped backup archives/snapshots.
                             Keep the latest per backup name/category.
  --apply --purge-orphans    Also delete directories in cache/appdata not mounted
                             by any current OR stopped Docker container.
  --include-template-orphans Also include unmounted folders referenced by
                             saved Docker templates (extra caution).
This script never deletes Docker system images, Docker named volumes, or
currently bind-mounted appdata. Backup scanning is limited to cache backup
folders, not random files inside active application directories.
USAGE
}
for arg in "$@"; do
 case "$arg" in
  --apply) APPLY=1 ;;
  --purge-orphans) PURGE_ORPHANS=1 ;;
  --include-template-orphans) INCLUDE_TEMPLATE=1 ;;
  -h|--help) usage; exit 0 ;;
  *) echo "Unknown option: $arg" >&2; usage >&2; exit 2 ;;
 esac
done
if (( PURGE_ORPHANS && !APPLY )); then echo '--purge-orphans requires --apply' >&2; exit 2; fi
if (( INCLUDE_TEMPLATE && !PURGE_ORPHANS )); then
 echo '--include-template-orphans requires --apply --purge-orphans' >&2; exit 2
fi
if (( APPLY )) && [[ $EUID -ne 0 ]]; then echo 'Run deletion as root in Unraid' >&2; exit 1; fi
if [[ ! -d "$APPDATA" ]]; then echo "Missing $APPDATA" >&2; exit 1; fi
for cmd in docker du find stat sort sed readlink grep rm df; do
 command -v "$cmd" >/dev/null || { echo "Missing $cmd" >&2; exit 1; }
done
CACHE_REAL="$(readlink -f "$CACHE_ROOT")"
APPDATA_REAL="$(readlink -f "$APPDATA")"
[[ -n "$CACHE_REAL" && "$CACHE_REAL" != / && "$APPDATA_REAL" == "$CACHE_REAL/appdata" ]] ||
 { echo 'Unsafe CACHE_ROOT: expected an appdata folder inside the cache' >&2; exit 1; }

# Do not guess which appdata is unused if Docker cannot be inspected.
docker info --format '{{.ServerVersion}}' >/dev/null 2>&1 ||
 { echo 'Docker daemon unavailable. Nothing changed.' >&2; exit 1; }
mapfile -t CONTAINERS < <(docker ps -aq)
(( ${#CONTAINERS[@]} > 0 )) ||
 { echo 'No Docker containers found. Refusing orphan selection.' >&2; exit 1; }

declare -A MOUNTED=()
PROTECT_ALL=0
for id in "${CONTAINERS[@]}"; do
 mounts="$(docker inspect --format '{{range .Mounts}}{{println .Source}}{{end}}' "$id")" ||
 { echo "Failed to inspect $id. Nothing changed." >&2; exit 1; }
 while IFS= read -r source; do
  [[ -n "$source" ]] || continue
  source="${source%/}"
  case "$source" in
   */appdata) PROTECT_ALL=1 ;;
   */appdata/*)
    suffix="${source##*/appdata/}"
    folder="${suffix%%/*}"
    [[ -n "$folder" ]] && MOUNTED["$folder"]=1 ;;
   /mnt/cache|/mnt/user|/mnt/disk[0-9]*|"$CACHE_REAL")
    PROTECT_ALL=1 ;;
  esac
 done <<< "$mounts"
done

has_template() {
 [[ -d "$TEMPLATE_DIR" ]] &&
 grep -RFq -- "/appdata/$1" "$TEMPLATE_DIR" 2>/dev/null
}
is_backup_dir() {
 local x="${1,,}"
 [[ "$x" == *backup* || "$x" == *snapshot* ]]
}
family() {
 local original="$1" fixed
 fixed="$(printf '%s\n' "$original" | sed -E \
   -e 's/20[0-9]{6}([T_-]?[0-9]{6})?Z?/<date>/g' \
   -e 's/20[0-9]{2}[-_][0-9]{2}[-_][0-9]{2}([T_-][0-9]{2}[-_]?[0-9]{2}([-_]?[0-9]{2})?)?/<date>/g')"
 [[ "$fixed" != "$original" ]] || return 1
 printf '%s' "$fixed"
}
declare -a ROOTS=() ITEMS=() STALE=() ORPHANS=() TEMPLATE_ONLY=()
declare -A GROUP=() LATEST=() LATEST_TIME=()
for dir in "$APPDATA"/* "$CACHE_ROOT"/backups "$CACHE_ROOT"/backup; do
 [[ -d "$dir" && ! -L "$dir" ]] || continue
 is_backup_dir "${dir##*/}" && ROOTS+=("$dir")
done
add_backup() {
 local path="$1" name key mt
 [[ ! -L "$path" && ( -f "$path" || -d "$path" ) ]] || return 0
 name="${path##*/}"
 key="$(family "$name")" || return 0
 key="${path%/*}/$key"
 mt="$(stat -c %Y -- "$path")"
 ITEMS+=("$path")
 GROUP["$path"]="$key"
 if [[ -z "${LATEST[$key]:-}" || "$mt" -gt "${LATEST_TIME[$key]}" ]]; then
  LATEST["$key"]="$path"
  LATEST_TIME["$key"]="$mt"
 fi
}
for root in "${ROOTS[@]}"; do
 while IFS= read -r -d '' entry; do
  if family "${entry##*/}" >/dev/null; then
   add_backup "$entry"
  elif [[ -d "$entry" && ! -L "$entry" ]]; then
   while IFS= read -r -d '' sub; do add_backup "$sub"; done \
     < <(find "$entry" -mindepth 1 -maxdepth 1 \( -type f -o -type d \) -print0)
  fi
 done < <(find "$root" -mindepth 1 -maxdepth 1 \( -type f -o -type d \) -print0)
done
for path in "${ITEMS[@]}"; do
 key="${GROUP[$path]}"
 [[ "${LATEST[$key]}" == "$path" ]] || STALE+=("$path")
done
for dir in "$APPDATA"/*; do
 [[ -d "$dir" && ! -L "$dir" ]] || continue
 name="${dir##*/}"
 is_backup_dir "$name" && continue
 case "${name,,}" in
  dysvegr-valheim-modpack|docker|system|lost+found|steamcmd) continue ;;
 esac
 if (( PROTECT_ALL )) || [[ -n "${MOUNTED[$name]:-}" ]]; then continue; fi
 if has_template "$name"; then
  TEMPLATE_ONLY+=("$dir")
  (( INCLUDE_TEMPLATE )) && ORPHANS+=("$dir")
 else
  ORPHANS+=("$dir")
 fi
done
echo '===== CACHE CAPACITY ====='
df -h "$CACHE_ROOT"
echo '===== CACHE FOLDERS (SYSTEM IS NEVER CLEANED) ====='
du -xhd1 "$CACHE_ROOT" 2>/dev/null | sort -h | tail -15
echo '===== LARGEST APPDATA ====='
du -xhd1 "$APPDATA" 2>/dev/null | sort -h | tail -20
echo '===== BACKUP RETENTION ====='
printf 'Found %d backup folders, %d dated backups, %d outdated entries.\n' \
 "${#ROOTS[@]}" "${#ITEMS[@]}" "${#STALE[@]}"
for path in "${STALE[@]}"; do du -sh -- "$path" || true; done
echo '===== APPDATA NOT MOUNTED BY ANY CONTAINER ====='
for path in "${ORPHANS[@]}"; do du -sh -- "$path" || true; done
if (( ${#TEMPLATE_ONLY[@]} )); then
 echo 'Unmounted but referenced by saved Docker templates (protected by default):'
 for path in "${TEMPLATE_ONLY[@]}"; do echo "$path"; done
fi
printf 'Inspected %d installed or stopped containers.\n' "${#CONTAINERS[@]}"
if (( !APPLY )); then
 echo '[PREVIEW ONLY] Nothing deleted.'
 echo 'Prune old backups: bash disk-cleanup-unraid.sh --apply'
 echo 'Also delete orphans: bash disk-cleanup-unraid.sh --apply --purge-orphans'
 exit 0
fi
if (( ${#STALE[@]} == 0 && (PURGE_ORPHANS == 0 || ${#ORPHANS[@]} == 0) )); then
 echo 'Nothing eligible for cleanup.'; exit 0
fi
[[ -t 0 ]] || { echo 'Destructive mode requires an interactive terminal.' >&2; exit 1; }
if (( PURGE_ORPHANS )); then
 echo 'WARNING: deleting orphan appdata can permanently destroy game saves!'
 read -r -p 'Type DELETE BACKUPS AND ORPHANS to continue: ' confirmation
 [[ "$confirmation" == 'DELETE BACKUPS AND ORPHANS' ]] || { echo Cancelled; exit 0; }
else
 read -r -p 'Type DELETE OLD BACKUPS to continue: ' confirmation
 [[ "$confirmation" == 'DELETE OLD BACKUPS' ]] || { echo Cancelled; exit 0; }
fi
delete_path() {
 local path="$1" real
 [[ -e "$path" && ! -L "$path" ]] || return 0
 real="$(readlink -f -- "$path")"
 [[ "$real" == "$APPDATA_REAL/"* ||
    "$real" == "$CACHE_REAL/backups/"* ||
    "$real" == "$CACHE_REAL/backup/"* ]] ||
 { echo "Unsafe deletion target: $path" >&2; return 1; }
 rm -rf --one-file-system -- "$path"
 echo "Deleted: $path"
}
for path in "${STALE[@]}"; do
 key="${GROUP[$path]}"
 [[ -e "${LATEST[$key]}" ]] ||
 { echo "Newest backup vanished; aborting: $path" >&2; exit 1; }
 modified="$(stat -c %Y "$path")"
 if (( $(date +%s) - modified < 600 )); then
  echo "Skipping recently changed backup: $path"; continue
 fi
 delete_path "$path"
done
if (( PURGE_ORPHANS )); then
 for path in "${ORPHANS[@]}"; do
  # Inspect mounts again immediately before deletion.
  for id in "${CONTAINERS[@]}"; do
   mounts="$(docker inspect --format '{{range .Mounts}}{{println .Source}}{{end}}' "$id")" ||
     { echo 'Docker changed during cleanup; aborting' >&2; exit 1; }
   if printf '%s\n' "$mounts" | grep -Fq -- "/appdata/${path##*/}"; then
    echo "Now mounted; skipping: $path"
    continue 2
   fi
  done
  delete_path "$path"
 done
fi
echo '===== SPACE AFTER CLEANUP ====='
df -h "$CACHE_ROOT"
echo 'Done. Docker system storage was not modified.'
