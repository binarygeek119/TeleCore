//
// TeleCore SoC
//
// Intel 80486 + L2 cache + ISA-style peripherals for a 1989 BBS terminal:
//   8259 PIC x2, 8254 PIT, 8042 keyboard/mouse, MC146818 RTC, 16550 COM1,
//   Tseng ET4000AX VGA, ROM bank window, (phase 2: SB1.0 + game port + DMA,
//   phase 3: 82077 floppy, phase 4: NVRAM).
//

module telecore_soc
(
	input         clk_sys,
	input         reset,
	input  [27:0] clock_rate,

	input         l1_disable,
	input         l2_disable,

	// PS/2
	input         ps2_kbclk_in,
	input         ps2_kbdat_in,
	output        ps2_kbclk_out,
	output        ps2_kbdat_out,
	input         ps2_mouseclk_in,
	input         ps2_mousedat_in,
	output        ps2_mouseclk_out,
	output        ps2_mousedat_out,
	output        ps2_reset_n,

	// COM1
	input         clk_uart1,
	input         uart1_rx,
	output        uart1_tx,
	input         uart1_cts_n,
	input         uart1_dcd_n,
	input         uart1_dsr_n,
	output        uart1_rts_n,
	output        uart1_dtr_n,

	// speaker
	output        speaker_out,

	// RTC time from HPS (MSM6242B layout, BCD)
	input  [64:0] rtc_time,

	// ROM slots
	input   [9:0] rom_present,

	// PhoneBook cartridge (S2, NVRAM-style image)
	input         pb_img_mounted,
	input         pb_img_readonly,
	input  [63:0] pb_img_size,
	output [31:0] pb_sd_lba,
	output        pb_sd_rd,
	output        pb_sd_wr,
	input         pb_sd_ack,
	input  [12:0] pb_sd_buff_addr,
	input  [15:0] pb_sd_buff_dout,
	output [15:0] pb_sd_buff_din,
	input         pb_sd_buff_wr,

	// Settings NVRAM (S0, settings.nvr image)
	input         nv_img_mounted,
	input         nv_img_readonly,
	input  [63:0] nv_img_size,
	output [31:0] nv_sd_lba,
	output        nv_sd_rd,
	output        nv_sd_wr,
	input         nv_sd_ack,
	input  [12:0] nv_sd_buff_addr,
	input  [15:0] nv_sd_buff_dout,
	output [15:0] nv_sd_buff_din,
	input         nv_sd_buff_wr,

	// video
	input         clk_vga,
	input  [27:0] clock_rate_vga,
	output        video_ce,
	output        video_blank_n,
	output        video_hsync,
	output        video_vsync,
	output [7:0]  video_r,
	output [7:0]  video_g,
	output [7:0]  video_b,
	input         video_f60,
	output [7:0]  video_pal_a,
	output [17:0] video_pal_d,
	output        video_pal_we,
	output [19:0] video_start_addr,
	output [8:0]  video_width,
	output [10:0] video_height,
	output [3:0]  video_flags,
	output [8:0]  video_stride,
	output        video_off,
	input         video_fb_en,
	input         video_lores,
	input         video_border,

	// DDR (64-bit words inside the core's 256 MB window)
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [24:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE
);

// ---------------------------------------------------------------- interrupts
wire        interrupt_done;
wire        interrupt_do;
wire  [7:0] interrupt_vector;
wire [15:0] irq;

//  0 PIT   1 KBD   2 cascade/VGA   3 -   4 COM1   5 -   6 FDC   7 SB
//  8 RTC   9 -    10 -   11 -   12 mouse   13 -   14 -   15 -
assign irq[3]  = 0;
assign irq[5]  = 0;
assign irq[6]  = 0;
assign irq[7]  = 0;
assign irq[9]  = 0;
assign irq[10] = 0;
assign irq[11] = 0;
assign irq[13] = 0;
assign irq[14] = 0;
assign irq[15] = 0;

// ---------------------------------------------------------------- CPU memory bus
wire [29:0] cpu_address;
wire [31:0] cpu_writedata;
wire [31:0] cpu_readdata;
wire  [3:0] cpu_byteenable;
wire  [3:0] cpu_burstcount;
wire        cpu_write;
wire        cpu_read;
wire        cpu_waitrequest;
wire        cpu_readdatavalid;
wire        a20_enable;

// ---------------------------------------------------------------- ROM bank window E0000h-EFFFFh
// CPU addresses are 32-bit dword addresses. E0000h>>2 = 38000h -> [29:14] == 0Eh.
// Slots 2-9 live at 400000h + (n-2)*10000h  ->  dword [29:14] = 40h + (n-2).
// Blank bank (all FFh) at 480000h -> dword [29:14] = 48h.
reg   [3:0] rom_bank;
wire        bank_valid = (rom_bank >= 4'd2) && (rom_bank <= 4'd9) && rom_present[rom_bank];
wire        win_hit    = (cpu_address[29:14] == 16'h000E);
wire [15:0] win_page   = bank_valid ? (16'h0040 + {12'd0, rom_bank - 4'd2}) : 16'h0048;

wire [29:0] mem_address = win_hit ? {win_page, cpu_address[13:0]} : cpu_address;
wire        mem_write   = cpu_write & ~win_hit;          // window is read-only

// ---------------------------------------------------------------- L2 cache
wire [16:0] vga_address;
wire  [7:0] vga_readdata;
wire  [7:0] vga_writedata;
wire        vga_read;
wire        vga_write;
wire  [2:0] vga_memmode;
wire  [5:0] video_wr_seg;
wire  [5:0] video_rd_seg;

l2_cache cache
(
	.CLK               (clk_sys),
	.RESET             (reset),
	.DISABLE           (l2_disable),

	.CPU_ADDR          (mem_address),
	.CPU_DIN           (cpu_writedata),
	.CPU_DOUT          (cpu_readdata),
	.CPU_DOUT_READY    (cpu_readdatavalid),
	.CPU_BE            (cpu_byteenable),
	.CPU_BURSTCNT      (cpu_burstcount),
	.CPU_BUSY          (cpu_waitrequest),
	.CPU_RD            (cpu_read),
	.CPU_WE            (mem_write),

	.DDRAM_ADDR        (DDRAM_ADDR),
	.DDRAM_DIN         (DDRAM_DIN),
	.DDRAM_DOUT        (DDRAM_DOUT),
	.DDRAM_DOUT_READY  (DDRAM_DOUT_READY),
	.DDRAM_BE          (DDRAM_BE),
	.DDRAM_BURSTCNT    (DDRAM_BURSTCNT),
	.DDRAM_BUSY        (DDRAM_BUSY),
	.DDRAM_RD          (DDRAM_RD),
	.DDRAM_WE          (DDRAM_WE),

	.VGA_ADDR          (vga_address),
	.VGA_DIN           (vga_readdata),
	.VGA_DOUT          (vga_writedata),
	.VGA_RD            (vga_read),
	.VGA_WE            (vga_write),
	.VGA_MODE          (vga_memmode),
	.VGA_WR_SEG        (video_wr_seg),
	.VGA_RD_SEG        (video_rd_seg),
	.VGA_FB_EN         (video_fb_en),

	.uma_ram           (1'b0)
);

// ---------------------------------------------------------------- CPU
wire        cpu_io_read_do;
wire [15:0] cpu_io_read_address;
wire  [2:0] cpu_io_read_length;
wire [31:0] cpu_io_read_data;
wire        cpu_io_read_done;
wire        cpu_io_write_do;
wire [15:0] cpu_io_write_address;
wire  [2:0] cpu_io_write_length;
wire [31:0] cpu_io_write_data;
wire        cpu_io_write_done;

i486 cpu
(
	.clk               (clk_sys),
	.rst_n             (~reset),

	.cache_disable     (l1_disable),

	.avm_address       (cpu_address),
	.avm_writedata     (cpu_writedata),
	.avm_byteenable    (cpu_byteenable),
	.avm_burstcount    (cpu_burstcount),
	.avm_write         (cpu_write),
	.avm_read          (cpu_read),
	.avm_waitrequest   (cpu_waitrequest),
	.avm_readdatavalid (cpu_readdatavalid),
	.avm_readdata      (cpu_readdata),

	.interrupt_do      (interrupt_do),
	.interrupt_vector  (interrupt_vector),
	.interrupt_done    (interrupt_done),

	.io_read_do        (cpu_io_read_do),
	.io_read_address   (cpu_io_read_address),
	.io_read_length    (cpu_io_read_length),
	.io_read_data      (cpu_io_read_data),
	.io_read_done      (cpu_io_read_done),
	.io_write_do       (cpu_io_write_do),
	.io_write_address  (cpu_io_write_address),
	.io_write_length   (cpu_io_write_length),
	.io_write_data     (cpu_io_write_data),
	.io_write_done     (cpu_io_write_done),

	.a20_enable        (a20_enable),

	// DMA master (phase 2)
	.dma_address       (24'd0),
	.dma_16bit         (1'b0),
	.dma_write         (1'b0),
	.dma_writedata     (16'd0),
	.dma_read          (1'b0),
	.dma_readdata      (),
	.dma_readdatavalid (),
	.dma_waitrequest   ()
);

// ---------------------------------------------------------------- I/O bus
wire [15:0] iobus_address;
wire        iobus_write;
wire        iobus_read;
wire  [2:0] iobus_datasize;
wire [31:0] iobus_writedata;

reg pic_master_cs, pic_slave_cs, pit_cs, ps2_io_cs, ps2_ctl_cs, rtc_cs, uart1_cs;
reg vga_b_cs, vga_c_cs, vga_d_cs, rombank_cs, phonebook_cs, joy_cs, sb_cs, fm_cs, fdc_cs, dma_m_cs, dma_p_cs, dma_s_cs, nvram_cs;

always @(posedge clk_sys) begin
	pic_master_cs <= ({iobus_address[15:1], 1'd0} == 16'h0020);
	pic_slave_cs  <= ({iobus_address[15:1], 1'd0} == 16'h00A0);
	pit_cs        <= ({iobus_address[15:2], 2'd0} == 16'h0040) || (iobus_address == 16'h0061);
	ps2_io_cs     <= ({iobus_address[15:3], 3'd0} == 16'h0060) && (iobus_address != 16'h0061);
	ps2_ctl_cs    <= ({iobus_address[15:4], 4'd0} == 16'h0090);
	rtc_cs        <= ({iobus_address[15:1], 1'd0} == 16'h0070);
	uart1_cs      <= ({iobus_address[15:3], 3'd0} == 16'h03F8);
	vga_b_cs      <= ({iobus_address[15:4], 4'd0} == 16'h03B0);
	vga_c_cs      <= ({iobus_address[15:4], 4'd0} == 16'h03C0);
	vga_d_cs      <= ({iobus_address[15:4], 4'd0} == 16'h03D0);
	rombank_cs    <= ({iobus_address[15:1], 1'd0} == 16'h0C02);
	nvram_cs      <= ({iobus_address[15:1], 1'd0} == 16'h0C00);
	phonebook_cs  <= ({iobus_address[15:4], 4'd0} == 16'h0C10);
	joy_cs        <= (iobus_address == 16'h0201);
	sb_cs         <= ({iobus_address[15:4], 4'd0} == 16'h0220);
	fm_cs         <= ({iobus_address[15:1], 1'd0} == 16'h0388);
	fdc_cs        <= ({iobus_address[15:3], 3'd0} == 16'h03F0) && (iobus_address != 16'h03F6);
	dma_m_cs      <= ({iobus_address[15:5], 5'd0} == 16'h00C0);
	dma_p_cs      <= ({iobus_address[15:4], 4'd0} == 16'h0080);
	dma_s_cs      <= ({iobus_address[15:4], 4'd0} == 16'h0000);
end

wire  [7:0] pit_readdata, ps2_readdata, rtc_readdata, uart1_readdata, pic_readdata, vga_io_readdata;
wire  [7:0] phonebook_readdata;

// ROM bank register (0C02h) and presence bitmap (0C03h)
always @(posedge clk_sys) begin
	if (reset) rom_bank <= 0;
	else if (iobus_write && rombank_cs && !iobus_address[0]) rom_bank <= iobus_writedata[3:0];
end
// 0C02h read: [3:0] current bank, [6] ROM1 present, [7] BIOS present
// 0C03h read: bit n-2 set when add-on slot n (2..9) is loaded
wire [7:0] rombank_readdata = iobus_address[0] ? rom_present[9:2] : {rom_present[0], rom_present[1], 2'b00, rom_bank};

wire [7:0] iobus_readdata8 =
	( pic_master_cs | pic_slave_cs ) ? pic_readdata     :
	( pit_cs                       ) ? pit_readdata     :
	( ps2_io_cs | ps2_ctl_cs       ) ? ps2_readdata     :
	( rtc_cs                       ) ? rtc_readdata     :
	( uart1_cs                     ) ? uart1_readdata   :
	( vga_b_cs | vga_c_cs | vga_d_cs ) ? vga_io_readdata :
	( rombank_cs                   ) ? rombank_readdata :
	( phonebook_cs                 ) ? phonebook_readdata :
	                                   8'hFF;

iobus iobus
(
	.clk               (clk_sys),
	.reset             (reset),

	.cpu_read_do       (cpu_io_read_do),
	.cpu_read_address  (cpu_io_read_address),
	.cpu_read_length   (cpu_io_read_length),
	.cpu_read_data     (cpu_io_read_data),
	.cpu_read_done     (cpu_io_read_done),
	.cpu_write_do      (cpu_io_write_do),
	.cpu_write_address (cpu_io_write_address),
	.cpu_write_length  (cpu_io_write_length),
	.cpu_write_data    (cpu_io_write_data),
	.cpu_write_done    (cpu_io_write_done),

	.bus_address       (iobus_address),
	.bus_write         (iobus_write),
	.bus_read          (iobus_read),
	.bus_io32          (1'b0),
	.bus_datasize      (iobus_datasize),
	.bus_writedata     (iobus_writedata),
	.bus_readdata      (iobus_readdata8),
	.bus_wait          (1'b0)
);

// ---------------------------------------------------------------- PIT + speaker
pit pit
(
	.clk               (clk_sys),
	.rst_n             (~reset),
	.clock_rate        (clock_rate),

	.io_address        ({iobus_address[5], iobus_address[1:0]}),
	.io_writedata      (iobus_writedata[7:0]),
	.io_readdata       (pit_readdata),
	.io_read           (iobus_read & pit_cs),
	.io_write          (iobus_write & pit_cs),

	.speaker_out       (speaker_out),
	.irq               (irq[0])
);

// ---------------------------------------------------------------- 8042 keyboard + mouse
ps2 ps2
(
	.clk               (clk_sys),
	.rst_n             (~reset),

	.io_address        (iobus_address[3:0]),
	.io_writedata      (iobus_writedata[7:0]),
	.io_read           (iobus_read),
	.io_write          (iobus_write),
	.io_readdata       (ps2_readdata),
	.io_cs             (ps2_io_cs),
	.ctl_cs            (ps2_ctl_cs),

	.ps2_kbclk         (ps2_kbclk_in),
	.ps2_kbdat         (ps2_kbdat_in),
	.ps2_kbclk_out     (ps2_kbclk_out),
	.ps2_kbdat_out     (ps2_kbdat_out),

	.ps2_mouseclk      (ps2_mouseclk_in),
	.ps2_mousedat      (ps2_mousedat_in),
	.ps2_mouseclk_out  (ps2_mouseclk_out),
	.ps2_mousedat_out  (ps2_mousedat_out),

	.output_a20_enable (),
	.output_reset_n    (ps2_reset_n),
	.a20_enable        (a20_enable),

	.irq_keyb          (irq[1]),
	.irq_mouse         (irq[12])
);

// ---------------------------------------------------------------- RTC (time loaded from HPS after reset)
// hps_io RTC[64:0] (MSM6242B layout, BCD): [7:0] sec [15:8] min [23:16] hour
// [31:24] day [39:32] month [47:40] year(2 digits) [55:48] weekday [64] toggles on update
reg  [7:0] rtc_mgmt_address;
reg        rtc_mgmt_write;
reg  [7:0] rtc_mgmt_writedata;

always @(posedge clk_sys) begin
	reg [3:0] step;
	reg       rtc_flag_d;
	reg       init_done;

	rtc_mgmt_write <= 0;
	rtc_flag_d     <= rtc_time[64];

	if (reset) begin step <= 0; init_done <= 0; end
	else if (rtc_flag_d != rtc_time[64] && step == 0) step <= 1;
	else if (step) begin
		step <= step + 1'd1;
		rtc_mgmt_write <= ~(init_done && step >= 8);   // CMOS defaults only on the first update
		if (step == 14) init_done <= 1;
		case (step)
			1: begin rtc_mgmt_address <= 8'h00; rtc_mgmt_writedata <= rtc_time[7:0];          end // seconds
			2: begin rtc_mgmt_address <= 8'h02; rtc_mgmt_writedata <= rtc_time[15:8];         end // minutes
			3: begin rtc_mgmt_address <= 8'h04; rtc_mgmt_writedata <= rtc_time[23:16];        end // hours
			4: begin rtc_mgmt_address <= 8'h06; rtc_mgmt_writedata <= rtc_time[55:48] + 8'd1; end // weekday (1=Sunday)
			5: begin rtc_mgmt_address <= 8'h07; rtc_mgmt_writedata <= rtc_time[31:24];        end // day
			6: begin rtc_mgmt_address <= 8'h08; rtc_mgmt_writedata <= rtc_time[39:32];        end // month
			7: begin rtc_mgmt_address <= 8'h09; rtc_mgmt_writedata <= rtc_time[47:40];        end // year
			8: begin rtc_mgmt_address <= 8'h32; rtc_mgmt_writedata <= 8'h20;                  end // century
			9: begin rtc_mgmt_address <= 8'h0A; rtc_mgmt_writedata <= 8'h26;                  end // reg A
			10: begin rtc_mgmt_address <= 8'h0B; rtc_mgmt_writedata <= 8'h02;                 end // reg B: 24h, BCD
			11: begin rtc_mgmt_address <= 8'h0D; rtc_mgmt_writedata <= 8'h80;                 end // reg D: battery ok
			12: begin rtc_mgmt_address <= 8'h14; rtc_mgmt_writedata <= 8'h4D;                 end // equipment
			13: begin rtc_mgmt_address <= 8'h15; rtc_mgmt_writedata <= 8'h80;                 end // base mem 640k lo
			14: begin rtc_mgmt_address <= 8'h16; rtc_mgmt_writedata <= 8'h02;                 end // base mem 640k hi
			default: begin rtc_mgmt_write <= 0; step <= 0; end
		endcase
	end
end

// Settings NVRAM pushes loaded/saved CMOS bytes through the same mgmt port;
// it wins over the boot-time defaults sequencer while it is pushing.
wire        nv_mgmt_req;
wire  [7:0] nv_mgmt_addr;
wire  [7:0] nv_mgmt_wdata;

wire  [7:0] rtc_mgmt_address_f   = nv_mgmt_req ? nv_mgmt_addr   : rtc_mgmt_address;
wire        rtc_mgmt_write_f     = nv_mgmt_req | rtc_mgmt_write;
wire  [7:0] rtc_mgmt_writedata_f = nv_mgmt_req ? nv_mgmt_wdata  : rtc_mgmt_writedata;

rtc rtc
(
	.clk               (clk_sys),
	.rst_n             (~reset),
	.clock_rate        (clock_rate),

	.io_address        (iobus_address[0]),
	.io_writedata      (iobus_writedata[7:0]),
	.io_read           (iobus_read & rtc_cs),
	.io_write          (iobus_write & rtc_cs),
	.io_readdata       (rtc_readdata),

	.mgmt_address      (rtc_mgmt_address_f),
	.mgmt_write        (rtc_mgmt_write_f),
	.mgmt_writedata    (rtc_mgmt_writedata_f),

	.bootcfg           (6'd0),

	.irq               (irq[8])
);

// ---------------------------------------------------------------- Settings NVRAM (S0)
nvram nvram0
(
	.clk              (clk_sys),
	.reset            (reset),

	.img_mounted      (nv_img_mounted),
	.img_readonly     (nv_img_readonly),
	.img_size         (nv_img_size),

	.sd_lba           (nv_sd_lba),
	.sd_rd            (nv_sd_rd),
	.sd_wr            (nv_sd_wr),
	.sd_ack           (nv_sd_ack),
	.sd_buff_addr     (nv_sd_buff_addr),
	.sd_buff_dout     (nv_sd_buff_dout),
	.sd_buff_din      (nv_sd_buff_din),
	.sd_buff_wr       (nv_sd_buff_wr),

	.cmos_wr          (iobus_write & rtc_cs),
	.cmos_addr        (iobus_address[0]),
	.cmos_wdata       (iobus_writedata[7:0]),

	.mgmt_req         (nv_mgmt_req),
	.mgmt_addr        (nv_mgmt_addr),
	.mgmt_wdata       (nv_mgmt_wdata)
);

// ---------------------------------------------------------------- COM1
uart uart1
(
	.clk               (clk_sys),
	.br_clk            (clk_uart1),
	.reset             (reset),

	.address           (iobus_address[2:0]),
	.writedata         (iobus_writedata[7:0]),
	.read              (iobus_read),
	.write             (iobus_write),
	.readdata          (uart1_readdata),
	.cs                (uart1_cs),

	.rx                (uart1_rx),
	.tx                (uart1_tx),
	.cts_n             (uart1_cts_n),
	.dcd_n             (uart1_dcd_n),
	.dsr_n             (uart1_dsr_n),
	.rts_n             (uart1_rts_n),
	.dtr_n             (uart1_dtr_n),
	.ri_n              (1'b1),

	.irq               (irq[4])
);

// ---------------------------------------------------------------- VGA (Tseng ET4000AX compatible)
vga vga
(
	.clk_sys           (clk_sys),
	.rst_n             (~reset),

	.clk_vga           (clk_vga),
	.clock_rate_vga    (clock_rate_vga),

	.io_address        (iobus_address[3:0]),
	.io_writedata      (iobus_writedata[7:0]),
	.io_read           (iobus_read),
	.io_write          (iobus_write),
	.io_readdata       (vga_io_readdata),
	.io_b_cs           (vga_b_cs),
	.io_c_cs           (vga_c_cs),
	.io_d_cs           (vga_d_cs),

	.mem_address       (vga_address),
	.mem_read          (vga_read),
	.mem_readdata      (vga_readdata),
	.mem_write         (vga_write),
	.mem_writedata     (vga_writedata),

	.vga_ce            (video_ce),
	.vga_blank_n       (video_blank_n),
	.vga_horiz_sync    (video_hsync),
	.vga_vert_sync     (video_vsync),
	.vga_r             (video_r),
	.vga_g             (video_g),
	.vga_b             (video_b),
	.vga_f60           (video_f60),
	.vga_memmode       (vga_memmode),
	.vga_pal_a         (video_pal_a),
	.vga_pal_d         (video_pal_d),
	.vga_pal_we        (video_pal_we),
	.vga_start_addr    (video_start_addr),
	.vga_wr_seg        (video_wr_seg),
	.vga_rd_seg        (video_rd_seg),
	.vga_width         (video_width),
	.vga_height        (video_height),
	.vga_flags         (video_flags),
	.vga_stride        (video_stride),
	.vga_off           (video_off),
	.vga_lores         (video_lores),
	.vga_border        (video_border),

	.irq               (irq[2])
);

// ---------------------------------------------------------------- PhoneBook cartridge
phonebook phonebook
(
	.clk              (clk_sys),
	.reset            (reset),

	.img_mounted      (pb_img_mounted),
	.img_readonly     (pb_img_readonly),
	.img_size         (pb_img_size),

	.sd_lba           (pb_sd_lba),
	.sd_rd            (pb_sd_rd),
	.sd_wr            (pb_sd_wr),
	.sd_ack           (pb_sd_ack),
	.sd_buff_addr     (pb_sd_buff_addr),
	.sd_buff_dout     (pb_sd_buff_dout),
	.sd_buff_din      (pb_sd_buff_din),
	.sd_buff_wr       (pb_sd_buff_wr),

	.io_address       (iobus_address[3:0]),
	.io_cs            (phonebook_cs),
	.io_read          (iobus_read),
	.io_write         (iobus_write),
	.io_wdata         (iobus_writedata[7:0]),
	.io_rdata         (phonebook_readdata)
);

// ---------------------------------------------------------------- PIC
pic pic
(
	.clk               (clk_sys),
	.rst_n             (~reset),

	.io_address        (iobus_address[0]),
	.io_writedata      (iobus_writedata[7:0]),
	.io_read           (iobus_read),
	.io_write          (iobus_write),
	.io_readdata       (pic_readdata),
	.io_master_cs      (pic_master_cs),
	.io_slave_cs       (pic_slave_cs),

	.interrupt_vector  (interrupt_vector),
	.interrupt_done    (interrupt_done),
	.interrupt_do      (interrupt_do),
	.interrupt_input   (irq)
);

endmodule
