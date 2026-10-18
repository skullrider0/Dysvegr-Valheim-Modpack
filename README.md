# Dysvegr Valheim Modpack

Version-pinned Thunderstore modpack for an **ich777 Valheim Docker server on Unraid**, assembled from the uploaded Thunderstore/r2modman profile.

- 42 enabled packages in the source profile
- 31 server-selected packages; 10 client-only candidates; BepInEx framework provided by ich777
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
