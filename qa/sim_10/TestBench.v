`timescale 1ns / 1ps
//
// Cache: instruction and data
//

`default_nettype none

module TestBench;

  localparam RAM_DATA_BITWIDTH = 64;
  localparam RAM_ADDRESS_BITWIDTH = 8;  // 2 ^ 8 * 8 bytes RAM
  localparam RAM_BURST_COUNT = 4;

  BurstRAM #(
      .DATA_FILE("RAM.mem"),
      .DATA_BITWIDTH(RAM_DATA_BITWIDTH),
      .DEPTH_BITWIDTH(RAM_ADDRESS_BITWIDTH),
      .CYCLES_BEFORE_DATA_READY(3),
      .BURST_COUNT(RAM_BURST_COUNT)
  ) burst_ram (
      .clk(clk_ram),
      .rst(rst),

      .cmd(br_cmd),
      .cmd_en(br_cmd_en),
      .addr(br_addr),
      .wr_data(br_wr_data),
      .data_mask(br_data_mask),
      .rd_data(br_rd_data),
      .rd_data_valid(br_rd_data_valid),
      .busy(br_busy)
  );

  Cache #(
      .ADDRESS_BITWIDTH(32),
      .DATA_BITWIDTH(32),
      .CACHE_LINE_IX_BITWIDTH(1),
      .CACHE_IX_IN_LINE_BITWIDTH(3),
      .RAM_DEPTH_BITWIDTH(RAM_ADDRESS_BITWIDTH),
      .RAM_BURST_DATA_COUNT(RAM_BURST_COUNT),
      .RAM_BURST_DATA_BITWIDTH(RAM_DATA_BITWIDTH)
  ) cache (
      .clk(clk_ram),
      .rst(rst),

      .enA  (enA),
      .weA  (weA),
      .addrA(addrA),
      .dinA (dinA),
      .doutA(doutA),

      .addrB(addrB),
      .doutB(doutB),
      .rdyB (rdyB),
      .bsyB (bsyB),

      // wiring to BurstRAM (prefix br_)
      .br_cmd(br_cmd),
      .br_cmd_en(br_cmd_en),
      .br_addr(br_addr),
      .br_wr_data(br_wr_data),
      .br_data_mask(br_data_mask),
      .br_rd_data(br_rd_data),
      .br_rd_data_valid(br_rd_data_valid),
      .br_busy(br_busy)
  );

  // wiring between BurstRAM and Cache
  wire br_cmd;
  wire br_cmd_en;
  wire [RAM_ADDRESS_BITWIDTH-1:0] br_addr;
  wire [63:0] br_wr_data;
  wire [7:0] br_data_mask;
  wire [63:0] br_rd_data;
  wire br_rd_data_valid;
  wire br_busy;
  // --

  // Cache interface
  reg [31:0] addrA = 0;
  reg [31:0] dinA = 0;
  reg [3:0] weA = 0;
  reg enA = 0;
  wire [31:0] doutA;
  reg [31:0] addrB = 0;
  wire [31:0] doutB;
  wire rdyB;
  wire bsyB;
  // --

  // CPU clock
  localparam clk_tk = 10;
  reg clk = 0;
  always #(clk_tk / 2) clk = ~clk;

  // RAM clock
  localparam clk_ram_tk = 2;
  reg clk_ram = 0;
  always #(clk_ram_tk / 2) clk_ram = ~clk_ram;

  reg rst = 1;

  initial begin
    $dumpfile("log.vcd");
    $dumpvars(0, TestBench);

    // reset
    #clk_tk;
    #(clk_tk / 2);
    rst = 0;

    // read instruction 0x0000 (cache miss) and request write
    addrB <= 4;
    enA   <= 1;
    weA   <= 4'b1111;
    addrA <= 32;
    dinA  <= 32'h2367_abcd;

    #clk_tk;

    addrB <= 8;
    enA   <= 1;
    weA   <= 4'b1111;
    addrA <= 36;
    dinA  <= 32'hfedc_ba98;

    #clk_tk;

    addrB <= 8;
    enA   <= 0;

    #clk_tk;

    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;

    $finish;
  end

endmodule
