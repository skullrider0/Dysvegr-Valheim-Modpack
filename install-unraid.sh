#!/usr/bin/env bash
# Dysvegr Thunderstore mod installer for ich777's Unraid Valheim Docker container.
# Uses the pinned mods.tsv; ich777 controls the BepInEx framework installation.
set -Eeuo pipefail
IFS=$'\n\t'
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
MANIFEST="$ROOT/mods.tsv"
CONTAINER="${CONTAINER:-Valheim}"
WITH_WORLD=0
DRY_RUN=0
INSTALL_CLIENT=0

for flag in "$@"; do
  case "$flag" in
    --mods-only) WITH_WORLD=0 ;;
    --with-world) WITH_WORLD=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --all-mods) INSTALL_CLIENT=1 ;;
    -h|--help)
      echo 'Usage: bash install-unraid.sh [--mods-only|--with-world] [--dry-run] [--all-mods]'
      exit 0 ;;
    *) echo "Unknown option: $flag" >&2; exit 2 ;;
  esac
done

[[ $EUID -eq 0 ]] || { echo 'Run as root in the Unraid terminal.' >&2; exit 1; }
for cmd in docker curl unzip tar find cp mkdir mktemp; do
  command -v "$cmd" >/dev/null || { echo "Missing command: $cmd" >&2; exit 1; }
done
[[ -f "$MANIFEST" ]] || { echo "Missing $MANIFEST" >&2; exit 1; }
docker inspect "$CONTAINER" >/dev/null 2>&1 || {
  echo "Container '$CONTAINER' not found. Use CONTAINER=your-container-name." >&2; exit 1;
}

GAME_DIR="$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/serverdata/serverfiles"}}{{.Source}}{{end}}{{end}}' "$CONTAINER")"
[[ -n "$GAME_DIR" && -d "$GAME_DIR" ]] || {
  echo 'Missing ich777 /serverdata/serverfiles bind mount. Nothing was modified.' >&2; exit 1;
}
GAME_DIR="$(cd "$GAME_DIR" && pwd -P)"
[[ -d "$GAME_DIR/BepInEx" ]] || {
  echo "BepInEx not found in $GAME_DIR. Enable it in the ich777 Docker template, start once, then retry." >&2
  exit 1
}
BEP_ENV="$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$CONTAINER" |
  grep -E '^(ENABLE_BEPINEX|BEPINEX)=' || true)"
if echo "$BEP_ENV" | grep -qiE '=(false|0|no)$'; then
  echo "Docker BepInEx setting appears disabled: $BEP_ENV" >&2; exit 1
fi

WORLD_ROOT=''
for candidate in \
  "$GAME_DIR/.config/unity3d/IronGate/Valheim/worlds_local" \
  "$(dirname "$GAME_DIR")/.config/unity3d/IronGate/Valheim/worlds_local"; do
  if [[ -d "$candidate" ]]; then WORLD_ROOT="$candidate"; break; fi
done
echo "[Dysvegr] Container: $CONTAINER"
echo "[Dysvegr] Game directory: $GAME_DIR"
if [[ $WITH_WORLD -eq 1 ]]; then
  [[ -f "$ROOT/world-Dysvegr.zip" ]] || {
    echo 'world-Dysvegr.zip is not in this Git checkout. Copy it from the original bundle first.' >&2
    exit 1
  }
  [[ -n "$WORLD_ROOT" ]] || { echo 'Could not locate worlds_local. Nothing changed.' >&2; exit 1; }
  [[ ! -e "$WORLD_ROOT/Dysvegr" ]] || {
    echo 'Dysvegr world already exists. Refusing to overwrite.' >&2; exit 1;
  }
  echo "[Dysvegr] World directory: $WORLD_ROOT"
fi

if [[ $DRY_RUN -eq 1 ]]; then
  echo '[Dysvegr] Dry run (nothing downloaded or changed):'
  while IFS=$'\t' read -r package version mode; do
    [[ -z "$package" || "$package" == \#* ]] && continue
    case "$mode" in
      framework) echo "  SKIP ich777 framework: $package $version" ;;
      client)
        if [[ $INSTALL_CLIENT -eq 1 ]]; then echo "  INSTALL client override: $package $version"
        else echo "  SKIP client mod: $package $version"; fi ;;
      server) echo "  INSTALL: $package $version" ;;
      *) echo "Unknown mode for $package: $mode" >&2; exit 1 ;;
    esac
  done < "$MANIFEST"
  exit 0
fi

# Download and validate every archive BEFORE stopping the game.
STAGE="$(mktemp -d "$GAME_DIR/.dysvegr-stage.XXXXXXXX")"
WAS_RUNNING="$(docker inspect -f '{{.State.Running}}' "$CONTAINER")"
STOPPED=0
cleanup() {
  status=$?
  if [[ $STOPPED -eq 1 && "$WAS_RUNNING" == true ]]; then
    echo '[Dysvegr] Starting Valheim container...'
    docker start "$CONTAINER" || true
  fi
  if [[ -n "${STAGE:-}" ]]; then rm -rf -- "$STAGE"; fi
  exit "$status"
}
trap cleanup EXIT
mkdir -p "$STAGE/downloads" "$STAGE/extracted"

