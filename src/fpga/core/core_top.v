//
// Commodore VIC-20 core top level for the Analogue Pocket
//
// Instantiated by the real top-level: apf_top. Wraps vic20_top (VIC20_MiSTer's VIC20.sv
// machine); see docs/architecture.md for how the APF side maps onto the MiSTer interfaces.
//

`default_nettype none

module core_top (

//
// physical connections
//

///////////////////////////////////////////////////
// clock inputs 74.25mhz. not phase aligned, so treat these domains as asynchronous

input   wire            clk_74a, // mainclk1
input   wire            clk_74b, // mainclk1 

///////////////////////////////////////////////////
// cartridge interface
// switches between 3.3v and 5v mechanically
// output enable for multibit translators controlled by pic32

// GBA AD[15:8]
inout   wire    [7:0]   cart_tran_bank2,
output  wire            cart_tran_bank2_dir,

// GBA AD[7:0]
inout   wire    [7:0]   cart_tran_bank3,
output  wire            cart_tran_bank3_dir,

// GBA A[23:16]
inout   wire    [7:0]   cart_tran_bank1,
output  wire            cart_tran_bank1_dir,

// GBA [7] PHI#
// GBA [6] WR#
// GBA [5] RD#
// GBA [4] CS1#/CS#
//     [3:0] unwired
inout   wire    [7:4]   cart_tran_bank0,
output  wire            cart_tran_bank0_dir,

// GBA CS2#/RES#
inout   wire            cart_tran_pin30,
output  wire            cart_tran_pin30_dir,
// when GBC cart is inserted, this signal when low or weak will pull GBC /RES low with a special circuit
// the goal is that when unconfigured, the FPGA weak pullups won't interfere.
// thus, if GBC cart is inserted, FPGA must drive this high in order to let the level translators
// and general IO drive this pin.
output  wire            cart_pin30_pwroff_reset,

// GBA IRQ/DRQ
inout   wire            cart_tran_pin31,
output  wire            cart_tran_pin31_dir,

// infrared
input   wire            port_ir_rx,
output  wire            port_ir_tx,
output  wire            port_ir_rx_disable, 

// GBA link port
inout   wire            port_tran_si,
output  wire            port_tran_si_dir,
inout   wire            port_tran_so,
output  wire            port_tran_so_dir,
inout   wire            port_tran_sck,
output  wire            port_tran_sck_dir,
inout   wire            port_tran_sd,
output  wire            port_tran_sd_dir,
 
///////////////////////////////////////////////////
// cellular psram 0 and 1, two chips (64mbit x2 dual die per chip)

output  wire    [21:16] cram0_a,
inout   wire    [15:0]  cram0_dq,
input   wire            cram0_wait,
output  wire            cram0_clk,
output  wire            cram0_adv_n,
output  wire            cram0_cre,
output  wire            cram0_ce0_n,
output  wire            cram0_ce1_n,
output  wire            cram0_oe_n,
output  wire            cram0_we_n,
output  wire            cram0_ub_n,
output  wire            cram0_lb_n,

output  wire    [21:16] cram1_a,
inout   wire    [15:0]  cram1_dq,
input   wire            cram1_wait,
output  wire            cram1_clk,
output  wire            cram1_adv_n,
output  wire            cram1_cre,
output  wire            cram1_ce0_n,
output  wire            cram1_ce1_n,
output  wire            cram1_oe_n,
output  wire            cram1_we_n,
output  wire            cram1_ub_n,
output  wire            cram1_lb_n,

///////////////////////////////////////////////////
// sdram, 512mbit 16bit

output  wire    [12:0]  dram_a,
output  wire    [1:0]   dram_ba,
inout   wire    [15:0]  dram_dq,
output  wire    [1:0]   dram_dqm,
output  wire            dram_clk,
output  wire            dram_cke,
output  wire            dram_ras_n,
output  wire            dram_cas_n,
output  wire            dram_we_n,

///////////////////////////////////////////////////
// sram, 1mbit 16bit

output  wire    [16:0]  sram_a,
inout   wire    [15:0]  sram_dq,
output  wire            sram_oe_n,
output  wire            sram_we_n,
output  wire            sram_ub_n,
output  wire            sram_lb_n,

///////////////////////////////////////////////////
// vblank driven by dock for sync in a certain mode

input   wire            vblank,

///////////////////////////////////////////////////
// i/o to 6515D breakout usb uart

output  wire            dbg_tx,
input   wire            dbg_rx,

///////////////////////////////////////////////////
// i/o pads near jtag connector user can solder to

output  wire            user1,
input   wire            user2,

///////////////////////////////////////////////////
// RFU internal i2c bus 

inout   wire            aux_sda,
output  wire            aux_scl,

///////////////////////////////////////////////////
// RFU, do not use
output  wire            vpll_feed,


//
// logical connections
//

///////////////////////////////////////////////////
// video, audio output to scaler
output  wire    [23:0]  video_rgb,
output  wire            video_rgb_clock,
output  wire            video_rgb_clock_90,
output  wire            video_de,
output  wire            video_skip,
output  wire            video_vs,
output  wire            video_hs,
    
output  wire            audio_mclk,
input   wire            audio_adc,
output  wire            audio_dac,
output  wire            audio_lrck,

///////////////////////////////////////////////////
// bridge bus connection
// synchronous to clk_74a
output  wire            bridge_endian_little,
input   wire    [31:0]  bridge_addr,
input   wire            bridge_rd,
output  reg     [31:0]  bridge_rd_data,
input   wire            bridge_wr,
input   wire    [31:0]  bridge_wr_data,

///////////////////////////////////////////////////
// controller data
// 
// key bitmap:
//   [0]    dpad_up
//   [1]    dpad_down
//   [2]    dpad_left
//   [3]    dpad_right
//   [4]    face_a
//   [5]    face_b
//   [6]    face_x
//   [7]    face_y
//   [8]    trig_l1
//   [9]    trig_r1
//   [10]   trig_l2
//   [11]   trig_r2
//   [12]   trig_l3
//   [13]   trig_r3
//   [14]   face_select
//   [15]   face_start
//   [31:28] type
// joy values - unsigned
//   [ 7: 0] lstick_x
//   [15: 8] lstick_y
//   [23:16] rstick_x
//   [31:24] rstick_y
// trigger values - unsigned
//   [ 7: 0] ltrig
//   [15: 8] rtrig
//
input   wire    [31:0]  cont1_key,
input   wire    [31:0]  cont2_key,
input   wire    [31:0]  cont3_key,
input   wire    [31:0]  cont4_key,
input   wire    [31:0]  cont1_joy,
input   wire    [31:0]  cont2_joy,
input   wire    [31:0]  cont3_joy,
input   wire    [31:0]  cont4_joy,
input   wire    [15:0]  cont1_trig,
input   wire    [15:0]  cont2_trig,
input   wire    [15:0]  cont3_trig,
input   wire    [15:0]  cont4_trig
    
);


// not using the IR port, so turn off both the LED, and
// disable the receive circuit to save power
assign port_ir_tx = 0;
assign port_ir_rx_disable = 1;

// bridge endianness
assign bridge_endian_little = 0;

// cart is unused, so set all level translators accordingly
// directions are 0:IN, 1:OUT
assign cart_tran_bank3 = 8'hzz;
assign cart_tran_bank3_dir = 1'b0;
assign cart_tran_bank2 = 8'hzz;
assign cart_tran_bank2_dir = 1'b0;
assign cart_tran_bank1 = 8'hzz;
assign cart_tran_bank1_dir = 1'b0;
assign cart_tran_bank0 = 4'hf;
assign cart_tran_bank0_dir = 1'b1;
assign cart_tran_pin30 = 1'b0;      // reset or cs2, we let the hw control it by itself
assign cart_tran_pin30_dir = 1'bz;
assign cart_pin30_pwroff_reset = 1'b0;  // hardware can control this
assign cart_tran_pin31 = 1'bz;      // input
assign cart_tran_pin31_dir = 1'b0;  // input

// link port is unused, set to input only to be safe
assign port_tran_so = 1'bz;
assign port_tran_so_dir = 1'b0;
assign port_tran_si = 1'bz;
assign port_tran_si_dir = 1'b0;
assign port_tran_sck = 1'bz;
assign port_tran_sck_dir = 1'b0;
assign port_tran_sd = 1'bz;
assign port_tran_sd_dir = 1'b0;

// cram0 holds the 1541 G64 images (ddram_psram); cram1 and SRAM are unused
assign sram_a = 'h0;
assign sram_dq = {16{1'bZ}};
assign sram_oe_n  = 1;
assign sram_we_n  = 1;
assign sram_ub_n  = 1;
assign sram_lb_n  = 1;

assign dbg_tx = 1'bZ;
assign user1 = 1'bZ;
assign aux_scl = 1'bZ;
assign vpll_feed = 1'bZ;

/* ------------------------------------------------------------------------------ */
/* ------------------------------------ Clocks ---------------------------------- */
/* ------------------------------------------------------------------------------ */

wire clk_sys, clk_sys_90;
wire pll_locked;
wire pll_locked_s;
synch_3 s_lock(pll_locked, pll_locked_s, clk_74a);

wire [63:0] reconfig_to_pll;
wire [63:0] reconfig_from_pll;

pll_vic20 pll (
	.refclk            ( clk_74a ),
	.rst               ( 1'b0 ),
	.outclk_0          ( clk_sys ),
	.outclk_1          ( clk_sys_90 ),
	.locked            ( pll_locked ),
	.reconfig_to_pll   ( reconfig_to_pll ),
	.reconfig_from_pll ( reconfig_from_pll )
);

wire        cfg_waitrequest;
reg         cfg_write;
reg   [5:0] cfg_address;
reg  [31:0] cfg_data;

pll_cfg pll_cfg (
	.mgmt_clk          ( clk_74a ),
	.mgmt_reset        ( 1'b0 ),
	.mgmt_waitrequest  ( cfg_waitrequest ),
	.mgmt_read         ( 1'b0 ),
	.mgmt_readdata     ( ),
	.mgmt_write        ( cfg_write ),
	.mgmt_address      ( cfg_address ),
	.mgmt_writedata    ( cfg_data ),
	.reconfig_to_pll   ( reconfig_to_pll ),
	.reconfig_from_pll ( reconfig_from_pll )
);

// PAL/NTSC: rewrite the PLL's fractional K (as VIC20.sv does); K values match pll_vic20.v.
// ntsc_r is the standard the PLL runs; vic20_top resets the VIC-20 when it changes.
reg ntsc_r = 1'b0;
always @(posedge clk_74a) begin
	reg  [2:0] pstate = 3'd0;
	reg [24:0] delay = 25'd0;

	cfg_write <= 1'b0;

	if (cfg_ntsc != ntsc_r) begin
		if (delay < 25'd11_137_500) delay <= delay + 25'd1;   // 150 ms
		else begin
			pstate <= 3'd1;
			ntsc_r <= cfg_ntsc;
			delay <= 25'd0;
		end
	end else
		delay <= 25'd0;

	if (!cfg_waitrequest) begin
		if (pstate != 3'd0) pstate <= pstate + 3'd1;
		case (pstate)
			3'd1: begin cfg_address <= 6'd0; cfg_data <= 32'd0; cfg_write <= 1'b1; end
			3'd3: begin cfg_address <= 6'd7; cfg_data <= ntsc_r ? 32'd224793671 : 32'd2762262895; cfg_write <= 1'b1; end
			3'd5: begin cfg_address <= 6'd2; cfg_data <= 32'd0; cfg_write <= 1'b1; end
			default: ;
		endcase
	end
end

/* ------------------------------------------------------------------------------ */
/* --------------------------- Host/target commands ----------------------------- */
/* ------------------------------------------------------------------------------ */

    wire            reset_n;                // driven by host commands, can be used as core-wide reset
    wire    [31:0]  cmd_bridge_rd_data;

    wire            status_boot_done = pll_locked_s;
    wire            status_setup_done = pll_locked_s; // rising edge triggers a target command
    wire            status_running = reset_n; // we are running as soon as reset_n goes high

    wire            dataslot_requestread;
    wire    [15:0]  dataslot_requestread_id;
    wire            dataslot_requestread_ack = 1;
    wire            dataslot_requestread_ok = 1;

    wire            dataslot_requestwrite;
    wire    [15:0]  dataslot_requestwrite_id;
    wire    [31:0]  dataslot_requestwrite_size;
    wire            dataslot_requestwrite_ack = 1;
    wire            dataslot_requestwrite_ok = 1;

    wire            dataslot_update;
    wire    [15:0]  dataslot_update_id;
    wire    [31:0]  dataslot_update_size;

    wire            dataslot_allcomplete;

    wire     [31:0] rtc_epoch_seconds;
    wire     [31:0] rtc_date_bcd;
    wire     [31:0] rtc_time_bcd;
    wire            rtc_valid;

    wire            savestate_supported = 0;
    wire    [31:0]  savestate_addr = 0;
    wire    [31:0]  savestate_size = 0;
    wire    [31:0]  savestate_maxloadsize = 0;

    wire            savestate_start;
    wire            savestate_start_ack = 0;
    wire            savestate_start_busy = 0;
    wire            savestate_start_ok = 0;
    wire            savestate_start_err = 0;

    wire            savestate_load;
    wire            savestate_load_ack = 0;
    wire            savestate_load_busy = 0;
    wire            savestate_load_ok = 0;
    wire            savestate_load_err = 0;

    wire            osnotify_inmenu;

    wire            target_dataslot_read;
    wire            target_dataslot_write;
    wire            target_dataslot_getfile = 0;
    wire            target_dataslot_openfile = 0;

    wire            target_dataslot_ack;
    wire            target_dataslot_done;
    wire    [2:0]   target_dataslot_err;

    wire    [15:0]  target_dataslot_id;
    wire    [31:0]  target_dataslot_slotoffset;
    wire    [31:0]  target_dataslot_bridgeaddr;
    wire    [31:0]  target_dataslot_length;

    wire    [31:0]  target_buffer_param_struct;
    wire    [31:0]  target_buffer_resp_struct;

    wire    [9:0]   datatable_addr;
    wire            datatable_wren = 0;
    wire    [31:0]  datatable_data = 0;
    wire    [31:0]  datatable_q;

core_bridge_cmd icb (

    .clk                ( clk_74a ),
    .reset_n            ( reset_n ),

    .bridge_endian_little   ( bridge_endian_little ),
    .bridge_addr            ( bridge_addr ),
    .bridge_rd              ( bridge_rd ),
    .bridge_rd_data         ( cmd_bridge_rd_data ),
    .bridge_wr              ( bridge_wr ),
    .bridge_wr_data         ( bridge_wr_data ),

    .status_boot_done       ( status_boot_done ),
    .status_setup_done      ( status_setup_done ),
    .status_running         ( status_running ),

    .dataslot_requestread       ( dataslot_requestread ),
    .dataslot_requestread_id    ( dataslot_requestread_id ),
    .dataslot_requestread_ack   ( dataslot_requestread_ack ),
    .dataslot_requestread_ok    ( dataslot_requestread_ok ),

    .dataslot_requestwrite      ( dataslot_requestwrite ),
    .dataslot_requestwrite_id   ( dataslot_requestwrite_id ),
    .dataslot_requestwrite_size ( dataslot_requestwrite_size ),
    .dataslot_requestwrite_ack  ( dataslot_requestwrite_ack ),
    .dataslot_requestwrite_ok   ( dataslot_requestwrite_ok ),

    .dataslot_update            ( dataslot_update ),
    .dataslot_update_id         ( dataslot_update_id ),
    .dataslot_update_size       ( dataslot_update_size ),

    .dataslot_allcomplete   ( dataslot_allcomplete ),

    .rtc_epoch_seconds      ( rtc_epoch_seconds ),
    .rtc_date_bcd           ( rtc_date_bcd ),
    .rtc_time_bcd           ( rtc_time_bcd ),
    .rtc_valid              ( rtc_valid ),

    .savestate_supported    ( savestate_supported ),
    .savestate_addr         ( savestate_addr ),
    .savestate_size         ( savestate_size ),
    .savestate_maxloadsize  ( savestate_maxloadsize ),

    .savestate_start        ( savestate_start ),
    .savestate_start_ack    ( savestate_start_ack ),
    .savestate_start_busy   ( savestate_start_busy ),
    .savestate_start_ok     ( savestate_start_ok ),
    .savestate_start_err    ( savestate_start_err ),

    .savestate_load         ( savestate_load ),
    .savestate_load_ack     ( savestate_load_ack ),
    .savestate_load_busy    ( savestate_load_busy ),
    .savestate_load_ok      ( savestate_load_ok ),
    .savestate_load_err     ( savestate_load_err ),

    .osnotify_inmenu        ( osnotify_inmenu ),

    .target_dataslot_read       ( target_dataslot_read ),
    .target_dataslot_write      ( target_dataslot_write ),
    .target_dataslot_getfile    ( target_dataslot_getfile ),
    .target_dataslot_openfile   ( target_dataslot_openfile ),

    .target_dataslot_ack        ( target_dataslot_ack ),
    .target_dataslot_done       ( target_dataslot_done ),
    .target_dataslot_err        ( target_dataslot_err ),

    .target_dataslot_id         ( target_dataslot_id ),
    .target_dataslot_slotoffset ( target_dataslot_slotoffset ),
    .target_dataslot_bridgeaddr ( target_dataslot_bridgeaddr ),
    .target_dataslot_length     ( target_dataslot_length ),

    .target_buffer_param_struct ( target_buffer_param_struct ),
    .target_buffer_resp_struct  ( target_buffer_resp_struct ),

    .datatable_addr         ( datatable_addr ),
    .datatable_wren         ( datatable_wren ),
    .datatable_data         ( datatable_data ),
    .datatable_q            ( datatable_q )
);

/* ------------------------------------------------------------------------------ */
/* ---------------------------- Bridge read multiplexer ------------------------- */
/* ------------------------------------------------------------------------------ */

wire [31:0] media_bridge_rd_data;
reg  [31:0] cfg_bridge_rd_data;

always @(*) begin
	casex (bridge_addr)
	32'h10xxxxxx: bridge_rd_data <= media_bridge_rd_data;
	32'h80xxxxxx: bridge_rd_data <= cfg_bridge_rd_data;
	32'hF8xxxxxx: bridge_rd_data <= cmd_bridge_rd_data;
	default:      bridge_rd_data <= 0;
	endcase
end

/* ------------------------------------------------------------------------------ */
/* -------------------------- Settings (interact.json) -------------------------- */
/* ------------------------------------------------------------------------------ */
// One register per menu entry; addresses must match interact.json.

reg        cfg_reset_t  = 1'b0;   // toggles on "Reset"
reg        cfg_detach_t = 1'b0;   // toggles on "Reset & Detach Cart"
reg        cfg_play_t   = 1'b0;   // toggles on "Tape Play/Pause"
reg  [2:0] cfg_mem      = 3'd0;   // 0 auto, 1 none, 2 3K, 3 8K, 4 16K, 5 24K, 6 35K
reg        cfg_ntsc     = 1'b0;
reg  [1:0] cfg_padmode  = 2'd0;   // 0 joystick, 2 keys
reg        cfg_auto     = 1'b1;   // autostart programs, disks and tapes
reg        cfg_cartwr   = 1'b0;   // cartridge RAM writable
reg        cfg_wp       = 1'b0;   // disk write protected
reg        cfg_tapesnd  = 1'b0;
reg        cfg_paddle   = 1'b0;   // analog sticks drive the paddles

always @(posedge clk_74a) begin
	if (bridge_wr && bridge_addr[31:8] == 24'h800000) begin
		case (bridge_addr[7:0])
		8'h00: cfg_reset_t  <= ~cfg_reset_t;
		8'h04: cfg_detach_t <= ~cfg_detach_t;
		8'h08: cfg_mem      <= bridge_wr_data[2:0];
		8'h0C: cfg_ntsc     <= bridge_wr_data[0];
		8'h14: cfg_padmode  <= bridge_wr_data[1:0];
		8'h1C: cfg_auto     <= bridge_wr_data[0];
		8'h20: cfg_cartwr   <= bridge_wr_data[0];
		8'h24: cfg_wp       <= bridge_wr_data[0];
		8'h28: cfg_tapesnd  <= bridge_wr_data[0];
		8'h2C: cfg_paddle   <= bridge_wr_data[0];
		8'h34: cfg_play_t   <= ~cfg_play_t;
		default: ;
		endcase
	end
	case (bridge_addr[7:0])
	8'h08: cfg_bridge_rd_data <= cfg_mem;
	8'h0C: cfg_bridge_rd_data <= cfg_ntsc;
	8'h14: cfg_bridge_rd_data <= cfg_padmode;
	8'h1C: cfg_bridge_rd_data <= cfg_auto;
	8'h20: cfg_bridge_rd_data <= cfg_cartwr;
	8'h24: cfg_bridge_rd_data <= cfg_wp;
	8'h28: cfg_bridge_rd_data <= cfg_tapesnd;
	8'h2C: cfg_bridge_rd_data <= cfg_paddle;
	default: cfg_bridge_rd_data <= 0;
	endcase
end

// quasi-static settings, synchronised as a bundle
wire [13:0] cfg_s;
synch_3 #(.WIDTH(14)) s_cfg(
	{cfg_paddle, cfg_tapesnd, cfg_wp, cfg_cartwr, cfg_auto, cfg_padmode, cfg_mem, cfg_play_t, cfg_detach_t, cfg_reset_t},
	cfg_s, clk_sys);
wire       reset_t_s  = cfg_s[0];
wire       detach_t_s = cfg_s[1];
wire       play_t_s   = cfg_s[2];
wire [2:0] mem_s      = cfg_s[5:3];
wire [1:0] padmode_s  = cfg_s[7:6];
wire       auto_s     = cfg_s[8];
wire       cartwr_s   = cfg_s[9];
wire       wp_s       = cfg_s[10];
wire       tapesnd_s  = cfg_s[11];
wire       paddle_s   = cfg_s[12];

// menu actions become pulses of a few hundred clocks
reg  [2:0] act_d;
reg  [8:0] reset_p, detach_p, play_p;
always @(posedge clk_sys) begin
	act_d <= {play_t_s, detach_t_s, reset_t_s};
	reset_p  <= (reset_t_s  != act_d[0]) ? 9'h1FF : reset_p  - (reset_p  != 0);
	detach_p <= (detach_t_s != act_d[1]) ? 9'h1FF : detach_p - (detach_p != 0);
	play_p   <= (play_t_s   != act_d[2]) ? 9'h1FF : play_p   - (play_p   != 0);
end

wire reset_n_s;
synch_3 s_rst(reset_n, reset_n_s, clk_sys);

/* ------------------------------------------------------------------------------ */
/* ---------------------------------- Controllers ------------------------------- */
/* ------------------------------------------------------------------------------ */

wire [31:0] cont1_key_s, cont2_key_s, cont3_key_s;
wire [31:0] cont1_joy_s, cont2_joy_s, cont3_joy_s;
wire [15:0] cont3_trig_s;
synch_3 #(.WIDTH(32)) s_c1k(cont1_key, cont1_key_s, clk_sys);
synch_3 #(.WIDTH(32)) s_c2k(cont2_key, cont2_key_s, clk_sys);
synch_3 #(.WIDTH(32)) s_c3k(cont3_key, cont3_key_s, clk_sys);
synch_3 #(.WIDTH(32)) s_c1j(cont1_joy, cont1_joy_s, clk_sys);
synch_3 #(.WIDTH(32)) s_c2j(cont2_joy, cont2_joy_s, clk_sys);
synch_3 #(.WIDTH(32)) s_c3j(cont3_joy, cont3_joy_s, clk_sys);
synch_3 #(.WIDTH(16)) s_c3t(cont3_trig, cont3_trig_s, clk_sys);

// MiSTer joystick encoding: [0] right [1] left [2] down [3] up [4] fire
function [15:0] pad2joy(input [31:0] k);
	pad2joy = {11'd0, k[4], k[0], k[1], k[2], k[3]};
endfunction

// Select opens the on-screen keyboard; Start switches joystick <-> keys.
wire        osk_visible;
wire  [2:0] osk_row;
wire  [3:0] osk_col;
wire  [2:0] osk_mods;
wire  [7:0] osk_key;
wire        osk_mode_next;
wire        port_swap_t;

osk_ctrl osk_ctrl (
	.clk          ( clk_sys ),
	.reset        ( ~reset_n_s ),
	.pad          ( cont1_key_s[15:0] ),
	.visible      ( osk_visible ),
	.cur_row      ( osk_row ),
	.cur_col      ( osk_col ),
	.mods         ( osk_mods ),
	.key          ( osk_key ),
	.mouse_toggle ( osk_mode_next ),
	.select_long  ( port_swap_t )
);

localparam PM_JOY = 2'd0, PM_MOUSE = 2'd1, PM_KEYS = 2'd2;
reg [1:0] pad_mode = PM_JOY;
reg [1:0] padmode_d = PM_JOY;
always @(posedge clk_sys) begin
	padmode_d <= padmode_s;
	if (padmode_s != padmode_d) pad_mode <= (padmode_s == PM_KEYS) ? PM_KEYS : PM_JOY;
	else if (osk_mode_next)
		pad_mode <= pad_mode == PM_JOY ? PM_KEYS : PM_JOY;
end
wire pad_joy_mode   = pad_mode == PM_JOY   && !osk_visible;
wire pad_keys_mode  = pad_mode == PM_KEYS  && !osk_visible;

// show JOYSTICK / KEYS for ~2 s whenever the mode changes
reg [25:0] badge_timer = 26'd0;
reg  [1:0] mode_d = PM_JOY;
reg  [2:0] badge_mode = 3'd0;
always @(posedge clk_sys) begin
	mode_d <= pad_mode;
	if (pad_mode != mode_d) begin badge_timer <= 26'd64_000_000; badge_mode <= {1'b0, pad_mode}; end
	else if (badge_timer != 0) badge_timer <= badge_timer - 26'd1;
end

// the VIC-20 has one joystick port: pads 1 and 2 both drive it
// with Paddles on, A is also the paddle's button (bit 5, VIC20.sv's "Paddle Fire")
wire [15:0] joyA = pad_joy_mode ? (pad2joy(cont1_key_s) | {10'd0, paddle_s & cont1_key_s[4], 5'd0}) : 16'd0;
wire [15:0] joyB = pad2joy(cont2_key_s) | {10'd0, paddle_s & cont2_key_s[4], 5'd0};

// Paddles: the left analog stick's X of Dock pads 1 and 2 (type 3), when enabled
wire [7:0] pd1 = (paddle_s && cont1_key_s[31:28] == 4'h3) ? cont1_joy_s[7:0] : 8'd0;
wire [7:0] pd2 = (paddle_s && cont2_key_s[31:28] == 4'h3) ? cont2_joy_s[7:0] : 8'd0;

// keys typed by pad 1 (HID usages, see hid_c64.sv for what they are on the C64)
function [7:0] k(input b, input [7:0] usage); k = b ? usage : 8'h00; endfunction
wire [15:0] p = cont1_key_s[15:0];
localparam [7:0] U_SPACE = 8'h2C, U_RETURN = 8'h28, U_RUNSTOP = 8'h29, U_F1 = 8'h3A, U_F3 = 8'h3C,
                 U_F5 = 8'h3E, U_F7 = 8'h40;
wire  [7:0] auto_key;
wire        auto_shift;
wire [79:0] pad_keys =
	(auto_key != 8'h00) ? {auto_key, auto_shift ? 8'hE1 : 8'h00, 64'd0} :
	osk_visible    ? {osk_key, osk_mods[0] ? 8'hE0 : 8'h00, osk_mods[1] ? 8'hE1 : 8'h00, osk_mods[2] ? 8'hE2 : 8'h00, 48'd0} :
	pad_keys_mode  ? {k(p[0], 8'h52), k(p[1], 8'h51), k(p[2], 8'h50), k(p[3], 8'h4F),     // cursor keys
	                  k(p[4], U_SPACE), k(p[5], U_RETURN), k(p[6], U_F1), k(p[7], U_F3),
	                  k(p[8], U_RUNSTOP), k(p[9], U_F5)} :
	                 {k(p[5], U_SPACE), k(p[6], U_RETURN), k(p[7], U_F1), k(p[8], U_RUNSTOP), k(p[9], U_F7), 40'd0};

// Dock keyboard on player 3 (type nibble 4)
wire        kbd_present   = cont3_key_s[31:28] == 4'h4;

wire [10:0] ps2_key;

hid_c64 hid (
	.clk           ( clk_sys ),
	.reset         ( ~reset_n_s ),
	.kbd_present   ( kbd_present ),
	.kbd_codes     ( {cont3_joy_s, cont3_trig_s} ),
	.kbd_mods      ( cont3_key_s[15:8] ),
	.pad_keys      ( pad_keys ),
	.mouse_event   ( 1'b0 ),
	.mouse_dx      ( 16'sd0 ),
	.mouse_dy      ( 16'sd0 ),
	.mouse_buttons ( 2'b00 ),
	.ps2_key       ( ps2_key ),
	.ps2_mouse     ( )
);

/* ------------------------------------------------------------------------------ */
/* /* ------------------------------ Files and disks ------------------------------- */
/* ------------------------------------------------------------------------------ */

wire        ioctl_download, ioctl_wr, ioctl_wait;
wire  [7:0] ioctl_index, ioctl_data;
wire [24:0] ioctl_addr;
wire [31:0] ioctl_file_ext;

wire [31:0] sd_lba[2];
wire  [5:0] sd_blk_cnt[2];
wire  [1:0] sd_rd, sd_wr, sd_ack;
wire [13:0] sd_buff_addr;
wire  [7:0] sd_buff_dout;
wire  [7:0] sd_buff_din[2];
wire        sd_buff_wr;
wire  [1:0] img_mounted;
wire [31:0] img_size;
wire  [1:0] img_type;

wire        media_loading, media_disk_inserted, media_tape_loaded;
wire  [2:0] media_load_kind;
wire [11:0] media_load_pct;
wire        ld_start, ld_we, ld_ack;
wire [21:0] ld_addr;
wire  [7:0] ld_wdata;
wire [15:0] ld_rdata;

vic20_media media (
	.clk_74a                    ( clk_74a ),
	.clk_sys                    ( clk_sys ),

	.bridge_addr                ( bridge_addr ),
	.bridge_wr                  ( bridge_wr ),
	.bridge_wr_data             ( bridge_wr_data ),
	.bridge_rd_data             ( media_bridge_rd_data ),

	.target_dataslot_read       ( target_dataslot_read ),
	.target_dataslot_write      ( target_dataslot_write ),
	.target_dataslot_id         ( target_dataslot_id ),
	.target_dataslot_slotoffset ( target_dataslot_slotoffset ),
	.target_dataslot_bridgeaddr ( target_dataslot_bridgeaddr ),
	.target_dataslot_length     ( target_dataslot_length ),
	.target_dataslot_done       ( target_dataslot_done ),

	.dataslot_update            ( dataslot_update ),
	.dataslot_update_id         ( dataslot_update_id ),
	.dataslot_update_size       ( dataslot_update_size ),
	.dataslot_allcomplete       ( dataslot_allcomplete ),
	.datatable_addr             ( datatable_addr ),
	.datatable_q                ( datatable_q ),

	.ioctl_download             ( ioctl_download ),
	.ioctl_index                ( ioctl_index ),
	.ioctl_wr                   ( ioctl_wr ),
	.ioctl_addr                 ( ioctl_addr ),
	.ioctl_data                 ( ioctl_data ),
	.ioctl_file_ext             ( ioctl_file_ext ),
	.ioctl_wait                 ( ioctl_wait ),

	.sd_lba                     ( sd_lba ),
	.sd_rd                      ( sd_rd ),
	.sd_wr                      ( sd_wr ),
	.sd_ack                     ( sd_ack ),
	.sd_buff_addr               ( sd_buff_addr ),
	.sd_buff_dout               ( sd_buff_dout ),
	.sd_buff_din                ( sd_buff_din ),
	.sd_buff_wr                 ( sd_buff_wr ),
	.img_mounted                ( img_mounted ),
	.img_size                   ( img_size ),
	.img_type                   ( img_type ),

	.ld_start                   ( ld_start ),
	.ld_we                      ( ld_we ),
	.ld_addr                    ( ld_addr ),
	.ld_wdata                   ( ld_wdata ),
	.ld_rdata                   ( ld_rdata ),
	.ld_ack                     ( ld_ack ),

	.busy                       ( ),
	.loading                    ( media_loading ),
	.load_kind                  ( media_load_kind ),
	.load_pct                   ( media_load_pct ),
	.disk_inserted              ( media_disk_inserted ),
	.tape_loaded                ( media_tape_loaded )
);

wire        DDRAM_BUSY, DDRAM_DOUT_READY, DDRAM_RD, DDRAM_WE;
wire  [7:0] DDRAM_BURSTCNT, DDRAM_BE;
wire [28:0] DDRAM_ADDR;
wire [63:0] DDRAM_DOUT, DDRAM_DIN;

ddram_psram ddram (
	.clk              ( clk_sys ),
	.reset            ( ~pll_locked ),
	.DDRAM_BUSY       ( DDRAM_BUSY ),
	.DDRAM_BURSTCNT   ( DDRAM_BURSTCNT ),
	.DDRAM_ADDR       ( DDRAM_ADDR ),
	.DDRAM_DOUT       ( DDRAM_DOUT ),
	.DDRAM_DOUT_READY ( DDRAM_DOUT_READY ),
	.DDRAM_RD         ( DDRAM_RD ),
	.DDRAM_WE         ( DDRAM_WE ),
	.DDRAM_DIN        ( DDRAM_DIN ),
	.DDRAM_BE         ( DDRAM_BE ),
	.ld_start         ( ld_start ),
	.ld_we            ( ld_we ),
	.ld_addr          ( ld_addr ),
	.ld_wdata         ( ld_wdata ),
	.ld_rdata         ( ld_rdata ),
	.ld_ack           ( ld_ack ),
	.cram_a           ( cram0_a ),
	.cram_dq          ( cram0_dq ),
	.cram_wait        ( cram0_wait ),
	.cram_clk         ( cram0_clk ),
	.cram_adv_n       ( cram0_adv_n ),
	.cram_cre         ( cram0_cre ),
	.cram_ce0_n       ( cram0_ce0_n ),
	.cram_ce1_n       ( cram0_ce1_n ),
	.cram_oe_n        ( cram0_oe_n ),
	.cram_we_n        ( cram0_we_n ),
	.cram_ub_n        ( cram0_ub_n ),
	.cram_lb_n        ( cram0_lb_n )
);

wire        TDDRAM_BUSY, TDDRAM_DOUT_READY, TDDRAM_RD, TDDRAM_WE;
wire  [7:0] TDDRAM_BURSTCNT, TDDRAM_BE;
wire [28:0] TDDRAM_ADDR;
wire [63:0] TDDRAM_DOUT, TDDRAM_DIN;

// the tape (VIC20.sv's ddram.sv) on the second PSRAM; no loader port
ddram_psram tape_ram (
	.clk              ( clk_sys ),
	.reset            ( ~pll_locked ),
	.DDRAM_BUSY       ( TDDRAM_BUSY ),
	.DDRAM_BURSTCNT   ( TDDRAM_BURSTCNT ),
	.DDRAM_ADDR       ( TDDRAM_ADDR ),
	.DDRAM_DOUT       ( TDDRAM_DOUT ),
	.DDRAM_DOUT_READY ( TDDRAM_DOUT_READY ),
	.DDRAM_RD         ( TDDRAM_RD ),
	.DDRAM_WE         ( TDDRAM_WE ),
	.DDRAM_DIN        ( TDDRAM_DIN ),
	.DDRAM_BE         ( TDDRAM_BE ),
	.ld_start         ( 1'b0 ),
	.ld_we            ( 1'b0 ),
	.ld_addr          ( 22'd0 ),
	.ld_wdata         ( 8'd0 ),
	.ld_rdata         ( ),
	.ld_ack           ( ),
	.cram_a           ( cram1_a ),
	.cram_dq          ( cram1_dq ),
	.cram_wait        ( cram1_wait ),
	.cram_clk         ( cram1_clk ),
	.cram_adv_n       ( cram1_adv_n ),
	.cram_cre         ( cram1_cre ),
	.cram_ce0_n       ( cram1_ce0_n ),
	.cram_ce1_n       ( cram1_ce1_n ),
	.cram_oe_n        ( cram1_oe_n ),
	.cram_we_n        ( cram1_we_n ),
	.cram_ub_n        ( cram1_ub_n ),
	.cram_lb_n        ( cram1_lb_n )
);

/* ------------------------------------------------------------------------------ */
/* ---------------------------------- The VIC-20 ----------------------------------- */
/* ------------------------------------------------------------------------------ */

// VIC20.sv's status[] bit map; bits not listed keep VIC20.sv's defaults (0)
wire [63:0] status;
assign status[0]      = reset_p != 0;                // Reset
assign status[10:1]   = 10'd0;                       // ExtRAM: mem_mode instead
assign status[11]     = cartwr_s;                    // Cart is writable
assign status[15:12]  = 4'd0;                        // centre both; PAL (ntsc_r); loadable kernal
assign status[16]     = play_p != 0;                 // Tape Play/Pause
assign status[17]     = tapesnd_s;                   // Tape Sound
assign status[26:18]  = 9'd0;                        // tape unload, external IEC, tape autoplay
assign status[27]     = detach_p != 0;               // Reset & Detach Cartridge
assign status[63:28]  = 36'd0;

wire        v20_disk_ready, v20_at_prompt, v20_basic_main, v20_prg_loaded;
wire  [7:0] v20_r, v20_g, v20_b;
wire        v20_hs, v20_vs, v20_hb, v20_vb, v20_ce, v20_ntsc;
wire [15:0] audio_l, audio_r;

vic20_top vic20 (
	.clk_sys          ( clk_sys ),
	.pll_locked       ( pll_locked ),
	.reset_req        ( ~reset_n_s ),
	.ntsc_r           ( ntsc_r ),

	.status           ( status ),
	.mem_mode         ( mem_s ),

	.ioctl_download   ( ioctl_download ),
	.ioctl_index      ( ioctl_index ),
	.ioctl_wr         ( ioctl_wr ),
	.ioctl_addr       ( ioctl_addr ),
	.ioctl_data       ( ioctl_data ),
	.ioctl_file_ext   ( ioctl_file_ext ),
	.ioctl_wait       ( ioctl_wait ),

	.sd_lba           ( sd_lba ),
	.sd_blk_cnt       ( sd_blk_cnt ),
	.sd_rd            ( sd_rd ),
	.sd_wr            ( sd_wr ),
	.sd_ack           ( sd_ack ),
	.sd_buff_addr     ( sd_buff_addr ),
	.sd_buff_dout     ( sd_buff_dout ),
	.sd_buff_din      ( sd_buff_din ),
	.sd_buff_wr       ( sd_buff_wr ),
	.img_mounted      ( img_mounted ),
	.img_size         ( img_size ),
	.img_readonly     ( wp_s ),
	.img_type         ( img_type ),

	.DDRAM_BUSY       ( DDRAM_BUSY ),
	.DDRAM_BURSTCNT   ( DDRAM_BURSTCNT ),
	.DDRAM_ADDR       ( DDRAM_ADDR ),
	.DDRAM_DOUT       ( DDRAM_DOUT ),
	.DDRAM_DOUT_READY ( DDRAM_DOUT_READY ),
	.DDRAM_RD         ( DDRAM_RD ),
	.DDRAM_WE         ( DDRAM_WE ),
	.DDRAM_DIN        ( DDRAM_DIN ),
	.DDRAM_BE         ( DDRAM_BE ),

	.TDDRAM_BUSY       ( TDDRAM_BUSY ),
	.TDDRAM_BURSTCNT   ( TDDRAM_BURSTCNT ),
	.TDDRAM_ADDR       ( TDDRAM_ADDR ),
	.TDDRAM_DOUT       ( TDDRAM_DOUT ),
	.TDDRAM_DOUT_READY ( TDDRAM_DOUT_READY ),
	.TDDRAM_RD         ( TDDRAM_RD ),
	.TDDRAM_WE         ( TDDRAM_WE ),
	.TDDRAM_DIN        ( TDDRAM_DIN ),
	.TDDRAM_BE         ( TDDRAM_BE ),

	.ps2_key          ( ps2_key ),
	.joya             ( joyA ),
	.joyb             ( joyB ),
	.pd1              ( pd1 ),
	.pd2              ( pd2 ),

	// sdram.sv drives DQM through A12/A11 as on MiSTer's SDRAM boards; the Pocket
	// has separate DQM pins, so they get the same two bits
	.SDRAM_A          ( dram_a ),
	.SDRAM_DQ         ( dram_dq ),
	.SDRAM_BA         ( dram_ba ),
	.SDRAM_nCS        ( ),
	.SDRAM_nWE        ( dram_we_n ),
	.SDRAM_nRAS       ( dram_ras_n ),
	.SDRAM_nCAS       ( dram_cas_n ),
	.SDRAM_CLK        ( dram_clk ),
	.SDRAM_CKE        ( dram_cke ),
	.SDRAM_DQML       ( dram_dqm[0] ),
	.SDRAM_DQMH       ( dram_dqm[1] ),

	.VGA_R            ( v20_r ),
	.VGA_G            ( v20_g ),
	.VGA_B            ( v20_b ),
	.VGA_HS           ( v20_hs ),
	.VGA_VS           ( v20_vs ),
	.VGA_HB           ( v20_hb ),
	.VGA_VB           ( v20_vb ),
	.VGA_CE           ( v20_ce ),
	.ntsc_out         ( v20_ntsc ),

	.AUDIO_L          ( audio_l ),
	.AUDIO_R          ( audio_r ),

	.disk_ready_out   ( v20_disk_ready ),
	.at_prompt        ( v20_at_prompt ),
	.basic_main       ( v20_basic_main ),
	.prg_loaded       ( v20_prg_loaded )
);

/* ------------------------------------------------------------------------------ */
/* ---------------------------------- Autostart --------------------------------- */
/* ------------------------------------------------------------------------------ */

autostart #(.CLK_HZ(35_468_944)) autostart (
	.clk           ( clk_sys ),
	.reset         ( ~reset_n_s || reset_p != 0 || detach_p != 0 ),
	.enable        ( auto_s ),
	.disk_inserted ( media_disk_inserted ),
	.tape_loaded   ( media_tape_loaded ),
	.prg_loaded    ( v20_prg_loaded ),
	.at_prompt     ( v20_at_prompt ),
	.basic_main    ( v20_basic_main ),
	.disk_ready    ( v20_disk_ready ),
	.key           ( auto_key ),
	.shift         ( auto_shift ),
	.busy          ( )
);

/* ------------------------------------------------------------------------------ */
/* ------------------------------------ Video ----------------------------------- */
/* ------------------------------------------------------------------------------ */

assign video_rgb_clock    = clk_sys;
assign video_rgb_clock_90 = clk_sys_90;

wire [23:0] v20_video_rgb;
wire        v20_video_de, v20_video_skip, v20_video_hs, v20_video_vs;

vic20_video vic20_video (
	.clk        ( clk_sys ),
	.ce_pix     ( v20_ce ),
	.ntsc       ( v20_ntsc ),
	.r          ( v20_r ),
	.g          ( v20_g ),
	.b          ( v20_b ),
	.hblank     ( v20_hb ),
	.vblank     ( v20_vb ),
	.video_rgb  ( v20_video_rgb ),
	.video_de   ( v20_video_de ),
	.video_skip ( v20_video_skip ),
	.video_hs   ( v20_video_hs ),
	.video_vs   ( v20_video_vs )
);

osk_overlay osk_overlay (
	.clk        ( clk_sys ),
	.visible    ( osk_visible ),
	.cur_row    ( osk_row ),
	.cur_col    ( osk_col ),
	.mods       ( osk_mods ),
	.badge      ( badge_timer != 0 ),
	.badge_mode ( badge_mode ),
	.loading    ( media_loading ),
	.load_kind  ( media_load_kind ),
	.load_pct   ( media_load_pct ),
	.in_rgb     ( v20_video_rgb ),
	.in_de      ( v20_video_de ),
	.in_skip    ( v20_video_skip ),
	.in_hs      ( v20_video_hs ),
	.in_vs      ( v20_video_vs ),
	.video_rgb  ( video_rgb ),
	.video_de   ( video_de ),
	.video_skip ( video_skip ),
	.video_hs   ( video_hs ),
	.video_vs   ( video_vs )
);

/* ------------------------------------------------------------------------------ */
/* ------------------------------------ Audio ----------------------------------- */
/* ------------------------------------------------------------------------------ */

sound_i2s #(
	.CHANNEL_WIDTH ( 16 ),
	.SIGNED_INPUT  ( 1 )
) sound_i2s (
	.clk_74a    ( clk_74a ),
	.clk_audio  ( clk_sys ),
	.audio_l    ( audio_l ),
	.audio_r    ( audio_r ),
	.audio_mclk ( audio_mclk ),
	.audio_lrck ( audio_lrck ),
	.audio_dac  ( audio_dac )
);

endmodule

`default_nettype wire
