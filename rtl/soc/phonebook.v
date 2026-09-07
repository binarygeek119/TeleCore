module phonebook (
	input wire clk,
	input wire reset,
	input wire img_mounted,
	input wire img_readonly,
	input wire [63:0] img_size,
	output [31:0] sd_lba,
	output reg sd_rd,
	output reg sd_wr,
	input wire sd_ack,
	input wire [12:0] sd_buff_addr,
	input wire [15:0] sd_buff_dout,
	output wire [15:0] sd_buff_din,
	input wire sd_buff_wr,
	input wire [3:0] io_address,
	input wire io_cs,
	input wire io_read,
	input wire io_write,
	input wire [7:0] io_wdata,
	output reg [7:0] io_rdata
);

localparam [16:0] MAX_SIZE = 17'd65536;
localparam [16:0] HEADER_SIZE = 17'd32;
localparam [16:0] RECORD_SIZE = 17'd128;
localparam [1:0] S_IDLE = 2'd0;
localparam [1:0] S_READ = 2'd1;
localparam [1:0] S_WRITE = 2'd2;

reg [1:0] state;
reg present;
reg readonly_r;
reg busy;
reg [15:0] cpu_addr;
reg [7:0] rdata;
reg [16:0] pb_size;
reg [15:0] pb_max_records;
reg [7:0] sectors_needed;
reg [7:0] sectors_done;
reg [6:0] sd_lba_r;
reg img_mounted_d;
reg sd_ack_d;
reg mount_pending;
reg [15:0] mount_timer;
reg [16:0] last_img_size;

wire img_mounted_rise = img_mounted && !img_mounted_d;
wire sd_ack_fall = !sd_ack && sd_ack_d;
wire size_changed = (img_size[16:0] != last_img_size);

