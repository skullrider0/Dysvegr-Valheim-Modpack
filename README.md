## Unraid cache disk checker and cleanup

The optional [disk-cleanup-unraid.sh](./disk-cleanup-unraid.sh) script checks space on the cache pool, reports large directories and offers two *explicit* cleanup operations. **Dry-run preview is the default**; the script does not install a scheduled destructive task.

```bash
cd /mnt/user/appdata/Dysvegr-Valheim-Modpack
git pull --ff-only
bash -n disk-cleanup-unraid.sh
bash disk-cleanup-unraid.sh
```

The preview lists older *date-stamped* backup sets from clearly named backup folders directly under `/mnt/cache/appdata` and `/mnt/cache/backup(s)`. It preserves the latest item **in each backup naming family**, never just one backup across all services. Files with ambiguous or undated names are not automatically deleted. It also lists unmounted appdata directories which *could* belong to removed containers. Docker's current **and stopped** container bind mounts are protected, and saved Docker templates protect additional directories unless an extra override is requested. Active Docker data, `/mnt/cache/system`, named Docker volumes, and the existing Dysvegr world are excluded.

**After reviewing the paths:**

```bash
bash disk-cleanup-unraid.sh --apply
```

This prompts before deleting old dated backups. For both old dated backups **and orphan candidates**, use:

```bash
bash disk-cleanup-unraid.sh --apply --purge-orphans
```

This requires typing `DELETE BACKUPS AND ORPHANS` interactively and irreversibly deletes the listed unmounted appdata folders. Those might contain valuable old game worlds, so ideally archive or move them to your array instead of deleting. Use `--include-template-orphans` only when you have confirmed saved Docker templates are no longer needed. The script does **not** shrink or delete Docker's image file or automatically clean the `system` share. Inspect `docker system df -v` separately for Docker image usage. There is no parity disk in the current Unraid setup; ensure you have independent backups.

# Dysvegr Valheim Modpack

Version-pinned Thunderstore modpack for an **ich777 Valheim Docker server on Unraid**, assembled from the uploaded Thunderstore/r2modman profile.

- 44 enabled packages in the uploaded Thunderstore export; **43** in the conflict-resolved modpack
- 30 server-selected packages; 12 client-side packages; BepInEx framework provided by ich777
- Package versions in [mods.tsv](mods.tsv)
- The script **downloads mod ZIPs directly from Thunderstore**; it doesn't redistribute mod DLLs.

## October 18, 2026 modpack update

Rebuilt the pinned manifest and client profile from `Mods_1792350318316.r2z`, which contains **44 enabled packages**. The compatible distribution has **43** because VikingQoL replaces MultiUserChest:

- Added `VegettaPT-No_Food_Degradation-1.0.0` to the client profile only (BepInEx filters out dedicated-server processes).
- Added `FF15Vikings-VikingQoL-1.4.0` to server (**server and all players must run the same version**).
- Removed `MSchmoecker-MultiUserChest-0.6.2` from both server and client manifests because VikingQoL refuses to coexist with it. The installer moves any installed server copy to `Dysvegr-disabled-plugins/` **after backup**. Every player must also remove or disable MultiUserChest locally.
- Added `Landoria-FirstPerson-1.0.16` to the client profile only.
- Upgraded `Vapok-AdventureBackpacks` from 2.4.4 to 2.4.5.
- Removed `cybrp-ItemDrawers-1.2.6` from both profiles; its prior quarantined server copy stays untouched.

VikingQoL defaults to larger item stacks and provides storage and crafting utilities that may overlap other enabled mods. Back up world saves and player characters before updating. The installer now backs up the world saves (where discoverable) after stopping the server, in addition to BepInEx. The user's exported `.r2z` configs are **not** automatically applied; newly installed mods will generate default configs on initial launch. Review `BepInEx/config/ff15vikings.vikingqol.cfg` on the server after first launch. Mod compatibility is not guaranteed.

**To update the server:**

```bash
cd /mnt/user/appdata/Dysvegr-Valheim-Modpack && git pull --ff-only && bash install-unraid.sh --mods-only
```

## Post-update server log verification

