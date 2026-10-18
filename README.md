# Dysvegr Valheim Modpack

Version-pinned Thunderstore modpack for an **ich777 Valheim Docker server on Unraid**, assembled from the uploaded Thunderstore/r2modman profile.

- 42 enabled packages in the source profile
- 30 server-selected packages; 11 client-side/held-back packages; BepInEx framework provided by ich777
- Package versions in [mods.tsv](mods.tsv)
- The script **downloads mod ZIPs directly from Thunderstore**; it doesn't redistribute mod DLLs.

## Server setup

1. In the Unraid Docker template for the ich777 **Valheim** container, set **Enable BepInEx** to enabled, apply the change, and start the container once.
2. From the **Unraid terminal**, clone this private GitHub repo (authenticate with GitHub username and a **personal access token** when Git requests a password; GitHub account passwords don't work):

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

The original Thunderstore profile includes \`cybrp-ItemDrawers-1.2.6\`, but on this dedicated server BepInEx produced over 16,000 \`TypeLoadException: VTable setup of type kg_ItemDrawers.DrawerComponent failed\` errors shortly after the first scene started. Only one ItemDrawers DLL was detected. Thunderstore categorizes the package as *client-side*, but also documents dedicated-server synchronization, so compatibility remains uncertain.

The package remains in the original client profile and is now skipped by default in \`mods.tsv\`. **Updating Git does not remove files previously installed on the server.** To reversibly quarantine only the existing server copy:

\`\`\`bash
docker stop -t 120 Valheim
GAME=/mnt/cache/appdata/valheim
mkdir -p "$GAME/Dysvegr-disabled-plugins"
mv "$GAME/BepInEx/plugins/cybrp-ItemDrawers" "$GAME/Dysvegr-disabled-plugins/"
docker start Valheim
\`\`\`

Adjust \`GAME\` if your ich777 bind mount differs (the installer prints the real source). Do **not** use a live world containing placed ItemDrawers after disabling the plugin until you've made and verified a world backup; removing modded pieces can lead to missing objects or inaccessible stored items. Moving the folder is reversible; no DLL or config is deleted. The next \`--mods-only\` install will not put ItemDrawers back on the server.

## Updates

```bash
cd /mnt/user/appdata/Dysvegr-Valheim-Modpack && git pull --ff-only && bash install-unraid.sh --mods-only
```

> **Important:** Before installing, back up your active world in addition to the automatic BepInEx backup. Restart the container and check `docker logs --tail 200 Valheim` after installation. Mods have not yet been tested together on this specific server. Server/client classifications are best-effort.

## Files and exclusions

- `install-unraid.sh`: shell installer that detects the ich777 bind mount, validates Thunderstore ZIPs, makes a BepInEx backup, installs server-classified mods, and restarts the container.
- `mods.tsv`: exact Thunderstore author, package, version, server/client/framework selection.
- `mods.json`: readable metadata for the complete profile.

**Your Dysvegr world save and original configuration ZIP aren't stored in GitHub.** They remain in the downloadable package shared in ChatGPT, preventing accidental save disclosure. The GitHub installer works without them, but it won't transfer your custom world or personalized mod settings. You can copy `server-configs.zip` into this checkout (optional) or import the separate world archive manually. World import requires `world-Dysvegr.zip` next to the script and an explicit `--with-world` flag.

Do not commit secrets, passwords, or world backups to a public repository. The `--all-mods` option is experimental and may load client-only plugins on the dedicated server.

Original Thunderstore shared-profile code: `01a14dde-0dfa-8017-121b-4e1dd5230946`.
