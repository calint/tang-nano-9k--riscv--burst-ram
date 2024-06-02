//
// instruction cache connected to BurstRAM
//

`default_nettype none
`define DBG
// `define INFO

module Cache #(
    parameter ADDRESS_BITWIDTH = 32,
    parameter DATA_BITWIDTH = 32,
    parameter CACHE_LINE_IX_BITWIDTH = 1,
    parameter CACHE_IX_IN_LINE_BITWIDTH = 3,
    parameter RAM_DEPTH_BITWIDTH = 4,
    parameter RAM_BURST_DATA_COUNT = 4,
    parameter RAM_BURST_DATA_BITWIDTH = 64
) (
    input wire clk,
    input wire rst,

    // port A: data
    input wire enA,
    input wire [DATA_BITWIDTH/8-1:0] weA,
    input wire [ADDRESS_BITWIDTH-1:0] addrA,
    input wire [DATA_BITWIDTH-1:0] dinA,
    output wire [DATA_BITWIDTH-1:0] doutA,
    output wire rdyA,
    output wire bsyA,

    // port B: instructions
    input wire [ADDRESS_BITWIDTH-1:0] addrB,
    output wire [DATA_BITWIDTH-1:0] doutB,
    output wire rdyB,
    output wire bsyB,

    // wiring to BurstRAM (prefix br_)
    output wire br_cmd,
    output wire br_cmd_en,
    output wire [RAM_DEPTH_BITWIDTH-1:0] br_addr,
    output wire [RAM_BURST_DATA_BITWIDTH-1:0] br_wr_data,
    output wire [RAM_BURST_DATA_BITWIDTH/8-1:0] br_data_mask,
    input wire [RAM_BURST_DATA_BITWIDTH-1:0] br_rd_data,
    input wire br_rd_data_valid,
    input wire br_busy
);

  // port A
  CacheInstructions #(
      .ADDRESS_BITWIDTH(ADDRESS_BITWIDTH),
      .DATA_BITWIDTH(32),
      .LINE_IX_BITWIDTH(CACHE_LINE_IX_BITWIDTH),
      .DATA_IX_IN_LINE_BITWIDTH(CACHE_IX_IN_LINE_BITWIDTH),
      .RAM_DEPTH_BITWIDTH(RAM_DEPTH_BITWIDTH),
      .RAM_BURST_DATA_BITWIDTH(RAM_BURST_DATA_BITWIDTH),
      .RAM_BURST_DATA_COUNT(RAM_BURST_DATA_COUNT)
  ) icache (
      .clk(clk),
      .rst(rst),
      .enable(icache_enable),
      .address(addrB),
      .data(doutB),
      .data_ready(rdyB),
      .busy(bsyB),

      // -- wiring to BurstRAM (prefix br_) -- -- -- -- -- --
      .br_cmd(icache_br_cmd),
      .br_cmd_en(icache_br_cmd_en),
      .br_addr(icache_br_addr),
      .br_rd_data(br_rd_data),
      .br_rd_data_valid(br_rd_data_valid),
      .br_busy(br_busy)
  );

  // port B
  CacheData #(
      .ADDRESS_BITWIDTH(ADDRESS_BITWIDTH),
      .DATA_BITWIDTH(32),
      .LINE_IX_BITWIDTH(CACHE_LINE_IX_BITWIDTH),
      .DATA_IX_IN_LINE_BITWIDTH(CACHE_IX_IN_LINE_BITWIDTH),
      .RAM_BURST_DATA_COUNT(RAM_BURST_DATA_COUNT),
      .RAM_BURST_DATA_BITWIDTH(RAM_BURST_DATA_BITWIDTH),
      .RAM_DEPTH_BITWIDTH(RAM_DEPTH_BITWIDTH),
      .ADDRESS_LEADING_ZEROS_BITWIDTH(2)
  ) dcache (
      .clk(clk),
      .rst(rst),
      .enable(dcache_enable),
      .write_enable_bytes(weA),
      .command(dcache_command),
      .address(addrA),
      .data_in(dinA),
      .data_out(doutA),
      .data_out_ready(dcache_data_out_ready),
      .busy(dcache_busy),

      // -- wiring to BurstRAM (prefix br_) -- -- -- -- -- --
      .br_cmd(dcache_br_cmd),
      .br_cmd_en(dcache_br_cmd_en),
      .br_addr(dcache_br_addr),
      .br_rd_data(br_rd_data),
      .br_rd_data_valid(br_rd_data_valid),
      .br_wr_data(br_wr_data),
      .br_data_mask(br_data_mask),
      .br_busy(br_busy)
  );

  // port B to BurstRAM wires
  wire icache_br_cmd;
  wire icache_br_cmd_en;
  wire [RAM_DEPTH_BITWIDTH-1:0] icache_br_addr;
  wire [RAM_BURST_DATA_BITWIDTH-1:0] icache_br_wr_data;
  wire [RAM_BURST_DATA_BITWIDTH/8-1:0] icache_br_data_mask;

  // port A to CacheData
  wire dcache_command;
  wire dcache_busy;
  wire dcache_data_out_ready;

  reg icache_enable;
  reg dcache_enable;

  assign bsyA = dcache_busy;
  assign rdyA = dcache_data_out_ready;

  // 
  wire dcache_br_cmd;
  wire dcache_br_cmd_en;
  wire [RAM_DEPTH_BITWIDTH-1:0] dcache_br_addr;
  wire [RAM_BURST_DATA_BITWIDTH-1:0] dcache_br_wr_data;
  wire [RAM_BURST_DATA_BITWIDTH/8-1:0] dcache_br_data_mask;

  localparam STATE_CACHE_INSTRUCTIONS_ACTIVATE = 4'b0001;
  localparam STATE_CACHE_INSTRUCTIONS_WAIT = 4'b0010;
  localparam STATE_CACHE_DATA_ACTIVATE = 4'b0100;
  localparam STATE_CACHE_DATA_WAIT = 4'b1000;

  assign br_cmd = icache_enable ? icache_br_cmd : dcache_br_cmd;
  assign br_cmd_en = icache_enable ? icache_br_cmd_en : dcache_br_cmd_en;
  assign br_addr = icache_enable ? icache_br_addr : dcache_br_addr;

  reg [3:0] state;

  always @(posedge clk) begin
    if (rst) begin
      state <= STATE_CACHE_INSTRUCTIONS_ACTIVATE;
      icache_enable <= 1;
      dcache_enable <= 0;
    end
  end

  always @(posedge clk) begin

// `ifdef DBG
//     $display("state: %0d  rdyA: %0d  bsyA: %0d  dcache_busy: %0d", state, rdyA, dcache_busy,
//              dcache_busy);
// `endif

    case (state)

      STATE_CACHE_INSTRUCTIONS_ACTIVATE: begin
        // note: skip one cycle for 'bsyB' to go high
        state <= STATE_CACHE_INSTRUCTIONS_WAIT;
      end

      STATE_CACHE_INSTRUCTIONS_WAIT: begin
        if (!bsyB && enA) begin
          icache_enable <= 0;
          dcache_enable <= 1;
          state = STATE_CACHE_DATA_ACTIVATE;
        end
      end

      STATE_CACHE_DATA_ACTIVATE: begin
        // note: skip one cycle for 'dcache_busy' to go high
        state <= STATE_CACHE_DATA_WAIT;
      end

      STATE_CACHE_DATA_WAIT: begin
        if (!dcache_busy) begin
          icache_enable <= 1;
          dcache_enable <= 0;
          state = STATE_CACHE_INSTRUCTIONS_ACTIVATE;
        end
      end

    endcase
  end

endmodule

`default_nettype wire
