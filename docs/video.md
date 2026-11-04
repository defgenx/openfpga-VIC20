# Video

The APF video clock is clk_sys (35.47 MHz PAL, 32.73 MHz NTSC). The M6561 puts out a pixel on each
`o_ce_pix` (clk_sys / 8); `vic20_video` takes every pixel with `hblank` and `vblank` low, marks the other
clocks of the line `video_skip`, and caps the window at a fixed size so the scaler sees the same geometry
every frame. HS is the `hblank` fall. VS is the `hblank` rise of the fourth line of vertical blanking:
4 blank lines after the picture, 26 (PAL) / 14 (NTSC) before the next one. At the `vblank` rise it fell on
the last picture line itself, with no HS between that line and VS. `sim/video_tb.sv` (`make -C sim
video`) checks the window and VS placement on the M6561's timing. The slot is
announced on the first clock with DE low after each line (`video_rgb = {8'h00, slot, 13'h0}`).

| Slot | Standard       | Active area | Aspect |
|------|----------------|-------------|--------|
| 0    | PAL (6561)     | 228 × 283   | 4:3    |
| 1    | NTSC (6560)    | 204 × 244   | 5:4    |

Sizes come from VIC20_MiSTer's `m6561.vhd` simulated with nvc (`make -C sim vic`, `sim/vic/tb_vic.vhd`,
I_CENTER "11", I_WIDE '0'). Aspect ratios follow from the pixel clocks: PAL 4.43 MHz against 7.375 MHz for
square pixels on 288 lines (×1.66), NTSC 4.09 MHz against 6.136 MHz on 240 lines (×1.5).

## Known gaps

* Untested on a real screen.
* The on-screen keyboard fills the line: 19-pixel cells on PAL (228), 17 on NTSC (204), where two-letter
  labels touch. `sim/osk_tb.sv` renders the PAL frame (set `W`/`H` to 204/244 for NTSC).
