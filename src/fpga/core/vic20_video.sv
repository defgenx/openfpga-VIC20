//
// vic20_video.sv - VIC (6560/6561) output to the APF scaler
//
// The APF video clock is clk_sys; the VIC puts out a pixel on each ce_pix (clk_sys / 8),
// the other clocks of a line's active area are video_skip. The window is the VIC's whole
// unblanked area, capped at a fixed size so the scaler sees the same geometry every frame.
// Sizes come from m6561.vhd's blanking constants; see docs/video.md.
//

`default_nettype none

module vic20_video (
	input  wire        clk,
	input  wire        ce_pix,
	input  wire        ntsc,
	input  wire  [7:0] r,
	input  wire  [7:0] g,
	input  wire  [7:0] b,
	input  wire        hblank,
	input  wire        vblank,

	output reg  [23:0] video_rgb,
	output reg         video_de,
	output reg         video_skip,
	output reg         video_hs,
	output reg         video_vs
);

// Scaler slots, in video.json order
localparam [2:0] SLOT_PAL  = 3'd0;
localparam [2:0] SLOT_NTSC = 3'd1;

reg        ntsc_f;                  // latched per frame
wire [8:0] w    = ntsc_f ? 9'd204 : 9'd228;
wire [8:0] h    = ntsc_f ? 9'd244 : 9'd283;
wire [2:0] slot = ntsc_f ? SLOT_NTSC : SLOT_PAL;

reg  [8:0] px, py;
reg        hb_d, vb_d;
reg        span;                    // the last pixel was in the window
reg  [2:0] vb_lines = 3'd0;         // blank lines since the vblank rise

wire hb_fall = hb_d & ~hblank;
wire hb_rise = ~hb_d & hblank;
wire vb_fall = vb_d & ~vblank;
wire vb_rise = ~vb_d & vblank;

// VS 4 lines into the vertical blanking, clear of the last and the first picture line (as
// openfpga-C64, where VS is the VIC-II's vsync); at an hblank rise, so never with HS
wire vs = hb_rise && vblank && vb_lines == 3'd3;

wire sample = ce_pix && !hblank && !vblank;
wire in_win = sample && px < w && py < h;
wire de     = sample ? in_win : span;

always @(posedge clk) begin
	hb_d <= hblank;
	vb_d <= vblank;

	if (hb_fall) px <= 9'd0;
	if (hb_rise) begin
		span <= 1'b0;
		if (!vblank) py <= py + 9'd1;
	end
	if (vb_fall) py <= 9'd0;
	if (vb_rise) vb_lines <= 3'd0;
	else if (hb_rise && vblank && vb_lines != 3'd7) vb_lines <= vb_lines + 3'd1;
	if (vs) ntsc_f <= ntsc;
	if (sample) begin
		px <= px + 9'd1;
		span <= in_win;
	end

	video_hs   <= hb_fall;
	video_vs   <= vs;
	video_de   <= de;
	video_skip <= de && !sample;

	if (in_win)
		video_rgb <= {r, g, b};
	else if (video_de && !de)
		video_rgb <= {8'h00, slot, 13'h0000};   // end of line: scaler slot select
	else if (!de)
		video_rgb <= 24'h000000;
end

endmodule

`default_nettype wire