count=0
while IFS=$'\t' read -r package version mode; do
  [[ -z "$package" || "$package" == \#* ]] && continue
  [[ "$mode" == framework ]] && continue
  [[ "$mode" == client && $INSTALL_CLIENT -eq 0 ]] && continue
  [[ "$mode" == server || "$mode" == client ]] || { echo "Bad mode: $mode" >&2; exit 1; }
  [[ "$package" =~ ^[A-Za-z0-9_-]+$ && "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
    { echo "Bad manifest entry: $package $version" >&2; exit 1; }
  author="${package%%-*}"
  mod="${package#*-}"
  url="https://thunderstore.io/package/download/$author/$mod/$version/"
  file="$STAGE/downloads/$package-$version.zip"
  echo "[Dysvegr] Downloading $package $version"
  curl -fL --retry 3 --connect-timeout 20 --max-time 240 -sS "$url" -o "$file"
  unzip -tqq "$file" >/dev/null || { echo "Invalid download: $url" >&2; exit 1; }
  # Treat Windows backslashes as separators when checking archive paths.
  if unzip -Z1 "$file" | tr '\\' '/' | grep -qE '(^/|(^|/)\.\.(/|$)|^[A-Za-z]:)'; then
    echo "Archive contains unsafe paths: $package" >&2; exit 1
  fi
  mkdir -p "$STAGE/extracted/$package"
  # Windows-created ZIPs can extract correctly but return status 1 for a
  # harmless Info-ZIP backslash warning. Accept ONLY that one warning.
  extract_rc=0
  extract_log="$(unzip -q "$file" -d "$STAGE/extracted/$package" 2>&1)" || extract_rc=$?
  if (( extract_rc != 0 )); then
    if (( extract_rc == 1 )) &&
       [[ "$extract_log" == warning:*" appears to use backslashes as path separators" ]] &&
       [[ "$extract_log" != *$'\n'* ]]; then
      echo "[Dysvegr] ZIP separator warning accepted: $package"
    else
      echo "Extraction failed for $package (exit $extract_rc): $extract_log" >&2
      exit 1
    fi
  fi
  if ! find "$STAGE/extracted/$package" -type f -print -quit | grep -q .; then
    echo "Archive extracted no files: $package" >&2; exit 1
  fi
  count=$((count + 1))
done < "$MANIFEST"
echo "[Dysvegr] Validated $count package ZIPs"

if [[ "$WAS_RUNNING" == true ]]; then
  echo '[Dysvegr] Stopping Valheim for backup and installation'
  docker stop -t 120 "$CONTAINER"
  STOPPED=1
fi

BACKUP_DIR="$(dirname "$GAME_DIR")/Dysvegr-modpack-backups"
mkdir -p "$BACKUP_DIR"
# Protect active world data whenever changing gameplay-affecting mods.
# This runs only after Valheim has stopped, avoiding a torn world snapshot.
WORLD_ROOT="$GAME_DIR/.config/unity3d/IronGate/Valheim/worlds_local"
if [[ ! -d "$WORLD_ROOT" ]]; then
  WORLD_ROOT="$(dirname "$GAME_DIR")/.config/unity3d/IronGate/Valheim/worlds_local"
fi
if [[ -d "$WORLD_ROOT" ]]; then
  WORLD_BACKUP="$BACKUP_DIR/worlds_local-before-mod-update-$(date -u +%Y%m%dT%H%M%SZ).tar.gz"
  echo "[Dysvegr] Backing up world saves to $WORLD_BACKUP"
  tar -czf "$WORLD_BACKUP" -C "$WORLD_ROOT" .
  tar -tzf "$WORLD_BACKUP" >/dev/null || {
    echo "World backup validation failed; refusing to change mods!" >&2
    exit 1
  }
  echo '[Dysvegr] World backup verified'
else
  echo '[Dysvegr] WARNING: worlds_local not found at the usual ich777 path; mod files will still be backed up.'
fi
BACKUP="$BACKUP_DIR/Valheim-BepInEx-before-Dysvegr-$(date -u +%Y%m%dT%H%M%SZ).tar.gz"
tar -czf "$BACKUP" -C "$GAME_DIR" BepInEx
echo "[Dysvegr] BepInEx backup saved at $BACKUP"

DEST_PLUGINS="$GAME_DIR/BepInEx/plugins"
DEST_PATCHERS="$GAME_DIR/BepInEx/patchers"
DEST_CONFIG="$GAME_DIR/BepInEx/config"
mkdir -p "$DEST_PLUGINS" "$DEST_PATCHERS" "$DEST_CONFIG"

while IFS=$'\t' read -r package version mode; do
  [[ -z "$package" || "$package" == \#* ]] && continue
  [[ "$mode" == framework ]] && continue
  [[ "$mode" == client && $INSTALL_CLIENT -eq 0 ]] && continue
  folder="$STAGE/extracted/$package"
  if [[ -d "$folder/BepInEx/plugins" ]]; then
    cp -a "$folder/BepInEx/plugins/." "$DEST_PLUGINS/"
  elif [[ -d "$folder/plugins" ]]; then
    cp -a "$folder/plugins/." "$DEST_PLUGINS/"
  else
    target="$DEST_PLUGINS/$package"
    mkdir -p "$target"
    # Many Thunderstore packages (including BetterArchery) store their DLL
    # inside a nested directory rather than at the ZIP root. Preserve those
    # directories; BepInEx recursively scans plugins for DLLs.
    find "$folder" -mindepth 1 -maxdepth 1 \
      ! -name manifest.json ! -name icon.png \
      ! -iname 'readme*' ! -iname 'changelog*' ! -iname 'license*' \
      -exec cp -a -t "$target" {} +
    if ! find "$target" -type f \( -iname '*.dll' -o -iname '*.so' \) -print -quit | grep -q .; then
      echo "[Dysvegr] WARNING: no plugin binary detected anywhere in $package" >&2
    fi
  fi
  if [[ -d "$folder/BepInEx/patchers" ]]; then
    cp -a "$folder/BepInEx/patchers/." "$DEST_PATCHERS/"
  fi
  if [[ -d "$folder/BepInEx/config" ]]; then
    cp -an "$folder/BepInEx/config/." "$DEST_CONFIG/"
  fi
  if [[ -d "$folder/config" ]]; then
    cp -an "$folder/config/." "$DEST_CONFIG/"
  fi
  echo "[Dysvegr] Installed $package $version"
done < "$MANIFEST"

# Optional exported settings from the ChatGPT downloadable bundle.
if [[ -f "$ROOT/server-configs.zip" ]]; then
  mkdir -p "$STAGE/config"
  unzip -tqq "$ROOT/server-configs.zip" >/dev/null
  unzip -qq "$ROOT/server-configs.zip" -d "$STAGE/config"
  while IFS= read -r -d '' src; do
    rel="${src#"$STAGE/config/"}"
    target="$DEST_CONFIG/$rel"
    mkdir -p "$(dirname "$target")"
    [[ -e "$target" ]] || cp -a "$src" "$target"
  done < <(find "$STAGE/config" -type f -print0)
  echo '[Dysvegr] Added missing exported config files'
fi

if [[ $WITH_WORLD -eq 1 ]]; then
  mkdir -p "$STAGE/world"
  unzip -tqq "$ROOT/world-Dysvegr.zip" >/dev/null
  unzip -qq "$ROOT/world-Dysvegr.zip" -d "$STAGE/world"
  [[ -f "$STAGE/world/Dysvegr/_main.62.ok" &&
     -f "$STAGE/world/Dysvegr/_main.62.db2" &&
     -f "$STAGE/world/Dysvegr/_main.62.fwl2" ]] ||
    { echo 'World archive missing expected files. Nothing imported.' >&2; exit 1; }
  [[ ! -e "$WORLD_ROOT/Dysvegr" ]] ||
    { echo 'Dysvegr world appeared during install; refusing to overwrite.' >&2; exit 1; }
  cp -a "$STAGE/world/Dysvegr" "$WORLD_ROOT/Dysvegr"
  echo "[Dysvegr] World imported to $WORLD_ROOT/Dysvegr"
fi

UID_DOCKER="$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$CONTAINER" |
  grep '^UID=' | tail -1 | cut -d= -f2 || true)"
GID_DOCKER="$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$CONTAINER" |
  grep '^GID=' | tail -1 | cut -d= -f2 || true)"
if [[ "${UID_DOCKER:-}" =~ ^[0-9]+$ && "${GID_DOCKER:-}" =~ ^[0-9]+$ ]]; then
  chown -R "$UID_DOCKER:$GID_DOCKER" "$DEST_PLUGINS" "$DEST_PATCHERS" "$DEST_CONFIG"
  if [[ $WITH_WORLD -eq 1 ]]; then chown -R "$UID_DOCKER:$GID_DOCKER" "$WORLD_ROOT/Dysvegr"; fi
fi

echo "[Dysvegr] SUCCESS: installed $count package archives; backup: $BACKUP"
if [[ $WITH_WORLD -eq 1 ]]; then
  echo 'Set World Name = Dysvegr in your Unraid Docker template if it is not already set.'
fi
if [[ "$WAS_RUNNING" == true ]]; then
  echo '[Dysvegr] Container will restart; inspect docker logs for plugin errors.'
fi