assign sd_lba = {25'd0, sd_lba_r};

wire [14:0] ram_addr_a = {sd_lba_r[6:0], sd_buff_addr[7:0]};
wire [14:0] ram_addr_b = cpu_addr[15:1];
wire [7:0] ram_data_a_lo = sd_buff_dout[7:0];
wire [7:0] ram_data_a_hi = sd_buff_dout[15:8];
wire ram_wren_a = (state == S_READ) ? (sd_ack & sd_buff_wr) : 1'b0;
wire [7:0] ram_q_a_lo;
wire [7:0] ram_q_a_hi;
wire [7:0] ram_q_b_lo;
wire [7:0] ram_q_b_hi;
wire [7:0] ram_byte = cpu_addr[0] ? ram_q_b_hi : ram_q_b_lo;
wire ram_wren_b_lo = (io_write && io_cs && (io_address == 4'd0) && !readonly_r && !busy && !cpu_addr[0]) ? 1'b1 : 1'b0;
wire ram_wren_b_hi = (io_write && io_cs && (io_address == 4'd0) && !readonly_r && !busy && cpu_addr[0]) ? 1'b1 : 1'b0;

assign sd_buff_din = {ram_q_a_hi, ram_q_a_lo};

always @(*) begin
	if (!io_cs) io_rdata = 8'hFF;
	else case (io_address)
		4'd0: io_rdata = rdata;
		4'd3: io_rdata = {5'b0, busy, readonly_r, present};
		4'd4: io_rdata = pb_size[7:0];
		4'd5: io_rdata = pb_size[15:8];
		4'd6: io_rdata = {7'b0, pb_size[16]};
		4'd7: io_rdata = pb_max_records[7:0];
		4'd8: io_rdata = pb_max_records[15:8];
		default: io_rdata = 8'hFF;
	endcase
end

always @(posedge clk) begin
	img_mounted_d <= img_mounted;
	sd_ack_d <= sd_ack;
	if (mount_timer != 0) mount_timer <= mount_timer - 16'd1;

	if (img_mounted_rise) begin
		mount_pending <= 1;
		mount_timer <= 16'hFFFF;
		last_img_size <= img_size[16:0];
	end

	if (mount_pending && (size_changed || (mount_timer == 0))) begin
		mount_pending <= 0;
		mount_timer <= 0;
		last_img_size <= img_size[16:0];
		readonly_r <= img_readonly;
		if (img_size[16:0] != 0) begin
			pb_size <= (img_size[16:0] > MAX_SIZE) ? MAX_SIZE : img_size[16:0];
			present <= 1;
			pb_max_records <= (img_size[16:0] > HEADER_SIZE) ? (((img_size[16:0] - HEADER_SIZE) / RECORD_SIZE) & 16'hFFFF) : 16'd0;
			sectors_needed <= (((img_size[16:0] + 17'd511) >> 9) & 8'hFF);
			state <= S_READ;
			busy <= 1;
			sd_rd <= 1;
			sd_wr <= 0;
			sd_lba_r <= 0;
			sectors_done <= 0;
		end else begin
			pb_size <= 0;
			present <= 0;
			pb_max_records <= 0;
			sectors_needed <= 0;
			busy <= 0;
			state <= S_IDLE;
			sd_rd <= 0;
			sd_wr <= 0;
		end
	end

	if (io_write && io_cs) begin
		case (io_address)
			4'd0: if (!readonly_r && !busy)
					cpu_addr <= cpu_addr + 16'd1;
			4'd1: cpu_addr[7:0] <= io_wdata;
			4'd2: cpu_addr[15:8] <= io_wdata;
			4'd3: begin
					if (io_wdata[0] && present && !readonly_r && !busy) begin
						state <= S_WRITE;
						busy <= 1;
						sd_wr <= 1;
						sd_rd <= 0;
						sd_lba_r <= 0;
						sectors_done <= 0;
					end
					if (io_wdata[1]) cpu_addr <= 0;
				end
		endcase
	end

	if (io_read && io_cs) begin
		if (io_address == 4'd0) begin
			rdata <= ram_byte;
			cpu_addr <= cpu_addr + 16'd1;
		end
	end

	case (state)
		S_IDLE: begin
		end
		S_READ: begin
			if (sd_ack_fall) begin
				sectors_done <= sectors_done + 8'd1;
				if ((sectors_done + 8'd1) >= sectors_needed) begin
					state <= S_IDLE;
					busy <= 0;
					sd_rd <= 0;
					sd_wr <= 0;
				end else begin
					sd_lba_r <= sd_lba_r + 7'd1;
					sd_rd <= 1;
					sd_wr <= 0;
				end
			end
		end
		S_WRITE: begin
			if (sd_ack_fall) begin
				sectors_done <= sectors_done + 8'd1;
				if ((sectors_done + 8'd1) >= sectors_needed) begin
					state <= S_IDLE;
					busy <= 0;
					sd_rd <= 0;
					sd_wr <= 0;
				end else begin
					sd_lba_r <= sd_lba_r + 7'd1;
					sd_wr <= 1;
					sd_rd <= 0;
				end
			end
		end
	endcase

	if (reset) begin
		present <= 0;
		readonly_r <= 0;
		busy <= 0;
		pb_size <= 0;
		pb_max_records <= 0;
		cpu_addr <= 0;
		rdata <= 0;
		state <= S_IDLE;
		sd_lba_r <= 0;
		sectors_done <= 0;
		sectors_needed <= 0;
		sd_rd <= 0;
		sd_wr <= 0;
		mount_pending <= 0;
		mount_timer <= 0;
		last_img_size <= 0;
		img_mounted_d <= 0;
		sd_ack_d <= 0;
	end
end

altsyncram ram_lo
(
	.clock0(clk),
	.address_a(ram_addr_a),
	.data_a(ram_data_a_lo),
	.wren_a(ram_wren_a),
	.q_a(ram_q_a_lo),
	.clock1(clk),
	.address_b(ram_addr_b),
	.data_b(io_wdata),
	.wren_b(ram_wren_b_lo),
	.q_b(ram_q_b_lo),
	.aclr0(1'b0),
	.aclr1(1'b0),
	.addressstall_a(1'b0),
	.addressstall_b(1'b0),
	.byteena_a(1'b1),
	.byteena_b(1'b1),
	.clocken0(1'b1),
	.clocken1(1'b1),
	.clocken2(1'b1),
	.clocken3(1'b1),
	.eccstatus(),
	.rden_a(1'b1),
	.rden_b(1'b1)
);
defparam
	ram_lo.numwords_a = 32768,
	ram_lo.widthad_a = 15,
	ram_lo.width_a = 8,
	ram_lo.numwords_b = 32768,
	ram_lo.widthad_b = 15,
	ram_lo.width_b = 8,
	ram_lo.operation_mode = "BIDIR_DUAL_PORT",
	ram_lo.outdata_reg_a = "UNREGISTERED",
	ram_lo.outdata_reg_b = "UNREGISTERED",
	ram_lo.intended_device_family = "Cyclone V",
	ram_lo.lpm_type = "altsyncram",
	ram_lo.power_up_uninitialized = "FALSE",
	ram_lo.read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ",
	ram_lo.read_during_write_mode_port_b = "NEW_DATA_NO_NBE_READ",
	ram_lo.width_byteena_a = 1,
	ram_lo.width_byteena_b = 1;

altsyncram ram_hi
(
	.clock0(clk),
	.address_a(ram_addr_a),
	.data_a(ram_data_a_hi),
	.wren_a(ram_wren_a),
	.q_a(ram_q_a_hi),
	.clock1(clk),
	.address_b(ram_addr_b),
	.data_b(io_wdata),
	.wren_b(ram_wren_b_hi),
	.q_b(ram_q_b_hi),
	.aclr0(1'b0),
	.aclr1(1'b0),
	.addressstall_a(1'b0),
	.addressstall_b(1'b0),
	.byteena_a(1'b1),
	.byteena_b(1'b1),
	.clocken0(1'b1),
	.clocken1(1'b1),
	.clocken2(1'b1),
	.clocken3(1'b1),
	.eccstatus(),
	.rden_a(1'b1),
	.rden_b(1'b1)
);
defparam
	ram_hi.numwords_a = 32768,
	ram_hi.widthad_a = 15,
	ram_hi.width_a = 8,
	ram_hi.numwords_b = 32768,
	ram_hi.widthad_b = 15,
	ram_hi.width_b = 8,
	ram_hi.operation_mode = "BIDIR_DUAL_PORT",
	ram_hi.outdata_reg_a = "UNREGISTERED",
	ram_hi.outdata_reg_b = "UNREGISTERED",
	ram_hi.intended_device_family = "Cyclone V",
	ram_hi.lpm_type = "altsyncram",
	ram_hi.power_up_uninitialized = "FALSE",
	ram_hi.read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ",
	ram_hi.read_during_write_mode_port_b = "NEW_DATA_NO_NBE_READ",
	ram_hi.width_byteena_a = 1,
	ram_hi.width_byteena_b = 1;

endmodule
