# Commodore VIC-20 for the Analogue Pocket

An openFPGA core for the Analogue Pocket, ported from [VIC20_MiSTer](https://github.com/MiSTer-devel/VIC20_MiSTer)
(MikeJ and WoS's VIC-20, MiSTer port by Sorgelig). The machine is used unmodified, as a git submodule; this
repository adds the Pocket board layer, built on the one from [openfpga-C64](https://github.com/defgenx/openfpga-C64).

**Status: pre-release (v0.1.0), not yet tested on hardware.** Builds at 60% of the FPGA, timing met. Reports are welcome in the issues.

## Features

* VIC-20 PAL (6561) and NTSC (6560), with their own KERNALs
* RAM expansions: Auto (chosen from a program's load address), unexpanded, +3K, +8K, +16K, +24K, +35K
* Programs (`.prg`), cartridges (`.crt`, `.prg`, headerless `.a0`), Megacart images
* 1541 drive 8 with `.d64` / `.g64` (writable, saved back to the SD card), 1581 with `.d81`
* Tapes (`.tap`), with play/pause and tape sound
* Autostart: `RUN` for programs, `LOAD"*",8,1` + `RUN` for disks, Shift + Run/Stop for tapes
* On-screen keyboard (Select), pad as joystick or as keys (Start), Dock USB keyboard
* Paddles from the analog sticks of Dock controllers
* Loadable System ROM (JiffyDOS)

Install: [INSTALL.md](INSTALL.md). How it is built: [docs/architecture.md](docs/architecture.md).

## Not ported

A second drive, external IEC / SNAC (no user port on the Pocket), Megacart NVRAM saving (it is kept while
the core runs), the scandoubler and HDMI scaler options (the Pocket's own scaler does that), screen
centering options.

## Building

`./build.sh` compiles with Quartus Lite 21.1 (native, or the `raetro/quartus:21.1` Docker image) and packages
`defgenx.VIC20.zip`. `make -C sim` runs the test benches (Icarus Verilog, nvc).

## License

GPL-2.0, as openfpga-C64 and the MiSTer cores. See [LICENSE](LICENSE). The VIC-20 and 1541 ROM images come with VIC20_MiSTer.
