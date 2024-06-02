`timescale 1ns / 1ps
//
// CacheData
//
`default_nettype none

module TestBench;

  BurstRAM #(
      .DATA_FILE("RAM.mem"),
      .DATA_BITWIDTH(64),
      .DEPTH_BITWIDTH(4),
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

  CacheData #(
      .LINE_IX_BITWIDTH(1),  // 2^1 cache lines
      .ADDRESS_BITWIDTH(32),
      .DATA_BITWIDTH(32),  // 4 B per data
      .DATA_IX_IN_LINE_BITWIDTH(3),  // 2^3 32 bit datas per cache line (32B)
      .RAM_DEPTH_BITWIDTH(4),
      .RAM_BURST_DATA_BITWIDTH(64),
      .RAM_BURST_DATA_COUNT(4)  // 4 * 64 bits = 32B
      // note: size of DATA_IX_IN_LINE_BITWIDTH and RAM_READ_BURST_COUNT must
      //       result in same number of bytes because a cache line is loaded by the size of a burst
  ) dut (
      .clk(clk),
      .rst(rst),
      .enable(enable),
      .address(address),
      .data_out(data),
      .data_out_ready(data_out_ready),
      .data_in(data_in),
      .write_enable_bytes(write_enable_bytes),
      .busy(busy),

      // wiring to BurstRAM (prefix br_)
      .br_cmd(br_cmd),
      .br_cmd_en(br_cmd_en),
      .br_addr(br_addr),
      .br_rd_data(br_rd_data),
      .br_rd_data_valid(br_rd_data_valid),
      .br_wr_data(br_wr_data),
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
  wire [31:0] data;
  wire data_out_ready;
  reg [31:0] data_in = 0;
  reg [3:0] write_enable_bytes = 0;
  wire busy;

  initial begin
    $dumpfile("log.vcd");
    $dumpvars(0, TestBench);

    // reset
    #clk_tk;
    #(clk_tk / 2);
    rst = 0;

    // cache miss
    address = 0;
    enable = 1;
    #clk_tk;
    enable = 0;

    while (!data_out_ready) #clk_tk;

    if (dut.stat_cache_misses == 1) $display("test 1 passed");
    else $display("test 1 FAILED");

    if (data == 32'hB7C6A980) $display("test 2 passed");
    else $display("test 2 FAILED");

    // note: data may be ready before cache is finished retrieving data
    while (busy) #clk_tk;

    // cache hit
    address = 4;
    enable  = 1;
    #clk_tk;
    enable = 0;

    while (!data_out_ready) #clk_tk;

    if (dut.stat_cache_hits == 1) $display("test 3 passed");
    else $display("test 3 FAILED");

    if (data == 32'h3F5A2E14) $display("test 4 passed");
    else $display("test 4 FAILED");

    while (busy) #clk_tk;

    // cache hit
    address = 8;
    enable  = 1;
    #clk_tk;
    enable = 0;

    while (!data_out_ready) #clk_tk;

    if (dut.stat_cache_hits == 2) $display("test 5 passed");
    else $display("test 5 FAILED");

    if (data == 32'hAB4C3E6F) $display("test 6 passed");
    else $display("test 6 FAILED");

    while (busy) #clk_tk;

    // cache hit
    address = 16;
    enable  = 1;
    #clk_tk;
    enable = 0;

    while (!data_out_ready) #clk_tk;

    if (dut.stat_cache_hits == 3) $display("test 7 passed");
    else $display("test 7 FAILED");

    if (data == 32'hD5B8A9C4) $display("test 8 passed");
    else $display("test 8 FAILED");

    while (busy) #clk_tk;

    // cache miss
    address = 32;
    enable  = 1;
    #clk_tk;
    enable = 0;

    while (!data_out_ready) #clk_tk;

    if (dut.stat_cache_misses == 2) $display("test 9 passed");
    else $display("test 9 FAILED");

    if (data == 32'h2F5E3C7A) $display("test 11 passed");
    else $display("test 11 FAILED");

    while (busy) #clk_tk;

    // cache miss, evict, not dirty
    address = 68;
    enable  = 1;
    #clk_tk;
    enable = 0;

    while (!data_out_ready) #clk_tk;

    if (dut.stat_cache_misses == 3) $display("test 12 passed");
    else $display("test 12 FAILED");

    if (data == 32'h0A1B2C3D) $display("test 13 passed");
    else $display("test 13 FAILED");

    while (busy) #clk_tk;

    // write 1 byte, cache miss, evict, not dirty, write
    address = 0;
    data_in <= 32'h12345678;
    write_enable_bytes = 4'b0010;  // write 0x56 => 0xB7C6_56_80
    enable = 1;
    #clk_tk;
    enable = 0;

    while (busy) #clk_tk;

    if (dut.stat_cache_misses == 4) $display("test 12 passed");
    else $display("test 12 FAILED");

    // read, cached, written byte
    write_enable_bytes = 0;
    address = 0;
    enable = 1;
    #clk_tk;
    enable = 0;

    while (!data_out_ready) #clk_tk;

    if (data == 32'hB7C6_56_80) $display("test 13 passed");
    else $display("test 13 FAILED");

    while (busy) #clk_tk;

    // write half word, cache miss, evict, dirty, write
    address = 64;
    data_in <= 32'h12345678;
    write_enable_bytes = 4'b0011;  // write 0x5678 to 0xD4E5F6A7B => D4E5F_5678
    enable = 1;
    #clk_tk;
    enable = 0;

    while (busy) #clk_tk;

    if (dut.stat_cache_misses == 5) $display("test 14 passed");
    else $display("test 14 FAILED");

    // read, cache miss, evict, dirty
    write_enable_bytes = 0;
    address = 0;
    enable = 1;
    #clk_tk;
    enable = 0;

    while (!data_out_ready) #clk_tk;

    if (data == 32'hB7C6_56_80) $display("test 15 passed");
    else $display("test 15 FAILED");

    while (busy) #clk_tk;

    //
    write_enable_bytes = 0;
    address = 8;
    enable = 1;
    #clk_tk;
    enable = 0;

    while (!data_out_ready) #clk_tk;

    if (data == 32'hAB4C3E6F) $display("test 15 passed");
    else $display("test 15 FAILED");

    while (busy) #clk_tk;

    // some clock ticks at the end
    #clk_tk;
    #clk_tk;
    #clk_tk;
    #clk_tk;

    $finish;
  end

endmodule
