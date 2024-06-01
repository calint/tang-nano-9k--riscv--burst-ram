//
// instructions and data RAM
// port A: read / write 32 bit data
// port B: read-only 32 bit instruction
//

`default_nettype none
// `define DBG

module Cache #(
    parameter ADDRESS_BITWIDTH = 32,
    // 2 ^ 32 addressable bytes

    parameter DATA_BITWIDTH = 32,
    // size of data; must be divisble by 8

    parameter CACHE_LINE_IX_BITWIDTH = 1,
    // 2 ^ 1 = 2 cache lines

    parameter CACHE_IX_IN_LINE_BITWIDTH = 3,
    // 2 ^ 3 = 8 data per cache line

    parameter RAM_DEPTH_BITWIDTH = 4,
    // 2 ^ 4 = 16 RAM entries of size RAM_BURST_DATA_BITWIDTH
    // note: must be same as specified to BurstRAM

    parameter RAM_BURST_DATA_COUNT = 4,
    // how many consecutive data elements are sent in a burst

    parameter RAM_BURST_DATA_BITWIDTH = 64
    // size of data sent in bits, must be divisible by 8 into bytes
    // RAM reads 4 * 8 = 32 B per burst
    // note: the burst size and cache line data must match in size
    //       a burst reads or writes one cache line thus:
    //       RAM_BURST_DATA_COUNT * RAM_BURST_DATA_BITWIDTH / 8 = 
    //       2 ^ CACHE_IX_IN_LINE_BITWIDTH * DATA_BITWIDTH / 8 =
    //       32 B
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

  CacheInstructions #(
      .ADDRESS_BITWIDTH(ADDRESS_BITWIDTH),
      .DATA_BITWIDTH(32),
      .LINE_IX_BITWIDTH(CACHE_LINE_IX_BITWIDTH),
      .DATA_IX_IN_LINE_BITWIDTH(CACHE_IX_IN_LINE_BITWIDTH),
      .RAM_DEPTH_BITWIDTH(RAM_DEPTH_BITWIDTH),
      .RAM_BURST_DATA_BITWIDTH(RAM_BURST_DATA_BITWIDTH),
      .RAM_BURST_DATA_COUNT(RAM_BURST_DATA_COUNT)
      // .ADDRESS_LEADING_ZEROS_BITWIDTH(2)
  ) icache (
      .clk(clk),
      .rst(rst),
      .enable(icache_enable),
      .address(addrB),
      .data(doutB),
      .data_ready(rdyB),
      .busy(bsyB),

      // -- wiring to BurstRAM (prefix br_) -- -- -- -- -- --
      .br_cmd(br_cmd),
      .br_cmd_en(br_cmd_en),
      .br_addr(br_addr),
      .br_rd_data(br_rd_data),
      .br_rd_data_valid(br_rd_data_valid),
      .br_busy(br_busy)
  );

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
      .br_cmd(br_cmd),
      .br_cmd_en(br_cmd_en),
      .br_addr(br_addr),
      .br_rd_data(br_rd_data),
      .br_rd_data_valid(br_rd_data_valid),
      .br_wr_data(br_wr_data),
      .br_data_mask(br_data_mask),
      .br_busy(br_busy)
      // -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
  );

  reg icache_br_cmd;
  reg icache_br_cmd_en;
  reg [ADDRESS_BITWIDTH-1:0] icache_br_addr;

  reg dcache_br_cmd;
  reg dcache_br_cmd_en;
  reg [ADDRESS_BITWIDTH-1:0] dcache_br_addr;
  reg dcache_enable;

  reg icache_enable;

  reg dcache_command;
  wire dcache_data_out_ready;
  wire dcache_busy;
  reg [DATA_BITWIDTH-1:0] din;

  assign br_cmd = icache_enable ? icache_br_cmd : dcache_br_cmd;
  assign br_cmd_en = icache_enable ? icache_br_cmd_en : dcache_br_cmd_en;
  assign br_addr = icache_enable ? icache_br_addr : dcache_br_addr;


  always @(posedge clk) begin
    icache_br_cmd_en <= 1;
    icache_enable <= 1;
  end

endmodule

`undef DBG
`default_nettype wire
