`default_nettype none

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
    // port A
    input wire enA,
    input wire [DATA_BITWIDTH/8-1:0] weA,
    input wire [ADDRESS_BITWIDTH-1:0] addrA,
    input wire [DATA_BITWIDTH-1:0] dinA,
    output wire [DATA_BITWIDTH-1:0] doutA,
    // port B
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
      .command(dcache_command),
      .address(addrA),
      .data_out(doutA),
      .data_out_ready(dcache_data_out_ready),
      .busy(dcache_busy),
      .write_enable_bytes(weA),
      .data_in(dinA),

      // -- wiring to BurstRAM (prefix br_) -- -- -- -- -- --
      .br_cmd(dcache_br_cmd),
      .br_cmd_en(dcache_br_cmd_en),
      .br_addr(dcache_br_addr),
      .br_rd_data(br_rd_data),
      .br_rd_data_valid(br_rd_data_valid),
      .br_wr_data(dcache_br_wr_data),
      .br_data_mask(dcache_br_data_mask),
      .br_busy(br_busy)
  );

  // Control signals for multiplexer
  reg icache_enable;
  reg dcache_enable;

  reg dcache_command;
  wire dcache_data_out_ready;
  wire dcache_busy;

  // Intermediate signals for BurstRAM
  wire icache_br_cmd;
  wire icache_br_cmd_en;
  wire [RAM_DEPTH_BITWIDTH-1:0] icache_br_addr;
  wire [RAM_BURST_DATA_BITWIDTH-1:0] icache_br_wr_data;
  wire [RAM_BURST_DATA_BITWIDTH/8-1:0] icache_br_data_mask;

  wire dcache_br_cmd;
  wire dcache_br_cmd_en;
  wire [RAM_DEPTH_BITWIDTH-1:0] dcache_br_addr;
  wire [RAM_BURST_DATA_BITWIDTH-1:0] dcache_br_wr_data;
  wire [RAM_BURST_DATA_BITWIDTH/8-1:0] dcache_br_data_mask;

  // Multiplexer logic for shared BurstRAM resource
  assign br_cmd = icache_enable ? icache_br_cmd : dcache_br_cmd;
  assign br_cmd_en = icache_enable ? icache_br_cmd_en : dcache_br_cmd_en;
  assign br_addr = icache_enable ? icache_br_addr : dcache_br_addr;
  assign br_wr_data = icache_enable ? icache_br_wr_data : dcache_br_wr_data;
  assign br_data_mask = icache_enable ? icache_br_data_mask : dcache_br_data_mask;

  // Control logic to enable either icache or dcache
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      icache_enable <= 1;
      dcache_enable <= 0;
    end
  end

endmodule

`default_nettype wire
