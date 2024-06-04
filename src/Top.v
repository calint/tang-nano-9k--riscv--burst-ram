`default_nettype none
//`define DBG

`include "Configuration.v"

module Top (
    input wire sys_clk,  // 27 MHz
    input wire sys_rst_n,
    output wire [5:0] led,
    input wire uart_rx,
    output wire uart_tx,
    input wire btn1
);

  wire soc_clk;

  Gowin_rPLL clk_rpll (
      .clkout(soc_clk),  // 20.250 MHz
      .clkin (sys_clk)   // 27 MHz
  );

  localparam RAM_DATA_BITWIDTH = 64;
  localparam RAM_DEPTH_BITWIDTH = `RAM_ADDR_WIDTH;  // 2 ^ x * 8 bytes RAM
  localparam RAM_BURST_COUNT = 4;

  BurstRAM #(
      .DATA_FILE("../os/os.mem"),
      .DEPTH_BITWIDTH(RAM_DEPTH_BITWIDTH),
      .DATA_BITWIDTH(RAM_DATA_BITWIDTH),
      .BURST_COUNT(RAM_BURST_COUNT),
      .CYCLES_BEFORE_INITIATED(10),
      .CYCLES_BEFORE_DATA_VALID(3)
  ) burst_ram (
      .clk(soc_clk),
      .rst(!sys_rst_n),

      .cmd(br_cmd),
      .cmd_en(br_cmd_en),
      .addr(br_addr),
      .wr_data(br_wr_data),
      .data_mask(br_data_mask),
      .rd_data(br_rd_data),
      .rd_data_valid(br_rd_data_valid),
      .busy(br_busy)
  );

  SoC #(
      .CLK_FREQ (50_000_000),
      .BAUD_RATE(9600),

      // RAM and cache
      .RAM_DEPTH_BITWIDTH(RAM_DEPTH_BITWIDTH),
      .RAM_BURST_DATA_BITWIDTH(RAM_DATA_BITWIDTH),
      .RAM_BURST_DATA_COUNT(RAM_BURST_COUNT),
      .CACHE_LINE_IX_BITWIDTH(1)
  ) soc (
      .rst(sys_rst_n),
      .clk(soc_clk),
      .clk_ram(soc_clk),
      .led(led),
      .uart_rx(uart_rx),
      .uart_tx(uart_tx),
      .btn(btn1),
//      .initiated(initiated),
//      .is_stalled(stalled),

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

  // -- wiring between BurstRAM and Cache
  wire br_cmd;
  wire br_cmd_en;
  wire [RAM_DEPTH_BITWIDTH-1:0] br_addr;
  wire [63:0] br_wr_data;
  wire [7:0] br_data_mask;
  wire [63:0] br_rd_data;
  wire br_rd_data_valid;
  wire br_busy;
  // --

endmodule

`undef DBG
`default_nettype wire
