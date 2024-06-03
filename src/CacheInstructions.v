//
// instruction cache connected to BurstRAM
//

`default_nettype none
// `define DBG
// `define INFO

module CacheInstructions #(
    parameter ADDRESS_BITWIDTH = 32,
    // address space assumed 32 bit

    parameter DATA_BITWIDTH = 32,
    // size of a data element stored in cache line, must be divisible by 8

    parameter DATA_IX_IN_LINE_BITWIDTH = 3,
    // 2 ^ 3 = 8 data per cache line

    parameter LINE_IX_BITWIDTH = 1,
    // 2 ^ 1 = 2 cache lines

    parameter RAM_BURST_DATA_COUNT = 4,
    // consecutive data elements retrieved in a burst

    parameter RAM_BURST_DATA_BITWIDTH = 64,
    // size of data sent by RAM in bits, must be divisible by 8 into bytes
    // note: the burst size and cache line size must match
    //       a burst reads or writes one cache line thus:
    //       RAM_BURST_DATA_COUNT * RAM_BURST_DATA_BITWIDTH = 
    //       2 ^ DATA_IX_IN_LINE_BITWIDTH * DATA_BITWIDTH =
    //       32 B
    // RAM reads 4 * 8 = 32 B per burst

    parameter RAM_DEPTH_BITWIDTH = 8
    // size of RAM: 2 ^ RAM_DEPTH_BITWIDTH * RAM_BURST_DATA_BITWIDTH / 8 = 2 KB
) (
    input wire clk,  // RAM clock

    input wire rst,  // reset

    input wire enable,
    // assert to request data, busy must not be asserted or the signal is ignored

    input wire [ADDRESS_BITWIDTH-1:0] address,
    // address in bytes, 4 byte words aligned with bottom 2 bits being 0

    output reg [DATA_BITWIDTH-1:0] data,
    // the cached data of the address

    output reg data_ready,
    // data retrieved and valid

    output reg busy,
    // asserted while busy
    // note: data_ready may be asserted while busy is asserted

    // -- wiring to BurstRAM (prefix br_) -- -- -- -- -- --
    output reg br_cmd,
    output reg br_cmd_en,
    output reg [RAM_DEPTH_BITWIDTH-1:0] br_addr,
    output reg [RAM_BURST_DATA_BITWIDTH-1:0] br_wr_data,
    output reg [RAM_BURST_DATA_BITWIDTH/8-1:0] br_data_mask,
    input wire [RAM_BURST_DATA_BITWIDTH-1:0] br_rd_data,
    input wire br_rd_data_valid,
    input wire br_busy
    // -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
);

  localparam DATA_SIZE_BYTES = DATA_BITWIDTH / 8;

  localparam DATA_PER_LINE = 2 ** DATA_IX_IN_LINE_BITWIDTH;
  // number of data per cache line

  localparam DATA_PER_RAM_DATA = RAM_BURST_DATA_BITWIDTH / DATA_BITWIDTH;
  // number of data elements per RAM data retrieved, must be evenly divisible
  // note: RAM may have bigger data such as 64 bit when data is 32 bit

  localparam ADDRESS_LEADING_ZEROS_BITWIDTH = 2;
  // number of leading zeros in the address; assumes 32 bit word aligned access

  localparam LINE_COUNT = 2 ** LINE_IX_BITWIDTH;
  // number of cache lines

  localparam TAG_BITWIDTH = 
    ADDRESS_BITWIDTH - LINE_IX_BITWIDTH - 
    DATA_IX_IN_LINE_BITWIDTH - ADDRESS_LEADING_ZEROS_BITWIDTH;
  // the upper bits of the address that is associated with a cache line

  localparam BYTE_ADDRESS_SHIFT_RIGHT_TO_RAM_ADDRESS = ADDRESS_LEADING_ZEROS_BITWIDTH + $clog2(
      RAM_BURST_DATA_BITWIDTH / DATA_BITWIDTH
  );
  // shift right amount to convert byte address to RAM address


  // state machine
  localparam STATE_IDLE = 2'b01;
  localparam STATE_RECV_WAIT_FOR_DATA_READY = 2'b10;
  localparam STATE_RECV_DATA = 2'b11;

  reg [1:0] state;

  //
  // cache data storage
  //
  reg cache_line_valid[LINE_COUNT-1:0];
  // array of bits asserting if a cache line is loaded

  reg [TAG_BITWIDTH-1:0] cache_line_tag[LINE_COUNT-1:0];
  // the upper bits of the address compared with the request to evict and load a new cache line

  reg [DATA_BITWIDTH-1:0] cache_line_data[LINE_COUNT-1:0][DATA_PER_LINE-1:0];
  // the cached instructions

  reg [$clog2(RAM_BURST_DATA_COUNT)-1:0] burst_counter;
  // counter of data packets retrieved in burst

  reg [DATA_IX_IN_LINE_BITWIDTH-1:0] burst_data_ix;
  // counter of which index in the cache line to update

  //
  // stats
  //
  reg [63:0] stat_cache_hits;
  reg [63:0] stat_cache_misses;

  // wires dividing the address into components
  // |tag|line|index|00| address
  //                |00| ignored (4 bytes word aligned)
  //          |index|    data_ix: the index of the data in the cached line
  //     |line|          line_ix: index in array where tag and cached data is stored
  // |tag|               tag: the rest of the upper bits of the address
  wire [DATA_IX_IN_LINE_BITWIDTH-1:0] data_ix = address[
    DATA_IX_IN_LINE_BITWIDTH+ADDRESS_LEADING_ZEROS_BITWIDTH-1
    -: DATA_IX_IN_LINE_BITWIDTH
  ];

  wire [LINE_IX_BITWIDTH-1:0] line_ix = address[
    LINE_IX_BITWIDTH+DATA_IX_IN_LINE_BITWIDTH+ADDRESS_LEADING_ZEROS_BITWIDTH-1
    -: LINE_IX_BITWIDTH
  ];

  wire [TAG_BITWIDTH-1:0] tag = address[ADDRESS_BITWIDTH-1-:TAG_BITWIDTH];

