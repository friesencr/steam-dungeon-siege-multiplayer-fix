# Dungeon Siege 1 multiplayer fix

These scripts apply the fixes used to get the Steam version of **Dungeon Siege 1** hosting multiplayer on Linux, plus a Windows version of the same configuration fixes. Both default to **1920 × 1080 widescreen** and create backups before changing files.

Share this README and the two scripts. Each player runs the script for their own operating system.

| Platform | File | Requirements |
| --- | --- | --- |
| Linux / Steam Deck | [fix-dungeon-siege.sh](fix-dungeon-siege.sh) | Steam, Proton, Python 3, and Protontricks |
| Windows 10 / 11 | [fix-dungeon-siege.bat](fix-dungeon-siege.bat) | Windows PowerShell and administrator access |

## What the patches do

- Set `zonematch = true` to open directly in the multiplayer menu.
- Set `dpnsvr = false` to apply the hosting workaround.
- Install native Microsoft DirectPlay into the game's Proton prefix on Linux, or enable the Windows DirectPlay feature on Windows.
- Set `width = 1920` and `height = 1080`, and add that resolution to `system_detail.gas`. Use the multiplayer-only option to keep your existing resolution.

The configuration workarounds are documented in the [Dungeon Siege troubleshooting guide](https://github.com/GenesisFR/DS1TroubleshootingGuide#play-mp). The original ZoneMatch service is offline; use **Network** or **Internet** to play together.

## Apply the Linux / Steam Deck patch

1. Install Dungeon Siege in Steam. Select a Proton compatibility tool in **Properties → Compatibility** if needed.
2. Launch the game once, then close it. Keep Steam open.
3. Install [Protontricks](https://github.com/Matoking/protontricks#installation). On Steam Deck, switch to Desktop Mode and install Protontricks from Discover. On other Linux systems, use your package manager or its Flatpak version.
4. Open a terminal in the folder containing the downloaded script and run:

```bash
bash fix-dungeon-siege.sh
```

Run this script as your normal user. It locates the Steam installation and game library, backs up the Proton prefix, and installs DirectPlay through Protontricks. The download can take a few minutes.

For multiplayer only:

```bash
bash fix-dungeon-siege.sh --no-widescreen
```

To preview the changes or use a different resolution:

```bash
bash fix-dungeon-siege.sh --dry-run
bash fix-dungeon-siege.sh --resolution 1280x720
```

The script accepts resolutions up to 1920 × 1080. Higher resolutions need additional fixes. For a custom Steam location, point to the Steam root, which contains `steamapps/libraryfolders.vdf`:

```bash
bash fix-dungeon-siege.sh --steam-dir "/path/to/Steam"
```

If Flatpak Protontricks cannot access a game on another drive, grant access to that specific library folder and rerun the patch. See the [Protontricks Flatpak instructions](https://github.com/Matoking/protontricks#flatpak-recommended).

```bash
flatpak override --user --filesystem="/path/to/SteamLibrary" com.github.Matoking.protontricks
```

## Apply the Windows patch

1. Install Dungeon Siege and launch it once, then close it.
2. Right-click `fix-dungeon-siege.bat` and select **Run as administrator**.
3. The script finds the Steam game and the user configuration. If it cannot find them, it asks for their paths. Select the configuration under your own **Documents\Dungeon Siege** folder, including a redirected or OneDrive Documents folder if applicable.
4. Wait for DirectPlay to finish enabling. Restart Windows if the script requests it, then launch the game from Steam.

Administrator access is needed for Windows' DirectPlay feature and files under Program Files. If you supply a different administrator account's credentials, check that the displayed user configuration belongs to the player.

For multiplayer only, open an **administrator PowerShell** window in the script folder and run:

```powershell
.\fix-dungeon-siege.bat --no-widescreen
```

To preview without administrator access:

```powershell
.\fix-dungeon-siege.bat --dry-run
```

The batch file accepts one option per run. Use `--help` for its built-in instructions. Windows PowerShell is already included in Windows 10/11; Protontricks is only needed on Linux.

## Host or join a game

After applying the patch, Dungeon Siege opens at the multiplayer menu.

1. The host selects **Network → Host Game**.
2. Other players select **Network**, find the session, and join.
3. Everyone selects or creates a character and marks themselves ready. The host starts the game.

For direct IP connections, the host selects **Internet → Host Game**. Other players select **Internet**, enter the host's reachable IP address, and connect. Over a virtual network, use the host's address assigned by that network tool. These connection modes are described in the [official game manual](https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/39190/manuals/DSMANUAL.PDF?t=1709630517).

## Play LAN games over the internet

For a group mixing Linux and Windows, **ZeroTier is the recommended starting point**. Its virtual Ethernet network supports the broadcast traffic used for LAN discovery. [Protocol details](https://docs.zerotier.com/protocol/)

| Tool | Download / instructions | When to use it |
| --- | --- | --- |
| ZeroTier | [Download](https://www.zerotier.com/download/) · [Setup guide](https://docs.zerotier.com/quickstart/) | Windows and Linux players; older games with LAN discovery |
| Radmin VPN | [Download](https://www.radmin-vpn.com/) · [Help](https://www.radmin-vpn.com/help/index.html) | Free virtual LAN gaming for a Windows-only group |
| Tailscale | [Download](https://tailscale.com/download) · [Gaming overview](https://tailscale.com/blog/hamachi) | Mesh networking with direct IP connections; general multicast discovery is [not supported](https://github.com/tailscale/tailscale/issues/11134) |

### Connect with ZeroTier

1. Everyone installs ZeroTier.
2. One person creates a private network in [ZeroTier Central](https://central.zerotier.com/) and shares its network ID.
3. Each player joins that network. On Windows, use the ZeroTier tray menu. On Linux, use `sudo zerotier-cli join NETWORK_ID`, replacing `NETWORK_ID` with the shared ID.
4. The network owner authorizes each player's device in Central.
5. Confirm each device is connected and has an assigned IPv4 address. Use the assigned IP, not the network ID or the device's node ID, to connect to a host.
6. Try Dungeon Siege's **Network** mode. If discovery does not find the session, have the host create an **Internet** game and have the others connect to the host's ZeroTier IPv4 address.

See the [official setup guide](https://docs.zerotier.com/start/) for joining and authorizing devices. Network-tool installation and account setup are separate from the game patch scripts.

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| Multiplayer button still says disabled | Restart the game after patching. The script opens the multiplayer menu directly; choose Network or Internet there. |
| Hosting returns to the menu | Confirm the script completed DirectPlay setup. On Windows, finish any requested restart. On Linux, inspect Protontricks' output for installation failures. |
| Script cannot find the game or configuration | Launch the game once first. On Linux, use `--steam-dir` for a custom installation. On Windows, supply the paths when prompted. |
| Friends cannot see or connect to the game | Check that every device joined and was authorized on the same virtual network. Try direct IP. Allow Dungeon Siege through the host's firewall on the relevant network. See [ZeroTier firewall guidance](https://docs.zerotier.com/routertips/). |
| Joining reports incompatible versions | Use matching game versions, languages, expansions, and resource mods. See the [version mismatch guide](https://github.com/GenesisFR/DS1TroubleshootingGuide#incompatible-version). |
| Interface looks small at 1080p | Restore the previous configuration, or use a lower resolution with the Linux script. `--no-widescreen` keeps the current resolution; it does not undo an earlier 1080p change. |

Avoid changing resolution through the in-game menu after setting a custom resolution; it lists the original sizes. Steam file verification may restore `system_detail.gas`, so rerun the patch afterward if needed.

## Backups and undo

Both scripts print the backup location when they run. Close the game before restoring files.

**Windows:** Backups are under the selected user configuration folder, normally `Documents\Dungeon Siege\dsfix-backups\<timestamp>`. Open `restore-locations.txt` and copy each `config-*` backup to its listed original path and filename. The file also records DirectPlay's original feature state; restoring the configuration files leaves DirectPlay enabled.

**Linux:** Backups are under `steamapps/compatdata/39190/dsfix-backups/<timestamp>` beside the game's `pfx` folder. `locations.json` identifies the original paths for the `config-*` files. Copy those files back to restore only the configuration.

To undo the Linux DirectPlay installation too, close Steam, move the current `pfx` folder aside, and copy the backup's `pfx` folder into its original location. The prefix backup contains saves as they were when the patch ran. Preserve any newer saves before restoring it; keeping the current prefix in a separate folder lets you recover them.

## Verification

The Linux multiplayer and 1080p changes were confirmed working on the installation these scripts were created for. Script checks covered discovery, backups, repeated runs, and configuration preservation. The Windows script's configuration and mocked feature-enable flow were tested with PowerShell; actual Windows DirectPlay activation has not been tested here.

## Reference

[GenesisFR's Dungeon Siege 1 Troubleshooting Guide — Play MP](https://github.com/GenesisFR/DS1TroubleshootingGuide#play-mp) documents the multiplayer startup setting used by these scripts and links to related troubleshooting advice.
