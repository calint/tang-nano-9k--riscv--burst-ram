`timescale 1ns / 1ps
//
// RAMIO
//
`default_nettype none

module TestBench;

  localparam RAM_DATA_BITWIDTH = 64;
  localparam RAM_ADDRESS_BITWIDTH = 8;  // 2 ^ 8 * 8 bytes RAM
  localparam RAM_BURST_COUNT = 4;

  BurstRAM #(
      .DATA_FILE("RAM.mem"),
      .CYCLES_BEFORE_INITIATED(10),
      .CYCLES_BEFORE_DATA_VALID(3),
      .DATA_BITWIDTH(RAM_DATA_BITWIDTH),
      .DEPTH_BITWIDTH(RAM_ADDRESS_BITWIDTH),
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

  RAMIO #(
      .RAM_DEPTH_BITWIDTH(RAM_ADDRESS_BITWIDTH),
      .RAM_BURST_DATA_BITWIDTH(RAM_DATA_BITWIDTH),
      .RAM_BURST_DATA_COUNT(RAM_BURST_COUNT),
      .CACHE_LINE_IX_BITWIDTH(1)
  ) dut (
      .rst(rst),
      .clk_cpu(clk),
      .clk_ram(clk_ram),

      .enA(enA),
      .weA(weA),
      .reA(reA),
      .addrA(addrA),
      .dinA(dinA),
      .doutA(doutA),
      .validA(validA),
      .bsyA(bsyA),

      .enB(enB),
      .addrB(addrB),
      .doutB(doutB),
      .validB(validB),
      .bsyB(bsyB),

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

  // cpu clock
  localparam clk_tk = 20;
  reg clk = 0;
  always #(clk_tk / 2) clk = ~clk;

  // RAM clock
  localparam clk_ram_tk = 2;
  reg clk_ram = 0;
  always #(clk_ram_tk / 2) clk_ram = ~clk_ram;

  // -- RAMIO
  reg rst = 1;
  // port A
  reg enA = 0;
  reg [1:0] weA = 0;
  reg [2:0] reA = 0;
  reg [31:0] addrA = 0;
  reg [31:0] dinA = 0;
  wire [31:0] doutA;
  wire validA;
  wire bsyA;
  // port B
  reg enB;
  reg [31:0] addrB = 0;
  wire [31:0] doutB;
  wire validB;
  wire bsyB;
  // --

  initial begin
    $dumpfile("log.vcd");
    $dumpvars(0, TestBench);

    // reset
    #clk_tk;
    #(clk_tk / 2);
    rst <= 0;
    #clk_tk;

    while (bsyA || bsyB) #clk_tk;

    // write 4 consecutive bytes then read a word
    enA   <= 1;
    weA   <= 4'b0001;

    dinA  <= 8'h12;
    addrA <= 0;
    #clk_tk;
    while (bsyA || bsyB) #clk_ram_tk;

    dinA  <= 8'h34;
    addrA <= 1;
    #clk_tk;
    while (bsyA || bsyB) #clk_ram_tk;

    dinA  <= 8'h56;
    addrA <= 2;
    #clk_tk;
    while (bsyA || bsyB) #clk_ram_tk;

    dinA  <= 8'h78;
    addrA <= 3;
    #clk_tk;
    while (bsyA || bsyB) #clk_ram_tk;

    // read word
    reA   <= 3'b111;
    weA   <= 0;
    addrA <= 0;
    #clk_tk;
    while (bsyA || bsyB) #clk_ram_tk;

    //    $display("%h",doutA);
    if (doutA == 32'h78563412) $display("test 2 passed");
    else $display("test 2 FAILED");

    // write half words
    reA   <= 0;
    weA   <= 2;
    dinA  <= 16'h1234;
    addrA <= 4;
    #clk_tk;
    while (bsyA || bsyB) #clk_ram_tk;

    dinA  <= 16'h5678;
    addrA <= 6;
    #clk_tk;
    while (bsyA || bsyB) #clk_ram_tk;

    // read word
    reA   <= 3'b111;
    weA   <= 0;
    addrA <= 4;
    #clk_tk;
    while (bsyA || bsyB) #clk_ram_tk;

    //    $display("%h",doutA);
    if (doutA == 32'h56781234) $display("test 4 passed");
    else $display("test 4 FAILED");

    // read unsigned byte
    reA   <= 3'b001;
    weA   <= 0;
    addrA <= 0;
    #clk_tk;
    while (bsyA || bsyB) #clk_ram_tk;

    //    $display("%h",doutA);
    if (doutA == 8'h12) $display("test 5 passed");
    else $display("test 5 FAILED");

    // read unsigned byte
    reA   <= 3'b001;
    weA   <= 0;
    addrA <= 1;
    #clk_tk;
    while (bsyA || bsyB) #clk_ram_tk;

    //    $display("%h",doutA);
    if (doutA == 8'h34) $display("test 6 passed");
    else $display("test 6 FAILED");

    // read unsigned byte
    reA   <= 3'b001;
    weA   <= 0;
    addrA <= 2;
    #clk_tk;
    while (bsyA || bsyB) #clk_ram_tk;

    //    $display("%h",doutA);
    if (doutA == 8'h56) $display("test 7 passed");
    else $display("test 7 FAILED");

    // read unsigned byte
    reA   <= 3'b001;
    weA   <= 0;
    addrA <= 3;
    #clk_tk;
    while (bsyA || bsyB) #clk_ram_tk;

    //    $display("%h",doutA);
    if (doutA == 8'h78) $display("test 8 passed");
    else $display("test 8 FAILED");

    // read unsigned half word
    reA   <= 3'b010;
    weA   <= 0;
    addrA <= 4;
    #clk_tk;
    while (bsyA || bsyB) #clk_ram_tk;

    //    $display("%h",doutA);
    if (doutA == 16'h1234) $display("test 9 passed");
    else $display("test 9 FAILED");

    // read unsigned half word
    reA   <= 3'b010;
    weA   <= 0;
    addrA <= 6;
    #clk_tk;
    while (bsyA || bsyB) #clk_ram_tk;

    //    $display("%h",doutA);
    if (doutA == 16'h5678) $display("test 10 passed");
    else $display("test 10 FAILED");

    // read word
    reA   <= 3'b111;
    weA   <= 0;
    addrA <= 4;
    #clk_tk;
    while (bsyA || bsyB) #clk_ram_tk;

    //    $display("%h",doutA);
    if (doutA == 32'h56781234) $display("test 11 passed");
    else $display("test 11 FAILED");

    // write word
    reA   <= 0;
    weA   <= 3;
    dinA  <= 32'hfffe_fdfc;
    addrA <= 8;
    #clk_tk;
    while (bsyA || bsyB) #clk_ram_tk;

    // read signed byte
    reA   <= 3'b101;
    weA   <= 0;
    addrA <= 8;
    #clk_tk;
    while (bsyA || bsyB) #clk_ram_tk;

    //    $display("%h",doutA);
    if (doutA == -4) $display("test 13 passed");
    else $display("test 13 FAILED");

    // read signed byte
    reA   <= 3'b101;
    weA   <= 0;
    addrA <= 9;
    #clk_tk;
    while (bsyA || bsyB) #clk_ram_tk;

    //    $display("%h",doutA);
    if (doutA == -3) $display("test 14 passed");
    else $display("test 14 FAILED");

    // read signed byte
    reA   <= 3'b101;
    weA   <= 0;
    addrA <= 10;
    #clk_tk;
    while (bsyA || bsyB) #clk_ram_tk;

    //    $display("%h",doutA);
    if (doutA == -2) $display("test 15 passed");
    else $display("test 15 FAILED");

    // read signed byte
    reA   <= 3'b101;
    weA   <= 0;
    addrA <= 11;
    #clk_tk;
    while (bsyA || bsyB) #clk_ram_tk;

    //    $display("%h",doutA);
    if (doutA == -1) $display("test 16 passed");
    else $display("test 16 FAILED");

    // read signed half word
    reA   <= 3'b110;
    weA   <= 0;
    addrA <= 8;
    #clk_tk;
    while (bsyA || bsyB) #clk_ram_tk;

    //    $display("%h",doutA);
    if (doutA == -516) $display("test 17 passed");
    else $display("test 17 FAILED");

    // read signed half word
    reA   <= 3'b110;
    weA   <= 0;
    addrA <= 10;
    #clk_tk;
    while (bsyA || bsyB) #clk_ram_tk;

    //    $display("%h",doutA);
    if (doutA == -2) $display("test 18 passed");
    else $display("test 18 FAILED");

    $finish;
  end

endmodule
