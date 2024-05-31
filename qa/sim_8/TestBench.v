`timescale 1ns / 1ps
//
`default_nettype none
`define DBG

module TestBench;

  localparam RAM_ADDRESS_BITWIDTH = 4;

  BurstRAM #(
      .DATA_FILE("RAM.mem"),
      .DATA_BITWIDTH(64),
      .DEPTH_BITWIDTH(RAM_ADDRESS_BITWIDTH),
      .CYCLES_BEFORE_DATA_READY(3),
      .BURST_COUNT(4)
  ) burst_ram (
      .clk(clk),
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
      .ADDRESS_BITWIDTH(10),
      .INSTRUCTION_BITWIDTH(32),
      .ICACHE_LINE_IX_BITWIDTH(1),
      .CACHE_IX_IN_LINE_BITWIDTH(3),
      // 2^3 => instructions per cache line, 8 * 4 = 32 B
      // how many consequitive data is retrieved by BurstRAM
      .RAM_DEPTH_BITWIDTH(RAM_ADDRESS_BITWIDTH),
      .RAM_BURST_DATA_COUNT(4),
      .RAM_BURST_DATA_BITWIDTH(64)
      // size of data sent in bits, must be divisible by 8 into bytes
      // RAM reads 4 * 8 = 32 B per burst
      // note: the burst size and cache line data must match in size
      //       a burst reads or writes one cache line thus:
      //       RAM_BURST_DATA_COUNT * RAM_BURST_DATA_BITWIDTH / 8 = 
      //       2 ^ CACHE_IX_IN_LINE_BITWIDTH * INSTRUCTION_BITWIDTH =
      //       32B
  ) cache (
      .clk  (clk),
      .rst  (rst),
      .weA  (4'b0000),
      .addrA(addrA),
      .dinA (dinA),
      .doutA(doutA),
      .addrB(addrB),
      .doutB(doutB),
      .enB  (enB),
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
  wire [3:0] br_addr;
  wire [63:0] br_wr_data;
  wire [7:0] br_data_mask;
  wire [63:0] br_rd_data;
  wire br_rd_data_valid;
  wire br_busy;
  // --

  // Cache interface
  reg [3:0] weA = 0;
  reg [9:0] addrA = 0;
  reg [31:0] dinA = 0;
  wire [31:0] doutA;
  reg [9:0] addrB = 0;
  wire [31:0] doutB;
  reg enB = 0;
  wire rdyB;
  wire bsyB;
  // --


  localparam clk_tk = 10;
  reg clk = 0;
  always #(clk_tk / 2) clk = ~clk;

  reg rst = 1;

  initial begin
    $dumpfile("log.vcd");
    $dumpvars(0, TestBench);

    // reset
    #clk_tk;
    #(clk_tk / 2);
    rst   = 0;

    // read instruction 0x0000
    addrB = 0;
    enB   = 1;
    #clk_tk;
    enB = 0;

    while (!rdyB) #clk_tk;

    if (doutB == 32'hB7C6A980) $display("test 1 passed");
    else $display("test 1 FAILED");

    while (bsyB) #clk_tk;

    // read instruction 0x0004 (cache hit)
    addrB = 4;
    enB   = 1;
    #clk_tk;
    enB = 0;

    while (!rdyB) #clk_tk;

    if (doutB == 32'h3F5A2E14) $display("test 2 passed");
    else $display("test 2 FAILED");

    while (bsyB) #clk_tk;

    // read instruction 0x0008 (cache hit)
    addrB = 8;
    enB   = 1;
    #clk_tk;
    enB = 0;

    while (!rdyB) #clk_tk;

    if (doutB == 32'hAB4C3E6F) $display("test 3 passed");
    else $display("test 3 FAILED");

    while (bsyB) #clk_tk;

    // read instruction 0x0008 (cache miss)
    addrB = 64;
    enB   = 1;
    #clk_tk;
    enB = 0;

    while (!rdyB) #clk_tk;

    if (doutB == 32'h4E5F6A7B) $display("test 4 passed");
    else $display("test 4 FAILED");

    while (bsyB) #clk_tk;

    // read instruction 0x0008 (cache miss)
    addrB = 32;
    enB   = 1;
    #clk_tk;
    enB = 0;

    while (!rdyB) #clk_tk;

    if (doutB == 32'h2F5E3C7A) $display("test 5 passed");
    else $display("test 5 FAILED");

    while (bsyB) #clk_tk;

    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;

    $finish;
  end

endmodule
