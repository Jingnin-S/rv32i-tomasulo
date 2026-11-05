`timescale 1ns/1ps

module rv32_rob (
    input  logic clk,
    input  logic rst_n,

    output logic                         alloc_ready,
    output logic [rv32_pkg::ROB_TAG_W-1:0] alloc_tag,
    output logic [rv32_pkg::SEQ_W-1:0]    alloc_seq,
    input  logic                         dispatch_fire,
    input  rv32_pkg::decoded_uop_t       dispatch_uop,

    input  logic                         query1_valid,
    input  logic [rv32_pkg::ROB_TAG_W-1:0] query1_tag,
    output logic                         query1_ready,
    output logic [31:0]                  query1_value,
    output logic [rv32_pkg::SEQ_W-1:0]  query1_seq,
    input  logic                         query2_valid,
    input  logic [rv32_pkg::ROB_TAG_W-1:0] query2_tag,
    output logic                         query2_ready,
    output logic [31:0]                  query2_value,
    output logic [rv32_pkg::SEQ_W-1:0]  query2_seq,

    input  logic                         completion_valid,
    input  rv32_pkg::completion_packet_t completion,

    output logic                         commit_valid,
    input  logic                         commit_ready,
    output rv32_pkg::commit_packet_t     commit,
    output logic                         commit_fire,

    input  logic                         recover_valid,
    input  logic [rv32_pkg::ROB_TAG_W-1:0] recover_tag,
    input  logic [rv32_pkg::SEQ_W-1:0]    recover_seq,

    output logic [$clog2(rv32_pkg::ROB_SIZE+1)-1:0] occupancy
);
    import rv32_pkg::*;

    logic valid_q [0:ROB_SIZE-1];
    logic ready_q [0:ROB_SIZE-1];
    decoded_uop_t uop_q [0:ROB_SIZE-1];
    logic [SEQ_W-1:0] seq_q [0:ROB_SIZE-1];
    logic [31:0] value_q [0:ROB_SIZE-1];
    logic exception_q [0:ROB_SIZE-1];
    trap_cause_e trap_cause_q [0:ROB_SIZE-1];
    logic actual_taken_q [0:ROB_SIZE-1];
    logic [31:0] actual_target_q [0:ROB_SIZE-1];
    logic [31:0] store_address_q [0:ROB_SIZE-1];
    logic [31:0] store_data_q [0:ROB_SIZE-1];
    logic [3:0] store_strobe_q [0:ROB_SIZE-1];

    logic [ROB_TAG_W-1:0] head_q;
    logic [ROB_TAG_W-1:0] tail_q;
    logic [$clog2(ROB_SIZE+1)-1:0] count_q;
    logic [SEQ_W-1:0] next_seq_q;

    always_comb begin
        alloc_ready = count_q != ROB_SIZE[$clog2(ROB_SIZE+1)-1:0];
        alloc_tag = tail_q;
        alloc_seq = next_seq_q;
        occupancy = count_q;

        query1_ready = query1_valid && valid_q[query1_tag] && ready_q[query1_tag];
        query1_value = value_q[query1_tag];
        query1_seq = seq_q[query1_tag];
        query2_ready = query2_valid && valid_q[query2_tag] && ready_q[query2_tag];
        query2_value = value_q[query2_tag];
        query2_seq = seq_q[query2_tag];

        commit_valid = count_q != 0 && valid_q[head_q] && ready_q[head_q] && !recover_valid;
        commit = '0;
        commit.rob_tag = head_q;
        commit.seq_num = seq_q[head_q];
        commit.pc = uop_q[head_q].pc;
        commit.instr = uop_q[head_q].instr;
        commit.writes_rd = uop_q[head_q].writes_rd;
        commit.rd = uop_q[head_q].rd;
        commit.value = value_q[head_q];
        commit.is_store = uop_q[head_q].memory_write;
        commit.store_address = store_address_q[head_q];
        commit.store_data = store_data_q[head_q];
        commit.store_strobe = store_strobe_q[head_q];
        commit.is_control = uop_q[head_q].branch_op != BR_NONE;
        commit.actual_taken = actual_taken_q[head_q];
        commit.actual_target = actual_target_q[head_q];
        commit.branch_op = uop_q[head_q].branch_op;
        commit.halt = uop_q[head_q].halt;
        commit.exception = exception_q[head_q];
        commit.trap_cause = trap_cause_q[head_q];
        commit_fire = commit_valid && commit_ready;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        int i;
        int survivors;

        if (!rst_n) begin
            head_q <= '0;
            tail_q <= '0;
            count_q <= '0;
            next_seq_q <= '0;
            for (i = 0; i < ROB_SIZE; i++) begin
                valid_q[i] <= 1'b0;
                ready_q[i] <= 1'b0;
                uop_q[i] <= '0;
                seq_q[i] <= '0;
                value_q[i] <= '0;
                exception_q[i] <= 1'b0;
                trap_cause_q[i] <= TRAP_NONE;
                actual_taken_q[i] <= 1'b0;
                actual_target_q[i] <= '0;
                store_address_q[i] <= '0;
                store_data_q[i] <= '0;
                store_strobe_q[i] <= '0;
            end
        end else if (recover_valid) begin
            survivors = 0;
            for (i = 0; i < ROB_SIZE; i++) begin
                if (valid_q[i] && seq_q[i] <= recover_seq) begin
                    survivors++;
                end else begin
                    valid_q[i] <= 1'b0;
                    ready_q[i] <= 1'b0;
                end
            end
            ready_q[recover_tag] <= 1'b1;
            value_q[recover_tag] <= completion.value;
            exception_q[recover_tag] <= completion.exception;
            trap_cause_q[recover_tag] <= completion.trap_cause;
            actual_taken_q[recover_tag] <= completion.actual_taken;
            actual_target_q[recover_tag] <= completion.actual_target;
            tail_q <= recover_tag + 1'b1;
            count_q <= survivors[$clog2(ROB_SIZE+1)-1:0];
        end else begin
            if (completion_valid) begin
                ready_q[completion.rob_tag] <= 1'b1;
                value_q[completion.rob_tag] <= completion.value;
                exception_q[completion.rob_tag] <= completion.exception;
                trap_cause_q[completion.rob_tag] <= completion.trap_cause;
                actual_taken_q[completion.rob_tag] <= completion.actual_taken;
                actual_target_q[completion.rob_tag] <= completion.actual_target;
                if (completion.is_store) begin
                    store_address_q[completion.rob_tag] <= completion.store_address;
                    store_data_q[completion.rob_tag] <= completion.store_data;
                    store_strobe_q[completion.rob_tag] <= completion.store_strobe;
                end
            end

            if (commit_fire) begin
                valid_q[head_q] <= 1'b0;
                ready_q[head_q] <= 1'b0;
                head_q <= head_q + 1'b1;
            end

            if (dispatch_fire) begin
                valid_q[tail_q] <= 1'b1;
                ready_q[tail_q] <= dispatch_uop.fu == FU_NONE;
                uop_q[tail_q] <= dispatch_uop;
                seq_q[tail_q] <= next_seq_q;
                value_q[tail_q] <= '0;
                exception_q[tail_q] <= dispatch_uop.illegal || dispatch_uop.halt;
                trap_cause_q[tail_q] <= dispatch_uop.trap_cause;
                actual_taken_q[tail_q] <= 1'b0;
                actual_target_q[tail_q] <= dispatch_uop.pc + 32'd4;
                store_address_q[tail_q] <= '0;
                store_data_q[tail_q] <= '0;
                store_strobe_q[tail_q] <= '0;
                tail_q <= tail_q + 1'b1;
                next_seq_q <= next_seq_q + 1'b1;
            end

            unique case ({dispatch_fire, commit_fire})
                2'b10: count_q <= count_q + 1'b1;
                2'b01: count_q <= count_q - 1'b1;
                default: count_q <= count_q;
            endcase
        end
    end

endmodule
