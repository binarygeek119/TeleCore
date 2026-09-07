//============================================================================
//  TeleCore - 1989-spec BBS terminal machine for MiSTer
//
//  Intel 80486, Tseng ET4000AX, Sound Blaster 1.0 (+game port), 1.44 MB A:,
//  PS/2 keyboard + mouse, COM1 modem. Boots from boot0.rom, runs the terminal
//  program from boot1.rom, add-on ROMs in slots 2-9.
//
//  CPU, cache and peripheral blocks derived from the ao486 project
//  (Aleksander Osman, Alexey Melnikov) - GPL v2.
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

assign ADC_BUS  = 'Z;
assign {SDRAM_A, SDRAM_BA, SDRAM_DQ, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

assign LED_DISK[1]  = 0;
assign LED_POWER    = 0;
assign BUTTONS      = {~ps2_reset_n, 1'b0};
assign HDMI_FREEZE  = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;
assign VGA_DISABLE  = 0;

led disk_led(clk_sys, |sd_rd | |sd_wr, LED_DISK[0]);
led load_led(clk_sys, ioctl_download, LED_USER);

// Status Bit Map:
// 0         1         2         3          4         5         6
// 01234567890123456789012345678901 23456789012345678901234567890123
// 0123456789ABCDEFGHIJKLMNOPQRSTUV 0123456789ABCDEFGHIJKLMNOPQRSTUV
// XXXX X    XXXXXXX  XX  XX          XX       X

`include "build_id.v"
localparam CONF_STR =
{
	"TELECORE;UART9600:300:1200:2400:4800:9600:19200:38400:57600:115200,MIDI;",
	"S0,NVR,Settings NVRAM;",
	"S1,IMGIMA,Floppy A:;",
	"S2,PBK,PhoneBook Cartridge;",
	"O5,Floppy A: Write Protect,Off,On;",
	"-;",
	"F2,ROM,ROM Slot 2;",
	"F3,ROM,ROM Slot 3;",
	"F4,ROM,ROM Slot 4;",
	"F5,ROM,ROM Slot 5;",
	"F6,ROM,ROM Slot 6;",
	"F7,ROM,ROM Slot 7;",
	"F8,ROM,ROM Slot 8;",
	"F9,ROM,ROM Slot 9;",
	"-;",
	"P1,Video;",
	"P1-;",
	"P1OMN,Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"P1O4,VSync,60Hz,Variable;",
	"P1OE,Low-Res,Native,4x;",
	"P1oDE,Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer;",
	"P1oN,Border,No,Yes;",
	"P2,Audio;",
	"P2-;",
	"P2OIJ,PC Speaker Volume,1,2,3,4;",
	"P3,Hardware;",
	"P3-;",
	"P3OB,CPU Clock,25MHz,33MHz;",
	"P3OF,L1/L2 Cache,On,Off;",
	"P3-;",
	"P3OCD,Joystick Type,2 Buttons,4 Buttons,None;",
	"P3OG,Joystick 2,Enabled,Disabled;",
	"-;",
	"R0,Reset;",
	"J,Button 1,Button 2,Button 3,Button 4;",
	"jn,A,B,X,Y;",
	"V,v",`BUILD_DATE
};

////////////////////////////////////////////////////////////////////////

wire        ps2_kbd_clk_out, ps2_kbd_data_out, ps2_kbd_clk_in, ps2_kbd_data_in;
wire        ps2_mouse_clk_out, ps2_mouse_data_out, ps2_mouse_clk_in, ps2_mouse_data_in;
wire [10:0] ps2_key;

wire  [1:0] buttons;
wire [63:0] status;
wire [21:0] gamma_bus;
wire  [7:0] uart1_mode;
wire [31:0] uart1_speed;
wire [64:0] rtc_time;

wire [31:0] joystick_0, joystick_1;
wire [15:0] joystick_l_analog_0, joystick_l_analog_1;

wire        ioctl_download;
wire [15:0] ioctl_index;
wire        ioctl_wr;
wire [26:0] ioctl_addr;
wire [15:0] ioctl_dout;
wire        ioctl_wait;

wire  [2:0] img_mounted;
wire        img_readonly;
wire [63:0] img_size;
wire [31:0] sd_lba[3];
wire  [2:0] sd_rd, sd_wr, sd_ack;
wire [12:0] sd_buff_addr;
wire [15:0] sd_buff_dout;
wire [15:0] sd_buff_din[3];
wire        sd_buff_wr;

hps_io #(.CONF_STR(CONF_STR), .CONF_STR_BRAM(0), .PS2DIV(2000), .PS2WE(1), .WIDE(1), .VDNUM(3)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.joystick_l_analog_0(joystick_l_analog_0),
	.joystick_l_analog_1(joystick_l_analog_1),

	.ps2_key(ps2_key),
	.ps2_kbd_clk_out(ps2_kbd_clk_out),
	.ps2_kbd_data_out(ps2_kbd_data_out),
	.ps2_kbd_clk_in(ps2_kbd_clk_in),
	.ps2_kbd_data_in(ps2_kbd_data_in),
	.ps2_mouse_clk_out(ps2_mouse_clk_out),
	.ps2_mouse_data_out(ps2_mouse_data_out),
	.ps2_mouse_clk_in(ps2_mouse_clk_in),
	.ps2_mouse_data_in(ps2_mouse_data_in),

	.buttons(buttons),
	.status(status),
	.status_menumask(0),

	.new_vmode(status[4]),
	.gamma_bus(gamma_bus),

	.uart_mode(uart1_mode),
	.uart_speed(uart1_speed),
	.RTC(rtc_time),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(ioctl_wait),

	.img_mounted(img_mounted),
	.img_readonly(img_readonly),
	.img_size(img_size),
	.sd_lba(sd_lba),
	.sd_blk_cnt('{0,0,0}),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr)
);

// block devices: S0 = settings NVRAM (nvram), S1 = floppy, S2 = PhoneBook
assign sd_lba[1]   = 0;
assign sd_rd[1]    = 0;
assign sd_wr[1]    = 0;
assign sd_buff_din[1] = 0;

/////////////////////////////  PLL  ////////////////////////////////////

wire clk_sys, clk_uart1, clk_mpu, clk_vga;
wire pll_locked;
reg [27:0] cur_rate;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.outclk_1(clk_uart1),
	.outclk_2(clk_mpu),
	.outclk_3(),
	.outclk_4(clk_vga),
	.outclk_5(),
	.locked(pll_locked),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll)
);