Latest startup logs confirm VikingQoL 1.4.0 loads successfully as a dedicated-server plugin, with no remaining MultiUserChest conflict. BepInEx skips **No Food Degradation 1.0.0** due to its `valheim.exe` executable filter. It is now client-only in `mods.tsv`; an already-installed copy on the server may still be present but is skipped automatically. Duplicate language-key warnings in Therzie's Warfare, Armory, Monstrum and Wizardry translations are not themselves fatal errors. Investigate game-world loading separately if no `ZNet.LoadWorld` or `Opened Steam server` line appears in the current log.

## VikingQoL / MultiUserChest compatibility fix (October 18)

The server log reported:

`[Error : VikingQoL] com.maxsch.valheim.MultiUserChest is installed and conflicts with VikingQoL: remove one of them (from the server and every player).`

**Resolution:** Keep VikingQoL 1.4.0 and remove MultiUserChest, which VikingQoL supersedes with shared-chest support. The repo's server and client manifests now omit MultiUserChest. After a successful BepInEx backup, `install-unraid.sh` quarantines the previous `BepInEx/plugins/MSchmoecker-MultiUserChest` directory outside the BepInEx tree. It does not delete the mod or your world data.

```bash
cd /mnt/user/appdata/Dysvegr-Valheim-Modpack && git pull --ff-only && bash install-unraid.sh --mods-only
```

Each player must update their Thunderstore/r2modman profile and **disable or uninstall MultiUserChest** before joining. VikingQoL 1.4.0 must be present on the server and all clients. The original uploaded `.r2z` is unchanged; `client-profile.yml` in GitHub reflects the corrected 43-package profile.

## Automatic Thunderstore version checks and manual updates

The modpack includes a **read-only checker**. It uses Thunderstore's package metadata API to compare new releases with the versions selected for Dysvegr. The check never stops Valheim, edits plugin files, or silently installs updates. The launcher supports host Python3 and, if missing, Docker's temporary `python:3.12-alpine` image.

**Check now (server and client packages):**

```bash
cd /mnt/user/appdata/Dysvegr-Valheim-Modpack
git pull --ff-only
bash update-mods.sh check
```

