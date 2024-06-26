//
// instruction cache containg a BurstRAM component
//

`default_nettype none
//`define DBG

module ICache #(
    parameter ADDRESS_BITWIDTH = 32,
    // device addressing assumed to be 32 bit
    parameter INSTRUCTION_BITWIDTH = 32,
    // size of an instruction. must be divisble by 8
    parameter LINE_IX_BITWIDTH = 1,
    // 2^1 cache lines
    parameter INSTRUCTION_IX_IN_LINE_BITWIDTH = 3,
    // 2^3 => instructions per cache line, 8 * 4 = 32 B
    parameter RAM_BURST_DATA_COUNT = 4,
    // how many consequitive data is retrieved by BurstRAM
    parameter RAM_BURST_DATA_BITWIDTH = 64,
    // size of data sent in bits, must be divisible by 8 into bytes
    // RAM reads 4 * 8 = 32 B per burst
    // note: the burst size and cache line data must match in size
    //       a burst reads or writes one cache line thus:
    //       RAM_BURST_DATA_COUNT * RAM_BURST_DATA_BITWIDTH / 8 = 
    //       2 ^ INSTRUCTION_IX_IN_LINE_BITWIDTH * INSTRUCTION_BITWIDTH / 8 =
    //       32 B
    parameter RAM_DEPTH_BITWIDTH = 4
    // size of RAM: 2^RAM_DEPTH_BITWIDTH*RAM_BURST_DATA_BITWIDTH
) (
    input wire clk,  // device clock
    input wire rst,  // reset
    input wire enable,  // assert to requests data, busy must be low
    input wire [ADDRESS_BITWIDTH-1:0] address,
    // address in bytes, 4 byte word aligned with bottom 2 bits 0
    output reg [INSTRUCTION_BITWIDTH-1:0] instruction,
    // the cached element
    output reg data_ready,
    // instruction retreived and valid
    output reg busy,
    // true while busy. note: data_ready may be asserted before busy false

    // wiring to BurstRAM (prefix br_)
    output reg br_cmd,
    output reg br_cmd_en,
    output reg [RAM_DEPTH_BITWIDTH-1:0] br_addr,
    input wire [RAM_BURST_DATA_BITWIDTH-1:0] br_rd_data,
    input wire br_rd_data_valid,
    input wire br_busy
);

  localparam RAM_ALIGNMENT_BITWIDTH = $clog2(RAM_BURST_DATA_BITWIDTH / 8);
  localparam INSTRUCTION_SIZE_BYTES = INSTRUCTION_BITWIDTH / 8;
  localparam INSTRUCTIONS_PER_DATA = RAM_BURST_DATA_BITWIDTH / INSTRUCTION_BITWIDTH;
  // number of instructions per data (1 or 2)
  localparam ADDRESS_LEADING_ZEROS_BITWIDTH = 2;
  // number of leading zeros in the address. assumes 32 bit instructions word aligned so 2
  localparam INSTRUCTIONS_PER_LINE = 2 ** INSTRUCTION_IX_IN_LINE_BITWIDTH;
  // number of instructions per cache line
  localparam LINE_COUNT = 2 ** LINE_IX_BITWIDTH;
  // number of cache lines
  localparam TAG_BITWIDTH = 
    ADDRESS_BITWIDTH - LINE_IX_BITWIDTH - 
    INSTRUCTION_IX_IN_LINE_BITWIDTH - ADDRESS_LEADING_ZEROS_BITWIDTH;
  // the upper bits of the address that is associated with a cache line

  // state machine
  localparam STATE_IDLE = 2'b00;
  localparam STATE_RECV_WAIT_FOR_DATA_READY = 2'b01;
  localparam STATE_RECV_DATA = 2'b10;

  reg [3:0] state;

  // data storage
  reg cache_line_valid[LINE_IX_BITWIDTH-1:0];
  // array of bits asserting if a cache line is loaded
  reg [TAG_BITWIDTH-1:0] cache_line_tag[LINE_IX_BITWIDTH-1:0];
  // the upper bits of the address compared with the request to evict and load a new cache line
  reg [INSTRUCTION_BITWIDTH-1:0] cache_line_data[LINE_COUNT-1:0][INSTRUCTIONS_PER_LINE-1:0];
  // the cached instructions
  reg [$clog2(RAM_BURST_DATA_COUNT)-1:0] burst_counter;
  // counter of data packets retrieved in burst
  reg [INSTRUCTION_IX_IN_LINE_BITWIDTH-1:0] burst_instruction_ix;
  // counter of which index in the cache line to update

  // stats
  reg [63:0] stat_cache_hits;
  reg [63:0] stat_cache_misses;

  // wires dividing the address into components
  // |tag|line|index|00| address
  //                |00| ignored (4 bytes word aligned instructions)
  //          |index|    instruction_ix: the index of the instruction in the cached line
  //     |line|          line_ix: index in array where tag and cached data is stored
  // |tag|               tag: the rest of the upper bits of the address
  wire [INSTRUCTION_IX_IN_LINE_BITWIDTH-1:0] instruction_ix = address[
    INSTRUCTION_IX_IN_LINE_BITWIDTH+ADDRESS_LEADING_ZEROS_BITWIDTH-1
    -: INSTRUCTION_IX_IN_LINE_BITWIDTH
  ];
  wire [LINE_IX_BITWIDTH-1:0] line_ix = address[
    LINE_IX_BITWIDTH+INSTRUCTION_IX_IN_LINE_BITWIDTH+ADDRESS_LEADING_ZEROS_BITWIDTH-1
    -: LINE_IX_BITWIDTH
  ];
  wire [TAG_BITWIDTH-1:0] tag = address[ADDRESS_BITWIDTH-1-:TAG_BITWIDTH];