wire [63:0] reconfig_to_pll;
wire [63:0] reconfig_from_pll;
wire        cfg_waitrequest;
reg         cfg_write;
reg   [5:0] cfg_address;
reg  [31:0] cfg_data;

pll_cfg pll_cfg
(
	.mgmt_clk(CLK_50M),
	.mgmt_reset(0),
	.mgmt_waitrequest(cfg_waitrequest),
	.mgmt_read(0),
	.mgmt_readdata(),
	.mgmt_write(cfg_write),
	.mgmt_address(cfg_address),
	.mgmt_writedata(cfg_data),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll)
);

// clk_sys: 0 = 30 MHz ("25 MHz" 486DX-25 class), 1 = 56.25 MHz ("33 MHz" class)
// Same divider table as ao486 (C-counter 0 of the fractional PLL, VCO 900 MHz).
reg [2:0] clk_req;
always @(posedge clk_sys) clk_req <= status[11] ? 3'd3 : 3'd2;

reg [2:0] speed;
always @(posedge CLK_50M) begin
	reg [2:0] sp1, sp2;
	sp1 <= clk_req;
	sp2 <= sp1;
	if(sp2 == sp1) speed <= sp2;
end

reg uspeed_sys;
always @(posedge clk_sys) uspeed_sys <= (uart1_speed <= 115200);

reg uspeed;
always @(posedge CLK_50M) begin
	reg sp1, sp2;
	sp1 <= uspeed_sys;
	sp2 <= sp1;
	if(sp2 == sp1) uspeed <= sp2;
end

(* romstyle = "logic" *) wire [27:0] clk_rate[8]  = '{90000000, 15000000, 30000000, 56250000, 100000000, 100000000, 100000000, 100000000 };
(* romstyle = "logic" *) wire [17:0] speed_div[8] = '{  'h0505,   'h1e1e,   'h0f0f,   'h0808,   'h20504,   'h20504,   'h20504,   'h20504 };

