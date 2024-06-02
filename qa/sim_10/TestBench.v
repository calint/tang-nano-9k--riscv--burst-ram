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
      .rdyA (rdyA),
      .bsyA (bsyA),

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
  reg enA = 0;
  reg [3:0] weA = 0;
  reg [31:0] addrA = 0;
  reg [31:0] dinA = 0;
  wire [31:0] doutA;
  wire rdyA;
  wire bsyA;

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

    addrB <= 4;
    while (!rdyB) #clk_tk;
    if (doutB == 32'h3F5A2E14) $display("test 1 passed");
    else $display("test 1 FAILED");
    while (bsyB) #clk_tk;

    addrB <= 8;
    #clk_tk;
    while (!rdyB) #clk_tk;
    if (doutB == 32'hAB4C3E6F) $display("test 2 passed");
    else $display("test 2 FAILED");
    while (bsyB) #clk_tk;

    addrB <= 12;
    addrA <= 16;
    enA   <= 1;

    #clk_tk;

    $finish;

    while (!rdyB) #clk_tk;
    if (doutB == 32'h9D8E2F17) $display("test 3 passed");
    else $display("test 3 FAILED");

    while (!rdyA) #clk_tk;
    if (doutA == 32'hD5B8A9C4) $display("test 4 passed");
    else $display("test 4 FAILED");

    while (bsyB || bsyA) #clk_tk;

    rst <= 1;
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
