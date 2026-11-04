// tape_tb.sv - a TAP download through VIC20.sv's tape logic, ddram.sv and ddram_psram, paced as
// vic20_media sends bytes; then the c1530 side's reads. Every byte must come back as sent.
// The tape logic is vic20_top.sv's (`include would pull the whole machine): keep the two in sync.

`timescale 1ns/1ps

module tape_tb;
	reg clk = 0;
	always #14.1 clk = ~clk;          // clk_sys PAL, 35.47 MHz

	localparam integer N = 3000;
	reg [7:0] file[N];

	// ---------------- vic20_media's byte pacing (S_DL_BYTE / S_DL_SEND / S_DL_PACE) ----------------
	reg         ioctl_download = 0, ioctl_wr = 0;
	reg  [24:0] ioctl_addr = 0;
	reg   [7:0] ioctl_data;
	wire        ioctl_wait;
	wire        load_tap = 1'b1;

	task send_all;
		integer i, c;
		begin
			ioctl_download = 1;
			for (i = 0; i < N; i = i + 1) begin
				repeat (2) @(posedge clk);
				while (ioctl_wait) @(posedge clk);       // S_DL_BYTE cnt 2
				ioctl_data <= file[i];
				@(posedge clk);
				while (ioctl_wait) @(posedge clk);       // S_DL_SEND
				ioctl_wr <= 1;
				@(posedge clk);
				ioctl_wr <= 0;
				repeat (3) @(posedge clk);               // S_DL_PACE
				ioctl_addr <= ioctl_addr + 1;
			end
			repeat (2) @(posedge clk);
			while (ioctl_wait) @(posedge clk);
			repeat (16) @(posedge clk);
			ioctl_download = 0;
		end
	endtask

	// ---------------- vic20_top.sv's tape write side ----------------
	wire        TDDRAM_BUSY, TDDRAM_DOUT_READY, TDDRAM_RD, TDDRAM_WE;
	wire  [7:0] TDDRAM_BURSTCNT, TDDRAM_BE;
	wire [28:0] TDDRAM_ADDR;
	wire [63:0] TDDRAM_DOUT, TDDRAM_DIN;
	reg         reset = 0;
	reg         tap_wr = 0, tap_rd = 0, tap_wait = 0;
	reg  [24:0] tap_play_addr = 0;
	wire  [7:0] tap_data;
	wire        tap_data_ready;

	assign ioctl_wait = tap_wait | (ioctl_download & load_tap & TDDRAM_BUSY);   // as vic20_top.sv

	always @(posedge clk) begin
		reg old_reset;
		old_reset <= reset;
		if (~old_reset && reset) tap_wait <= 0;
		tap_wr <= 0;
		if (ioctl_wr & load_tap) begin
			tap_wait <= 1;
			tap_wr <= 1;
		end else if (~tap_wr & tap_wait & tap_data_ready) tap_wait <= 0;
	end

	ddram ddram (
		.reset(reset), .DDRAM_CLK(clk),
		.DDRAM_BUSY(TDDRAM_BUSY), .DDRAM_BURSTCNT(TDDRAM_BURSTCNT), .DDRAM_ADDR(TDDRAM_ADDR),
		.DDRAM_DOUT(TDDRAM_DOUT), .DDRAM_DOUT_READY(TDDRAM_DOUT_READY), .DDRAM_RD(TDDRAM_RD),
		.DDRAM_DIN(TDDRAM_DIN), .DDRAM_BE(TDDRAM_BE), .DDRAM_WE(TDDRAM_WE),
		.addr(ioctl_download ? ioctl_addr : tap_play_addr), .dout(tap_data), .din(ioctl_data),
		.we(tap_wr), .rd(tap_rd), .ready(tap_data_ready));

	wire [21:16] cram_a;
	wire [15:0] cram_dq;
	wire        cram_adv_n, cram_ce0_n, cram_ce1_n, cram_oe_n, cram_we_n, cram_ub_n, cram_lb_n;
	ddram_psram tape_ram (
		.clk(clk), .reset(1'b0),
		.DDRAM_BUSY(TDDRAM_BUSY), .DDRAM_BURSTCNT(TDDRAM_BURSTCNT), .DDRAM_ADDR(TDDRAM_ADDR),
		.DDRAM_DOUT(TDDRAM_DOUT), .DDRAM_DOUT_READY(TDDRAM_DOUT_READY), .DDRAM_RD(TDDRAM_RD),
		.DDRAM_WE(TDDRAM_WE), .DDRAM_DIN(TDDRAM_DIN), .DDRAM_BE(TDDRAM_BE),
		.ld_start(1'b0), .ld_we(1'b0), .ld_addr(22'd0), .ld_wdata(8'd0), .ld_rdata(), .ld_ack(),
		.cram_a(cram_a), .cram_dq(cram_dq), .cram_wait(1'b0), .cram_clk(), .cram_adv_n(cram_adv_n), .cram_cre(),
		.cram_ce0_n(cram_ce0_n), .cram_ce1_n(cram_ce1_n), .cram_oe_n(cram_oe_n), .cram_we_n(cram_we_n),
		.cram_ub_n(cram_ub_n), .cram_lb_n(cram_lb_n));

	// ---------------- PSRAM model (media_tb's) ----------------
	reg  [15:0] pmem[2097152];
	reg  [21:0] paddr;
	reg  [15:0] wlat;
	reg         wub, wlb, wact = 0;
	always @(posedge cram_adv_n) if (!cram_ce0_n) paddr <= {cram_a, cram_dq};
	always @(*) if (!cram_ce0_n && !cram_we_n && cram_adv_n && cram_dq !== 16'hzzzz) begin
		wlat = cram_dq; wub = cram_ub_n; wlb = cram_lb_n; wact = 1;
	end
	always @(posedge cram_we_n) if (wact) begin
		if (!wlb) pmem[paddr[20:0]][7:0]  = wlat[7:0];
		if (!wub) pmem[paddr[20:0]][15:8] = wlat[15:8];
		wact = 0;
	end
	assign #5 cram_dq = (!cram_ce0_n && !cram_oe_n && cram_we_n) ? pmem[paddr[20:0]] : 16'hzzzz;

	// ---------------- run ----------------
	integer i, bad_w, bad_r;
	reg [7:0] got;
	initial begin
		for (i = 0; i < N; i = i + 1) file[i] = (i * 37 + 11) ^ (i >> 3);
		for (i = 0; i < 2097152; i = i + 1) pmem[i] = 16'h0000;
		reset = 1; repeat (4) @(posedge clk); reset = 0; repeat (4) @(posedge clk);

		send_all;

		bad_w = 0;
		for (i = 0; i < N; i = i + 1) begin
			got = i[0] ? pmem[i >> 1][15:8] : pmem[i >> 1][7:0];
			if (got !== file[i]) begin
				if (bad_w < 5) $display("write: byte %0d is %02x, want %02x", i, got, file[i]);
				bad_w = bad_w + 1;
			end
		end

		// playback: c1530's side, one rd pulse per byte, wait for ready (vic20_top's tap_cycle)
		bad_r = 0;
		for (i = 0; i < N; i = i + 1) begin
			tap_play_addr <= i;
			@(posedge clk); tap_rd <= 1;
			@(posedge clk); tap_rd <= 0;
			@(posedge clk);
			while (!tap_data_ready) @(posedge clk);
			if (tap_data !== file[i]) begin
				if (bad_r < 5) $display("read: byte %0d is %02x, want %02x", i, tap_data, file[i]);
				bad_r = bad_r + 1;
			end
		end

		if (bad_w == 0 && bad_r == 0) $display("tape: %0d bytes written and read back OK", N);
		else $display("tape: FAIL, %0d bytes wrong in PSRAM, %0d read back wrong", bad_w, bad_r);
		$finish;
	end
endmodule