always @(posedge CLK_50M) begin
	reg [2:0] old_speed = 0;
	reg [2:0] state = 0;
	reg       old_uspeed = 0;
	reg       old_rst = 0;

	if(!cfg_waitrequest) begin
		cfg_write <= 0;
		if(pll_locked) begin
			if(state) state<=state+1'd1;
			case(state)
				0: begin
						old_rst <= reset;
						old_speed <= speed;
						old_uspeed <= uspeed;
						if((old_speed != speed) || (old_uspeed != uspeed) || (old_rst & ~reset)) state <= 1;
					end
				1: begin cfg_address <= 0; cfg_data <= 0;                            cfg_write <= 1; end
				3: begin cfg_address <= 5; cfg_data <= speed_div[speed];             cfg_write <= 1; end
				5: begin cfg_address <= 5; cfg_data <= uspeed ? 32'h4F4F4 : 32'h40909; cfg_write <= 1; end
				7: begin cfg_address <= 2; cfg_data <= 0;                            cfg_write <= 1; end
			endcase
		end
	end
end

always @(posedge clk_sys) cur_rate <= clk_rate[clk_req];

////////////////////////////  UART  ////////////////////////////////////

wire uart1_cts, uart1_dcd, uart1_dsr, uart1_rts, uart1_dtr, uart1_tx, uart1_rx;

assign UART_RTS  = uart1_rts;
assign UART_DTR  = uart1_dtr;
assign uart1_cts = UART_CTS;
assign uart1_dcd = UART_DSR;
assign uart1_dsr = UART_DSR;
assign uart1_rx  = UART_RXD;
assign UART_TXD  = uart1_tx;

////////////////////////////  VIDEO  ///////////////////////////////////

assign VGA_F1 = 0;
assign VGA_SL = 0;
assign VGA_SCALER = 1;
assign CLK_VIDEO = clk_vga;
assign CE_PIXEL = vga_ce;

wire [7:0] r,g,b;
wire       HSync,VSync;

video_cleaner video_cleaner
(
	.clk_vid(CLK_VIDEO),
	.ce_pix(vga_ce),
	.R(r), .G(g), .B(b),
	.HSync(HSync), .VSync(VSync), .DE_in(vga_de),
	.VGA_R(R), .VGA_G(G), .VGA_B(B),
	.VGA_VS(vs), .VGA_HS(hs), .DE_out(de1)
);

wire hs,vs,de1;
wire [7:0] R,G,B;

gamma_fast gamma
(
	.clk_vid(CLK_VIDEO),
	.ce_pix(CE_PIXEL),
	.gamma_bus(gamma_bus),
	.HSync(hs), .VSync(vs), .DE(de1), .RGB_in({R,G,B}),
	.HSync_out(VGA_HS), .VSync_out(VGA_VS), .DE_out(VGA_DE), .RGB_out({VGA_R,VGA_G,VGA_B})
);

wire  [7:0] vga_pal_a;
wire [17:0] vga_pal_d;
wire        vga_pal_we;
wire [19:0] vga_start_addr;
wire  [8:0] vga_width;
wire  [8:0] vga_stride;
wire [10:0] vga_height;
wire  [3:0] vga_flags;
wire        vga_off;
wire        vga_ce;
wire        vga_de;

reg         fb_en;
reg  [31:0] fb_base;
reg  [11:0] fb_height;
reg  [11:0] fb_width;
reg  [13:0] fb_stride;
reg   [4:0] fb_fmt;
reg         fb_off;