`ifdef INFO
  initial begin
    $display("----------------------------------------");
    $display("  CacheInstructions");
    $display("----------------------------------------");
    $display("       line size: %0d B", DATA_PER_LINE * DATA_SIZE_BYTES);
    $display("           lines: %0d", LINE_COUNT);
    $display("   data per line: %0d", DATA_PER_LINE);
    $display("       data size: %0d bits", DATA_BITWIDTH);
    $display("     total usage: %0d B",
             DATA_PER_LINE * DATA_SIZE_BYTES * LINE_COUNT + (TAG_BITWIDTH + 1) * LINE_COUNT / 8);
    // note: 1 is valid bit and 8 is bits per byte
    $display("             tag: %0d bits", TAG_BITWIDTH);
    $display("         line ix: %0d bits", LINE_IX_BITWIDTH);
    $display("         data ix: %0d bits", DATA_IX_IN_LINE_BITWIDTH);
    $display("  trailing zeros: %0d bits", ADDRESS_LEADING_ZEROS_BITWIDTH);
    $display(" write data mask: %0d bits", RAM_BURST_DATA_BITWIDTH / 8);
    $display("----------------------------------------");
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
      burst_data_ix <= 0;
      data <= 0;
      br_cmd <= 0;
      br_cmd_en <= 0;
      br_addr <= 0;
    end else begin

      case (state)
        STATE_IDLE: begin
          // data_ready <= 0;
          if (enable) begin

`ifdef DBG
            $display("address: 0x%h  tag: %0d  line_ix: %0d  data_ix: %0d", address, tag, line_ix,
                     data_ix);
            if (cache_line_valid[line_ix] && cache_line_tag[line_ix] != tag) begin
              $display("tag mismatch, evict");
            end
`endif

            if (cache_line_valid[line_ix] && cache_line_tag[line_ix] == tag) begin

`ifdef DBG
              $display("cache hit");
`endif

              data <= cache_line_data[line_ix][data_ix];
              busy <= 0;
              data_ready <= 1;
              stat_cache_hits <= stat_cache_hits + 1;

            end else begin  // not (cache_line_valid[line_ix] && cache_line_tag[line_ix] == tag)

`ifdef DBG
              $display("cache miss");
`endif

              stat_cache_misses <= stat_cache_misses + 1;
              busy <= 1;
              data_ready <= 0;
              br_cmd <= 0;  // read
              // extract the cache line address from current address
              br_addr <= {
                  address[ADDRESS_BITWIDTH-1-:(TAG_BITWIDTH+LINE_IX_BITWIDTH)],
                  {DATA_IX_IN_LINE_BITWIDTH{1'b0}},
                  {ADDRESS_LEADING_ZEROS_BITWIDTH{1'b0}}
                }>>BYTE_ADDRESS_SHIFT_RIGHT_TO_RAM_ADDRESS;

`ifdef DBG
              $display(
                  "load cache line from BurstRAM address: %h",
                  {address[ADDRESS_BITWIDTH-1-:(TAG_BITWIDTH+LINE_IX_BITWIDTH)], {DATA_IX_IN_LINE_BITWIDTH{1'b0}}, {ADDRESS_LEADING_ZEROS_BITWIDTH{1'b0}}} >> BYTE_ADDRESS_SHIFT_RIGHT_TO_RAM_ADDRESS);
`endif

              br_cmd_en <= 1;
              cache_line_valid[line_ix] <= 1;
              // note: ok to flag cache line as valid here
              cache_line_tag[line_ix] <= tag;
              burst_counter <= 0;
              burst_data_ix <= 0;
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
            burst_data_ix <= 0;
            state <= STATE_IDLE;
          end
        end

      endcase
    end
  end

  task update_cache_line_data;
    begin
      for (integer i = 0; i < DATA_PER_RAM_DATA; i = i + 1) begin

`ifdef DBG
        $display("cache[%0d][%0d]=%h", line_ix, burst_data_ix + i,
                 br_rd_data[(i+1)*DATA_BITWIDTH-1-:DATA_BITWIDTH]);
`endif

        // set first cached element in line data
        cache_line_data[line_ix][burst_data_ix + i] 
          <= br_rd_data[(i+1)*DATA_BITWIDTH-1-:DATA_BITWIDTH];
      end

      // check if the requested data is in this RAM data
      for (integer i = 0; i < DATA_PER_RAM_DATA; i = i + 1) begin
        // check if this was the requested data
        if (data_ix == burst_data_ix + i) begin
          data <= br_rd_data[(i+1)*DATA_BITWIDTH-1-:DATA_BITWIDTH];
          data_ready <= 1;
        end
      end

      burst_data_ix <= burst_data_ix + DATA_PER_RAM_DATA;
      burst_counter <= burst_counter + 1;

    end
  endtask

endmodule

`undef DBG
`undef INFO
`default_nettype wire
