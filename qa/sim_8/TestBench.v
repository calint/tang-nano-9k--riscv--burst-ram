`timescale 1ns / 1ps
//
// Cache: instruction
//
`default_nettype none

module TestBench;

  localparam RAM_DATA_BITWIDTH = 64;
  localparam RAM_ADDRESS_BITWIDTH = 8;  // 2 ^ 8 * 8 bytes RAM
  localparam RAM_BURST_COUNT = 4;

  BurstRAM #(
      .DATA_FILE("RAM.mem"),
      .DEPTH_BITWIDTH(RAM_ADDRESS_BITWIDTH),
      .DATA_BITWIDTH(RAM_DATA_BITWIDTH),
      .BURST_COUNT(RAM_BURST_COUNT),
      .CYCLES_BEFORE_INITIATED(10),
      .CYCLES_BEFORE_DATA_VALID(4)
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
      .RAM_DEPTH_BITWIDTH(RAM_ADDRESS_BITWIDTH),
      .RAM_BURST_DATA_COUNT(RAM_BURST_COUNT),
      .RAM_BURST_DATA_BITWIDTH(RAM_DATA_BITWIDTH),
      .CACHE_LINE_IX_BITWIDTH(1)
  ) cache (
      .clk(clk_ram),
      .rst(rst),

      .enA  (enA),
      .weA  (weA),
      .addrA(addrA),
      .dinA (dinA),
      .doutA(doutA),
      .validA(validA),
      .bsyA(bsyA),

      .addrB (addrB),
      .doutB (doutB),
      .validB(validB),
      .bsyB  (bsyB),

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
  reg enA = 0;
  reg [3:0] weA = 0;
  wire [31:0] doutA;
  wire validA;
  wire bsyA;

  reg [31:0] addrB = 0;
  wire [31:0] doutB;
  wire validB;
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

    $finish;

    // read instruction 0x0000 (cache miss)
    addrB <= 0;
    #clk_tk;
    #clk_tk;

    while (!validB) #clk_tk;

    if (doutB == 32'hB7C6A980) $display("test 1 passed");
    else $display("test 1 FAILED");

    while (bsyB) #clk_tk;

    // read instruction 0x0004 (cache hit)
    addrB <= 4;
    #clk_tk;

    // read instruction 0x0008 (cache hit)
    addrB <= 8;
    #clk_tk;

    // check result from address 4 (one cycle delay)
    if (validB) $display("test 2 passed");
    else $display("test 2 FAILED");

    if (!bsyB) $display("test 3 passed");
    else $display("test 3 FAILED");

    // read instruction 0x0040 (cache miss)
    addrB <= 64;
    #clk_tk;

    // check result from address 8 (one cycle delay)
    if (doutB == 32'hAB4C3E6F) $display("test 4 passed");
    else $display("test 4 FAILED");

    // the cache miss from address 64
    while (!validB) #clk_tk;

    if (doutB == 32'h4E5F6A7B) $display("test 5 passed");
    else $display("test 5 FAILED");

    while (bsyB) #clk_tk;

    // read instruction 0x0008 (cache miss, eviction)
    addrB <= 32;
    #clk_tk;

    while (!validB) #clk_tk;

    if (doutB == 32'h2F5E3C7A) $display("test 7 passed");
    else $display("test 7 FAILED");

    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;

    $finish;
  end

endmodule