always @(posedge clk_sys) begin
	fb_en       <= ~vga_flags[2] && |vga_flags[1:0];
	fb_base     <= {4'h3, 6'b111110, vga_start_addr, 2'b00};
	fb_width    <= (vga_flags[1:0] == 3) ? 12'd640 : vga_flags[2] ? {vga_width, 2'b00} : {vga_width, 3'b000};
	fb_stride   <= {vga_stride, 3'b000};
	fb_height   <= ~status[14] && vga_flags[3] ? vga_height[10:1] : vga_height;
	fb_fmt[2:0] <= (vga_flags[1:0] == 3) ? 3'b101 : (vga_flags[1:0] == 2) ? 3'b100 : 3'b011;
	fb_fmt[4:3] <= 2'b11;
	fb_off      <= vga_off;
end

assign FB_PAL_CLK     = clk_sys;
assign FB_PAL_ADDR    = vga_pal_a;
assign FB_PAL_DOUT    = {vga_pal_d[17:12], vga_pal_d[17:16], vga_pal_d[11:6], vga_pal_d[11:10], vga_pal_d[5:0], vga_pal_d[5:4]};
assign FB_PAL_WR      = vga_pal_we;
assign FB_EN          = fb_en;
assign FB_BASE        = fb_base;
assign FB_FORMAT      = fb_fmt;
assign FB_WIDTH       = fb_width;
assign FB_HEIGHT      = fb_height;
assign FB_STRIDE      = fb_stride;
assign FB_FORCE_BLANK = fb_off;

reg f60;
always @(posedge clk_sys) f60 <= fb_en || (fb_width > 760);

reg  [2:0] ar,SCALE;
reg [11:0] arx_i,ary_i;
always @(posedge CLK_VIDEO) begin
	ar    <= status[23:22];
	SCALE <= status[46:45];
	arx_i <= (!ar) ? 8'd4 : (ar - 1'd1);
	ary_i <= (!ar) ? 8'd3 : 8'd0;
end

wire [12:0] fb_arx, arx, fb_ary, ary;

video_scale_int fb_scale
(
	.*,
	.hsize(fb_width),
	.vsize(fb_height),
	.arx_o(fb_arx),
	.ary_o(fb_ary)
);

video_freak video_freak
(
	.*,
	.VGA_DE_IN(VGA_DE),
	.VGA_DE(),
	.ARX(arx_i),
	.ARY(ary_i),
	.CROP_SIZE(0),
	.CROP_OFF(0),
	.VIDEO_ARX(arx),
	.VIDEO_ARY(ary)
);

assign VIDEO_ARX = fb_en ? fb_arx : arx;
assign VIDEO_ARY = fb_en ? fb_ary : ary;

////////////////////////////  ROM LOADER + DDR MUX  ////////////////////

wire [24:0] ldr_ddr_addr;
wire [63:0] ldr_ddr_din;
wire  [7:0] ldr_ddr_be;
wire        ldr_ddr_we;
wire        ldr_active;
wire  [9:0] rom_present;
wire        bios_present;

rom_loader rom_loader
(
	.clk(clk_sys),
	.reset(RESET | ~pll_locked),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(ioctl_wait),

	.ddr_addr(ldr_ddr_addr),
	.ddr_din(ldr_ddr_din),
	.ddr_be(ldr_ddr_be),
	.ddr_we(ldr_ddr_we),
	.ddr_busy(DDRAM_BUSY),

	.active(ldr_active),
	.rom_present(rom_present),
	.bios_present(bios_present)
);

wire [24:0] soc_ddr_addr;
wire [63:0] soc_ddr_din;
wire  [7:0] soc_ddr_be;
wire  [7:0] soc_ddr_burstcnt;
wire        soc_ddr_we, soc_ddr_rd;

assign DDRAM_CLK           = clk_sys;
assign DDRAM_ADDR[28:25]   = 4'h3;
assign DDRAM_ADDR[24:0]    = ldr_active ? ldr_ddr_addr : soc_ddr_addr;
assign DDRAM_DIN           = ldr_active ? ldr_ddr_din  : soc_ddr_din;
assign DDRAM_BE            = ldr_active ? ldr_ddr_be   : soc_ddr_be;
assign DDRAM_BURSTCNT      = ldr_active ? 8'd1         : soc_ddr_burstcnt;
assign DDRAM_WE            = ldr_active ? ldr_ddr_we   : soc_ddr_we;
assign DDRAM_RD            = ldr_active ? 1'b0         : soc_ddr_rd;

////////////////////////////  SYSTEM  //////////////////////////////////

wire       ps2_reset_n;

reg reset;
always @(posedge clk_sys) reset <= buttons[1] | status[0] | RESET | ldr_active | ~pll_locked;

telecore_soc soc
(
	.clk_sys              (clk_sys),
	.reset                (reset),
	.clock_rate           (cur_rate),

	.l1_disable           (status[15]),
	.l2_disable           (status[15]),

	.nv_img_mounted       (img_mounted[0]),
	.nv_img_readonly      (img_readonly),
	.nv_img_size          (img_size),
	.nv_sd_lba            (sd_lba[0]),
	.nv_sd_rd             (sd_rd[0]),
	.nv_sd_wr             (sd_wr[0]),
	.nv_sd_ack            (sd_ack[0]),
	.nv_sd_buff_addr      (sd_buff_addr),
	.nv_sd_buff_dout      (sd_buff_dout),
	.nv_sd_buff_din       (sd_buff_din[0]),
	.nv_sd_buff_wr        (sd_buff_wr),

	.pb_img_mounted       (img_mounted[2]),
	.pb_img_readonly      (img_readonly),
	.pb_img_size          (img_size),
	.pb_sd_lba            (sd_lba[2]),
	.pb_sd_rd             (sd_rd[2]),
	.pb_sd_wr             (sd_wr[2]),
	.pb_sd_ack            (sd_ack[2]),
	.pb_sd_buff_addr      (sd_buff_addr),
	.pb_sd_buff_dout      (sd_buff_dout),
	.pb_sd_buff_din       (sd_buff_din[2]),
	.pb_sd_buff_wr        (sd_buff_wr),

	.ps2_kbclk_in         (ps2_kbd_clk_out),
	.ps2_kbdat_in         (ps2_kbd_data_out),
	.ps2_kbclk_out        (ps2_kbd_clk_in),
	.ps2_kbdat_out        (ps2_kbd_data_in),
	.ps2_mouseclk_in      (ps2_mouse_clk_out),
	.ps2_mousedat_in      (ps2_mouse_data_out),
	.ps2_mouseclk_out     (ps2_mouse_clk_in),
	.ps2_mousedat_out     (ps2_mouse_data_in),
	.ps2_reset_n          (ps2_reset_n),

	.clk_uart1            (clk_uart1),
	.uart1_rx             (uart1_rx),
	.uart1_tx             (uart1_tx),
	.uart1_cts_n          (uart1_cts),
	.uart1_dcd_n          (uart1_dcd),
	.uart1_dsr_n          (uart1_dsr),
	.uart1_rts_n          (uart1_rts),
	.uart1_dtr_n          (uart1_dtr),

	.speaker_out          (speaker_out),
	.rtc_time             (rtc_time),
	.rom_present          (rom_present),

	.clk_vga              (clk_vga),
	.clock_rate_vga       (28'd90000000),
	.video_ce             (vga_ce),
	.video_f60            (~status[4] | f60),
	.video_blank_n        (vga_de),
	.video_hsync          (HSync),
	.video_vsync          (VSync),
	.video_r              (r),
	.video_g              (g),
	.video_b              (b),
	.video_pal_a          (vga_pal_a),
	.video_pal_d          (vga_pal_d),
	.video_pal_we         (vga_pal_we),
	.video_start_addr     (vga_start_addr),
	.video_width          (vga_width),
	.video_stride         (vga_stride),
	.video_height         (vga_height),
	.video_flags          (vga_flags),
	.video_off            (vga_off),
	.video_fb_en          (fb_en),
	.video_lores          (~status[14]),
	.video_border         (status[55] && ~fb_en),

	.DDRAM_BUSY           (DDRAM_BUSY),
	.DDRAM_BURSTCNT       (soc_ddr_burstcnt),
	.DDRAM_ADDR           (soc_ddr_addr),
	.DDRAM_DOUT           (DDRAM_DOUT),
	.DDRAM_DOUT_READY     (DDRAM_DOUT_READY & ~ldr_active),
	.DDRAM_RD             (soc_ddr_rd),
	.DDRAM_DIN            (soc_ddr_din),
	.DDRAM_BE             (soc_ddr_be),
	.DDRAM_WE             (soc_ddr_we)
);

////////////////////////////  AUDIO  ///////////////////////////////////

wire        speaker_out, speaker_out_clk_audio;
reg  [15:0] audio_l, audio_r;

synchronizer speaker_out_sync
(
	.clk(CLK_AUDIO),
	.in(speaker_out),
	.out(speaker_out_clk_audio)
);

always @(posedge CLK_AUDIO) begin
	reg [15:0] spk;
	spk <= {2'b00, {3'b000,speaker_out_clk_audio} << status[19:18], 10'd0};
	audio_l <= spk;
	audio_r <= spk;
end

assign AUDIO_L   = audio_l;
assign AUDIO_R   = audio_r;
assign AUDIO_S   = 1;
assign AUDIO_MIX = 0;

endmodule

module led
(
	input      clk,
	input      in,
	output reg out
);

integer counter = 0;
always @(posedge clk) begin
	if(!counter) out <= 0;
	else begin
		counter <= counter - 1'b1;
		out <= 1;
	end
	if(in) counter <= 4500000;
end

endmodule
