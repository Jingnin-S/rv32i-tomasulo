`timescale 1ns/1ps

module rv32_decode (
    input  logic                    fetch_valid,
    output logic                    fetch_ready,
    input  rv32_pkg::fetch_packet_t fetch_packet,

    output logic                    uop_valid,
    input  logic                    uop_ready,
    output rv32_pkg::decoded_uop_t  uop
);
    import rv32_pkg::*;

    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;

    always_comb begin
        opcode = fetch_packet.instr[6:0];
        funct3 = fetch_packet.instr[14:12];
        funct7 = fetch_packet.instr[31:25];

        fetch_ready = uop_ready;
        uop_valid = fetch_valid;
        uop = '0;
        uop.pc = fetch_packet.pc;
        uop.instr = fetch_packet.instr;
        uop.rs1 = fetch_packet.instr[19:15];
        uop.rs2 = fetch_packet.instr[24:20];
        uop.rd = fetch_packet.instr[11:7];
        uop.pred_taken = fetch_packet.pred_taken;
        uop.pred_target = fetch_packet.pred_target;
        uop.illegal = 1'b1;
        uop.trap_cause = TRAP_ILLEGAL;
        uop.alu_op = ALU_ADD;
        uop.branch_op = BR_NONE;
        uop.memory_size = MEM_WORD;

        unique case (opcode)
            7'b0110111: begin // LUI
                uop.illegal = 1'b0;
                uop.fu = FU_INT;
                uop.alu_op = ALU_LUI;
                uop.imm = {fetch_packet.instr[31:12], 12'b0};
                uop.writes_rd = 1'b1;
            end
            7'b0010111: begin // AUIPC
                uop.illegal = 1'b0;
                uop.fu = FU_INT;
                uop.alu_op = ALU_AUIPC;
                uop.imm = {fetch_packet.instr[31:12], 12'b0};
                uop.writes_rd = 1'b1;
            end
            7'b1101111: begin // JAL
                uop.illegal = 1'b0;
                uop.fu = FU_BRANCH;
                uop.branch_op = BR_JAL;
                uop.imm = {{11{fetch_packet.instr[31]}}, fetch_packet.instr[31],
                           fetch_packet.instr[19:12], fetch_packet.instr[20],
                           fetch_packet.instr[30:21], 1'b0};
                uop.writes_rd = 1'b1;
            end
            7'b1100111: begin // JALR
                if (funct3 == 3'b000) begin
                    uop.illegal = 1'b0;
                    uop.fu = FU_BRANCH;
                    uop.branch_op = BR_JALR;
                    uop.imm = {{20{fetch_packet.instr[31]}}, fetch_packet.instr[31:20]};
                    uop.use_rs1 = 1'b1;
                    uop.writes_rd = 1'b1;
                end
            end
            7'b1100011: begin // BRANCH
                uop.fu = FU_BRANCH;
                uop.use_rs1 = 1'b1;
                uop.use_rs2 = 1'b1;
                uop.imm = {{19{fetch_packet.instr[31]}}, fetch_packet.instr[31],
                           fetch_packet.instr[7], fetch_packet.instr[30:25],
                           fetch_packet.instr[11:8], 1'b0};
                unique case (funct3)
                    3'b000: begin uop.illegal = 1'b0; uop.branch_op = BR_BEQ; end
                    3'b001: begin uop.illegal = 1'b0; uop.branch_op = BR_BNE; end
                    3'b100: begin uop.illegal = 1'b0; uop.branch_op = BR_BLT; end
                    3'b101: begin uop.illegal = 1'b0; uop.branch_op = BR_BGE; end
                    3'b110: begin uop.illegal = 1'b0; uop.branch_op = BR_BLTU; end
                    3'b111: begin uop.illegal = 1'b0; uop.branch_op = BR_BGEU; end
                    default: begin end
                endcase
            end
            7'b0000011: begin // LOAD
                uop.fu = FU_MEMORY;
                uop.use_rs1 = 1'b1;
                uop.writes_rd = 1'b1;
                uop.imm = {{20{fetch_packet.instr[31]}}, fetch_packet.instr[31:20]};
                unique case (funct3)
                    3'b000: begin uop.illegal = 1'b0; uop.memory_size = MEM_BYTE; end
                    3'b001: begin uop.illegal = 1'b0; uop.memory_size = MEM_HALF; end
                    3'b010: begin uop.illegal = 1'b0; uop.memory_size = MEM_WORD; end
                    3'b100: begin uop.illegal = 1'b0; uop.memory_size = MEM_BYTE; uop.load_unsigned = 1'b1; end
                    3'b101: begin uop.illegal = 1'b0; uop.memory_size = MEM_HALF; uop.load_unsigned = 1'b1; end
                    default: begin end
                endcase
            end
            7'b0100011: begin // STORE
                uop.fu = FU_MEMORY;
                uop.use_rs1 = 1'b1;
                uop.use_rs2 = 1'b1;
                uop.memory_write = 1'b1;
                uop.imm = {{20{fetch_packet.instr[31]}}, fetch_packet.instr[31:25],
                           fetch_packet.instr[11:7]};
                unique case (funct3)
                    3'b000: begin uop.illegal = 1'b0; uop.memory_size = MEM_BYTE; end
                    3'b001: begin uop.illegal = 1'b0; uop.memory_size = MEM_HALF; end
                    3'b010: begin uop.illegal = 1'b0; uop.memory_size = MEM_WORD; end
                    default: begin end
                endcase
            end
            7'b0010011: begin // OP-IMM
                uop.fu = FU_INT;
                uop.use_rs1 = 1'b1;
                uop.writes_rd = 1'b1;
                uop.imm = {{20{fetch_packet.instr[31]}}, fetch_packet.instr[31:20]};
                unique case (funct3)
                    3'b000: begin uop.illegal = 1'b0; uop.alu_op = ALU_ADD; end
                    3'b010: begin uop.illegal = 1'b0; uop.alu_op = ALU_SLT; end
                    3'b011: begin uop.illegal = 1'b0; uop.alu_op = ALU_SLTU; end
                    3'b100: begin uop.illegal = 1'b0; uop.alu_op = ALU_XOR; end
                    3'b110: begin uop.illegal = 1'b0; uop.alu_op = ALU_OR; end
                    3'b111: begin uop.illegal = 1'b0; uop.alu_op = ALU_AND; end
                    3'b001: if (funct7 == 7'b0000000) begin
                        uop.illegal = 1'b0; uop.alu_op = ALU_SLL; uop.imm = {27'b0, fetch_packet.instr[24:20]};
                    end
                    3'b101: begin
                        if (funct7 == 7'b0000000) begin
                            uop.illegal = 1'b0; uop.alu_op = ALU_SRL; uop.imm = {27'b0, fetch_packet.instr[24:20]};
                        end else if (funct7 == 7'b0100000) begin
                            uop.illegal = 1'b0; uop.alu_op = ALU_SRA; uop.imm = {27'b0, fetch_packet.instr[24:20]};
                        end
                    end
                    default: begin end
                endcase
            end
            7'b0110011: begin // OP
                uop.fu = FU_INT;
                uop.use_rs1 = 1'b1;
                uop.use_rs2 = 1'b1;
                uop.writes_rd = 1'b1;
                unique case ({funct7, funct3})
                    {7'b0000000, 3'b000}: begin uop.illegal = 1'b0; uop.alu_op = ALU_ADD; end
                    {7'b0100000, 3'b000}: begin uop.illegal = 1'b0; uop.alu_op = ALU_SUB; end
                    {7'b0000000, 3'b001}: begin uop.illegal = 1'b0; uop.alu_op = ALU_SLL; end
                    {7'b0000000, 3'b010}: begin uop.illegal = 1'b0; uop.alu_op = ALU_SLT; end
                    {7'b0000000, 3'b011}: begin uop.illegal = 1'b0; uop.alu_op = ALU_SLTU; end
                    {7'b0000000, 3'b100}: begin uop.illegal = 1'b0; uop.alu_op = ALU_XOR; end
                    {7'b0000000, 3'b101}: begin uop.illegal = 1'b0; uop.alu_op = ALU_SRL; end
                    {7'b0100000, 3'b101}: begin uop.illegal = 1'b0; uop.alu_op = ALU_SRA; end
                    {7'b0000000, 3'b110}: begin uop.illegal = 1'b0; uop.alu_op = ALU_OR; end
                    {7'b0000000, 3'b111}: begin uop.illegal = 1'b0; uop.alu_op = ALU_AND; end
                    default: begin end
                endcase
            end
            7'b0001111: begin // FENCE
                if (funct3 == 3'b000) begin
                    uop.illegal = 1'b0;
                    uop.fence = 1'b1;
                end
            end
            7'b1110011: begin
                if (fetch_packet.instr == 32'h0000_0073) begin
                    uop.illegal = 1'b0;
                    uop.halt = 1'b1;
                    uop.trap_cause = TRAP_ECALL;
                end else if (fetch_packet.instr == 32'h0010_0073) begin
                    uop.illegal = 1'b0;
                    uop.halt = 1'b1;
                    uop.trap_cause = TRAP_BREAKPOINT;
                end
            end
            default: begin end
        endcase

        if (uop.rd == 5'd0) begin
            uop.writes_rd = 1'b0;
        end
        if (fetch_packet.fault) begin
            uop = '0;
            uop.pc = fetch_packet.pc;
            uop.instr = fetch_packet.instr;
            uop.illegal = 1'b1;
            uop.trap_cause = TRAP_INSTR_ACCESS;
            uop.pred_taken = fetch_packet.pred_taken;
            uop.pred_target = fetch_packet.pred_target;
        end
    end

endmodule
