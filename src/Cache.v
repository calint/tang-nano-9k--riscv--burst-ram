//
// instruction and data cache connected to BurstRAM
//

`default_nettype none
// `define DBG
// `define INFO

module Cache #(
    parameter ADDRESS_BITWIDTH = 32,
    parameter DATA_BITWIDTH = 32,
    parameter RAM_DEPTH_BITWIDTH = 4,
    parameter RAM_BURST_DATA_COUNT = 4,
    parameter RAM_BURST_DATA_BITWIDTH = 64,
    parameter CACHE_LINE_IX_BITWIDTH = 1,
    parameter CACHE_ADDRESS_LEADING_ZEROS_BITWIDTH = 2
) (
    input wire clk,
    input wire rst,

    // port A: data
    input wire enA,
    input wire [DATA_BITWIDTH/8-1:0] weA,
    input wire [ADDRESS_BITWIDTH-1:0] addrA,
    input wire [DATA_BITWIDTH-1:0] dinA,
    output wire [DATA_BITWIDTH-1:0] doutA,
    output wire validA,
    output wire bsyA,

    // port B: instructions
    input wire [ADDRESS_BITWIDTH-1:0] addrB,
    output wire [DATA_BITWIDTH-1:0] doutB,
    output wire validB,
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

  // port B
  CacheInstructions #(
      .ADDRESS_BITWIDTH(ADDRESS_BITWIDTH),
      .ADDRESS_LEADING_ZEROS_BITWIDTH(CACHE_ADDRESS_LEADING_ZEROS_BITWIDTH),
      .DATA_BITWIDTH(DATA_BITWIDTH),
      .RAM_DEPTH_BITWIDTH(RAM_DEPTH_BITWIDTH),
      .RAM_BURST_DATA_BITWIDTH(RAM_BURST_DATA_BITWIDTH),
      .RAM_BURST_DATA_COUNT(RAM_BURST_DATA_COUNT),
      .LINE_IX_BITWIDTH(CACHE_LINE_IX_BITWIDTH)
  ) icache (
      .clk(clk),
      .rst(rst),
      .enable(icache_enable),
      .address(addrB),
      .data(doutB),
      .data_valid(validB),
      .busy(bsyB),

      // -- wiring to BurstRAM (prefix br_) -- -- -- -- -- --
      .br_cmd(icache_br_cmd),
      .br_cmd_en(icache_br_cmd_en),
      .br_addr(icache_br_addr),
      .br_rd_data(br_rd_data),
      .br_rd_data_valid(br_rd_data_valid),
      .br_busy(br_busy)
  );

  // port A
  CacheData #(
      .ADDRESS_BITWIDTH(ADDRESS_BITWIDTH),
      .ADDRESS_LEADING_ZEROS_BITWIDTH(CACHE_ADDRESS_LEADING_ZEROS_BITWIDTH),
      .DATA_BITWIDTH(DATA_BITWIDTH),
      .RAM_DEPTH_BITWIDTH(RAM_DEPTH_BITWIDTH),
      .RAM_BURST_DATA_COUNT(RAM_BURST_DATA_COUNT),
      .RAM_BURST_DATA_BITWIDTH(RAM_BURST_DATA_BITWIDTH),
      .LINE_IX_BITWIDTH(CACHE_LINE_IX_BITWIDTH)
  ) dcache (
      .clk(clk),
      .rst(rst),
      .enable(dcache_enable),
      .write_enable_bytes(weA),
      .address(addrA),
      .data_in(dinA),
      .data_out(doutA),
      .data_out_valid(validA),
      .busy(bsyA),

      // -- wiring to BurstRAM (prefix br_) -- -- -- -- -- --
      .br_cmd(dcache_br_cmd),
      .br_cmd_en(dcache_br_cmd_en),
      .br_addr(dcache_br_addr),
      .br_rd_data(br_rd_data),
      .br_rd_data_valid(br_rd_data_valid),
      .br_wr_data(br_wr_data),
      .br_data_mask(br_data_mask),
      .br_busy(br_busy)
  );

  // port B to BurstRAM wires
  reg icache_enable;
  wire icache_br_cmd;
  wire icache_br_cmd_en;
  wire [RAM_DEPTH_BITWIDTH-1:0] icache_br_addr;
  wire [RAM_BURST_DATA_BITWIDTH-1:0] icache_br_wr_data = 0;
  wire [RAM_BURST_DATA_BITWIDTH/8-1:0] icache_br_data_mask = 0;

  // port A to BurstRAM wires
  reg dcache_enable;
  wire dcache_br_cmd;
  wire dcache_br_cmd_en;
  wire [RAM_DEPTH_BITWIDTH-1:0] dcache_br_addr;
  wire [RAM_BURST_DATA_BITWIDTH-1:0] dcache_br_wr_data;
  wire [RAM_BURST_DATA_BITWIDTH/8-1:0] dcache_br_data_mask;

  localparam STATE_ICACHE_ACTIVATE = 4'b0001;
  localparam STATE_ICACHE_WAIT = 4'b0010;
  localparam STATE_DCACHE_ACTIVATE = 4'b0100;
  localparam STATE_DCACHE_WAIT = 4'b1000;

  assign br_cmd = icache_enable ? icache_br_cmd : dcache_br_cmd;
  assign br_cmd_en = icache_enable ? icache_br_cmd_en : dcache_br_cmd_en;
  assign br_addr = icache_enable ? icache_br_addr : dcache_br_addr;

  reg [3:0] state;

  always @(posedge clk) begin
    if (rst) begin
      state <= STATE_ICACHE_ACTIVATE;
      icache_enable <= 1;
      dcache_enable <= 0;
    end else begin

      // `ifdef DBG
      //     $display("state: %0d  validA: %0d  bsyA: %0d  dcache_busy: %0d", state, validA, dcache_busy,
      //              dcache_busy);
      // `endif

      case (state)

        STATE_ICACHE_ACTIVATE: begin
          // note: skip one cycle for 'bsyB' to go high
          state <= STATE_ICACHE_WAIT;
        end

        STATE_ICACHE_WAIT: begin
          if (!bsyB && enA) begin
            icache_enable <= 0;
            dcache_enable <= 1;
            state = STATE_DCACHE_ACTIVATE;
          end
        end

        STATE_DCACHE_ACTIVATE: begin
          // note: skip one cycle for 'bsyA' to go high
          state <= STATE_DCACHE_WAIT;
        end

        STATE_DCACHE_WAIT: begin
          if (!bsyA) begin
            icache_enable <= 1;
            dcache_enable <= 0;
            state = STATE_ICACHE_ACTIVATE;
          end
        end

      endcase
    end
  end

endmodule

`default_nettype wire
