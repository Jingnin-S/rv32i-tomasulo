`timescale 1ns/1ps

module rv32_alu_branch (
    input  logic clk,
    input  logic rst_n,

    input  logic                       issue_valid,
    output logic                       issue_ready,
    input  rv32_pkg::dispatch_packet_t issue,

    output logic                         completion_valid,
    input  logic                         completion_ready,
    output rv32_pkg::completion_packet_t completion,

    input  logic                       recover_valid,
    input  logic [rv32_pkg::SEQ_W-1:0] recover_seq
);
    import rv32_pkg::*;

    logic completion_valid_q;
    completion_packet_t completion_q;
    completion_packet_t calculated;
    logic [31:0] rhs;
    logic branch_taken;
    logic [31:0] branch_target;
    logic [31:0] expected_next;
    logic [31:0] actual_next;

    always_comb begin
        issue_ready = !completion_valid_q || completion_ready;
        completion_valid = completion_valid_q;
        completion = completion_q;
        rhs = issue.uop.use_rs2 ? issue.src2_value : issue.uop.imm;
        branch_taken = 1'b0;
        branch_target = issue.uop.pc + issue.uop.imm;
        expected_next = issue.uop.pc + 32'd4;
        actual_next = issue.uop.pc + 32'd4;

        unique case (issue.uop.branch_op)
            BR_BEQ:  branch_taken = issue.src1_value == issue.src2_value;
            BR_BNE:  branch_taken = issue.src1_value != issue.src2_value;
            BR_BLT:  branch_taken = $signed(issue.src1_value) < $signed(issue.src2_value);
            BR_BGE:  branch_taken = $signed(issue.src1_value) >= $signed(issue.src2_value);
            BR_BLTU: branch_taken = issue.src1_value < issue.src2_value;
            BR_BGEU: branch_taken = issue.src1_value >= issue.src2_value;
            BR_JAL:  branch_taken = 1'b1;
            BR_JALR: begin
                branch_taken = 1'b1;
                branch_target = (issue.src1_value + issue.uop.imm) & 32'hffff_fffe;
            end
            default: begin end
        endcase

        calculated = '0;
        calculated.rob_tag = issue.rob_tag;
        calculated.seq_num = issue.seq_num;
        calculated.trap_cause = TRAP_NONE;

        unique case (issue.uop.alu_op)
            ALU_ADD:   calculated.value = issue.src1_value + rhs;
            ALU_SUB:   calculated.value = issue.src1_value - issue.src2_value;
            ALU_SLL:   calculated.value = issue.src1_value << rhs[4:0];
            ALU_SLT:   calculated.value = {31'd0, $signed(issue.src1_value) < $signed(rhs)};
            ALU_SLTU:  calculated.value = {31'd0, issue.src1_value < rhs};
            ALU_XOR:   calculated.value = issue.src1_value ^ rhs;
            ALU_SRL:   calculated.value = issue.src1_value >> rhs[4:0];
            ALU_SRA:   calculated.value = $signed(issue.src1_value) >>> rhs[4:0];
            ALU_OR:    calculated.value = issue.src1_value | rhs;
            ALU_AND:   calculated.value = issue.src1_value & rhs;
            ALU_LUI:   calculated.value = issue.uop.imm;
            ALU_AUIPC: calculated.value = issue.uop.pc + issue.uop.imm;
            default:   calculated.value = '0;
        endcase

        if (issue.uop.branch_op != BR_NONE) begin
            calculated.is_control = 1'b1;
            calculated.actual_taken = branch_taken;
            calculated.actual_target = branch_taken ? branch_target : issue.uop.pc + 32'd4;
            if (issue.uop.branch_op == BR_JAL || issue.uop.branch_op == BR_JALR) begin
                calculated.value = issue.uop.pc + 32'd4;
            end
            if (branch_taken && branch_target[1:0] != 2'b00) begin
                calculated.exception = 1'b1;
                calculated.trap_cause = TRAP_INSTR_MISALIGNED;
                calculated.actual_taken = 1'b0;
                calculated.actual_target = issue.uop.pc + 32'd4;
            end
            expected_next = issue.uop.pred_taken ? issue.uop.pred_target : issue.uop.pc + 32'd4;
            actual_next = calculated.actual_target;
            calculated.mispredict = expected_next != actual_next;
        end

    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            completion_valid_q <= 1'b0;
            completion_q <= '0;
        end else begin
            if (completion_valid && completion_ready) begin
                completion_valid_q <= 1'b0;
            end
            if (issue_valid && issue_ready) begin
                completion_valid_q <= 1'b1;
                completion_q <= calculated;
            end
            if (recover_valid && completion_valid_q && completion_q.seq_num > recover_seq) begin
                completion_valid_q <= 1'b0;
            end
        end
    end

endmodule