**Set up daily checks:** (Requires Unraid's **User Scripts** plugin.)

```bash
bash /mnt/user/appdata/Dysvegr-Valheim-Modpack/setup-daily-check.sh
```

Then go to **Unraid Settings → User Scripts → DysvegrModUpdateCheck**, set **Schedule: Daily** and click **Apply**. The plugin retains the script on the Unraid flash drive across reboots. Only checks run daily; you decide when to restart the server.

Read the latest report:

```bash
cat /mnt/user/appdata/Dysvegr-Valheim-Modpack/.dysvegr-updates/latest-report.txt
```

**Apply newer versions on demand:**

```bash
cd /mnt/user/appdata/Dysvegr-Valheim-Modpack
git pull --ff-only
bash update-mods.sh update
```

The command performs a fresh check of server mods only, validates new dependencies, shows exact proposed versions and asks you to type `UPDATE`. Upon confirmation, the installer downloads every selected package and validates ZIPs, stops the container, backs up BepInEx and any accessible worlds, quarantines old package directories, installs, and restarts Valheim. Successful approved versions are stored in untracked `mods.local.tsv`, avoiding Git conflicts/downgrades. The GitHub `mods.tsv` remains the curated default. Use `bash update-mods.sh update --yes` **only** if you understand the downtime, backup and mod compatibility risk.

**Always update joining players' matching multiplayer mods** using Thunderstore/r2modman before reconnecting. The script cannot automatically update players' game installations or guarantee new versions are compatible. No Food Degradation and FirstPerson are client-only; ich777 manages BepInEx itself. The checker refuses a failed/incomplete API lookup or unknown new dependency instead of installing an uncertain update.

A report can be checked anytime even if the User Scripts scheduling option has not been enabled.

## Server setup

1. In the Unraid Docker template for the ich777 **Valheim** container, set **Enable BepInEx** to enabled, apply the change, and start the container once.
2. From the **Unraid terminal**, clone the public GitHub repository:

   ```bash
   git clone https://github.com/skullrider0/Dysvegr-Valheim-Modpack.git /mnt/user/appdata/Dysvegr-Valheim-Modpack
   ```

3. Preview and install:

   ```bash
   bash /mnt/user/appdata/Dysvegr-Valheim-Modpack/install-unraid.sh --dry-run
   bash /mnt/user/appdata/Dysvegr-Valheim-Modpack/install-unraid.sh --mods-only
   ```

   If your Docker container is not named `Valheim`, run with e.g. `CONTAINER=MyValheim bash ...`.


## ItemDrawers compatibility warning (Valheim 1.0)

The earlier Thunderstore profile included `cybrp-ItemDrawers-1.2.6` (removed in the newest export), but on this dedicated server BepInEx produced over 16,000 `TypeLoadException: VTable setup of type kg_ItemDrawers.DrawerComponent failed` errors shortly after the first scene started. Only one ItemDrawers DLL was detected. Thunderstore categorizes the package as *client-side*, but also documents dedicated-server synchronization, so compatibility remains uncertain.

The package is absent from the new client profile and server manifest; it remains disabled on the server.  **Updating Git does not remove files previously installed on the server.** To reversibly quarantine only the existing server copy:

```bash
docker stop -t 120 Valheim
GAME=/mnt/cache/appdata/valheim
mkdir -p "$GAME/Dysvegr-disabled-plugins"
mv "$GAME/BepInEx/plugins/cybrp-ItemDrawers" "$GAME/Dysvegr-disabled-plugins/"
docker start Valheim
```

Adjust `GAME` if your ich777 bind mount differs (the installer prints the real source). Do **not** use a live world containing placed ItemDrawers after disabling the plugin until you've made and verified a world backup; removing modded pieces can lead to missing objects or inaccessible stored items. Moving the folder is reversible; no DLL or config is deleted. The next `--mods-only` install will not put ItemDrawers back on the server.

## Import the exact Dysvegr world from the uploaded RAR

The original **Dysvegr.rar** uploaded in ChatGPT has been repacked without changing its save files as `world-Dysvegr.zip` (26 files, Valheim 1.0 format: `_main.62.db2`, `.fwl2`, `.chunks`, `.ok`, and terrain chunks). The binary ZIP is **not on public GitHub**.

1. Download **world-Dysvegr.zip** from the ChatGPT conversation and upload it into the Unraid appdata share as `/mnt/user/appdata/world-Dysvegr.zip` (Unraid File Manager or SMB).
2. Update this checkout and preview the import:

   ```bash
   cd /mnt/user/appdata/Dysvegr-Valheim-Modpack
   git pull --ff-only
   bash import-dysvegr-world.sh --check /mnt/user/appdata/world-Dysvegr.zip
   ```

3. Import the original save **without reinstalling mods**:

   ```bash
   bash import-dysvegr-world.sh /mnt/user/appdata/world-Dysvegr.zip
   ```

The world importer checks the ZIP and Valheim world's location, stages the new world, stops Valheim, backs up **all** worlds, moves any previous `Dysvegr` world to a timestamped backup, activates the uploaded world folder, sets permissions, and restarts Valheim if it was running. It does **not delete** the previous world. Check that the Docker template's **World Name** is `Dysvegr`.

**Warning:** If the source world contains placed ItemDrawers, running it with ItemDrawers disabled could hide/break drawers or their contents. Keep the complete world backup and avoid playing/saving if those objects matter until the compatibility issue is resolved.

## Updates

```bash
cd /mnt/user/appdata/Dysvegr-Valheim-Modpack && git pull --ff-only && bash install-unraid.sh --mods-only
```

> **Important:** Before installing, back up your active world in addition to the automatic BepInEx backup. Restart the container and check `docker logs --tail 200 Valheim` after installation. Mods have not yet been tested together on this specific server. Server/client classifications are best-effort.

## Files and exclusions

- `install-unraid.sh`: shell installer that detects the ich777 bind mount, validates Thunderstore ZIPs, makes a BepInEx backup, installs server-classified mods, and restarts the container.
- `mods.tsv`: exact Thunderstore author, package, version, server/client/framework selection.
- `mods.json`: readable metadata for the complete profile.

**Your Dysvegr world save and original configuration ZIP aren't stored in GitHub.** They remain in the downloadable package shared in ChatGPT, preventing accidental save disclosure. The GitHub installer works without them, but it won't transfer your custom world or personalized mod settings. You can copy `server-configs.zip` into this checkout if needed. For the original world use the dedicated **`import-dysvegr-world.sh`** procedure above; it safely handles a pre-existing Dysvegr world.

Do not commit secrets, passwords, or world backups to a public repository. The `--all-mods` option is experimental and may load client-only plugins on the dedicated server.

Original Thunderstore shared-profile code: `01a14dde-0dfa-8017-121b-4e1dd5230946`.
