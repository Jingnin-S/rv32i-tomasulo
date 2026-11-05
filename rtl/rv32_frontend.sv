`timescale 1ns/1ps

module rv32_frontend #(
    parameter int PRED_ENTRIES = 16,
    parameter logic [31:0] RESET_PC = 32'h0000_0000
) (
    input  logic clk,
    input  logic rst_n,

    output logic        imem_req_valid,
    input  logic        imem_req_ready,
    output logic [31:0] imem_req_address,
    input  logic        imem_rsp_valid,
    output logic        imem_rsp_ready,
    input  logic [31:0] imem_rsp_data,
    input  logic        imem_rsp_error,

    output logic                     fetch_valid,
    input  logic                     fetch_ready,
    output rv32_pkg::fetch_packet_t  fetch_packet,

    input  logic        redirect_valid,
    input  logic [31:0] redirect_pc,

    input  logic                    predictor_update_valid,
    input  logic [31:0]             predictor_update_pc,
    input  logic                    predictor_update_taken,
    input  logic [31:0]             predictor_update_target,
    input  rv32_pkg::branch_op_e     predictor_update_op
);
    import rv32_pkg::*;

    localparam int PRED_IDX_W = $clog2(PRED_ENTRIES);

    logic [31:0] pc_q;
    logic epoch_q;
    logic request_pending_q;
    logic [31:0] request_pc_q;
    logic request_pred_taken_q;
    logic [31:0] request_pred_target_q;
    logic request_epoch_q;

    logic buffer_valid_q;
    fetch_packet_t buffer_q;

    logic btb_valid [0:PRED_ENTRIES-1];
    logic [31:0] btb_tag [0:PRED_ENTRIES-1];
    logic [31:0] btb_target [0:PRED_ENTRIES-1];
    logic btb_unconditional [0:PRED_ENTRIES-1];
    logic [1:0] bht_counter [0:PRED_ENTRIES-1];

    logic [PRED_IDX_W-1:0] lookup_idx;
    logic lookup_hit;
    logic lookup_taken;
    logic [31:0] lookup_target;

    always_comb begin
        lookup_idx = pc_q[2 +: PRED_IDX_W];
        lookup_hit = btb_valid[lookup_idx] && btb_tag[lookup_idx] == pc_q;
        lookup_taken = lookup_hit &&
                       (btb_unconditional[lookup_idx] || bht_counter[lookup_idx][1]);
        lookup_target = lookup_taken ? btb_target[lookup_idx] : pc_q + 32'd4;

        imem_req_valid = !request_pending_q && !buffer_valid_q;
        imem_req_address = pc_q;
        imem_rsp_ready = request_pending_q && !buffer_valid_q;

        fetch_valid = buffer_valid_q;
        fetch_packet = buffer_q;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        int i;
        logic [PRED_IDX_W-1:0] update_idx;

        if (!rst_n) begin
            pc_q <= RESET_PC;
            epoch_q <= 1'b0;
            request_pending_q <= 1'b0;
            request_pc_q <= '0;
            request_pred_taken_q <= 1'b0;
            request_pred_target_q <= '0;
            request_epoch_q <= 1'b0;
            buffer_valid_q <= 1'b0;
            buffer_q <= '0;
            for (i = 0; i < PRED_ENTRIES; i++) begin
                btb_valid[i] <= 1'b0;
                btb_tag[i] <= '0;
                btb_target[i] <= '0;
                btb_unconditional[i] <= 1'b0;
                bht_counter[i] <= 2'b01;
            end
        end else begin
            if (fetch_valid && fetch_ready) begin
                buffer_valid_q <= 1'b0;
            end

            if (imem_req_valid && imem_req_ready) begin
                request_pending_q <= 1'b1;
                request_pc_q <= pc_q;
                request_pred_taken_q <= lookup_taken;
                request_pred_target_q <= lookup_target;
                request_epoch_q <= epoch_q;
                pc_q <= lookup_target;
            end

            if (imem_rsp_valid && imem_rsp_ready) begin
                request_pending_q <= 1'b0;
                if (request_epoch_q == epoch_q) begin
                    buffer_valid_q <= 1'b1;
                    buffer_q.pc <= request_pc_q;
                    buffer_q.instr <= imem_rsp_error ? 32'h0000_0000 : imem_rsp_data;
                    buffer_q.fault <= imem_rsp_error;
                    buffer_q.pred_taken <= request_pred_taken_q;
                    buffer_q.pred_target <= request_pred_target_q;
                end
            end

            if (predictor_update_valid) begin
                update_idx = predictor_update_pc[2 +: PRED_IDX_W];
                btb_valid[update_idx] <= 1'b1;
                btb_tag[update_idx] <= predictor_update_pc;
                btb_target[update_idx] <= predictor_update_target;
                btb_unconditional[update_idx] <=
                    predictor_update_op == BR_JAL || predictor_update_op == BR_JALR;
                if (predictor_update_taken && bht_counter[update_idx] != 2'b11) begin
                    bht_counter[update_idx] <= bht_counter[update_idx] + 1'b1;
                end else if (!predictor_update_taken && bht_counter[update_idx] != 2'b00) begin
                    bht_counter[update_idx] <= bht_counter[update_idx] - 1'b1;
                end
            end

            if (redirect_valid) begin
                pc_q <= redirect_pc;
                epoch_q <= ~epoch_q;
                buffer_valid_q <= 1'b0;
                if (imem_rsp_valid && imem_rsp_ready) begin
                    request_pending_q <= 1'b0;
                end
            end
        end
    end

endmodule
