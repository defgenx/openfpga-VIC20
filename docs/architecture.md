# Architecture

This core is [VIC20_MiSTer](https://github.com/MiSTer-devel/VIC20_MiSTer) with a board layer for the
Analogue Pocket, taken from [openfpga-C64](https://github.com/defgenx/openfpga-C64). The machine — `rtl/`
of VIC20_MiSTer (vic20.vhd, M6561, VIAs, T65, c1530, Megacart, sdram.sv, ddram.sv) — is used
**unmodified**, as a git submodule pinned in `src/fpga/VIC20_MiSTer`. Replaced: `VIC20.sv` (the `emu` top),
the MiSTer framework under `sys/`, and VIC20_MiSTer's old `iec_drive`.

```
apf_top (Analogue)
└── core_top                      src/fpga/core/core_top.v
    ├── pll_vic20 + pll_cfg       74.25 MHz -> clk_sys 35.468944 (PAL) / 32.727260 (NTSC), clk_sys_90
    ├── core_bridge_cmd           Analogue host/target command handler (template, unchanged)
    ├── vic20_media               files and disk images over target commands (stands in for the ARM)
    │   ├── gcr_synth             D64 track -> GCR (Main_MiSTer's c64_synthesize_gcr_track)
    │   └── gcr_decode            flushed GCR track -> D64 sectors (Main_MiSTer's c64_writeGCR)
    ├── ddram_psram  (cram0)      the drive's DDRAM port: G64 image
    ├── ddram_psram  (cram1)      ddram.sv's DDRAM port: TAP file
    ├── hid_c64                   Dock keyboard + pad -> ps2_key words (VIC-20 and C64 share the matrix)
    ├── autostart                 types RUN / LOAD"*",8,1 / Shift+Run/Stop at the BASIC prompt
    ├── osk_ctrl / osk_overlay    on-screen keyboard and loading screen
    ├── vic20_video               M6561 output -> APF scaler
    ├── sound_i2s                 16-bit -> Pocket I2S DAC (agg23, MIT)
    └── vic20_top                 VIC20.sv's machine without hps_io / scaler / HDMI
        └── iec_drive             C64_MiSTer's drive (src/fpga/rtl/iec_drive, see SOURCE there)
```

`vic20_top.sv` is derived from `VIC20.sv` and keeps its logic (PRG loader and BASIC pointers, CRT / CTx
blocks, ROM loading, Megacart, tape, audio) as is; its `status[]` input keeps VIC20.sv's bit map. When
updating the submodule, diff `VIC20.sv` against the version the splice was made from (submodule commit
`4386b36`) and carry changes over.

## The drive

VIC20_MiSTer's `iec_drive` is an older copy that asks the ARM for each track over `sd_rd`. C64_MiSTer's
current one reads a G64 image from DDRAM, which is what openfpga-C64's media loader prepares, so that drive
is vendored in `src/fpga/rtl/iec_drive` (`PARPORT(0)`, `DRIVES(1)`: drive 8 only, 1541 or 1581). Its
`rom_addr` gets the first 16 KB of a System ROM, as VIC20.sv does with boot.rom.

## Media

All slots are `deferload`; `vic20_media` (openfpga-C64's `c64_media`) pulls them with target commands and
replays them on VIC20.sv's `ioctl_*` port. Sequences, bridge buffers and the D64/G64/D81 handling are
the C64 port's: see [openfpga-C64's architecture](https://github.com/defgenx/openfpga-C64/blob/main/docs/architecture.md#media).

| Slot | File        | ioctl index | Handling |
|------|-------------|-------------|----------|
| 0    | Program     | `0x01`      | streamed; vic20_top stores it, sets `$2D-$32`, `$AE-$AF`, pulses `prg_loaded`. A load address in `$A000-$BFFF` is a cartridge dump: sent as `0x41` (VIC20.sv's PRG path drops bytes from `$A000`) |
| 1    | Cartridge   | `0x41` / `0x81` | `0x41`: load address in the first 2 bytes. Exactly 2/4/8/16 KB: `0x81` with extension `.CTA`, loaded at `$A000`. Both reset the VIC-20 while loading (VIC20.sv resets for `0x41` only), so the cartridge starts |
| 2    | Disk        | –           | G64 / D64 / D81, drive 8 |
| 3    | Megacart    | `0x02`      | streamed into SDRAM (VIC20.sv's `sdram.sv`, 8 MB window) |
| 4    | Tape        | `0xC1`      | streamed into PSRAM cram1 through `ddram.sv` (4 MB: `ddram_psram` uses 19 address bits); `ioctl_wait` also follows `TDDRAM_BUSY`, see below |
| 5    | System ROM  | `0x06`      | first 16 KB to the 1541, then PAL and NTSC KERNAL |

### Tape writes

`ddram.sv` reports ready one clock after it hands a write to the DDRAM port, and only sees a new `we`
pulse on a clock where `DDRAM_BUSY` is low. A PSRAM write through `ddram_psram` lasts longer than the
loader's gap between bytes, so the next byte's pulse fell on a busy clock and was lost: every other TAP byte
never reached PSRAM. `vic20_top` holds `ioctl_wait` while a tape download sees `TDDRAM_BUSY`.
`sim/tape_tb.sv` (`make -C sim tape`) streams a file at the loader's pace and reads it back.

### Memory = Auto

The PRG's second byte (load address high) selects the expansion: `$04` +3K, `< $11` none, `< $20` +24K
(`$1201` programs), otherwise all 35K. If that differs from the current map, `vic20_top` raises
`ioctl_wait` after that byte, resets the VIC-20 (BASIC sets the screen and its pointers at boot), waits for
`at_prompt` to drop and come back, and releases the download. With a fixed *Memory* setting nothing is held.

### Prompt detection

`o_extmem_addr` is the CPU address bus. `at_prompt` is set when the CPU spends over 1/16 of a ~30 ms window
in the KERNAL's key wait loop at `$E5E8`–`$E5F0` (same bytes as the C64's `$E5CD` loop, found in both
KERNAL images); `basic_main` is BASIC's direct-mode loop at `$C483` (`$0302`'s value, vector table at
`$E451`). `autostart.sv` uses them as on the C64; see [input.md](input.md).

## Memory

* SDRAM: Megacart only, VIC20.sv's `sdram.sv` at clk_sys, DQM on A12/A11 as on MiSTer boards (the Pocket's
  DQM pins get the same two bits), SDRAM clock = inverted clk_sys through a DDIO register.
* PSRAM cram0: G64 of drive 8. PSRAM cram1: the TAP file. Both via `ddram_psram` (agg23's async
  `psram.sv`, four 16-bit accesses per 64-bit word).
* VIC-20 RAM, expansions and ROMs are block RAM inside vic20.vhd.

## Clocks

`pll_vic20` is openfpga-C64's reconfigurable fractional PLL with other counters: VCO = 74.25 × 7.643
(÷2 = 567.503 MHz), outputs ÷16 clk_sys and clk_sys_90 (4 counts late, 90°). NTSC rewrites only K
(register 7): 7.05234, fractional part 0.052, inside Altera's 0.05–0.95. The VIC-20 is held in reset for
~2 ms after the standard changes. The APF video clock is clk_sys; `video_rgb_clock_90` must come from the
PLL (see openfpga-C64's notes).

## Settings

| Address      | Setting             | Values                                                  |
|--------------|---------------------|---------------------------------------------------------|
| `0x80000000` | Reset               | any write (status[0] pulse)                             |
| `0x80000004` | Reset & Detach Cart | any write (status[27] pulse)                            |
| `0x80000008` | Memory              | 0 auto, 1 none, 2 3K, 3 8K, 4 16K, 5 24K, 6 35K (`mem_mode`) |
| `0x8000000C` | Video               | 0 PAL, 1 NTSC (PLL reconfiguration)                     |
| `0x80000014` | Pad Mode            | 0 joystick, 2 keys                                      |
| `0x8000001C` | Autostart           | 0 off, 1 on                                             |
| `0x80000020` | Cart RAM Writable   | status[11]                                              |
| `0x80000024` | Write Protect       | disk mounted read-only                                  |
| `0x80000028` | Tape Sound          | status[17]                                              |
| `0x8000002C` | Paddles             | Dock analog stick X of pads 1 / 2 -> pd1 / pd2          |
| `0x80000034` | Tape Play/Pause     | any write (status[16] pulse)                            |

## Not ported

Drive 9, external IEC and SNAC (user port), Megacart NVRAM save to SD, tape ADC input, scandoubler /
HDMI options, screen centering (fixed at "both", so the scaler sees one geometry).