`ifdef DBG
  initial begin
    $display("ICache");
    $display("      bitwidths");
    $display("           tag: %0d", TAG_BITWIDTH);
    $display("       line ix: %0d", LINE_IX_BITWIDTH);
    $display("      instr ix: %0d", INSTRUCTION_IX_IN_LINE_BITWIDTH);
    $display("         zeros: %0d", ADDRESS_LEADING_ZEROS_BITWIDTH);
    $display("  br_data_mask: %0d", BR_DATA_MASK_SIZE_BITS);
    $display("    line count: %0d", LINE_COUNT);
  end
`endif

  always @(posedge clk) begin
    if (rst) begin
      state <= STATE_IDLE;
      busy <= 0;
      data_ready <= 0;
      stat_cache_hits <= 0;
      stat_cache_misses <= 0;
      burst_counter <= 0;
      burst_instruction_ix <= 0;
      instruction <= 0;
    end else begin
      case (state)

        STATE_IDLE: begin
          // data_ready <= 0;
          if (enable) begin
`ifdef DBG
            $display("address: 0x%h  line_ix: %0d  tag: %0h", address, line_ix, tag);
            if (cache_line_valid[line_ix] && cache_line_tag[line_ix] != tag) begin
              $display("TAG MISSMATCH, evict");
            end
`endif

            if (cache_line_valid[line_ix] && cache_line_tag[line_ix] == tag) begin

`ifdef DBG
              $display("CACHE HIT");
`endif

              instruction <= cache_line_data[line_ix][instruction_ix];
              busy <= 0;
              data_ready <= 1;
              stat_cache_hits <= stat_cache_hits + 1;
            end else begin

`ifdef DBG
              $display("CACHE MISS");
`endif

              stat_cache_misses <= stat_cache_misses + 1;
              busy <= 1;
              data_ready <= 0;
              br_cmd <= 0;  // read
              // extract the cache line address from current address
              br_addr <= address[ADDRESS_BITWIDTH-1:RAM_ALIGNMENT_BITWIDTH];
              br_cmd_en <= 1;
              cache_line_valid[line_ix] <= 1;
              // note: ok to flag cache line as valid here
              cache_line_tag[line_ix] <= tag;
              burst_counter <= 0;
              burst_instruction_ix <= 0;
              state <= STATE_RECV_WAIT_FOR_DATA_READY;
            end
          end
        end

        STATE_RECV_WAIT_FOR_DATA_READY: begin
          br_cmd_en <= 0;  // note: can turn of 'cmd' after one cycle
          if (br_rd_data_valid) begin
            update_cache_line_data;
            state <= STATE_RECV_DATA;
          end
        end

        STATE_RECV_DATA: begin
          update_cache_line_data;
          if (burst_counter == RAM_BURST_DATA_COUNT - 1) begin
            // -1 because of the non-blocking assignments are updated at
            // the end of the always block
            busy <= 0;
            burst_counter <= 0;
            burst_instruction_ix <= 0;
            state <= STATE_IDLE;
          end
        end

        default: ;
      endcase
    end
  end

  task update_cache_line_data;
    begin
      for (integer i = 0; i < INSTRUCTIONS_PER_DATA; i = i + 1) begin

`ifdef DBG
        $display("cache[%0d][%0d]=%h", line_ix, burst_instruction_ix + i,
                 br_rd_data[(i+1)*INSTRUCTION_BITWIDTH-1-:INSTRUCTION_BITWIDTH]);
`endif

        // set first cached element in line data
        cache_line_data[line_ix][burst_instruction_ix + i] 
          <= br_rd_data[(i+1)*INSTRUCTION_BITWIDTH-1-:INSTRUCTION_BITWIDTH];
      end

      // check if the requested instruction is in this data
      for (integer i = 0; i < INSTRUCTIONS_PER_DATA; i = i + 1) begin
        // check if this was the requested instruction
        if (instruction_ix == burst_instruction_ix + i) begin
          instruction <= br_rd_data[(i+1)*INSTRUCTION_BITWIDTH-1-:INSTRUCTION_BITWIDTH];
          data_ready  <= 1;
        end
      end

      burst_instruction_ix <= burst_instruction_ix + INSTRUCTIONS_PER_DATA;
      burst_counter <= burst_counter + 1;

    end
  endtask

endmodule

`undef DBG
`default_nettype wire
