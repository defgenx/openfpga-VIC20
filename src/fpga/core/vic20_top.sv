//
// vic20_top.sv - VIC20_MiSTer's VIC20.sv machine without hps_io, scaler and HDMI
//
// Logic kept from VIC20.sv: memory loader (PRG pointers, CRT / CTx blocks, ROM), Megacart,
// tape (c1530 from DDRAM), audio mix. The drive is C64_MiSTer's newer iec_drive (G64 in
// DDRAM, see rtl/iec_drive/SOURCE), one drive (#8). status[] keeps VIC20.sv's bit map.
// See docs/architecture.md.
//

module vic20_top
(
	input         clk_sys,
	input         pll_locked,
	input         reset_req,
	input         ntsc_r,          // the standard the PLL runs

	input  [63:0] status,
	input   [2:0] mem_mode,        // 0 auto, 1 none, 2 3K, 3 8K, 4 16K, 5 24K, 6 35K

	input         ioctl_download,
	input   [7:0] ioctl_index,
	input         ioctl_wr,
	input  [24:0] ioctl_addr,
	input   [7:0] ioctl_data,
	input  [31:0] ioctl_file_ext,
	output        ioctl_wait,

	output [31:0] sd_lba[2],
	output  [5:0] sd_blk_cnt[2],
	output  [1:0] sd_rd,
	output  [1:0] sd_wr,
	input   [1:0] sd_ack,
	input  [13:0] sd_buff_addr,
	input   [7:0] sd_buff_dout,
	output  [7:0] sd_buff_din[2],
	input         sd_buff_wr,
	input   [1:0] img_mounted,
	input  [31:0] img_size,
	input         img_readonly,
	input   [1:0] img_type,

	// drive: G64 images (PSRAM cram0)
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	// tape: TAP file (PSRAM cram1)
	input         TDDRAM_BUSY,
	output  [7:0] TDDRAM_BURSTCNT,
	output [28:0] TDDRAM_ADDR,
	input  [63:0] TDDRAM_DOUT,
	input         TDDRAM_DOUT_READY,
	output        TDDRAM_RD,
	output [63:0] TDDRAM_DIN,
	output  [7:0] TDDRAM_BE,
	output        TDDRAM_WE,

	input  [10:0] ps2_key,
	input  [15:0] joya,
	input  [15:0] joyb,
	input   [7:0] pd1,
	input   [7:0] pd2,

	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_HB,
	output        VGA_VB,
	output        VGA_CE,          // one clk_sys pulse per pixel
	output        ntsc_out,

	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,

	output        disk_ready_out,
	output reg    at_prompt,       // the KERNAL is waiting for a key (BASIC prompt)
	output reg    basic_main,      // BASIC's direct-mode main loop ran ($C483)
	output reg    prg_loaded       // pulse: a PRG has been stored and its pointers set
);

