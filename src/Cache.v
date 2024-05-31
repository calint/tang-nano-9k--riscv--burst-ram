//
// instructions and data RAM
// port A: read / write 32 bit data
// port B: read-only 32 bit instruction
//

`default_nettype none
//`define DBG

module Cache #(
    parameter ADDRESS_BITWIDTH = 12,  // 2^12 = RAM depth
    parameter INSTRUCTION_BITWIDTH = 32,
    // size of an instruction. must be divisble by 8
    parameter ICACHE_LINE_IX_BITWIDTH = 1,
    // 2^1 cache lines
    parameter CACHE_IX_IN_LINE_BITWIDTH = 3,
    // 2^3 => instructions per cache line,B 8 * 4 = 32 B
    // how many consequitive data is retrieved by BurstRAM
    parameter RAM_DEPTH_BITWIDTH = 4,
    parameter RAM_BURST_DATA_BITWIDTH = 64,
    parameter RAM_BURST_DATA_COUNT = 4
    // size of data sent in bits, must be divisible by 8 into bytes
    // RAM reads 4 * 8 = 32 B per burst
    // note: the burst size and cache line data must match in size
    //       a burst reads or writes one cache line thus:
    //       RAM_BURST_DATA_COUNT * RAM_BURST_DATA_BITWIDTH / 8 = 
    //       2 ^ CACHE_IX_IN_LINE_BITWIDTH * INSTRUCTION_BITWIDTH =
    //       32B
) (
    input wire clk,
    input wire rst,
    input wire [NUM_COL-1:0] weA,
    input wire [ADDRESS_BITWIDTH-1:0] addrA,
    input wire [DATA_BITWIDTH-1:0] dinA,
    output reg [DATA_BITWIDTH-1:0] doutA,
    input wire [ADDRESS_BITWIDTH-1:0] addrB,
    output wire [INSTRUCTION_BITWIDTH-1:0] doutB,
    input wire enB,
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

  ICache #(
      .LINE_IX_BITWIDTH(ICACHE_LINE_IX_BITWIDTH),  // 2^1 cache lines
      .ADDRESS_BITWIDTH(ADDRESS_BITWIDTH),
      .INSTRUCTION_BITWIDTH(32),  // 4 B per instruction
      .INSTRUCTION_IX_IN_LINE_BITWIDTH(CACHE_IX_IN_LINE_BITWIDTH),  // 2^3 32 bit instructions per cache line (32B)
      .RAM_DEPTH_BITWIDTH(RAM_DEPTH_BITWIDTH),
      .RAM_BURST_DATA_BITWIDTH(RAM_BURST_DATA_BITWIDTH),
      .RAM_BURST_DATA_COUNT(RAM_BURST_DATA_COUNT)  // 4 * 64 bits = 32B
      // note: size of INSTRUCTION_IX_IN_LINE_BITWIDTH and RAM_READ_BURST_COUNT must
      //       result in same number of bytes because a cache line is loaded by the size of a burst
  ) icache (
      .clk(clk),
      .clk_ram(clk),
      .rst(rst),
      .enable(icache_enable),
      .address(addrB),
      .instruction(doutB),
      .data_ready(rdyB),
      .busy(bsyB),

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

  // ICacheSTATE_PORT_B_IDLE
  reg icache_enable;
  reg [ADDRESS_BITWIDTH-1:0] icache_address;
  // --

  localparam ADDRESS_DEPTH = 2 ** ADDRESS_BITWIDTH;
  localparam NUM_COL = 4;  // 4
  localparam COL_WIDTH = 8;  // 1 byte
  localparam DATA_BITWIDTH = NUM_COL * COL_WIDTH;  // data width in bits

  reg [DATA_BITWIDTH-1:0] data[ADDRESS_DEPTH-1:0];
  // note: synthesizes to SP (single port block ram)

  localparam STATE_PORT_B_IDLE = 4'b0000;
  localparam STATE_PORT_B_WAIT_ICACHE_BUSY = 4'b0010;
  localparam STATE_PORT_B_WAIT_ONE_CYCLE = 4'b0100;
  localparam STATE_PORT_B_WAIT_ICACHE_DATA_READY = 4'b1000;

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
        data[addrA][i*COL_WIDTH+:COL_WIDTH] <= dinA[i*COL_WIDTH+:COL_WIDTH];
      end
    end
    doutA <= data[addrA];
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
          if (enB) begin
            if (bsyB) begin
              state_port_b <= STATE_PORT_B_WAIT_ICACHE_BUSY;
            end else begin
              icache_address <= addrB;
              icache_enable  <= 1;
              state_port_b   <= STATE_PORT_B_WAIT_ONE_CYCLE;
            end
          end
        end

        STATE_PORT_B_WAIT_ICACHE_BUSY: begin
          if (!bsyB) begin
            icache_address <= addrB;
            icache_enable  <= 1;
            state_port_b   <= STATE_PORT_B_WAIT_ONE_CYCLE;
          end
        end

        STATE_PORT_B_WAIT_ONE_CYCLE: begin
        //   icache_enable <= 0;
        //   state_port_b  <= STATE_PORT_B_WAIT_ICACHE_DATA_READY;
        // end

        // STATE_PORT_B_WAIT_ICACHE_DATA_READY: begin
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
