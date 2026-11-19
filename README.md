# Dev Map Launcher for Aurora

<img src="logo.png" alt="Shmees logo" width="128">

An Aurora utility script that boots Call of Duty development and prototype builds on an Xbox 360 using only the controller. Pick a build, an executable and a level, and the console reboots into it. No PC is involved.

It does the job PC tools do with the Xbdm `magicboot` command, but from the console itself.

> **Status: working on the author's console.** Booting a devkit `.exe` and loading levels with `+devmap` are both confirmed on one console (details under "Tested on"). Other setups are untested. Use it offline, at your own risk.

## What it does

- Finds build folders on your drives (any folder with an `.xex` or `.exe` plus `.ff` level files or a `zone` folder).
- Lists the executables in a build and the levels found in its zone files.
- Boots the executable with `+devmap <level>`, with no level (main menu), or with startup commands you type.
- **Browse for any executable:** walk your drives with the controller and boot any `.xex` or `.exe`, with startup options you type. This is not limited to Call of Duty.
- Saves favorite build, executable and command combinations.
- Writes what it sent to `launcher.log` so failures can be diagnosed.

## Requirements

- An Xbox 360 that runs homebrew (RGH, JTAG, or a BadUpdate-style softmod).
- The Aurora dashboard.
- The **Xbdm.xex** plugin loaded through `launch.ini` (`[Plugins]` section). The script talks to Xbdm on port 730.
- For devkit `.exe` files: a loader that lets your console run them, such as the Hayzen plugin.
- Your own builds, in a folder such as `Hdd1:\Games\<build name>`. This project contains no game files.

## Install

1. Copy the `DevMapLauncher` folder to `Aurora\User\Scripts\Utility\` on the drive Aurora runs from.
2. Restart Aurora.

To remove it, delete that folder.

## Use

1. In Aurora press **Back > Scripts > Utility Scripts > Dev Map Launcher**.
2. Pick a build, then an executable, then a level or one of the options at the top of the list.
3. Choose **Boot**, or **Save favorite** to keep the combination.

For anything that is not a Call of Duty build, choose **Browse for any executable** on the first screen, open the folder, pick the file, then boot it with or without startup options.

If the console does not reboot into the build, a message appears and `launcher.log` in the script folder records the attempt.

## Settings

Two tables at the top of `Main.lua` can be edited:

- `BuildParents`: folders under each drive root that are searched for builds. Default: `Games`, `games\dev`, `Debuilds`.
- `XbdmDriveNames`: Aurora drive name to Xbdm drive name. `Hdd1` to `HDD` is confirmed. The USB entries are guesses; correct them if your builds are on USB.

## How it works

Aurora's script API has no socket functions and no way to launch a title with a command line. Its only network calls are HTTP requests.

The script asks Aurora to fetch a URL on the console's own Xbdm port, with a line break inside the URL followed by the command:

```
magicboot title="HDD:\Games\<build>\<exe>" directory="HDD:\Games\<build>" cmdline="+devmap <level>"
```

Xbdm reads its input line by line. It rejects the HTTP request line as an unknown command, then runs the `magicboot` line, which reboots the console into the build.

## Tested on

| Console | Setup | Result |
|---|---|---|
| Xbox 360 Slim, kernel 2.0.17559.0 | ABadAvatarUpdate + XeUnshackle, Aurora 0.7b (rev 1655), DashLaunch 3.21, Xbdm + JRPC2 + Hayzen plugins | Modern Warfare 2 Build 482: `1-iw4sp.exe` booted to the menu and straight into `char_museum` through `+devmap` |

Not yet confirmed: the Browse option and the wrong-executable warning (added in 0.2 and 0.3, untested on hardware), non-Call of Duty executables, builds stored on USB, RGH/JTAG consoles, other Aurora versions.

## Limitations

- Aurora scripts cannot appear as cover art tiles; the launcher is opened from the Scripts menu.
- Double quotes cannot be used in startup commands.
- Whether a devkit `.exe` runs at all depends on the game. Some expect things only a real development kit has and will crash or hang at boot.
- Whether a level loads depends on the build. Some executables ignore `+devmap` or need files the build does not include.

## Safety

- Keep the console off Xbox Live when running modified software. Leave `liveblock` on in `launch.ini`.
- The script changes nothing on the console except its own `favorites.txt` and `launcher.log`.

## Licence

MIT. See `LICENSE`. Written by Shmees.
