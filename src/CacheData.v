//
// data cache connected to BurstRAM
//
// reviewed: 2024-06-04

`default_nettype none
// `define DBG
// `define INFO

module CacheData #(
    parameter ADDRESS_BITWIDTH = 32,
    // address space assumed 32 bit

    parameter DATA_BITWIDTH = 32,
    // size of a data element stored in cache line; must be divisible by 8

    parameter RAM_DEPTH_BITWIDTH = 8,
    // size of RAM: 2 ^ RAM_DEPTH_BITWIDTH * RAM_BURST_DATA_BITWIDTH / 8 = 2 KB

    parameter RAM_BURST_DATA_BITWIDTH = 64,
    // size of data sent by RAM in bits, must be divisible by 8 into bytes
    // note: the burst size and cache line size must match because
    //       a burst reads or writes one cache line

    parameter RAM_BURST_DATA_COUNT = 4,
    // consecutive data elements retrieved in a burst

    parameter LINE_IX_BITWIDTH = 1,
    // 2 ^ 1 = 2 cache lines
    // 64 bits * 4  (RAM_BURST_DATA_BITWIDTH * RAM_BURST_DATA_COUNT)

    parameter ADDRESS_LEADING_ZEROS_BITWIDTH = 2
    // data accessed have leading 2 zeros; 4 bytes aligned, e.g. 0xabcdef00
) (
    input wire clk,  // clock

    input wire rst,  // reset

    input wire enable,
    // assert to request data; busy must not be asserted or the signal is ignored

    input wire [ADDRESS_BITWIDTH-1:0] address,
    // address in bytes; 4 byte words aligned with bottom 2 bits being 0

    output reg [DATA_BITWIDTH-1:0] data_out,
    // the cached data of the address

    output reg data_out_valid,
    // asserted when data retrieved and valid

    output reg busy,
    // asserted while busy
    // note: 'data_out_valid' may be asserted while 'busy' is asserted if burst 
    //       ram transaction not complete

    input wire [DATA_BITWIDTH-1:0] data_in,
    // data to be written

    input wire [DATA_BITWIDTH/8-1:0] write_enable_bytes,
    // bit map for which bytes to be written from 'data_in'

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

  localparam DATA_IX_IN_LINE_BITWIDTH = $clog2(
      RAM_BURST_DATA_BITWIDTH * RAM_BURST_DATA_COUNT / DATA_BITWIDTH
  );
  // bits used to index a data in a cache line

  localparam DATA_SIZE_BYTES = DATA_BITWIDTH / 8;

  localparam DATA_PER_LINE = 2 ** DATA_IX_IN_LINE_BITWIDTH;
  // number of data per cache line

  localparam DATA_PER_RAM_DATA = RAM_BURST_DATA_BITWIDTH / DATA_BITWIDTH;
  // number of data elements per RAM data retrieved, must be evenly divisible
  // note: RAM may have bigger data such as 64 bit when data is 32 bit

  localparam BYTE_ADDRESS_SHIFT_RIGHT_TO_RAM_ADDRESS = ADDRESS_LEADING_ZEROS_BITWIDTH + $clog2(
      RAM_BURST_DATA_BITWIDTH / DATA_BITWIDTH
  );
  // shift right amount to convert byte address to RAM address

  localparam LINE_COUNT = 2 ** LINE_IX_BITWIDTH;
  // number of cache lines

  localparam TAG_BITWIDTH = 
    ADDRESS_BITWIDTH - LINE_IX_BITWIDTH - 
    DATA_IX_IN_LINE_BITWIDTH - ADDRESS_LEADING_ZEROS_BITWIDTH;
  // the upper bits of the address that is associated with a cache line

  // state machine
  localparam STATE_INITIATE = 8'b0000_0001;
  localparam STATE_IDLE = 8'b0000_0010;
  localparam STATE_RECV_WAIT_FOR_DATA_VALID = 8'b0000_0100;
  localparam STATE_RECV_DATA = 8'b0000_1000;
  localparam STATE_WRITE_LINE = 8'b0001_0000;
  localparam STATE_WRITE_FETCH = 8'b0010_0000;
  localparam STATE_WRITE_FETCH_RECV_DATA = 8'b0100_0000;
  localparam STATE_WRITE_FETCH_LINE = 8'b1000_0000;

  reg [7:0] state;

  //
  // cache data storage
  //
  reg cache_line_valid[LINE_COUNT-1:0];
  // array of bits asserting if a cache line is loaded

  reg cache_line_dirty[LINE_COUNT-1:0];
  // array of bits asserting if a cache line needs to be written when evicted

  reg [TAG_BITWIDTH-1:0] cache_line_tag[LINE_COUNT-1:0];
  // the upper bits of the address compared with the request to evict and load a new cache line

  reg [DATA_BITWIDTH-1:0] cache_line_data[LINE_COUNT-1:0][DATA_PER_LINE-1:0];
  // the cached data

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
    $display("  CacheData");
    $display("----------------------------------------");
    $display("       line size: %0d B", DATA_PER_LINE * DATA_SIZE_BYTES);
    $display("           lines: %0d", LINE_COUNT);
    $display("   data per line: %0d", DATA_PER_LINE);
    $display("       data size: %0d bits", DATA_BITWIDTH);
    $display("     total usage: %0d B",
             DATA_PER_LINE * DATA_SIZE_BYTES * LINE_COUNT + (TAG_BITWIDTH + 2) * LINE_COUNT / 8);
    // note: 2 is valid and dirty bit; 8 is bits per byte
    $display("             tag: %0d bits", TAG_BITWIDTH);
    $display("         line ix: %0d bits", LINE_IX_BITWIDTH);
    $display("         data ix: %0d bits", DATA_IX_IN_LINE_BITWIDTH);
    $display("  trailing zeros: %0d bits", ADDRESS_LEADING_ZEROS_BITWIDTH);
    $display(" write data mask: %0d bits", RAM_BURST_DATA_BITWIDTH / 8);
    $display(" byte to ram shf: %0d bits", BYTE_ADDRESS_SHIFT_RIGHT_TO_RAM_ADDRESS);
    $display("----------------------------------------");
  end
`endif

  always @(posedge clk) begin
    if (rst) begin
      data_out_valid <= 0;
      stat_cache_hits <= 0;
      stat_cache_misses <= 0;
      burst_counter <= 0;
      burst_data_ix <= 0;
      data_out <= 0;
      br_cmd_en <= 0;
      br_cmd <= 0;
      br_addr <= 0;
      br_wr_data <= 0;
      br_data_mask <= 0;
      busy <= 1;
      state <= STATE_INITIATE;
    end else begin
      case (state)

        STATE_INITIATE: begin
          if (!br_busy) begin
            busy  <= 0;
            state <= STATE_IDLE;
          end
        end

        STATE_IDLE: begin
          // data_out_valid <= 0;
          if (enable) begin

`ifdef DBG
            $display("address: 0x%h  tag: %0h  line_ix: %0d  data_ix: %0d  write: %0b", address,
                     tag, line_ix, data_ix, write_enable_bytes);
`endif

            if (cache_line_valid[line_ix] && cache_line_tag[line_ix] == tag) begin

`ifdef DBG
              $display("cache hit");
              $display("write bytes: 0b%b", write_enable_bytes);
`endif

              // write the data depending on which bytes are enabled
              for (integer i = 0; i < DATA_BITWIDTH / 8; i = i + 1) begin
                if (write_enable_bytes[i]) begin

`ifdef DBG
                  $display("set %0h: byte[%0d]=0x%0h", cache_line_data[line_ix][data_ix], i,
                           data_in[(i+1)*8-1-:8]);
`endif

                  cache_line_data[line_ix][data_ix][(i+1)*8-1-:8] <= data_in[(i+1)*8-1-:8];
                end
              end

              if (write_enable_bytes == 0) begin
                data_out <= cache_line_data[line_ix][data_ix];
                data_out_valid <= 1;
              end else begin

`ifdef DBG
                $display("cache line %0d set to dirty", line_ix);
`endif

                cache_line_dirty[line_ix] <= 1;
              end

              busy <= 0;
              stat_cache_hits <= stat_cache_hits + 1;

            end else begin  // not (cache_line_valid[line_ix] && cache_line_tag[line_ix] == tag)

`ifdef DBG
              $display("cache miss");
              if (cache_line_valid[line_ix]) begin
                $display("cache line valid");
              end else begin
                $display("cache line invalid");
              end
              if (cache_line_valid[line_ix] && cache_line_tag[line_ix] != tag) begin
                $display("tag mismatch, evict");
              end
`endif

              stat_cache_misses <= stat_cache_misses + 1;

              busy <= 1;
              data_out_valid <= 0;
              br_cmd_en <= 1;
              if (cache_line_dirty[line_ix]) begin

`ifdef DBG
                $display("cache line dirty");
`endif

                // write back cache line then read the new line and set data
                // extract the cache line address from the tag and line index
                //  address: [ tag 26b ] [ line index 1b ] [ data index 3b ] [ zero 2b ]
                // BurstRAM: address >> CACHE_LINE_ALIGNMENT_BITWIDTH (3b)
                br_addr <= {
                  cache_line_tag[line_ix],
                  line_ix,
                  {DATA_IX_IN_LINE_BITWIDTH{1'b0}},
                  {ADDRESS_LEADING_ZEROS_BITWIDTH{1'b0}}
                }>>BYTE_ADDRESS_SHIFT_RIGHT_TO_RAM_ADDRESS;

`ifdef DBG
                $display(
                    "write line to BurstRAM address: 0x%h",
                    {cache_line_tag[line_ix], line_ix, {DATA_IX_IN_LINE_BITWIDTH{1'b0}}, {ADDRESS_LEADING_ZEROS_BITWIDTH{1'b0}}} >> BYTE_ADDRESS_SHIFT_RIGHT_TO_RAM_ADDRESS);
`endif


                br_cmd <= 1;  // write
                for (integer i = 0; i < DATA_PER_RAM_DATA; i = i + 1) begin
                  br_wr_data[(i+1)*DATA_BITWIDTH-1-:DATA_BITWIDTH] <= cache_line_data[line_ix][i];

`ifdef DBG
                  $display("write data %0d: %h", i, cache_line_data[line_ix][i]);
`endif

                end
                burst_counter <= 0;  // first payload will have been sent
                burst_data_ix <= DATA_PER_RAM_DATA;  // skip the first payload
                state <= STATE_WRITE_LINE;

              end else begin  // not (cache_line_dirty[line_ix]) 

`ifdef DBG
                $display("cache line not dirty");
`endif

                // extract the cache line address from current address
                br_addr <= {
                  address[ADDRESS_BITWIDTH-1-:(TAG_BITWIDTH+LINE_IX_BITWIDTH)],
                  {DATA_IX_IN_LINE_BITWIDTH{1'b0}},
                  {ADDRESS_LEADING_ZEROS_BITWIDTH{1'b0}}
                }>>BYTE_ADDRESS_SHIFT_RIGHT_TO_RAM_ADDRESS;

`ifdef DBG
                $display(
                    "read line from BurstRAM address: 0x%h",
                    {address[ADDRESS_BITWIDTH-1-:(TAG_BITWIDTH+LINE_IX_BITWIDTH)], {DATA_IX_IN_LINE_BITWIDTH{1'b0}}, {ADDRESS_LEADING_ZEROS_BITWIDTH{1'b0}}} >> BYTE_ADDRESS_SHIFT_RIGHT_TO_RAM_ADDRESS);
`endif

                // cache line not dirty; read cache line and set data
                br_cmd <= 0;  // read
                cache_line_valid[line_ix] <= 1;
                // note: ok to flag cache line as valid here
                cache_line_tag[line_ix] <= tag;
                cache_line_dirty[line_ix] <= 0;
                burst_counter <= 0;
                burst_data_ix <= 0;
                state <= STATE_WRITE_FETCH_LINE;
              end
            end
          end
        end

        STATE_RECV_WAIT_FOR_DATA_VALID: begin
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
            busy  <= 0;
            state <= STATE_IDLE;
          end
        end

        STATE_WRITE_LINE: begin
          br_cmd_en <= 0;
          if (burst_counter == RAM_BURST_DATA_COUNT - 1) begin
            // -1 because of the non-blocking assignments are updated at
            // the end of the always block

            // after write back is done read the line and then set the data
            br_addr <= {
                address[ADDRESS_BITWIDTH-1-:(TAG_BITWIDTH+LINE_IX_BITWIDTH)],
                {DATA_IX_IN_LINE_BITWIDTH{1'b0}},
                {ADDRESS_LEADING_ZEROS_BITWIDTH{1'b0}}
              }>>BYTE_ADDRESS_SHIFT_RIGHT_TO_RAM_ADDRESS;

            br_cmd <= 0;  // read
            br_cmd_en <= 1;
            // set the cache line tag to the new address
            cache_line_tag[line_ix] <= tag;
            cache_line_valid[line_ix] <= 1;
            cache_line_dirty[line_ix] <= 0;

`ifdef DBG
            $display(
                "read line from BurstRAM address: 0x%h",
                {address[ADDRESS_BITWIDTH-1-:(TAG_BITWIDTH+LINE_IX_BITWIDTH)], {DATA_IX_IN_LINE_BITWIDTH{1'b0}}, {ADDRESS_LEADING_ZEROS_BITWIDTH{1'b0}}} >> BYTE_ADDRESS_SHIFT_RIGHT_TO_RAM_ADDRESS);
`endif

            burst_counter <= 0;
            burst_data_ix <= 0;

            state <= STATE_WRITE_FETCH_LINE;
          end else begin  // not (burst_counter == RAM_BURST_DATA_COUNT - 1)
            // write next data from cache line
            for (integer i = 0; i < DATA_PER_RAM_DATA; i = i + 1) begin
              br_wr_data[(i+1)*DATA_BITWIDTH-1 -:DATA_BITWIDTH] 
                <= cache_line_data[line_ix][burst_data_ix + i];

`ifdef DBG
              $display("write data %0d: %0h", i, cache_line_data[line_ix][burst_data_ix+i]);
`endif

            end
            burst_data_ix <= burst_data_ix + DATA_PER_RAM_DATA;
            burst_counter <= burst_counter + 1;
          end
        end

        STATE_WRITE_FETCH_LINE: begin
          br_cmd_en <= 0;  // note: can turn of 'cmd' after one cycle
          // wait for read to be valid
          if (br_rd_data_valid) begin
            update_cache_line_data;
            state <= STATE_WRITE_FETCH_RECV_DATA;
          end
        end

        STATE_WRITE_FETCH_RECV_DATA: begin
          update_cache_line_data;
          if (burst_counter == RAM_BURST_DATA_COUNT - 1) begin
            // -1 because of the non-blocking assignments are updated at
            // the end of the always block

            // new cache line has been fetched
            // write the enabled bytes into the cache line
            for (integer i = 0; i < DATA_SIZE_BYTES; i = i + 1) begin
              if (write_enable_bytes[i]) begin
                cache_line_data[line_ix][data_ix][(i+1)*8-1-:8] <= data_in[(i+1)*8-1-:8];
              end
            end

            if (write_enable_bytes == 0) begin
              data_out <= cache_line_data[line_ix][data_ix];
              data_out_valid <= 1;
            end else begin

`ifdef DBG
              $display("set cache line %0d dirty", line_ix);
`endif

              cache_line_dirty[line_ix] <= 1;
            end

            busy  <= 0;
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
          data_out <= br_rd_data[(i+1)*DATA_BITWIDTH-1-:DATA_BITWIDTH];
          data_out_valid <= 1;
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
