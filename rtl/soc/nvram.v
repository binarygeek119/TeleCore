//
// TeleCore settings NVRAM (S0 slot)
//
// Backs a 256-byte settings.nvr file mounted through the MiSTer OSD:
//   - on mount, reads the image into a shadow RAM and pushes the CMOS
//     bytes into the RTC through its mgmt interface
//   - snoops CPU writes to ports 0x70/0x71 into the shadow RAM and,
//     after a short idle delay, writes the image back to the SD card
//

module nvram
(
	input         clk,
	input         reset,

	// mounted image (MiSTer sd slot)
	input         img_mounted,
	input         img_readonly,
	input  [63:0] img_size,

	output [31:0] sd_lba,
	output reg    sd_rd,
	output reg    sd_wr,
	input         sd_ack,
	input  [12:0] sd_buff_addr,
	input  [15:0] sd_buff_dout,
	output [15:0] sd_buff_din,
	input         sd_buff_wr,

	// CMOS write snoop (ports 0x70/0x71)
	input         cmos_wr,
	input         cmos_addr,   // iobus_address[0]
	input   [7:0] cmos_wdata,

	// push into RTC mgmt port
	output reg        mgmt_req,
	output reg  [7:0] mgmt_addr,
	output reg  [7:0] mgmt_wdata
);

localparam [7:0]  NVR_BYTES   = 8'd128;    // CMOS bytes pushed to the RTC
localparam [23:0] SAVE_DELAY  = 24'd8000000; // ~0.16s idle before write-back

localparam [2:0] S_IDLE = 3'd0;
localparam [2:0] S_LOAD = 3'd1;
localparam [2:0] S_PUSH = 3'd2;
localparam [2:0] S_SAVE = 3'd3;

reg  [7:0] shadow [0:255];
reg  [2:0] state;
reg        busy;
reg        loaded;
reg        readonly_r;
reg        dirty;
reg [23:0] save_timer;
reg  [7:0] push_addr;
reg        img_mounted_d;
reg        sd_ack_d;
reg        mount_pending;
reg [15:0] mount_timer;
reg [16:0] last_img_size;
reg  [6:0] cmos_index;

wire img_mounted_rise = img_mounted && !img_mounted_d;
wire sd_ack_fall      = !sd_ack && sd_ack_d;
wire size_changed     = (img_size[16:0] != last_img_size);

assign sd_lba = 32'd0;

// HPS reads the shadow during sd_wr
wire [7:0] buff_wa = sd_buff_addr[7:0];
assign sd_buff_din = (buff_wa < 8'd128) ?
	{shadow[{buff_wa[6:0],1'b1}], shadow[{buff_wa[6:0],1'b0}]} : 16'h0000;

always @(posedge clk) begin
	img_mounted_d <= img_mounted;
	sd_ack_d      <= sd_ack;
	mgmt_req      <= 0;

	if (mount_timer != 0)  mount_timer <= mount_timer - 16'd1;
	if (save_timer  != 0)  save_timer  <= save_timer  - 24'd1;

	// ---- mount: start loading the image
	if (img_mounted_rise) begin
		mount_pending <= 1;
		mount_timer   <= 16'hFFFF;
		last_img_size <= img_size[16:0];
	end

	if (mount_pending && (size_changed || (mount_timer == 0))) begin
		mount_pending <= 0;
		mount_timer   <= 0;
		last_img_size <= img_size[16:0];
		readonly_r    <= img_readonly;
		if (img_size[16:0] != 0) begin
			state  <= S_LOAD;
			busy   <= 1;
			sd_rd  <= 1;
			sd_wr  <= 0;
		end
	end

	// ---- snoop CMOS writes (0x70 = index, 0x71 = data)
	if (cmos_wr) begin
		if (!cmos_addr) cmos_index <= cmos_wdata[6:0];
		else if (loaded && !busy) begin
			shadow[cmos_index] <= cmos_wdata;
			dirty      <= 1;
			save_timer <= SAVE_DELAY;
		end
	end

	case (state)
		S_IDLE: begin
			// write back after the CPU has been idle for SAVE_DELAY
			if (dirty && save_timer == 0 && !readonly_r) begin
				state <= S_SAVE;
				busy  <= 1;
				sd_rd <= 0;
				sd_wr <= 1;
			end
		end

		S_LOAD: begin
			// capture incoming sector data (first 256 bytes only)
			if (sd_ack && sd_buff_wr && sd_buff_addr[7:0] < 8'd128) begin
				shadow[{sd_buff_addr[6:0],1'b0}] <= sd_buff_dout[7:0];
				shadow[{sd_buff_addr[6:0],1'b1}] <= sd_buff_dout[15:8];
			end
			if (sd_ack_fall) begin
				sd_rd     <= 0;
				state     <= S_PUSH;
				push_addr <= 0;
			end
		end

		S_PUSH: begin
			// one CMOS byte per clock into the RTC mgmt port
			mgmt_req   <= 1;
			mgmt_addr  <= push_addr;
			mgmt_wdata <= shadow[push_addr];
			if (push_addr == NVR_BYTES - 8'd1) begin
				state  <= S_IDLE;
				busy   <= 0;
				loaded <= 1;
			end else begin
				push_addr <= push_addr + 8'd1;
			end
		end

		S_SAVE: begin
			if (sd_ack_fall) begin
				sd_wr <= 0;
				busy  <= 0;
				dirty <= 0;
				state <= S_IDLE;
			end
		end
	endcase

	if (reset) begin
		state          <= S_IDLE;
		busy           <= 0;
		loaded         <= 0;
		readonly_r     <= 0;
		dirty          <= 0;
		save_timer     <= 0;
		push_addr      <= 0;
		cmos_index     <= 0;
		sd_rd          <= 0;
		sd_wr          <= 0;
		mount_pending  <= 0;
		mount_timer    <= 0;
		last_img_size  <= 0;
		img_mounted_d  <= 0;
		sd_ack_d       <= 0;
	end
end

endmodule
