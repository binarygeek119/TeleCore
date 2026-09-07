//
// TeleCore ROM loader
//
// Receives files from the MiSTer HPS through the hps_io ioctl interface and
// writes them into the emulated PC's DDR memory while the machine is held in
// reset.
//
//   slot 0  boot0.rom   BIOS            -> F0000h  (64 KB)
//   slot 1  boot1.rom   terminal ROM    -> C8000h  (96 KB)
//   slot 2-9  OSD F2..F9 add-on ROMs    -> 400000h + (n-2)*10000h (64 KB each)
//
// ioctl_index decode (MiSTer):
//   boot<N>.rom auto-load : index = N<<6         (low 6 bits zero)
//   OSD "F<n>" entry      : index = (ext<<6) | n  (low 6 bits = n)
//
// A 64 KB "blank" bank at 480000h is filled with FFh at power-up; the SoC maps
// the E0000h window there when no slot is selected or the slot is empty.
// If no BIOS arrives within ~3 s a small fallback stub is written to FFE00h so
// the screen never stays black.
//

module rom_loader
(
	input             clk,
	input             reset,          // framework reset (not the CPU reset)

	// hps_io ioctl
	input             ioctl_download,
	input      [15:0] ioctl_index,
	input             ioctl_wr,
	input      [26:0] ioctl_addr,
	input      [15:0] ioctl_dout,
	output            ioctl_wait,

	// DDR master (64-bit words inside the 256 MB core window)
	output reg [24:0] ddr_addr,
	output reg [63:0] ddr_din,
	output reg  [7:0] ddr_be,
	output reg        ddr_we,
	input             ddr_busy,

	output            active,         // 1 = loader owns DDR, hold the machine in reset
	output reg  [9:0] rom_present,
	output reg        bios_present
);

localparam [3:0] S_FILL     = 0,  // fill blank bank with FFh
                 S_WAIT     = 1,  // waiting for BIOS
                 S_LOAD     = 2,  // download in progress
                 S_SETTLE   = 3,  // short delay after download
                 S_FALLBACK = 4,  // write fallback stub
                 S_RUN      = 5;  // machine running

reg  [3:0] state = S_FILL;
assign active = (state != S_RUN);

// ---------------------------------------------------------------- slot decode
wire [3:0] slot = (ioctl_index[5:0] == 0) ? {2'b00, ioctl_index[7:6]} : ioctl_index[3:0];
wire       slot_ok = (ioctl_index[5:0] == 0) ? (ioctl_index[7:6] < 2) : (ioctl_index[5:0] >= 2 && ioctl_index[5:0] <= 9);

reg  [27:0] slot_base;
reg  [17:0] slot_size;
always @(*) begin
	case (slot)
		4'd0:    begin slot_base = 28'h00F0000; slot_size = 18'h10000; end
		4'd1:    begin slot_base = 28'h00C8000; slot_size = 18'h18000; end
		default: begin slot_base = 28'h0400000 + ({24'd0, slot - 4'd2} << 16); slot_size = 18'h10000; end
	endcase
end

wire        in_range = ioctl_addr < slot_size;
wire [27:0] byte_addr = slot_base + ioctl_addr;

// ---------------------------------------------------------------- fallback stub
reg [7:0] stub [0:511];
initial $readmemh("rtl/fallback.hex", stub);

// ---------------------------------------------------------------- main FSM
reg [27:0] timer;
reg [13:0] fill_cnt;
reg        pending;         // a DDR write is queued but not yet accepted
reg [24:0] hold_addr;
reg [63:0] hold_din;
reg  [7:0] hold_be;
reg        dl_active_d;
reg  [3:0] dl_slot;

assign ioctl_wait = pending;

always @(posedge clk) begin
	dl_active_d <= ioctl_download;

	if (ddr_we && !ddr_busy) ddr_we <= 0;

	if (reset) begin
		state        <= S_FILL;
		fill_cnt     <= 0;
		timer        <= 0;
		pending      <= 0;
		ddr_we       <= 0;
		rom_present  <= 0;
		bios_present <= 0;
	end
	else case (state)

	// fill 64 KB blank bank (8192 x 64-bit words) with FFh
	S_FILL: begin
		if (!ddr_we || !ddr_busy) begin
			if (fill_cnt == 14'd8192) begin
				ddr_we <= 0;
				timer  <= 0;
				state  <= S_WAIT;
			end
			else begin
				ddr_addr <= 25'h0090000 + fill_cnt;   // 480000h >> 3
				ddr_din  <= {64{1'b1}};
				ddr_be   <= 8'hFF;
				ddr_we   <= 1;
				fill_cnt <= fill_cnt + 1'd1;
			end
		end
	end

	// wait for BIOS download; ~3 s timeout at 30 MHz
	S_WAIT: begin
		timer <= timer + 1'd1;
		if (ioctl_download) begin
			state   <= S_LOAD;
			dl_slot <= slot;
			if (slot_ok) rom_present[slot] <= 0;
		end
		else if (timer[27:0] >= 28'd90000000) begin
			fill_cnt <= 0;
			state    <= S_FALLBACK;
		end
	end

	// stream ioctl words into DDR (one-entry holding register, ioctl_wait throttles the HPS)
	S_LOAD: begin
		if (pending && !(ddr_we && ddr_busy)) begin
			ddr_addr <= hold_addr;
			ddr_din  <= hold_din;
			ddr_be   <= hold_be;
			ddr_we   <= 1;
			pending  <= 0;
		end
		if (ioctl_wr && slot_ok && in_range) begin
			hold_addr <= byte_addr[27:3];
			hold_din  <= {4{ioctl_dout}};
			hold_be   <= 8'h03 << {byte_addr[2:1], 1'b0};
			pending   <= 1;
		end
		if (!ioctl_download && !ddr_we && !pending) begin
			if (slot_ok) begin
				rom_present[dl_slot] <= 1;
				if (dl_slot == 0) bios_present <= 1;
			end
			timer <= 0;
			state <= S_SETTLE;
		end
	end

	// let the HPS send the next auto-load file before releasing the CPU
	S_SETTLE: begin
		timer <= timer + 1'd1;
		if (ioctl_download) begin
			state   <= S_LOAD;
			dl_slot <= slot;
			if (slot_ok) rom_present[slot] <= 0;
		end
		else if (timer >= 28'd15000000) begin        // ~0.5 s
			timer <= 0;
			state <= bios_present ? S_RUN : S_WAIT;
		end
	end

	// no BIOS: write 512-byte stub to FFE00h..FFFFFh
	S_FALLBACK: begin
		if (!ddr_we || !ddr_busy) begin
			if (fill_cnt == 14'd512) begin
				ddr_we <= 0;
				state  <= S_RUN;
			end
			else begin
				ddr_addr <= 25'h001FFC0 + fill_cnt[8:3];   // FFE00h >> 3
				ddr_din  <= {8{stub[fill_cnt[8:0]]}};
				ddr_be   <= 8'h01 << fill_cnt[2:0];
				ddr_we   <= 1;
				fill_cnt <= fill_cnt + 1'd1;
			end
		end
	end

	// running; a new download (OSD file pick) resets the machine
	S_RUN: begin
		if (ioctl_download && !dl_active_d) begin
			state   <= S_LOAD;
			dl_slot <= slot;
			if (slot_ok) rom_present[slot] <= 0;
		end
	end

	default: state <= S_RUN;
	endcase
end

endmodule
