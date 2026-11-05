`timescale 1ns/1ps

module rv32_int_rs #(
    parameter int ENTRY_COUNT = 8
) (
    input  logic clk,
    input  logic rst_n,

    output logic                         dispatch_ready,
    input  logic                         dispatch_fire,
    input  rv32_pkg::dispatch_packet_t   dispatch,

    input  logic                         completion_valid,
    input  rv32_pkg::completion_packet_t completion,

    output logic                         issue_valid,
    input  logic                         issue_ready,
    output rv32_pkg::dispatch_packet_t   issue,

    input  logic                         recover_valid,
    input  logic [rv32_pkg::SEQ_W-1:0]   recover_seq
);
    import rv32_pkg::*;

    localparam int IDX_W = $clog2(ENTRY_COUNT);
    logic busy_q [0:ENTRY_COUNT-1];
    dispatch_packet_t entry_q [0:ENTRY_COUNT-1];
    logic [IDX_W-1:0] free_idx;
    logic [IDX_W-1:0] issue_idx;
    logic found_free;
    logic found_issue;

    always_comb begin
        found_free = 1'b0;
        free_idx = '0;
        found_issue = 1'b0;
        issue_idx = '0;
        issue = '0;

        for (int i = 0; i < ENTRY_COUNT; i++) begin
            if (!found_free && !busy_q[i]) begin
                found_free = 1'b1;
                free_idx = i[IDX_W-1:0];
            end
            if (busy_q[i] && entry_q[i].src1_ready && entry_q[i].src2_ready) begin
                if (!found_issue || entry_q[i].seq_num < issue.seq_num) begin
                    found_issue = 1'b1;
                    issue_idx = i[IDX_W-1:0];
                    issue = entry_q[i];
                end
            end
        end

        dispatch_ready = found_free && !recover_valid;
        issue_valid = found_issue && !recover_valid;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        int i;

        if (!rst_n) begin
            for (i = 0; i < ENTRY_COUNT; i++) begin
                busy_q[i] <= 1'b0;
                entry_q[i] <= '0;
            end
        end else if (recover_valid) begin
            for (i = 0; i < ENTRY_COUNT; i++) begin
                if (busy_q[i] && entry_q[i].seq_num > recover_seq) begin
                    busy_q[i] <= 1'b0;
                end
            end
        end else begin
            if (completion_valid) begin
                for (i = 0; i < ENTRY_COUNT; i++) begin
                    if (busy_q[i]) begin
                        if (!entry_q[i].src1_ready && entry_q[i].src1_tag == completion.rob_tag &&
                            entry_q[i].src1_seq == completion.seq_num) begin
                            entry_q[i].src1_ready <= 1'b1;
                            entry_q[i].src1_value <= completion.value;
                        end
                        if (!entry_q[i].src2_ready && entry_q[i].src2_tag == completion.rob_tag &&
                            entry_q[i].src2_seq == completion.seq_num) begin
                            entry_q[i].src2_ready <= 1'b1;
                            entry_q[i].src2_value <= completion.value;
                        end
                    end
                end
            end
            if (issue_valid && issue_ready) begin
                busy_q[issue_idx] <= 1'b0;
            end
            if (dispatch_fire) begin
                busy_q[free_idx] <= 1'b1;
                entry_q[free_idx] <= dispatch;
            end
        end
    end

endmodule
