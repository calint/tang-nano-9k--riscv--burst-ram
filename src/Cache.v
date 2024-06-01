//
// instructions and data RAM
// port A: read / write 32 bit data
// port B: read-only 32 bit instruction
//

`default_nettype none
//`define DBG

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
    input wire [NUM_COL-1:0] weA,
    input wire [ADDRESS_BITWIDTH-1:0] addrA,
    input wire [DATA_BITWIDTH-1:0] dinA,
    output reg [DATA_BITWIDTH-1:0] doutA,
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
      .LINE_IX_BITWIDTH(CACHE_LINE_IX_BITWIDTH),
      .DATA_BITWIDTH(32),
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

      // wiring to BurstRAM (prefix br_)
      .br_cmd(br_cmd),
      .br_cmd_en(br_cmd_en),
      .br_addr(br_addr),
      .br_rd_data(br_rd_data),
      .br_rd_data_valid(br_rd_data_valid),
      .br_busy(br_busy)
  );

  // ICache wiring
  reg icache_enable;
  // --

  localparam NUM_COL = 4;  // 4
  localparam COL_WIDTH = 8;  // 1 byte

  localparam STATE_PORT_B_IDLE = 4'b0000;
  localparam STATE_PORT_B_WAIT_ICACHE_BUSY = 4'b0010;
  localparam STATE_PORT_B_WAIT_ICACHE_DATA_READY = 4'b0100;

  reg [3:0] state_port_b;

  always @(posedge clk) begin
    if (rst) begin
      state_port_b <= STATE_PORT_B_IDLE;
    end
  end

  // Port-A Operation
  always @(posedge clk) begin
    for (integer i = 0; i < NUM_COL; i = i + 1) begin
      if (weA[i]) begin
        // data[addrA][i*COL_WIDTH+:COL_WIDTH] <= dinA[i*COL_WIDTH+:COL_WIDTH];
      end
    end
    // doutA <= data[addrA];
  end

  // Port-B Operation:
  always @(posedge clk) begin
    if (!rst) begin

`ifdef DBG
      $display("state_b: %0d  enB: %0d  icache_busy: %0d  doutB: %0h", state_port_b, enB,
               icache_busy, doutB);
`endif

      case (state_port_b)

        STATE_PORT_B_IDLE: begin
          if (bsyB) begin
            state_port_b <= STATE_PORT_B_WAIT_ICACHE_BUSY;
          end else begin
            icache_enable <= 1;
            state_port_b  <= STATE_PORT_B_WAIT_ICACHE_DATA_READY;
          end
        end

        STATE_PORT_B_WAIT_ICACHE_BUSY: begin
          if (!bsyB) begin
            icache_enable <= 1;
            state_port_b  <= STATE_PORT_B_WAIT_ICACHE_DATA_READY;
          end
        end

        STATE_PORT_B_WAIT_ICACHE_DATA_READY: begin
          icache_enable <= 0;
          if (rdyB) begin
            state_port_b <= STATE_PORT_B_IDLE;
          end
        end

      endcase
    end
  end

endmodule

`undef DBG
`default_nettype wire
