`timescale 1ns / 1ps
//
// CacheInstructions
//
`default_nettype none

module TestBench;

  BurstRAM #(
      .DATA_FILE("RAM.mem"),
      .DATA_BITWIDTH(64),
      .DEPTH_BITWIDTH(4),
      .CYCLES_BEFORE_DATA_VALID(3),
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

  CacheInstructions #(
      .LINE_IX_BITWIDTH(1),  // 2^1 cache lines
      .ADDRESS_BITWIDTH(32),
      .DATA_BITWIDTH(32),  // 4 B per instruction
      .DATA_IX_IN_LINE_BITWIDTH(3),  // 2^3 32 bit instructions per cache line (32B)
      .RAM_DEPTH_BITWIDTH(4),
      .RAM_BURST_DATA_BITWIDTH(64),
      .RAM_BURST_DATA_COUNT(4)  // 4 * 64 bits = 32B
      // note: size of INSTRUCTION_IX_IN_LINE_BITWIDTH and RAM_READ_BURST_COUNT must
      //       result in same number of bytes because a cache line is loaded by the size of a burst
  ) dut (
      .clk(clk),
      .rst(rst),
      .enable(enable),
      .address(address),
      .data(instruction),
      .data_valid(data_valid),
      .busy(busy),

      // wiring to BurstRAM (prefix br_)
      .br_cmd(br_cmd),
      .br_cmd_en(br_cmd_en),
      .br_addr(br_addr),
      .br_rd_data(br_rd_data),
      .br_rd_data_valid(br_rd_data_valid),
      .br_busy(br_busy)
  );

  // wiring between BurstRAM and ICache
  wire br_cmd;
  wire br_cmd_en;
  wire [3:0] br_addr;
  wire [63:0] br_wr_data;
  wire [7:0] br_data_mask;
  wire [63:0] br_rd_data;
  wire br_rd_data_valid;
  wire br_busy;
  // --

  localparam clk_tk = 10;
  reg clk = 0;
  always #(clk_tk / 2) clk = ~clk;

  reg rst = 1;

  reg enable = 0;
  reg [31:0] address = 0;
  wire [31:0] instruction;
  wire data_valid;
  wire busy;

  initial begin
    $dumpfile("log.vcd");
    $dumpvars(0, TestBench);

    // reset
    #clk_tk;
    #(clk_tk / 2);
    rst = 0;

    // wait for initiation to complete
    while (busy) #clk_tk;

    // cache miss
    address <= 0;
    enable  <= 1;
    #clk_tk;
    enable <= 0;

    while (!data_valid) #clk_tk;

    if (dut.stat_cache_misses == 1) $display("test 1 passed");
    else $display("test 1 FAILED");

    if (instruction == 32'hB7C6A980) $display("test 2 passed");
    else $display("test 2 FAILED");

    // note: data may be valid before BurstRAM transaction is finished
    while (busy) #clk_tk;

    // cache hit
    address <= 4;
    enable  <= 1;
    #clk_tk;
    enable  <= 0;

    // cache hit
    address <= 8;
    enable  <= 1;
    #clk_tk;
    enable <= 0;

    // checking result from address 4 (one cycle delay from cache)
    if (dut.stat_cache_hits == 1) $display("test 3 passed");
    else $display("test 3 FAILED");

    if (instruction == 32'h3F5A2E14) $display("test 4 passed");
    else $display("test 4 FAILED");

    // cache hit
    address <= 16;
    enable  <= 1;
    #clk_tk;
    enable <= 0;

    // check result from address 8 (one cycle delay from cache)
    if (dut.stat_cache_hits == 2) $display("test 5 passed");
    else $display("test 5 FAILED");

    if (instruction == 32'hAB4C3E6F) $display("test 6 passed");
    else $display("test 6 FAILED");

    // cache miss
    address <= 32;
    enable  <= 1;
    #clk_tk;
    enable <= 0;

    // checking result from address 16 (one cycle delay from cache)
    if (dut.stat_cache_hits == 3) $display("test 7 passed");
    else $display("test 7 FAILED");

    if (instruction == 32'hD5B8A9C4) $display("test 8 passed");
    else $display("test 8 FAILED");

    #clk_tk;

    // waiting for result from address 32
    while (!data_valid) #clk_tk;

    if (dut.stat_cache_misses == 2) $display("test 9 passed");
    else $display("test 9 FAILED");

    if (instruction == 32'h2F5E3C7A) $display("test 11 passed");
    else $display("test 11 FAILED");

    while (busy) #clk_tk;

    // cache miss (eviction)
    address <= 68;
    enable  <= 1;
    #clk_tk;
    enable <= 0;

    #clk_tk;
    
    while (!data_valid) #clk_tk;

    if (dut.stat_cache_misses == 3) $display("test 12 passed");
    else $display("test 12 FAILED");

    if (instruction == 32'h0A1B2C3D) $display("test 13 passed");
    else $display("test 13 FAILED");

    while (busy) #clk_tk;

    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;

    // $display("cache(hits,misses): (%0d,%0d)", dut.stat_cache_hits, dut.stat_cache_misses);

    $finish;
  end

endmodule
