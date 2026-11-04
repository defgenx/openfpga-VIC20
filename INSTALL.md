# Installing the Commodore VIC-20 core on the Analogue Pocket

## 1. Copy the core to the microSD card

**The easy way:** put the microSD card in your computer and run the installer, from a clone of the repo
or on its own after downloading it from the release page:

| System        | Run                                                                 |
|---------------|---------------------------------------------------------------------|
| Windows       | double-click **`install.bat`** (or `.\install.ps1` in PowerShell)  |
| macOS / Linux | `./install.sh`                                                      |

It finds the Pocket SD card, asks you to confirm, copies the core and this guide, and offers to eject the
card. Options: `--dry-run` / `-DryRun` shows what would be copied and changes nothing;
`--sd /Volumes/POCKET` / `-SD E:\` names the card yourself.

**It never replaces a file without asking.** Identical files are skipped; for each one that differs it
asks `Replace it? [y]es / [N]o / [a]ll / [s]kip all` (Enter keeps the card's file). Without a built core
next to it, the installer downloads the newest release from GitHub.

**By hand:** copy the contents of `defgenx.VIC20.zip` (or the `release/` folder made by `./build.sh`) to
the **root** of the card, merging with the folders already there:

```
SD card root
├── Assets/
│   └── vic20/
│       └── common/              <- your .prg .crt .d64 .g64 .tap files go here
├── Cores/
│   └── defgenx.VIC20/
│       ├── vic20.rbf_r          <- the core bitstream
│       ├── core.json  data.json  input.json  interact.json  video.json ...
└── Platforms/
    ├── vic20.json
    └── _images/vic20.bin        <- the platform picture
```

## 2. ROMs (nothing to do)

BASIC, the PAL and NTSC KERNALs, the character ROM and the 1541 / 1581 ROMs are built into the core, as on
MiSTer. To use another set (JiffyDOS), make a `boot.rom` as for MiSTer — 1541 ROM (16 KB), PAL KERNAL
(8 KB), NTSC KERNAL (8 KB) — put it in `Assets/vic20/common/` and pick it in *System ROM*.

## 3. Add software

Copy files to `Assets/vic20/common/`, then load them from *Core Settings*:

| File                     | Slot          | Then                                                      |
|--------------------------|---------------|-----------------------------------------------------------|
| `.prg`                   | Program       | memory set from its load address, then `RUN` is typed     |
| `.crt` / `.prg` / `.a0`  | Cartridge     | the VIC-20 restarts into it                               |
| `.d64` / `.g64` / `.d81` | Disk          | `LOAD"*",8,1` and `RUN` are typed (autostart)             |
| `.rom` / `.crt`          | Megacart      | the Megacart menu starts                                  |
| `.tap`                   | Tape          | Shift + Run/Stop is typed and the tape plays (autostart)  |

* **Memory = Auto** (the default) reads a program's load address: `$1001` unexpanded, `$0401` +3K,
  `$1201` +24K, anything else all 35K. When that changes the memory map, the VIC-20 restarts first and the
  program goes in once BASIC is ready. Pick a fixed size when a game wants exactly that much.
* **Cartridges:** a file with a 2-byte load address (most `.crt` and `.prg` dumps) goes where it says. A
  file of exactly 2, 4, 8 or 16 KB has none and goes in at `$A000`. A cartridge made of several files
  (`-2000`, `-a000`): load each part, then *Reset* — the KERNAL starts the `$A000` part.
* Disks are **writable**: saves are written back to the file. Keep backups, or set *Write Protect* before
  inserting the disk.

## 4. Start it

On the Pocket: *openFPGA → VIC-20*. The BASIC screen appears in a second.

| Setting            | What it does                                                   |
|--------------------|----------------------------------------------------------------|
| Memory             | Auto, or a fixed RAM expansion (see above)                     |
| Video              | PAL (most European games) or NTSC (US games)                   |
| Autostart          | Type the commands for programs, disks and tapes               |
| Pad Mode           | Joystick (default) or Keys                                     |
| Paddles            | Analog sticks of Dock controllers 1 and 2 turn the paddles     |
| Cart RAM Writable  | For cartridge images that use RAM in their blocks              |
| Tape Sound         | Hear the tape while it loads                                   |
| Reset & Detach Cart| Restart without the cartridge                                  |

## Controls

**Start** switches the pad between **Joystick** (default) and **Keys**. A label shows the new mode.

| Button | Joystick | Keys | On-screen keyboard |
|---|---|---|---|
| D-pad | joystick | cursor keys | move cursor |
| A | fire (and paddle button) | Space | press key |
| B | Space | Return | close |
| X / Y | Return / F1 | F1 / F3 | – |
| L / R | Run/Stop / F7 | Run/Stop / F5 | – |
| **Select** | keyboard | keyboard | close |

On the on-screen keyboard CTRL, SHIFT and C= are sticky: press SHIFT, then the key. In the Dock a USB
keyboard works too (Esc = Run/Stop, Tab = C=).

## Troubleshooting

* **Stuck after changing a setting:** `./install.sh --reset-settings` (Windows: `install.bat
  -ResetSettings`), or delete `Settings/defgenx.VIC20/` on the card.
* **A program crashes or shows garbage:** it wants another memory size — set *Memory* by hand, then load it
  again.
* **`?DEVICE NOT PRESENT ERROR`:** no disk in drive 8 — pick one in *Disk*.
* **Wrong speed or picture off-screen:** the game is for the other video standard — change *Video*.