wire load_prg = (ioctl_index == 'h01);
wire load_crt = (ioctl_index == 'h41);
wire load_ct  = (ioctl_index == 'h81);
wire load_tap = (ioctl_index == 'hC1);
wire load_rom = (ioctl_index == 'h06);
wire load_mc  = (ioctl_index[4:0] == 2);

wire pal = ~ntsc_r;
assign ntsc_out = ntsc_r;

// the PLL changes frequency on a standard change: hold the machine in reset meanwhile
reg tv_reset = 1'b1;
always @(posedge clk_sys) begin
	reg        pald = 1'b0;
	reg [15:0] cnt = 16'hFFFF;
	pald <= pal;
	if (pald != pal) cnt <= 16'hFFFF;
	else if (cnt) cnt <= cnt - 1'd1;
	tv_reset <= cnt != 0;
end

reg v20_en = 0;
always @(negedge clk_sys) begin
	reg [1:0] div = 0;
	div <= div + 1'd1;
	v20_en <= !div;
end

/////////////////  MEMORY EXPANSION  //////////////

// Auto: a PRG's load address says which expansion it was saved with. When that differs
// from the current one, the download is held, the VIC-20 restarts with the new memory map
// (BASIC places the screen and its pointers at boot) and the rest of the PRG goes in
// once the BASIC prompt is back.
reg  [4:0] auto_ram = 5'b00000;
reg  [4:0] fixed_ram;
always @(*) begin
	case (mem_mode)
		3'd2:    fixed_ram = 5'b00001;   // 3K at $0400
		3'd3:    fixed_ram = 5'b00010;   // 8K at $2000
		3'd4:    fixed_ram = 5'b00110;   // 16K
		3'd5:    fixed_ram = 5'b01110;   // 24K
		3'd6:    fixed_ram = 5'b11111;   // 35K (3K + 24K + $A000)
		default: fixed_ram = 5'b00000;
	endcase
end
wire [4:0] extram = (mem_mode == 3'd0) ? auto_ram : fixed_ram;

function [4:0] ram_for(input [7:0] hi);
	if (hi[7:2] == 6'b000001)  ram_for = 5'b00001;    // $04xx: 3K
	else if (hi < 8'h11)       ram_for = 5'b00000;    // $10xx (and below): unexpanded
	else if (hi < 8'h20)       ram_for = 5'b01110;    // $12xx: 8K or more
	else                       ram_for = 5'b11111;    // machine code anywhere else
endfunction

reg       prg_hold = 1'b0;
reg [9:0] auto_reset = 10'd0;
always @(posedge clk_sys) begin
	reg [1:0] hstate = 2'd0;
	reg       old_dl = 1'b0;
	old_dl <= ioctl_download;

	if (auto_reset) auto_reset <= auto_reset - 1'd1;
	case (hstate)
		2'd0: if (ioctl_download && load_prg && ioctl_wr && ioctl_addr == 25'd1 && mem_mode == 3'd0 &&
		          ram_for(ioctl_data) != auto_ram) begin
			auto_ram <= ram_for(ioctl_data);
			auto_reset <= 10'h3FF;
			prg_hold <= 1'b1;
			hstate <= 2'd1;
		end
		2'd1: if (!auto_reset && !at_prompt) hstate <= 2'd2;    // the reset took the prompt away
		2'd2: if (at_prompt) begin prg_hold <= 1'b0; hstate <= 2'd0; end
		default: hstate <= 2'd0;
	endcase
	if (old_dl && !ioctl_download) begin prg_hold <= 1'b0; hstate <= 2'd0; end
	if (reset_req) begin prg_hold <= 1'b0; hstate <= 2'd0; end
end

/////////////////  RESET  /////////////////////////

wire sys_reset = reset_req | status[0] | status[27] | (auto_reset != 0);
wire reset = sys_reset | cart_reset | mc_reset;

////////////////  LOADING  ////////////////////////

reg  [15:0] dl_addr;
reg   [7:0] dl_data;
reg         dl_wr;
reg         cart_reset = 0;
reg   [4:0] cart_blk = 0;

always @(posedge clk_sys) begin
	reg        old_download = 0;
	reg  [3:0] state = 0;
	reg [15:0] addr;

	dl_wr <= 0;
	prg_loaded <= 0;
	old_download <= ioctl_download;

	if(ioctl_download && load_prg) begin
		state <= 0;
		if(ioctl_wr) begin
			     if(ioctl_addr == 0) addr[7:0]  <= ioctl_data;
			else if(ioctl_addr == 1) addr[15:8] <= ioctl_data;
			else begin
				if(addr<'hA000) begin
					dl_addr <= addr;
					dl_data <= ioctl_data;
					dl_wr   <= 1;
					addr    <= addr + 1'd1;
				end
			end
		end
	end

	if(old_download && ~ioctl_download && load_prg) state <= 1;
	if(state) state <= state + 1'd1;

	case(state)
		 1: begin dl_addr <= 16'h2d; dl_data <= addr[7:0];  dl_wr <= 1; end
		 3: begin dl_addr <= 16'h2e; dl_data <= addr[15:8]; dl_wr <= 1; end
		 5: begin dl_addr <= 16'h2f; dl_data <= addr[7:0];  dl_wr <= 1; end
		 7: begin dl_addr <= 16'h30; dl_data <= addr[15:8]; dl_wr <= 1; end
		 9: begin dl_addr <= 16'h31; dl_data <= addr[7:0];  dl_wr <= 1; end
		11: begin dl_addr <= 16'h32; dl_data <= addr[15:8]; dl_wr <= 1; end
		13: begin dl_addr <= 16'hae; dl_data <= addr[7:0];  dl_wr <= 1; end
		15: begin dl_addr <= 16'haf; dl_data <= addr[15:8]; dl_wr <= 1; prg_loaded <= 1; end
	endcase

	if(ioctl_download && load_rom) begin
		state <= 0;
		if(ioctl_wr) begin
			if(ioctl_addr>='h4000 && ioctl_addr<'h8000) begin
				dl_addr <= ioctl_addr[15:0] + 16'h8000;
				dl_data <= ioctl_data;
				dl_wr   <= 1;
			end
		end
	end

	if(ioctl_download && (load_crt || load_ct)) begin
		if(ioctl_wr) begin
			     if(ioctl_addr == 0 && load_crt) addr[7:0]  <= ioctl_data;
			else if(ioctl_addr == 1 && load_crt) addr[15:8] <= ioctl_data;
			else if(addr < 'hC000) begin
				if(addr[15:13] == 3'b000) cart_blk[0] <= 1;
				if(addr[15:13] == 3'b001) cart_blk[1] <= 1;
				if(addr[15:13] == 3'b010) cart_blk[2] <= 1;
				if(addr[15:13] == 3'b011) cart_blk[3] <= 1;
				if(addr[15:13] == 3'b101) cart_blk[4] <= 1;
				dl_addr <= addr;
				dl_data <= ioctl_data;
				dl_wr   <= 1;
				addr    <= addr + 1'd1;
			end
		end
	end

	// VIC20.sv resets for CRT and Megacart only; a headerless cart (CTA) must start the same way
	if((old_download ^ ioctl_download) & (load_crt | load_ct | load_mc)) cart_reset <= ioctl_download;
	if(status[27]) {cart_reset, cart_blk} <= 0;
	if(ioctl_download & load_mc) cart_blk <= 0;

	if(~old_download & ioctl_download & load_ct) begin
		if(ioctl_file_ext[7:0] >= "2" && ioctl_file_ext[7:0] <= "9") addr <= {ioctl_file_ext[3:0],     12'h000};
		if(ioctl_file_ext[7:0] >= "A" && ioctl_file_ext[7:0] <= "B") addr <= {ioctl_file_ext[3:0]+4'd9,12'h000};
	end
end

reg mc_loaded = 0;
always @(posedge clk_sys) begin
	if(status[27] | (ioctl_download & (load_crt | load_ct))) mc_loaded <= 0;
	if(ioctl_download & load_mc) mc_loaded <= 1;
end

wire        extmem_sel;
wire        p2_h;

wire        mc_reset;
wire [22:0] mc_addr;
wire        mc_wr_n;
wire        mc_nvram_sel;

wire        vic_wr_n;
wire        vic_io2_sel;
wire        vic_io3_sel;
wire        vic_blk123_sel;
wire        vic_blk5_sel;
wire        vic_ram123_sel;
wire  [7:0] vic_data;
wire [15:0] vic_addr;

megacart mc
(
	.clk(clk_sys),
	.reset_n(mc_loaded & ~sys_reset & ~cart_reset),

	.vic_addr(vic_addr),
	.vic_wr_n(vic_wr_n),
	.vic_io2_sel(vic_io2_sel),
	.vic_io3_sel(vic_io3_sel),
	.vic_blk123_sel(vic_blk123_sel),
	.vic_blk5_sel(vic_blk5_sel),
	.vic_ram123_sel(vic_ram123_sel),
	.vic_data(vic_data),

	.mc_addr(mc_addr),
	.mc_wr_n(mc_wr_n),
	.mc_nvram_sel(mc_nvram_sel),
	.mc_soft_reset(mc_reset)
);

reg ioctl_wr_d;
always @(posedge clk_sys) ioctl_wr_d <= ioctl_wr;

wire [7:0] sdram_out;
sdram ram
(
	.SDRAM_CLK(SDRAM_CLK),
	.SDRAM_DQ(SDRAM_DQ),
	.SDRAM_A(SDRAM_A),
	.SDRAM_DQML(SDRAM_DQML),
	.SDRAM_DQMH(SDRAM_DQMH),
	.SDRAM_BA(SDRAM_BA),
	.SDRAM_nCS(SDRAM_nCS),
	.SDRAM_nWE(SDRAM_nWE),
	.SDRAM_nRAS(SDRAM_nRAS),
	.SDRAM_nCAS(SDRAM_nCAS),
	.SDRAM_CKE(SDRAM_CKE),

	.clk(clk_sys),
	.init(~pll_locked),
	.clkref(ioctl_download ? ioctl_wr : p2_h),

	.dout(sdram_out),
	.din ((ioctl_download & load_mc) ? ioctl_data : vic_data),
	.addr((ioctl_download & load_mc) ? ioctl_addr : {2'b00, mc_addr}),
	.we  ((ioctl_download & load_mc) ? ioctl_wr_d : (~mc_nvram_sel & extmem_sel & ~mc_wr_n)),
	.oe  ((ioctl_download & load_mc) ? 1'b0       : (~mc_nvram_sel & extmem_sel & mc_wr_n))
);

// Megacart NVRAM: kept while the core runs, not saved to the SD card
wire [7:0] mc_nvram_out;
gen_dpram #(13, 8) mc_nvram
(
	.clock_a(clk_sys),
	.address_a(vic_addr[12:0]),
	.data_a(vic_data),
	.wren_a(mc_nvram_sel & ~mc_wr_n),
	.q_a(mc_nvram_out),

	.clock_b(clk_sys),
	.address_b(13'd0),
	.data_b(8'd0),
	.wren_b(1'b0),
	.q_b()
);

wire [7:0] mc_data = mc_nvram_sel ? mc_nvram_out : sdram_out;

///////////////////////////////////////////////////

wire [15:0] joy = joya | joyb;

reg [10:0] v20_key;
always @(posedge clk_sys) begin
	reg [10:0] key;
	key <= ps2_key;
	v20_key <= key;
end

wire key_play;

VIC20 VIC20
(
	.i_sysclk(clk_sys),
	.i_sysclk_en(v20_en),
	.i_reset(reset|tv_reset),
	.o_p2h(p2_h),

	//IEC
	.atn_o(v20_iec_atn_o),
	.clk_o(v20_iec_clk_o),
	.data_o(v20_iec_data_o),
	.clk_i(c1541_iec_clk_o),
	.data_i(c1541_iec_data_o),

	.i_joy(~{joy[0] | joya[5], joy[1] | joyb[5], joy[2], joy[3]}),
	.i_fire(~joy[4]),
	.i_potx(~pd1),
	.i_poty(~pd2),

	.i_ram_ext_ro(mc_loaded ? 5'b00000 : (cart_blk & ~{5{status[11]}})),
	.i_ram_ext   (mc_loaded ? 5'b11111 : (extram|cart_blk)),

	.o_ce_pix(VGA_CE),
	.o_video_r(r),
	.o_video_g(g),
	.o_video_b(b),
	.o_hsync(VGA_HS),
	.o_vsync(VGA_VS),
	.o_hblank(VGA_HB),
	.o_vblank(VGA_VB),
	.i_center(2'b11),
	.i_pal(pal),
	.i_wide(1'b0),

	.i_extmem_en(mc_loaded),
	.o_extmem_sel(extmem_sel),
	.o_extmem_r_wn(vic_wr_n),
	.o_extmem_addr(vic_addr),
	.o_extmem_data(vic_data),
	.i_extmem_data(mc_data),
	.o_io2_sel(vic_io2_sel),
	.o_io3_sel(vic_io3_sel),
	.o_blk123_sel(vic_blk123_sel),
	.o_blk5_sel(vic_blk5_sel),
	.o_ram123_sel(vic_ram123_sel),

	.ps2_key(v20_key),
	.tape_play(key_play),

	.o_audio(audio),

	.cass_write(),
	.cass_read(cass_read),
	.cass_motor(cass_motor),
	.cass_sw(cass_sense),

	.rom_std(1'b0),
	.conf_clk(clk_sys),
	.conf_ai(dl_addr),
	.conf_di(dl_data),
	.conf_wr(dl_wr)
);

wire v20_iec_atn_o;
wire v20_iec_data_o;
wire v20_iec_clk_o;

wire [5:0] audio;
assign AUDIO_L = {1'b0,audio, 9'd0} + {cass_aud,10'd0};
assign AUDIO_R = AUDIO_L;

wire [3:0] r,g,b;
assign VGA_R = {r,r};
assign VGA_G = {g,g};
assign VGA_B = {b,b};

/////////////////  PROMPT DETECTION  //////////////
// o_extmem_addr is the CPU address bus. The KERNAL waits for a key in its loop at
// $E5E8-$E5F0 (PAL and NTSC kernals); at the BASIC prompt the CPU spends most of its time
// there. Measured over ~30 ms windows of clk_sys.
initial at_prompt = 1'b0;
always @(posedge clk_sys) begin
	reg [19:0] win = 0;
	reg [19:0] hits = 0;
	win <= win + 1'd1;
	if (vic_addr >= 16'hE5E8 && vic_addr <= 16'hE5F0) hits <= hits + 1'd1;
	if (&win) begin
		at_prompt <= !reset && hits > 20'd65536;
		hits <= 0;
	end
end

// $0302 (IMAIN) points here (the KERNAL's vector table at $E451)
initial basic_main = 1'b0;
always @(posedge clk_sys) basic_main <= vic_addr == 16'hC483;

///////////////////  DRIVE  ///////////////////////

wire c1541_iec_data_o;
wire c1541_iec_clk_o;

reg drive_mounted = 0;
always @(posedge clk_sys) if(img_mounted[0]) drive_mounted <= |img_size;

// One drive (#8, 1541 or 1581); drive 9's ports read as idle.
wire [31:0] drv_sd_lba[1];
wire  [5:0] drv_sd_blk_cnt[1];
wire  [7:0] drv_sd_buff_din[1];
assign sd_lba[0] = drv_sd_lba[0];           assign sd_lba[1] = 32'd0;
assign sd_blk_cnt[0] = drv_sd_blk_cnt[0];   assign sd_blk_cnt[1] = 6'd0;
assign sd_buff_din[0] = drv_sd_buff_din[0]; assign sd_buff_din[1] = 8'h00;
assign sd_rd[1] = 1'b0;
assign sd_wr[1] = 1'b0;

iec_drive #(.PARPORT(0), .DRIVES(1)) iec_drive
(
	.clk(clk_sys),
	.reset(reset | tv_reset | ~drive_mounted),
	.ce(ce_c1541),

	.iec_atn_i(v20_iec_atn_o),
	.iec_data_i(v20_iec_data_o),
	.iec_clk_i(v20_iec_clk_o),
	.iec_data_o(c1541_iec_data_o),
	.iec_clk_o(c1541_iec_clk_o),

	.pause(1'b0),

	.img_mounted(img_mounted[0]),
	.img_size(img_size),
	.img_readonly(img_readonly),
	.img_type(img_type),
	.drive_rpm(3'd0),
	.drive_wobble(1'b0),

	.led(),
	.out_track(),
	.out_we(),
	.disk_ready(disk_ready_out),

	.par_data_i(8'hFF),
	.par_stb_i(1'b1),
	.par_data_o(),
	.par_stb_o(),

	.clk_sys(clk_sys),

	.sd_lba(drv_sd_lba),
	.sd_blk_cnt(drv_sd_blk_cnt),
	.sd_rd(sd_rd[0]),
	.sd_wr(sd_wr[0]),
	.sd_ack(sd_ack[0]),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(drv_sd_buff_din),
	.sd_buff_wr(sd_buff_wr),

	// System ROM: the first 16 KB are the 1541's (boot.rom layout of VIC20_MiSTer)
	.rom_addr({2'b00, ioctl_addr[13:0]}),
	.rom_data(ioctl_data),
	.rom_wr(ioctl_wr && ioctl_download && load_rom && (ioctl_addr[24:14] == 0)),
	.rom_std(1'b0),

	.DDRAM_BUSY(DDRAM_BUSY),
	.DDRAM_BURSTCNT(DDRAM_BURSTCNT),
	.DDRAM_ADDR(DDRAM_ADDR),
	.DDRAM_DOUT(DDRAM_DOUT),
	.DDRAM_DOUT_READY(DDRAM_DOUT_READY),
	.DDRAM_RD(DDRAM_RD),
	.DDRAM_WE(DDRAM_WE),
	.DDRAM_DIN(DDRAM_DIN),
	.DDRAM_BE(DDRAM_BE)
);

reg ce_c1541;
always @(negedge clk_sys) begin
	int sum = 0;
	int msum;

	msum <= pal ? 35468944 : 32727260;

	ce_c1541 <= 0;
	sum = sum + 16000000;
	if(sum >= msum) begin
		sum = sum - msum;
		ce_c1541 <= 1;
	end
end

////////////////////  TAPE  ///////////////////////

ddram ddram
(
	.reset(reset),
	.DDRAM_CLK(clk_sys),
	.DDRAM_BUSY(TDDRAM_BUSY),
	.DDRAM_BURSTCNT(TDDRAM_BURSTCNT),
	.DDRAM_ADDR(TDDRAM_ADDR),
	.DDRAM_DOUT(TDDRAM_DOUT),
	.DDRAM_DOUT_READY(TDDRAM_DOUT_READY),
	.DDRAM_RD(TDDRAM_RD),
	.DDRAM_DIN(TDDRAM_DIN),
	.DDRAM_BE(TDDRAM_BE),
	.DDRAM_WE(TDDRAM_WE),

	.addr((ioctl_download & load_tap) ? ioctl_addr : tap_play_addr),
	.dout(tap_data),
	.din(ioctl_data),
	.we(tap_wr),
	.rd(tap_rd),
	.ready(tap_data_ready)
);

reg tap_wr;
reg [1:0] tap_version;
reg tap_wait = 0;
// ddram.sv drops a write that arrives while TDDRAM_BUSY (a PSRAM write outlasts its ready);
// on MiSTer the DDR3 is never busy that long. sim/tape_tb.sv.
assign ioctl_wait = tap_wait | prg_hold | (ioctl_download & load_tap & TDDRAM_BUSY);

always @(posedge clk_sys) begin
	reg old_reset;

	old_reset <= reset;
	if(~old_reset && reset) tap_wait <= 0;

	tap_wr <= 0;
	if(ioctl_wr & load_tap) begin
		tap_wait <= 1;
		tap_wr <= 1;
		if (ioctl_addr == 'h0C) tap_version <= ioctl_data[1:0];
	end
	else if(~tap_wr & tap_wait & tap_data_ready) begin
		tap_wait <= 0;
	end
end

reg        tap_rd;
wire       tap_finish;
reg [24:0] tap_play_addr;
reg [24:0] tap_last_addr;
wire [7:0] tap_data;
wire       tap_data_ready;
wire       tap_reset = reset | (ioctl_download & load_tap) | status[18] | tap_finish | (cass_run & ((tap_last_addr - tap_play_addr) < 80));
reg        tap_wrreq;
wire       tap_wrfull;
wire       tap_loaded = (tap_play_addr < tap_last_addr);
wire       cass_sense;
reg        tap_autoplay = 0;

always @(posedge clk_sys) begin
	reg tap_cycle = 0;

	if(tap_reset) begin
		//C1530 module requires one more byte at the end due to fifo early check.
		tap_last_addr <= (ioctl_download & load_tap) ? ioctl_addr+2'd2 : 25'd0;
		tap_play_addr <= 0;
		tap_rd <= 0;
		tap_cycle <= 0;
		tap_autoplay <= ioctl_download & load_tap & ~status[22];
	end
	else begin
		tap_rd <= 0;
		tap_wrreq <= 0;
		tap_autoplay <= 0;

		if(~tap_rd & ~tap_wrreq) begin
			if(tap_cycle) begin
				if(tap_data_ready) begin
					tap_play_addr <= tap_play_addr + 1'd1;
					tap_cycle <= 0;
					tap_wrreq <= 1;
				end
			end
			else begin
				if(~tap_wrfull & tap_loaded) begin
					tap_rd <= 1;
					tap_cycle <= 1;
				end
			end
		end
	end
end

wire cass_motor;
wire cass_run;
wire cass_read;
wire cass_aud = cass_read & status[17] & ~cass_sense & ~cass_motor;

c1530 c1530
(
	.clk32(clk_sys),
	.restart_tape(tap_reset),

	.wav_mode(1'b0),
	.tap_version(tap_version),

	.host_tap_in(tap_data),
	.host_tap_wrreq(tap_wrreq),
	.tap_fifo_wrfull(tap_wrfull),
	.tap_fifo_error(tap_finish),

	.osd_play_stop_toggle(status[16]|key_play|tap_autoplay),
	.cass_motor(cass_motor),
	.cass_sense(cass_sense),
	.cass_read(cass_read),
	.cass_run(cass_run),
	.ear_input(1'b0)
);

endmodule
