`timescale 1ns/1ps

module rv32_lsu (
    input  logic clk,
    input  logic rst_n,

    input  logic                    load_valid,
    output logic                    load_ready,
    input  rv32_pkg::load_request_t load_request,

    input  logic                       store_valid,
    output logic                       store_ready,
    input  rv32_pkg::commit_packet_t   store_commit,

    output logic        dmem_req_valid,
    input  logic        dmem_req_ready,
    output logic        dmem_req_write,
    output logic [31:0] dmem_req_address,
    output logic [31:0] dmem_req_wdata,
    output logic [3:0]  dmem_req_wstrb,
    input  logic        dmem_rsp_valid,
    output logic        dmem_rsp_ready,
    input  logic [31:0] dmem_rsp_rdata,
    input  logic        dmem_rsp_error,

    output logic                         completion_valid,
    input  logic                         completion_ready,
    output rv32_pkg::completion_packet_t completion,

    input  logic                       recover_valid,
    input  logic [rv32_pkg::SEQ_W-1:0] recover_seq
);
    import rv32_pkg::*;

    typedef enum logic [1:0] {LSU_IDLE, LSU_WAIT, LSU_RESULT} state_e;
    state_e state_q;
    load_request_t pending_q;
    completion_packet_t completion_q;
    logic drop_response_q;

    always_comb begin
        dmem_req_valid = state_q == LSU_IDLE && (store_valid || load_valid) && !recover_valid;
        dmem_req_write = store_valid;
        dmem_req_address = store_valid ? store_commit.store_address :
                           {load_request.address[31:2], 2'b00};
        dmem_req_wdata = store_commit.store_data;
        dmem_req_wstrb = store_valid ? store_commit.store_strobe : 4'b0000;
        store_ready = state_q == LSU_IDLE && dmem_req_ready && !recover_valid;
        load_ready = state_q == LSU_IDLE && !store_valid && dmem_req_ready && !recover_valid;
        dmem_rsp_ready = state_q == LSU_WAIT;
        completion_valid = state_q == LSU_RESULT;
        completion = completion_q;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        logic [31:0] shifted;
        logic [15:0] half_value;
        logic [7:0] byte_value;

        if (!rst_n) begin
            state_q <= LSU_IDLE;
            pending_q <= '0;
            completion_q <= '0;
            drop_response_q <= 1'b0;
        end else begin
            if (state_q == LSU_IDLE && dmem_req_valid && dmem_req_ready) begin
                if (store_valid) begin
                    state_q <= LSU_IDLE;
                end else begin
                    state_q <= LSU_WAIT;
                    pending_q <= load_request;
                    drop_response_q <= 1'b0;
                end
            end

            if (state_q == LSU_WAIT && dmem_rsp_valid && dmem_rsp_ready) begin
                if (drop_response_q) begin
                    state_q <= LSU_IDLE;
                    drop_response_q <= 1'b0;
                end else begin
                    shifted = dmem_rsp_rdata >> (pending_q.address[1:0] * 8);
                    half_value = shifted[15:0];
                    byte_value = shifted[7:0];
                    completion_q <= '0;
                    completion_q.rob_tag <= pending_q.rob_tag;
                    completion_q.seq_num <= pending_q.seq_num;
                    completion_q.exception <= dmem_rsp_error;
                    completion_q.trap_cause <= dmem_rsp_error ? TRAP_LOAD_ACCESS : TRAP_NONE;
                    unique case (pending_q.size)
                        MEM_BYTE: completion_q.value <= pending_q.load_unsigned ?
                            {24'd0, byte_value} : {{24{byte_value[7]}}, byte_value};
                        MEM_HALF: completion_q.value <= pending_q.load_unsigned ?
                            {16'd0, half_value} : {{16{half_value[15]}}, half_value};
                        default: completion_q.value <= dmem_rsp_rdata;
                    endcase
                    state_q <= LSU_RESULT;
                end
            end

            if (state_q == LSU_RESULT && completion_valid && completion_ready) begin
                state_q <= LSU_IDLE;
            end

            if (recover_valid) begin
                if (state_q == LSU_WAIT && pending_q.seq_num > recover_seq) begin
                    drop_response_q <= 1'b1;
                end
                if (state_q == LSU_RESULT && completion_q.seq_num > recover_seq) begin
                    state_q <= LSU_IDLE;
                end
            end
        end
    end

endmodule

