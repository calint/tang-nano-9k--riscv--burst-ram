`default_nettype none
//`define DBG

module SoC #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 9600,

    // RAM and cache
    parameter RAM_DEPTH_BITWIDTH = 8,
    parameter RAM_BURST_DATA_BITWIDTH = 64,
    parameter RAM_BURST_DATA_COUNT = 4,
    parameter CACHE_LINE_IX_BITWIDTH = 1,
    parameter CACHE_IX_IN_LINE_BITWIDTH = 3
) (
    input wire rst,
    input wire clk_cpu,
    input wire clk_ram,
    output wire [5:0] led,
    input wire uart_rx,
    output wire uart_tx,
    input wire btn,
    output reg initiated,
    output reg is_stalled,

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

  reg [31:0] pc;  // program counter, byte addressed, next instruction to fetch
  reg [31:0] pc_nxt;  // next value of program counter
  reg [31:0] pc_ir;  // program counter of current instruction

  wire [31:0] ram_doutB;
  reg [31:0] ir;  // instruction register (one cycle delay due to ram access)
  wire [6:0] opcode = ir[6:0];
  wire [4:0] rd = ir[11:7];  // destination register
  wire [2:0] funct3 = ir[14:12];
  wire [4:0] rs1 = ir[19:15];  // source register 1
  wire [4:0] rs2 = ir[24:20];  // source register 2
  wire [6:0] funct7 = ir[31:25];
  wire signed [31:0] I_imm12 = {{20{ir[31]}}, ir[31:20]};
  wire [31:0] U_imm20 = {ir[31:12], {12{1'b0}}};
  wire signed [31:0] S_imm12 = {{20{ir[31]}}, ir[31:25], ir[11:7]};
  wire signed [31:0] B_imm12 = {{20{ir[31]}}, ir[7], ir[30:25], ir[11:8], 1'b0};
  wire signed [31:0] J_imm20 = {{12{ir[31]}}, ir[19:12], ir[20], ir[30:21], 1'b0};

  reg [31:0] regs_rd_wd;  // data for write to register 'rd' if 'regs_rd_we' is enabled
  reg regs_rd_we;
  wire signed [31:0] regs_rd1;  // register value of 'rs1'
  wire signed [31:0] regs_rd2;  // register value of 'rs2'

  // RAM port A
  reg ram_enA;
  reg [2:0] ram_reA;  // ram port A read enable
  reg [1:0] ram_weA;  // ram port A write enable
  reg [31:0] ram_addrA;  // ram port A address
  reg [31:0] ram_dinA;  // data to ram port A
  wire [31:0] ram_doutA;  // data from ram port A
  wire ram_validA;
  wire ram_bsyA;

  // RAM port B
  reg ram_enB;
  wire ram_validB;
  wire ram_bsyB;

  reg is_ld;  // current instruction is 'load'
  reg [4:0] ld_rd;  // previous instruction 'rd'
  reg regs_we3;  // enabled when previous instruction was 'load'
                 // will write 'ram_doutA' to register 'ld_rd'

  reg signed [31:0] rs1_dat;  // resolved rs1 value considering pipeline
  reg signed [31:0] rs2_dat;  // resolved rs2 value considering pipeline

  reg bubble;  // signals that next instruction is a bubble
  reg is_bubble;  // signals that current instruction is a bubble

  reg stalled;

  localparam STATE_INITIATE = 2'b01;
  localparam STATE_RUN = 2'b10;

  reg [1:0] state;

  always @(*) begin
    regs_rd_we = 0;
    regs_rd_wd = 0;
    ram_addrA = 0;
    ram_dinA = 0;
    ram_weA = 0;
    ram_reA = 0;
    is_ld = 0;
    bubble = 0;
    rs1_dat = 0;
    rs2_dat = 0;
    stalled = ram_bsyA || ram_bsyB;

    if (!is_stalled && initiated) begin
      pc_nxt = pc + 4;
    end else begin
      pc_nxt = pc;
    end

    if (!is_bubble && !is_stalled && initiated) begin
      // if last instruction was a load to a register and the same register
      // is used in this instruction then use the output of ram since it is
      // not in the register yet 
      rs1_dat = regs_we3 && rs1 == ld_rd ? ram_doutA : regs_rd1;
      rs2_dat = regs_we3 && rs2 == ld_rd ? ram_doutA : regs_rd2;

      case (opcode)
        7'b0110111: begin  // LUI
          regs_rd_wd = U_imm20;
          regs_rd_we = 1;
        end
        7'b0010011: begin  // logical ops immediate
          regs_rd_we = 1;
          case (funct3)
            3'b000: begin  // ADDI
              regs_rd_wd = rs1_dat + I_imm12;
            end
            3'b010: begin  // SLTI
              regs_rd_wd = rs1_dat < I_imm12;
            end
            3'b011: begin  // SLTIU
              regs_rd_wd = $unsigned(rs1_dat) < $unsigned(I_imm12);
            end
            3'b100: begin  // XORI
              regs_rd_wd = rs1_dat ^ I_imm12;
            end
            3'b110: begin  // ORI
              regs_rd_wd = rs1_dat | I_imm12;
            end
            3'b111: begin  // ANDI
              regs_rd_wd = rs1_dat & I_imm12;
            end
            3'b001: begin  // SLLI
              regs_rd_wd = rs1_dat << rs2;
            end
            3'b101: begin  // SRLI and SRAI
              regs_rd_wd = ir[30] ? rs1_dat >>> rs2 : rs1_dat >> rs2;
            end
          endcase  // case (funct3)
        end
        7'b0110011: begin  // logical ops
          regs_rd_we = 1;
          case (funct3)
            3'b000: begin  // ADD and SUB
              regs_rd_wd = ir[30] ? rs1_dat - rs2_dat : rs1_dat + rs2_dat;
            end
            3'b001: begin  // SLL
              regs_rd_wd = rs1_dat << rs2_dat[4:0];
            end
            3'b010: begin  // SLT
              regs_rd_wd = rs1_dat < rs2_dat;
            end
            3'b011: begin  // SLTU
              regs_rd_wd = $unsigned(rs1_dat) < $unsigned(rs2_dat);
            end
            3'b100: begin  // XOR
              regs_rd_wd = rs1_dat ^ rs2_dat;
            end
            3'b101: begin  // SRL and SRA
              regs_rd_wd = ir[30] ? rs1_dat >>> rs2_dat[4:0] : rs1_dat >> rs2_dat[4:0];
            end
            3'b110: begin  // OR
              regs_rd_wd = rs1_dat | rs2_dat;
            end
            3'b111: begin  // AND
              regs_rd_wd = rs1_dat & rs2_dat;
            end
          endcase  // case (funct3)
        end
        7'b0100011: begin  // store
          ram_addrA = rs1_dat + S_imm12;
          ram_dinA  = rs2_dat;
          case (funct3)
            3'b000: begin  // SB
              ram_weA = 2'b01;  // write byte
            end
            3'b001: begin  // SH
              ram_weA = 2'b10;  // write half word
            end
            3'b010: begin  // SW
              ram_weA = 2'b11;  // write word
            end
          endcase  // case (funct3)
        end
        7'b0000011: begin  // load
          ram_addrA = rs1_dat + I_imm12;
          is_ld = 1;
          case (funct3)
            3'b000: begin  // LB
              ram_reA = 3'b101;  // read sign extended byte
            end
            3'b001: begin  // LH
              ram_reA = 3'b110;  // read sign extended half word
            end
            3'b010: begin  // LW
              ram_reA = 3'b111;  // read word (signed)
            end
            3'b100: begin  // LBU
              ram_reA = 3'b001;  // read unsigned byte
            end
            3'b101: begin  // LHU
              ram_reA = 3'b010;  // read unsigned half word
            end
          endcase  // case (funct3)
        end
        7'b0010111: begin  // AUIPC
          regs_rd_wd = pc_ir + U_imm20;
          regs_rd_we = 1;
        end
        7'b1101111: begin  // JAL
          regs_rd_wd = pc;  // note. 'pc' is ahead one instruction (+4)
          regs_rd_we = 1;
          pc_nxt = pc_ir + J_imm20;
          bubble = 1;
        end
        7'b1100111: begin  // JALR
          regs_rd_wd = pc;  // note. 'pc' is ahead one instruction (+4)
          regs_rd_we = 1;
          pc_nxt = rs1_dat + I_imm12;
          bubble = 1;
        end
        7'b1100011: begin  // branches
          case (funct3)
            3'b000: begin  // BEQ
              if (rs1_dat == rs2_dat) begin
                pc_nxt = pc_ir + B_imm12;
                bubble = 1;
              end
            end
            3'b001: begin  // BNE
              if (rs1_dat != rs2_dat) begin
                pc_nxt = pc_ir + B_imm12;
                bubble = 1;
              end
            end
            3'b100: begin  // BLT
              if (rs1_dat < rs2_dat) begin
                pc_nxt = pc_ir + B_imm12;
                bubble = 1;
              end
            end
            3'b101: begin  // BGE
              if (rs1_dat >= rs2_dat) begin
                pc_nxt = pc_ir + B_imm12;
                bubble = 1;
              end
            end
            3'b110: begin  // BLTU
              if ($unsigned(rs1_dat) < $unsigned(rs2_dat)) begin
                pc_nxt = pc_ir + B_imm12;
                bubble = 1;
              end
            end
            3'b111: begin  // BGEU
              if ($unsigned(rs1_dat) >= $unsigned(rs2_dat)) begin
                pc_nxt = pc_ir + B_imm12;
                bubble = 1;
              end
            end
          endcase  // case (funct3)
        end
      endcase  // case (opcode)
    end
  end

  always @(posedge clk_cpu) begin
    if (rst) begin
      pc <= 0;
      pc_ir <= 0;
      is_bubble <= 0;
      initiated <= 0;
      ir <= 0;
      is_stalled <= 0;
      state <= STATE_INITIATE;
    end else begin
      case (state)
        STATE_INITIATE: begin
          if (!ram_bsyA && !ram_bsyB) begin
            initiated <= 1;
            ram_enA <= 1;
            ram_enB <= 1;
            state <= STATE_RUN;
          end
        end
        STATE_RUN: begin
          ir <= ram_doutB;

          regs_we3 <= is_ld;  // if this is a 'load' from ram enable write to
                              // register 'ld_rd' during next cycle due to one
                              // cycle delay for data valid from ram
          ld_rd <= rd;  // save the destination register for next cycle write
          is_bubble <= bubble;  // if instruction generates bubble of next
                                // instruction (branch, jumps instructions)
          is_stalled <= stalled;
          if (!stalled) begin
            pc <= pc_nxt;
            pc_ir <= pc_nxt - 4;  // -4 because 'pc' is the next instruction to be
                                  // fetched. when branching there is a bubble and
                                  // 'pc' is incremented by 4 during that
          end
        end
      endcase
    end
  end

  Registers regs (
      .clk(clk_cpu),
      .rs1(rs1),  // register source 1
      .rs2(rs2),  // register source 2
      .rd(rd),  // destination register
      .rd_wd(regs_rd_wd),  // write data to destination register
      .rd_we(regs_rd_we),  // write enable to destination register
      .rd1(regs_rd1),  // data out of register 'rs1'
      .rd2(regs_rd2),  // data out of register 'rs2'
      .ra3(ld_rd),  // register to write from ram out (load instructions)
      .wd3(ram_doutA),  // data for write to register 'ra3' when 'we3' is enabled
      .we3(regs_we3)  // write enable port 3
  );

  RAMIO #(
      .CLK_FREQ (CLK_FREQ),
      .BAUD_RATE(BAUD_RATE),

      // RAM and cache
      .RAM_DEPTH_BITWIDTH(RAM_DEPTH_BITWIDTH),
      .RAM_BURST_DATA_BITWIDTH(RAM_BURST_DATA_BITWIDTH),
      .RAM_BURST_DATA_COUNT(RAM_BURST_DATA_COUNT),
      .CACHE_LINE_IX_BITWIDTH(CACHE_LINE_IX_BITWIDTH)
  ) ram (
      .rst(rst),
      .clk_cpu(clk_cpu),
      .clk_ram(clk_ram),

      // port A: data memory, read / write byte addressable ram
      .enA(ram_enA),  // enables port A
      .reA(ram_reA),  // read: reA[2] sign extended, b01 - byte, b10 - half word, b11 - word
      .weA(ram_weA),  // write: b01 - byte, b10 - half word, b11 - word
      .addrA(ram_addrA),  // +1 because byte addressable
      .doutA(ram_doutA),  // data out from 'ram_addrA' depending on 'ram_reA' one cycle later
      .dinA(ram_dinA),  // data to write to 'ram_addrA' depending on 'ram_weA'
      .validA(ram_validA),  // when asserted doutA is valid
      .bsyA(ram_bsyA),  // when asserted port A is busy

      // port B: instruction memory, byte addressed, bottom 2 bits ignored, word aligned
      .enB(ram_enB),  // enables port B
      .addrB(pc),  // program counter
      .doutB(ram_doutB),  // instruction register
      .validB(ram_validB),  // when asserted doutB is valid
      .bsyB(ram_bsyB),  // when asserted port B is busy

      // I/O
      .leds(led),
      .uart_tx(uart_tx),
      .uart_rx(uart_rx),

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

endmodule

`undef DBG
`default_nettype wire
