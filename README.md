# Dysvegr Valheim Modpack

Version-pinned Thunderstore modpack for an **ich777 Valheim Docker server on Unraid**, assembled from the uploaded Thunderstore/r2modman profile.

- 44 enabled packages in the uploaded Thunderstore export; **43** in the conflict-resolved modpack
- 31 server-selected packages; 11 client-side packages; BepInEx framework provided by ich777
- Package versions in [mods.tsv](mods.tsv)
- The script **downloads mod ZIPs directly from Thunderstore**; it doesn't redistribute mod DLLs.

## October 18, 2026 modpack update

Rebuilt the pinned manifest and client profile from `Mods_1792350318316.r2z`, which contains **44 enabled packages**. The compatible distribution has **43** because VikingQoL replaces MultiUserChest:

- Added `VegettaPT-No_Food_Degradation-1.0.0` to server.
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

## VikingQoL / MultiUserChest compatibility fix (October 18)

The server log reported:

`[Error : VikingQoL] com.maxsch.valheim.MultiUserChest is installed and conflicts with VikingQoL: remove one of them (from the server and every player).`

**Resolution:** Keep VikingQoL 1.4.0 and remove MultiUserChest, which VikingQoL supersedes with shared-chest support. The repo's server and client manifests now omit MultiUserChest. After a successful BepInEx backup, `install-unraid.sh` quarantines the previous `BepInEx/plugins/MSchmoecker-MultiUserChest` directory outside the BepInEx tree. It does not delete the mod or your world data.

```bash
cd /mnt/user/appdata/Dysvegr-Valheim-Modpack && git pull --ff-only && bash install-unraid.sh --mods-only
```

Each player must update their Thunderstore/r2modman profile and **disable or uninstall MultiUserChest** before joining. VikingQoL 1.4.0 must be present on the server and all clients. The original uploaded `.r2z` is unchanged; `client-profile.yml` in GitHub reflects the corrected 43-package profile.

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
