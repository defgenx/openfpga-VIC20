// video_tb.sv - vic20_video on the M6561's blanking (m6561.vhd's PAL / NTSC counters, I_CENTER "11"
// with BASIC's registers, so vcnt_c = vcnt): per frame, DE lines and pixels, one VS, and the HS
// count between the picture and VS on both sides.

`timescale 1ns/1ps

module video_tb;
	reg clk = 0;
	always #14 clk = ~clk;

	reg        ntsc = 0;
	reg  [2:0] div = 0;
	wire       ce = div == 0;
	always @(posedge clk) div <= div + 3'd1;

	// m6561.vhd: hcnt 0..CLOCKS_PER_LINE_M1, hblank set at H_END_M1, cleared at H_START_M1;
	// vblank set at the end of the last line, cleared at the end of line V_START; outputs registered
	wire [8:0] cpl  = ntsc ? 9'd259 : 9'd283;
	wire [8:0] tl   = ntsc ? 9'd260 : 9'd311;
	wire [8:0] hs_  = ntsc ? 9'd43  : 9'd47;
	wire [8:0] he_  = ntsc ? 9'd247 : 9'd275;
	wire [8:0] vst  = ntsc ? 9'd16  : 9'd28;
	reg  [8:0] hcnt = 0, vcnt = 0;
	reg        hb = 1, vb = 1, o_hb = 1, o_vb = 1;
	always @(posedge clk) if (ce) begin
		hcnt <= (hcnt == cpl) ? 9'd0 : hcnt + 9'd1;
		if (hcnt == cpl) vcnt <= (vcnt == tl) ? 9'd0 : vcnt + 9'd1;
		if (hcnt == he_) hb <= 1; else if (hcnt == hs_) hb <= 0;
		if (hcnt == cpl) begin
			if (vcnt == tl) vb <= 1; else if (vcnt == vst) vb <= 0;
		end
		o_hb <= hb;
		o_vb <= vb;
	end

	wire [23:0] rgb;
	wire de, skip, hs, vs;
	vic20_video dut (.clk(clk), .ce_pix(ce), .ntsc(ntsc), .r(8'h11), .g(8'h22), .b(8'h33),
		.hblank(o_hb), .vblank(o_vb), .video_rgb(rgb), .video_de(de), .video_skip(skip),
		.video_hs(hs), .video_vs(vs));

	// per frame (VS to VS)
	integer px, lines, minpx, maxpx, vss, hs_since_de, hs_since_vs, gap_after, gap_before, errs;
	reg de_d = 0, line_de = 0, seen_de = 0;
	always @(posedge clk) begin
		de_d <= de;
		if (vs && (hs || de)) begin $display("FAIL VS with HS or DE"); errs = errs + 1; end
		if (de && !skip) px = px + 1;
		if (de) begin
			if (!seen_de) gap_before = hs_since_vs;
			line_de = 1; seen_de = 1; hs_since_de = 0;
		end
		if (hs) begin
			if (line_de) begin
				lines = lines + 1;
				if (px < minpx) minpx = px;
				if (px > maxpx) maxpx = px;
			end
			line_de = 0; px = 0;
			hs_since_de = hs_since_de + 1; hs_since_vs = hs_since_vs + 1;
		end
		if (vs) begin
			vss = vss + 1;
			gap_after = hs_since_de;
			hs_since_vs = 0;
		end
	end

	task frame(input integer want_w, input integer want_h);
		integer f;
		begin
			@(posedge vs); @(posedge clk);
			for (f = 0; f < 3; f = f + 1) begin
				lines = 0; minpx = 9999; maxpx = 0; seen_de = 0;
				@(posedge vs); @(posedge clk);
				$display("video: %0s frame %0d: %0d-%0d x %0d, %0d HS picture->VS, %0d HS VS->picture",
				         ntsc ? "NTSC" : "PAL", f, minpx, maxpx, lines, gap_after, gap_before);
				if (minpx != want_w || maxpx != want_w || lines != want_h || gap_after < 3 || gap_before < 3) begin
					$display("FAIL"); errs = errs + 1;
				end
			end
		end
	endtask

	initial begin
		errs = 0; vss = 0; px = 0; hs_since_de = 0; hs_since_vs = 0; gap_after = 0; gap_before = 0;
		frame(228, 283);
		ntsc = 1;
		@(posedge vs);                 // the slot and window change at this VS
		frame(204, 244);
		if (errs) $display("video: FAIL"); else $display("video: OK");
		$finish;
	end
endmodule
